-- Stage C: Telemetry & Analytics (v3)
-- Purpose: Monitor AI Effectiveness, Noise Reduction, and Behavior.

-- 1. AI Performance Audit
-- Compares AI Decisions with actual user Engagement (Utility Validation)
CREATE OR REPLACE VIEW public.ai_performance_audit AS
SELECT 
    l.user_id,
    p.username,
    l.utility_score,
    l.factor_engagement,
    l.final_decision,
    l.created_at as ai_decision_at,
    (SELECT count(*) FROM public.user_notification_engagement e 
     WHERE e.user_id = l.user_id AND e.last_interacted_at > l.created_at) as interaction_count
FROM public.ai_decision_logs l
JOIN public.profiles p ON l.user_id = p.id
ORDER BY l.created_at DESC;

-- 2. Noise Reduction Efficiency
-- Quantifies how many "low-value" notifications were silenced
CREATE OR REPLACE VIEW public.noise_reduction_efficiency AS
SELECT 
    user_id,
    count(*) filter (where final_decision != 'sent') as noise_silenced,
    count(*) as total_ai_decisions,
    round(count(*) filter (where final_decision != 'sent') * 100.0 / count(*), 2) as reduction_percentage
FROM public.ai_decision_logs
GROUP BY user_id;

-- 3. AI vs Manual Decisions
-- Compares AI decisions with User Preference overrides
CREATE OR REPLACE VIEW public.ai_vs_manual_stats AS
SELECT 
    reason,
    count(*) as count,
    round(count(*) * 100.0 / sum(count(*)) over(), 2) as percentage
FROM public.routing_logs
WHERE reason LIKE 'AI_%' OR reason LIKE 'USER_PREF_%'
GROUP BY reason;

-- 4. User Engagement Heat Map
-- Shows which users are currently "ignored" by AI due to low engagement
CREATE OR REPLACE VIEW public.user_engagement_heat_map AS
SELECT 
    recipient_id,
    count(*) filter (where reason = 'AI_LOW_UTILITY_THROTTLED') as throttled_count,
    count(*) filter (where reason = 'AI_MID_UTILITY_SILENT') as silenced_count,
    count(*) as total_notifications
FROM public.routing_logs
WHERE created_at > now() - interval '24 hours'
GROUP BY recipient_id
HAVING count(*) filter (where reason LIKE 'AI_%') > 0
ORDER BY throttled_count DESC;

COMMENT ON VIEW public.ai_performance_audit IS 'Audits AI decisions against subsequent user interactions.';
COMMENT ON VIEW public.noise_reduction_efficiency IS 'Quantifies the percentage of noise reduction per user.';
COMMENT ON VIEW public.ai_vs_manual_stats IS 'Compares the volume of AI-driven vs User-driven routing decisions.';
COMMENT ON VIEW public.user_engagement_heat_map IS 'Heat map of users currently targeted by AI for noise reduction.';
