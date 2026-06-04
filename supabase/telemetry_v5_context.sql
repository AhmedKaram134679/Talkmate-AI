-- 1. AI Context Effectiveness Score
-- Measures the correlation between context penalty and delivery success.
CREATE OR REPLACE VIEW public.ai_context_effectiveness_score AS
SELECT 
    avg((explanation_context->>'penalty')::float) as avg_penalty,
    count(*) as total_decisions,
    round(
        avg(CASE WHEN final_decision = 'sent' THEN utility_score ELSE 0 END)::numeric, 
        3
    ) as avg_utility_sent,
    round(
        (count(*) filter (where final_decision = 'throttled'))::numeric * 100.0 / nullif(count(*), 0)::numeric, 
        2
    ) as smart_throttle_rate
FROM public.ai_decision_logs;

-- 2. Notification Fatigue Index
-- Measures the suppression of low-relevance notifications during sensitive segments.
CREATE OR REPLACE VIEW public.ai_notification_fatigue_index AS
SELECT 
    (explanation_context->>'time_segment') as segment,
    count(*) filter (where final_decision = 'silent' AND explanation_key = 'AI_LOW_RELEVANCE') as fatigue_saved_notifications,
    sum((explanation_context->>'penalty')::float) as cumulative_fatigue_reduction
FROM public.ai_decision_logs
WHERE (explanation_context->>'time_segment') IN ('night', 'work', 'weekend')
GROUP BY 1;

-- 3. Predictive Timing Performance (Time-to-Open Improvement Proxy)
CREATE OR REPLACE VIEW public.ai_predictive_timing_stats AS
SELECT 
    avg((explanation_context->>'delay')::float) as avg_delay_minutes,
    count(*) as total_predictions,
    count(*) filter (where explanation_key = 'AI_CONTEXT_DELAYED') as contextual_delays
FROM public.ai_decision_logs
WHERE explanation_key = 'AI_CONTEXT_DELAYED';

COMMENT ON VIEW public.ai_context_effectiveness_score IS 'Measures how well context penalties align with smart delivery.';
COMMENT ON VIEW public.ai_notification_fatigue_index IS 'Tracks noise reduction during high-fatigue user segments.';
COMMENT ON VIEW public.ai_predictive_timing_stats IS 'Tracks successful smart delays for optimal timing.';

