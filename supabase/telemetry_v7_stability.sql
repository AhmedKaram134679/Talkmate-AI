-- Telemetry v7: AI Governance & Stability
-- Purpose: Monitor model drift, sandbox accuracy, and system stability.

-- 1. Model Drift Velocity
-- Tracks how fast and how significantly weights are changing.
CREATE OR REPLACE VIEW public.model_drift_velocity AS
SELECT 
    user_id,
    count(*) as adjustment_cycles,
    round(avg(abs(engagement_weight - lag_ew))::numeric, 4) as avg_engagement_drift,
    round(avg(abs(context_weight - lag_cw))::numeric, 4) as avg_context_drift,
    max(created_at) as last_update
FROM (
    SELECT 
        user_id,
        engagement_weight,
        context_weight,
        created_at,
        lag(engagement_weight) OVER (PARTITION BY user_id ORDER BY created_at) as lag_ew,
        lag(context_weight) OVER (PARTITION BY user_id ORDER BY created_at) as lag_cw
    FROM public.ai_weight_snapshots
) drift_data
GROUP BY user_id;

-- 2. Sandbox Accuracy Delta
-- Compares shadow decisions (candidate) with actual decisions (production).
CREATE OR REPLACE VIEW public.sandbox_accuracy_delta AS
SELECT 
    user_id,
    count(*) as total_shadow_runs,
    round((count(*) FILTER (WHERE concordance = true)::float / nullif(count(*), 0))::numeric, 4) as concordance_rate,
    round(avg(accuracy_gain)::numeric, 4) as avg_simulated_gain,
    max(created_at) as last_test_at
FROM public.ai_shadow_logs
GROUP BY user_id;

-- 3. Governance Health Audit
-- Summarizes automated safety interventions and rollbacks.
CREATE OR REPLACE VIEW public.governance_health_audit AS
SELECT 
    action_type,
    severity,
    count(*) as occurrence_count,
    min(created_at) as first_seen,
    max(created_at) as last_seen
FROM public.ai_governance_audit
GROUP BY action_type, severity;

-- 4. Weight Version Adoption
-- Tracks which versions are currently being used by users.
CREATE OR REPLACE VIEW public.weight_version_stats AS
SELECT 
    COALESCE(s.version_tag, 'latest_learned') as version_flavor,
    count(n.user_id) as active_users,
    round(avg(n.stability_score)::numeric, 4) as avg_stability
FROM public.notification_ai_settings n
LEFT JOIN public.ai_weight_snapshots s ON n.weight_version_id = s.id
GROUP BY s.version_tag;

COMMENT ON VIEW public.model_drift_velocity IS 'Magnitude of AI weight changes over time to detect unstable learning.';
COMMENT ON VIEW public.sandbox_accuracy_delta IS 'Performance of new weights vs production weights in shadow mode.';
COMMENT ON VIEW public.governance_health_audit IS 'Audit of all automated safety interventions and guardrail triggers.';

