-- Stage F: Telemetry v6 — Autonomous Learning Metrics
-- Purpose: Monitor how well the system adapts and gains user trust.

-- 1. Learning Gain Trend
-- Measures correlation between learning cycles and notification interaction.
CREATE OR REPLACE VIEW public.learning_gain_stats AS
SELECT 
    w.user_id,
    w.learning_cycles,
    w.trust_score,
    count(l.id) filter (where l.feedback_type = 'positive') as positive_signals,
    count(l.id) filter (where l.feedback_type = 'negative') as negative_signals,
    round(
        (count(l.id) filter (where l.feedback_type = 'positive'))::numeric * 100.0 / 
        nullif(count(l.id), 0)::numeric, 
        2
    ) as user_satisfaction_rate
FROM public.ai_learning_weights w
LEFT JOIN public.user_feedback_logs l ON w.user_id = l.user_id
GROUP BY w.user_id, w.learning_cycles, w.trust_score;

-- 2. Override Reduction Audit
-- Tracks if manual exclusions/pauses decrease as the system learns.
CREATE OR REPLACE VIEW public.learning_impact_audit AS
SELECT 
    w.user_id,
    w.learning_cycles,
    count(e.id) as active_exclusions,
    (SELECT count(*) FROM public.ai_decision_logs dl WHERE dl.user_id = w.user_id AND dl.final_decision = 'throttled') as digest_count
FROM public.ai_learning_weights w
LEFT JOIN public.notification_ai_exclusions e ON w.user_id = e.user_id
GROUP BY w.user_id, w.learning_cycles;

-- 3. Weight Evolution Monitoring
-- High-level view of how much weights have deviated from defaults.
CREATE OR REPLACE VIEW public.weight_drift_metrics AS
SELECT 
    avg(engagement_weight) as avg_engagement_w,
    avg(context_weight) as avg_context_w,
    avg(trust_score) as global_trust_avg
FROM public.ai_learning_weights;

COMMENT ON VIEW public.learning_gain_stats IS 'Tracks how learning cycles correlate with explicit user satisfaction.';
COMMENT ON VIEW public.learning_impact_audit IS 'Monitors if learning reduces the need for manual overrides like exclusions.';
COMMENT ON VIEW public.weight_drift_metrics IS 'Provides a global view of how the AI model is evolving across the user base.';
