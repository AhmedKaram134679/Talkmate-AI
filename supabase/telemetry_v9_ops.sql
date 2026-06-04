-- Stage J: AI Operations Telemetry (v9)

-- 1. Shadow Mode Performance Matrix
-- Measures how often the Shadow Logic agrees with Production Logic.
-- High concordance means the new logic is "safe" or "similar".
-- Low concordance invites investigation.
CREATE OR REPLACE VIEW public.ai_shadow_performance_matrix AS
SELECT 
    feature_key,
    COUNT(*) as total_comparisons,
    SUM(CASE WHEN diff_reason IS NULL THEN 1 ELSE 0 END) as agreement_count,
    ROUND((SUM(CASE WHEN diff_reason IS NULL THEN 1 ELSE 0 END)::numeric / COUNT(*)) * 100, 2) as concordance_rate,
    AVG(prod_score) as avg_prod_score,
    AVG(shadow_score) as avg_shadow_score,
    MAX(created_at) as last_shadow_run
FROM 
    public.ai_shadow_comparisons
GROUP BY 
    feature_key;

-- 2. Rollout Status Dashboard
-- centralized view of active feature flags and their rollout status
CREATE OR REPLACE VIEW public.ai_rollout_status_dashboard AS
SELECT 
    feature_key,
    is_enabled,
    rollout_percentage,
    shadow_mode,
    created_at,
    (SELECT COUNT(*) FROM public.ai_shadow_comparisons WHERE ai_shadow_comparisons.feature_key = ai_feature_flags.feature_key) as shadow_samples_collected
FROM 
    public.ai_feature_flags;

-- 3. Operations Alert Feed (Drift & Shadows)
-- Combines anomalies from drift and shadow failures for a "Single Pane of Glass"
CREATE OR REPLACE VIEW public.ai_ops_alert_feed AS
SELECT 
    'SHADOW_DISAGREEMENT' as alert_type,
    diff_reason as message,
    'medium' as severity,
    created_at,
    user_id
FROM 
    public.ai_shadow_comparisons
WHERE 
    diff_reason IS NOT NULL
UNION ALL
SELECT 
    'HIGH_DRIFT' as alert_type,
    'User drift score exceeded safety threshold' as message,
    'high' as severity,
    last_drift_update as created_at,
    user_id
FROM 
    public.ai_drift_stats
WHERE 
    drift_score > 2.0;
