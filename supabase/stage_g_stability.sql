-- Stage G: AI Governance & Stability Schema
-- Purpose: Robust weight versioning, rollback support, and sandbox testing.

-- 1. Weight Snapshots (Versioning)
CREATE TABLE IF NOT EXISTS public.ai_weight_snapshots (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    engagement_weight FLOAT NOT NULL,
    context_weight FLOAT NOT NULL,
    urgency_weight FLOAT NOT NULL,
    trust_score FLOAT NOT NULL,
    version_tag TEXT, -- 'production', 'gold_standard', 'rollback_candidate'
    metadata JSONB DEFAULT '{}', -- { "trigger": "manual", "prev_satisfaction": 0.85 }
    created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_weight_snapshots_user_idx ON public.ai_weight_snapshots (user_id);
CREATE INDEX IF NOT EXISTS ai_weight_snapshots_created_idx ON public.ai_weight_snapshots (created_at DESC);

-- 2. Governance Audit Logs
-- Tracks automated actions like guardrail intervention or rollbacks.
CREATE TABLE IF NOT EXISTS public.ai_governance_audit (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL, -- 'guardrail_violation', 'auto_rollback', 'manual_rollback', 'snapshot_created'
    details JSONB NOT NULL, -- { "violation": "max_delta_exceeded", "requested": 1.5, "clamped": 1.2 }
    severity TEXT DEFAULT 'info', -- 'info', 'warning', 'critical'
    created_at timestamptz DEFAULT now()
);

-- 3. Shadow Logs (Sandbox)
-- Stores decisions that candidate weights *would* have made.
CREATE TABLE IF NOT EXISTS public.ai_shadow_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    decision_id uuid, -- Reference to the ACTUAL decision log
    shadow_weights JSONB NOT NULL,
    shadow_decision TEXT NOT NULL,
    actual_decision TEXT NOT NULL,
    concordance BOOLEAN NOT NULL, -- true if shadow == actual
    accuracy_gain FLOAT, -- simulated utility improvement
    created_at timestamptz DEFAULT now()
);

-- 4. Extensions to AI Settings for Governance
ALTER TABLE public.notification_ai_settings 
ADD COLUMN IF NOT EXISTS sandbox_mode_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS weight_version_id uuid REFERENCES public.ai_weight_snapshots(id),
ADD COLUMN IF NOT EXISTS stability_score FLOAT DEFAULT 1.0;

-- 5. Helper Function: Create Weight Snapshot
CREATE OR REPLACE FUNCTION public.create_ai_weight_snapshot(
    p_user_id UUID, 
    p_tag TEXT DEFAULT 'manual'
) RETURNS UUID AS $$
DECLARE
    v_snapshot_id UUID;
    v_current RECORD;
BEGIN
    SELECT * INTO v_current FROM public.ai_learning_weights WHERE user_id = p_user_id;
    
    INSERT INTO public.ai_weight_snapshots (
        user_id, engagement_weight, context_weight, urgency_weight, trust_score, version_tag
    ) VALUES (
        p_user_id, v_current.engagement_weight, v_current.context_weight, v_current.urgency_weight, v_current.trust_score, p_tag
    ) RETURNING id INTO v_snapshot_id;
    
    RETURN v_snapshot_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS
ALTER TABLE public.ai_weight_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_governance_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_shadow_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own weight snapshots" ON public.ai_weight_snapshots;
CREATE POLICY "Users view own weight snapshots" ON public.ai_weight_snapshots FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users view own governance audit" ON public.ai_governance_audit;
CREATE POLICY "Users view own governance audit" ON public.ai_governance_audit FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users view own shadow logs" ON public.ai_shadow_logs;
CREATE POLICY "Users view own shadow logs" ON public.ai_shadow_logs FOR SELECT USING (auth.uid() = user_id);

COMMENT ON TABLE public.ai_weight_snapshots IS 'Versioned history of user AI decision weights for rollback and tracking.';
COMMENT ON TABLE public.ai_governance_audit IS 'Record of all safety interventions and model stability events.';
COMMENT ON TABLE public.ai_shadow_logs IS 'Experimental results of new weights running in parallel to production.';

-- 6. Link Decisions with Versions
ALTER TABLE public.ai_decision_logs 
ADD COLUMN IF NOT EXISTS weight_version_id UUID REFERENCES public.ai_weight_snapshots(id);

