-- Stage O: Continuous Learning & Self-Optimization
-- This script implements the infrastructure for confidence scoring, shadow decisions, and passive learning.

BEGIN;

-- 1. AI Confidence Metrics
-- Tracks the certainty of each decision to prevent low-confidence learning drift.
CREATE TABLE IF NOT EXISTS public.ai_confidence_metrics (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    message_id uuid NOT NULL,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    confidence_score float NOT NULL, -- 0.0 to 1.0
    confidence_level text CHECK (confidence_level IN ('LOW', 'MEDIUM', 'HIGH')),
    factors jsonb, -- e.g., {"trust_contribution": 0.2, "utility_proximity": 0.1}
    created_at timestamptz DEFAULT now()
);

-- Index for fast lookup by message
CREATE INDEX IF NOT EXISTS idx_ai_confidence_metrics_message_id ON public.ai_confidence_metrics(message_id);

-- 2. AI Shadow Logs
-- Stores "what-if" decisions from parallel models/weights for zero-risk evaluation.
CREATE TABLE IF NOT EXISTS public.ai_shadow_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    shadow_decision text,
    shadow_reason text,
    shadow_weights jsonb,
    actual_decision text,
    concordance boolean, -- true if shadow matched actual
    created_at timestamptz DEFAULT now()
);

-- ROBUST MIGRATION: Add columns if they were missed in previous table creation
ALTER TABLE public.ai_shadow_logs ADD COLUMN IF NOT EXISTS actual_message_id uuid;




-- 3. User Learning States & Trust Preservation
-- Tracks when to freeze learning for specific categories due to excessive overrides.
CREATE TABLE IF NOT EXISTS public.user_learning_states (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    category text NOT NULL,
    learning_paused boolean DEFAULT false,
    reason text,
    override_count_30d int DEFAULT 0,
    last_override_at timestamptz,
    updated_at timestamptz DEFAULT now(),
    UNIQUE(user_id, category)
);

-- 4. Learning Engine Observability Views
CREATE OR REPLACE VIEW public.ai_learning_dashboard AS
SELECT 
    ai_confidence_metrics.user_id,
    COUNT(*) as total_decisions,
    AVG(confidence_score) as avg_confidence,
    SUM(CASE WHEN concordance = true THEN 1 ELSE 0 END)::float / NULLIF(COUNT(*), 0) as shadow_accuracy_rate,
    COUNT(*) FILTER (WHERE confidence_level = 'LOW') as low_confidence_count
FROM 
    public.ai_confidence_metrics
LEFT JOIN 
    public.ai_shadow_logs ON ai_confidence_metrics.message_id = ai_shadow_logs.actual_message_id
GROUP BY 
    ai_confidence_metrics.user_id;


-- 5. Trigger for Passive Trust Preservation
-- If a user consistently overrides (Stage N) a category, we pause learning for it.
CREATE OR REPLACE FUNCTION public.fn_update_learning_state_on_override()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.user_override->>'applied' = 'true' THEN
        INSERT INTO public.user_learning_states (user_id, category, override_count_30d, last_override_at)
        VALUES (NEW.recipient_id, COALESCE(NEW.meta->>'scenario', 'chat'), 1, now())
        ON CONFLICT (user_id, category) DO UPDATE SET
            override_count_30d = user_learning_states.override_count_30d + 1,
            last_override_at = now(),
            learning_paused = CASE WHEN user_learning_states.override_count_30d + 1 >= 5 THEN true ELSE user_learning_states.learning_paused END,
            reason = CASE WHEN user_learning_states.override_count_30d + 1 >= 5 THEN 'EXCESSIVE_OVERRIDES' ELSE user_learning_states.reason END;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_routing_logs_learning_guard ON public.routing_logs;
CREATE TRIGGER tr_routing_logs_learning_guard
AFTER INSERT ON public.routing_logs
FOR EACH ROW EXECUTE FUNCTION public.fn_update_learning_state_on_override();

COMMIT;
