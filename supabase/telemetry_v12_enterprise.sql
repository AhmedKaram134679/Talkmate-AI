-- STAGE M: TELEMETRY v12 - ORGANIZATIONAL INTELLIGENCE
-- Purpose: Provide workspace-level insights for administrators.

-- 1. Digital Noise Impact Dashboard
-- Measures how many notifications were silenced (throttled/silent) per workspace.
CREATE OR REPLACE VIEW public.ai_enterprise_noise_dashboard AS
SELECT 
    s.id as workspace_id,
    s.name as workspace_name,
    COUNT(l.id) as total_interactions,
    COUNT(CASE WHEN l.decision IN ('silent', 'throttled', 'delayed') THEN 1 END) as silenced_notifications,
    ROUND(
        (COUNT(CASE WHEN l.decision IN ('silent', 'throttled', 'delayed') THEN 1 END)::float / 
        NULLIF(COUNT(l.id), 0)::float) * 100
    ) as noise_reduction_pct
FROM 
    public.ai_scopes s
LEFT JOIN 
    public.routing_logs l ON l.meta->>'workspace_id' = s.id::text -- Requires workspace_id in meta
GROUP BY 
    s.id, s.name;

-- 2. Enterprise Policy Impact
-- Tracks how often Hard/Soft overrides were applied.
CREATE OR REPLACE VIEW public.ai_enterprise_policy_impact AS
SELECT 
    workspace_id,
    override_type,
    final_decision,
    COUNT(*) as override_count,
    MIN(created_at) as earliest_audit,
    MAX(created_at) as latest_audit
FROM 
    public.ai_enterprise_audit
GROUP BY 
    workspace_id, override_type, final_decision;

-- 3. Workspace Drift Overview
-- Aggregates drift scores by workspace to detect when institutional models need retuning.
CREATE OR REPLACE VIEW public.ai_enterprise_drift_overview AS
SELECT 
    ur.scope_id as workspace_id,
    AVG(ds.drift_score) as avg_workspace_drift,
    MAX(ds.drift_score) as max_user_drift,
    COUNT(DISTINCT ur.user_id) as active_users
FROM 
    public.user_roles ur
JOIN 
    public.ai_drift_stats ds ON ds.user_id = ur.user_id
GROUP BY 
    ur.scope_id;

-- 4. Enterprise Audit Feed
-- Detailed logs for admins (Explainability).
CREATE OR REPLACE VIEW public.ai_enterprise_audit_feed AS
SELECT 
    a.created_at,
    s.name as workspace_name,
    p.email as user_email,
    o.reason as policy_reason,
    a.override_type,
    a.final_decision,
    a.metadata
FROM 
    public.ai_enterprise_audit a
JOIN 
    public.ai_scopes s ON s.id = a.workspace_id
JOIN 
    public.profiles p ON p.id = a.user_id
JOIN 
    public.ai_enterprise_overrides o ON o.id = a.policy_id
ORDER BY 
    a.created_at DESC;
