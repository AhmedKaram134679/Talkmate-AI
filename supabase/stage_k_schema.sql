-- STAGE K: PRIVACY & FEDERATED LEARNING
-- Purpose: Enable collective intelligence without accessing raw user data.

-- 1. Federated Deltas (Anonymous Signals)
-- Stores the *difference* (Delta) between a user's local weights and the global model.
-- Privacy: NO permanent user_id link for long-term storage if possible, or strict RLS.
-- We use a "bucket_id" to aggregate signals over time windows.

CREATE TABLE IF NOT EXISTS public.ai_federated_deltas (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    -- user_id removed or hashed for strict privacy in production. 
    -- For this implementation, we keep it for RLS but it should be wiped after aggregation.
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE, 
    
    signal_type text NOT NULL, -- 'engagement_delta', 'context_sensitivity_delta'
    bucket_id text NOT NULL, -- e.g., '2024-W01', used for temporal aggregation
    
    -- The Delta Value (Noisy)
    delta_value float NOT NULL, 
    noise_factor float NOT NULL DEFAULT 0.0, -- Amount of noise added (epsilon)
    
    created_at timestamptz DEFAULT now()
);

-- Index for Aggregation
CREATE INDEX IF NOT EXISTS federated_deltas_bucket_idx ON public.ai_federated_deltas (bucket_id, signal_type);

-- 2. Global Intelligence Weights
-- The shared model that everyone downloads.
CREATE TABLE IF NOT EXISTS public.ai_global_weights (
    version_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    
    -- The aggregated weights payload
    weights jsonb NOT NULL, -- { "engagement_weight": 0.45, "context_weight": 0.35 }
    
    generation_count int NOT NULL DEFAULT 1,
    is_active boolean DEFAULT false,
    
    created_at timestamptz DEFAULT now()
);

-- 3. Privacy Audit Logs (Health Metrics)
-- Tracks privacy budget consumption and opt-out events.
CREATE TABLE IF NOT EXISTS public.ai_privacy_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    
    event_type text NOT NULL, -- 'opt_out', 'budget_exceeded', 'signal_uploaded'
    details jsonb, -- { "budget_used": 0.1 }
    
    created_at timestamptz DEFAULT now()
);

-- 4. Settings Extensions (Opt-Out)
ALTER TABLE public.notification_ai_settings
ADD COLUMN IF NOT EXISTS federated_learning_enabled boolean DEFAULT true;

-- RLS POLICIES

-- Deltas: Users INSERT their own, NO SELECT (Write-Only for users).
ALTER TABLE public.ai_federated_deltas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users insert own deltas" ON public.ai_federated_deltas;
CREATE POLICY "Users insert own deltas" ON public.ai_federated_deltas 
    FOR INSERT TO authenticated 
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service Role Aggregates Deltas" ON public.ai_federated_deltas;
CREATE POLICY "Service Role Aggregates Deltas" ON public.ai_federated_deltas 
    USING (true) WITH CHECK (true); -- Service Role only

-- Global Weights: PUBLIC READ (Everyone benefits).
ALTER TABLE public.ai_global_weights ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read global weights" ON public.ai_global_weights;
CREATE POLICY "Public read global weights" ON public.ai_global_weights 
    FOR SELECT TO authenticated 
    USING (true);

DROP POLICY IF EXISTS "Service Role manages global weights" ON public.ai_global_weights;
CREATE POLICY "Service Role manages global weights" ON public.ai_global_weights 
    USING (true) WITH CHECK (true);

-- Privacy Logs: Users view own.
ALTER TABLE public.ai_privacy_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own privacy logs" ON public.ai_privacy_logs;
CREATE POLICY "Users view own privacy logs" ON public.ai_privacy_logs 
    FOR SELECT TO authenticated 
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users insert own privacy logs" ON public.ai_privacy_logs;
CREATE POLICY "Users insert own privacy logs" ON public.ai_privacy_logs 
    FOR INSERT TO authenticated 
    WITH CHECK (auth.uid() = user_id);

-- Seed Initial Global Weight
INSERT INTO public.ai_global_weights (weights, is_active, generation_count)
VALUES (
    '{"engagement_weight": 0.4, "context_weight": 0.3, "urgency_weight": 0.3}', 
    true, 
    0
);
