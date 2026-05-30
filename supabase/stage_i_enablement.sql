/*
  STAGE I: RELIABILITY & OPS LAYER (Enablement)
  =============================================
  
  This script deploys the "Safety Net" infrastructure:
  1. Dead Letter Queue (DLQ) for failed notifications.
  2. Circuit Breakers to prevent cascading failures.
  3. Reliability RPCs (Trip/Reset Breakers, Record Failures).

*/

-- =================================================================
-- PART 1: DEAD LETTER QUEUE (DLQ)
-- =================================================================

CREATE TABLE IF NOT EXISTS public.notification_dlq (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, -- Nullable if user deleted
    payload JSONB NOT NULL,
    error_reason TEXT NOT NULL,
    retry_count INT DEFAULT 0,
    max_retries INT DEFAULT 5,
    next_retry_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    status TEXT DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'RETRYING', 'FAILED', 'RESOLVED')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dlq_status_retry ON public.notification_dlq (status, next_retry_at);

-- RPC: Record a failed item to DLQ (called by Edge Function)
CREATE OR REPLACE FUNCTION public.record_dlq_entry(
    p_user_id UUID,
    p_payload JSONB,
    p_error_reason TEXT
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.notification_dlq (user_id, payload, error_reason)
    VALUES (p_user_id, p_payload, p_error_reason)
    RETURNING id INTO v_id;
    
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =================================================================
-- PART 2: CIRCUIT BREAKERS configuration & state
-- =================================================================

CREATE TABLE IF NOT EXISTS public.circuit_breakers (
    service_name TEXT PRIMARY KEY, -- e.g., 'fcm', 'openai', 'supabase_db'
    state TEXT DEFAULT 'CLOSED' CHECK (state IN ('CLOSED', 'OPEN', 'HALF-OPEN')),
    failure_threshold INT DEFAULT 5,
    failure_count INT DEFAULT 0,
    last_failure_at TIMESTAMP WITH TIME ZONE,
    recovery_timeout_ms INT DEFAULT 30000, -- 30 seconds default
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Seed initial breakers
INSERT INTO public.circuit_breakers (service_name) VALUES 
('fcm'), 
('openai'), 
('email_provider')
ON CONFLICT (service_name) DO NOTHING;

-- RPC: Check Breaker State
CREATE OR REPLACE FUNCTION public.check_circuit_breaker(p_service_name TEXT)
RETURNS JSONB AS $$
DECLARE
    r RECORD;
    v_now TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    SELECT * INTO r FROM public.circuit_breakers WHERE service_name = p_service_name;
    
    IF r IS NULL THEN
        -- Default closed if unknown
        RETURN jsonb_build_object('state', 'CLOSED', 'allowed', true);
    END IF;

    -- If OPEN, check if recovery timeout has passed -> Switch to HALF-OPEN
    IF r.state = 'OPEN' THEN
        IF r.last_failure_at + (r.recovery_timeout_ms || ' milliseconds')::interval < v_now THEN
            -- Autorecover to half-open locally? Or wait for explicit write?
            -- For simplicity, we report allowed=true (probing) but don't write state change here to avoid write overhead on reads.
            -- Real implementation might do a fast update.
            RETURN jsonb_build_object('state', 'HALF-OPEN', 'allowed', true);
        ELSE
            RETURN jsonb_build_object('state', 'OPEN', 'allowed', false);
        END IF;
    END IF;

    RETURN jsonb_build_object('state', r.state, 'allowed', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Trip Breaker (called when Edge detects repeated failures)
CREATE OR REPLACE FUNCTION public.trip_circuit_breaker(p_service_name TEXT, p_force_open BOOLEAN DEFAULT false)
RETURNS VOID AS $$
BEGIN
    UPDATE public.circuit_breakers
    SET 
        failure_count = failure_count + 1,
        last_failure_at = NOW(),
        updated_at = NOW(),
        state = CASE 
            WHEN p_force_open OR (failure_count + 1 >= failure_threshold) THEN 'OPEN' 
            ELSE state 
        END
    WHERE service_name = p_service_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Reset Breaker (called on success)
CREATE OR REPLACE FUNCTION public.reset_circuit_breaker(p_service_name TEXT)
RETURNS VOID AS $$
BEGIN
    -- Only write if dirty
    UPDATE public.circuit_breakers
    SET 
        state = 'CLOSED',
        failure_count = 0,
        updated_at = NOW()
    WHERE service_name = p_service_name AND (state != 'CLOSED' OR failure_count > 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =================================================================
-- PART 3: OPS DASHBOARD VIEWS
-- =================================================================

-- View for Dashboard: failing services
CREATE OR REPLACE VIEW public.ops_system_health AS
SELECT 
    service_name, 
    state, 
    failure_count, 
    last_failure_at,
    CASE 
        WHEN state = 'OPEN' THEN 'CRITICAL'
        WHEN failure_count > 0 THEN 'WARNING'
        ELSE 'HEALTHY'
    END as health_status
FROM public.circuit_breakers;

-- Permissions
ALTER TABLE public.notification_dlq ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circuit_breakers ENABLE ROW LEVEL SECURITY;

-- Admins/Service Role Only for now (modify if needed for user visibility)
CREATE POLICY "Admins view DLQ" ON public.notification_dlq FOR SELECT USING (auth.uid() IN (SELECT id FROM auth.users)); -- relaxed for dev
CREATE POLICY "Admins view Breakers" ON public.circuit_breakers FOR SELECT USING (true); -- relaxed for dev
