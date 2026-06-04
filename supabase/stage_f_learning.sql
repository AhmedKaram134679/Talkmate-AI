-- Stage F: Autonomous Learning & Continuous Optimization
-- SQL Schema for Feedback and Weights

-- 1. Learning Weights Table
-- Stores the evolved weights for each user.
CREATE TABLE IF NOT EXISTS public.ai_learning_weights (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    engagement_weight FLOAT DEFAULT 0.4, -- Initial weight from Stage C
    context_weight FLOAT DEFAULT 0.3,    -- Initial weight from Stage E
    urgency_weight FLOAT DEFAULT 0.3,    -- Initial weight
    trust_score FLOAT DEFAULT 1.0,      -- 0.0 to 1.0 (How much the user trusts the AI)
    learning_cycles INTEGER DEFAULT 0,
    last_updated TIMESTAMPTZ DEFAULT now(),
    
    CONSTRAINT weights_range CHECK (
        engagement_weight >= 0 AND engagement_weight <= 2.0 AND
        context_weight >= 0 AND context_weight <= 2.0 AND
        urgency_weight >= 0 AND urgency_weight <= 2.0
    )
);

-- 2. User Feedback Logs
-- Captures explicit 👍/👎 signals from the Explainability UI.
CREATE TABLE IF NOT EXISTS public.user_feedback_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    decision_id UUID REFERENCES public.ai_decision_logs(id),
    feedback_type TEXT NOT NULL, -- 'positive', 'negative'
    comment TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    
    CONSTRAINT valid_feedback CHECK (feedback_type IN ('positive', 'negative'))
);

-- 3. Extend Notification AI Settings
-- Track learning status and global trust.
ALTER TABLE public.notification_ai_settings 
ADD COLUMN IF NOT EXISTS learning_enabled BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS system_trust_index FLOAT DEFAULT 1.0;

-- 4. RLS Policies
ALTER TABLE public.ai_learning_weights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own learning weights"
ON public.ai_learning_weights FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can manage their own feedback logs"
ON public.user_feedback_logs FOR ALL
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 5. Helper function to adjust weights (The Learning Loop)
-- This is a simplified gradient update called from the Edge Function or a worker.
CREATE OR REPLACE FUNCTION public.adjust_user_weights(
    p_user_id UUID,
    p_factor TEXT, -- 'engagement', 'context', 'urgency'
    p_delta FLOAT  -- + or - adjustment
) RETURNS VOID AS $$
BEGIN
    INSERT INTO public.ai_learning_weights (user_id) VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;

    IF p_factor = 'engagement' THEN
        UPDATE public.ai_learning_weights SET engagement_weight = clip(engagement_weight + p_delta, 0.1, 1.5) WHERE user_id = p_user_id;
    ELSIF p_factor = 'context' THEN
        UPDATE public.ai_learning_weights SET context_weight = clip(context_weight + p_delta, 0.1, 1.5) WHERE user_id = p_user_id;
    END IF;
    
    UPDATE public.ai_learning_weights 
    SET learning_cycles = learning_cycles + 1, last_updated = now() 
    WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Simple helper to keep weights in bounds
CREATE OR REPLACE FUNCTION public.clip(val FLOAT, min_val FLOAT, max_val FLOAT) 
RETURNS FLOAT AS $$
BEGIN
    RETURN LEAST(GREATEST(val, min_val), max_val);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON TABLE public.ai_learning_weights IS 'Stores the autonomous evolution of decision parameters for each user.';
COMMENT ON TABLE public.user_feedback_logs IS 'Explicit user signals used to optimize the learning loop.';
