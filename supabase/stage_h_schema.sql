-- STAGE H: COMPLIANCE, PRIVACY & GOVERNANCE

-- 1. Consent Management
CREATE TABLE IF NOT EXISTS public.user_consent (
    user_id uuid NOT NULL, -- references auth.users
    notification_type text NOT NULL, -- 'marketing', 'chat', 'system', 'call'
    consent_status boolean DEFAULT true,
    updated_at timestamptz DEFAULT now(),
    PRIMARY KEY (user_id, notification_type)
);

CREATE INDEX IF NOT EXISTS user_consent_user_idx ON public.user_consent (user_id);

-- 2. Data Retention & Purge Function
CREATE OR REPLACE FUNCTION public.purge_old_data(retention_days int DEFAULT 90)
RETURNS void AS $$
DECLARE
    cutoff_date timestamptz;
    deleted_logs int;
    deleted_signals int;
BEGIN
    cutoff_date := now() - (retention_days || ' days')::interval;

    -- Purge Routing Logs
    WITH deleted AS (
        DELETE FROM public.routing_logs 
        WHERE created_at < cutoff_date
        RETURNING id
    )
    SELECT count(*) INTO deleted_logs FROM deleted;

    -- Purge Feedback Signals
    WITH deleted AS (
        DELETE FROM public.feedback_signals 
        WHERE created_at < cutoff_date
        RETURNING id
    )
    SELECT count(*) INTO deleted_signals FROM deleted;

    -- Log the purge event (Privacy-safe: no PII, just counts)
    INSERT INTO public.routing_logs (
        decision, 
        reason, 
        meta
    ) VALUES (
        'system',
        'DATA_PURGE',
        jsonb_build_object(
            'retention_days', retention_days,
            'deleted_logs', deleted_logs,
            'deleted_signals', deleted_signals,
            'timestamp', now()
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Consent Check RPC (Optional helper for potential Flutter use, mostly Logic in Edge Function)
CREATE OR REPLACE FUNCTION public.check_user_consent(
    p_user_id uuid, 
    p_notification_type text
)
RETURNS boolean AS $$
DECLARE
    v_consent boolean;
BEGIN
    SELECT consent_status INTO v_consent
    FROM public.user_consent
    WHERE user_id = p_user_id AND notification_type = p_notification_type;
    
    -- Default Policies:
    -- Marketing: Default False if missing (Strict) -> Actually typically explicit opt-in.
    -- Chat/System/Call: Default True if missing (Implicit).
    
    IF v_consent IS NULL THEN
        IF p_notification_type = 'marketing' THEN
            RETURN false;
        ELSE
            RETURN true;
        END IF;
    END IF;

    RETURN v_consent;
END;
$$ LANGUAGE plpgsql STABLE;

-- RLS Policies
ALTER TABLE public.user_consent ENABLE ROW LEVEL SECURITY;

-- Service Role Full Access
DROP POLICY IF EXISTS "Service Role Full Access Consent" ON public.user_consent;
CREATE POLICY "Service Role Full Access Consent" ON public.user_consent USING (true) WITH CHECK (true);

-- Authenticated Read (Users see their own consent)
DROP POLICY IF EXISTS "Auth Read Own Consent" ON public.user_consent;
CREATE POLICY "Auth Read Own Consent" ON public.user_consent 
FOR SELECT TO authenticated 
USING (auth.uid() = user_id);

-- Authenticated Update (Users manage their own consent)
DROP POLICY IF EXISTS "Auth Update Own Consent" ON public.user_consent;
CREATE POLICY "Auth Update Own Consent" ON public.user_consent 
FOR UPDATE TO authenticated 
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Authenticated Insert (Users set own consent)
DROP POLICY IF EXISTS "Auth Insert Own Consent" ON public.user_consent;
CREATE POLICY "Auth Insert Own Consent" ON public.user_consent 
FOR INSERT TO authenticated 
WITH CHECK (auth.uid() = user_id);

-- Seed Initial Config for Retention (using existing routing_config)
INSERT INTO public.routing_config (key, value, description)
VALUES 
('data_retention_policy', '{
  "retention_days": 90,
  "purge_enabled": true
}', 'Configuration for data retention and purging')
ON CONFLICT (key) DO NOTHING;
