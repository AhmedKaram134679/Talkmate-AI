-- Stage D: Telemetry v4 — Governance & Trust Metrics
-- Purpose: Monitor AI alignment, Acceptability, and Trust Drift.

-- 1. AI Decision Acceptance Rate
-- Measures how often AI "silencing" matches user expectations (i.e. not overridden)
CREATE OR REPLACE VIEW public.ai_acceptance_metrics AS
SELECT 
    l.explanation_key,
    count(*) as total_decisions,
    count(*) filter (where l.final_decision = 'sent') as sent_count,
    count(*) filter (where l.final_decision != 'sent') as silenced_count,
    round(
        ((count(*) filter (where l.final_decision != 'sent'))::float * 100.0 / count(*))::numeric, 
        2
    ) as reduction_rate
FROM public.ai_decision_logs l
GROUP BY l.explanation_key;

-- 2. Governance Override Frequency
-- Tracks how many AI decisions were bypassed by Governance Rules (Kill-Switch, Safe Mode, Exclusions)
CREATE OR REPLACE VIEW public.governance_override_audit AS
SELECT 
    reason,
    count(*) as total_bypasses,
    round((count(*) * 100.0 / sum(count(*)) over())::numeric, 2) as override_percentage
FROM public.routing_logs
WHERE reason LIKE 'GOV_%'
GROUP BY reason;

-- 3. Trust Drift Scoreboard
-- Monitors users with high disagreement scores who might need automated Safe Mode.
CREATE OR REPLACE VIEW public.trust_drift_scoreboard AS
SELECT 
    d.user_id,
    p.username,
    d.drift_score,
    d.total_overrides,
    s.is_safe_mode,
    s.paused_until
FROM public.ai_drift_stats d
JOIN public.profiles p ON d.user_id = p.id
JOIN public.notification_ai_settings s ON d.user_id = s.user_id
ORDER BY d.drift_score DESC;

-- 4. Explainability Distribution
-- Shows which AI segments are driving the most decisions.
CREATE OR REPLACE VIEW public.ai_explanation_stats AS
SELECT 
    explanation_key,
    count(*) as volume,
    round(avg(utility_score::float)::numeric, 3) as avg_utility
FROM public.ai_decision_logs
WHERE explanation_key LIKE 'AI_%'
GROUP BY explanation_key;

COMMENT ON VIEW public.ai_acceptance_metrics IS 'Measures the reduction performance of AI across different explanation segments.';
COMMENT ON VIEW public.governance_override_audit IS 'Audits the impact of manual governance controls vs AI logic.';
COMMENT ON VIEW public.trust_drift_scoreboard IS 'Identifies users whose behavior deviates from AI predictions (High Drift).';
