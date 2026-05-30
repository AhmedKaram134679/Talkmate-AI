-- Stage H Telemetry: Policy & Identity Metrics

-- 1. Policy Intervention Rate
-- Measures how often policies override standard AI decisions
CREATE OR REPLACE VIEW policy_intervention_metrics AS
SELECT 
    DATE_TRUNC('hour', created_at) as time_window,
    COUNT(*) FILTER (WHERE action_taken = 'FORCE_SILENT') as silent_interventions,
    COUNT(*) FILTER (WHERE action_taken = 'FORCE_DELIVER') as deliver_interventions,
    COUNT(*) FILTER (WHERE action_taken = 'BLOCK') as blocked_messages,
    COUNT(*) as total_interventions
FROM 
    public.policy_decision_logs
GROUP BY 
    1
ORDER BY 
    1 DESC;

-- 2. Scope Activity Distribution
-- Analyze which scopes are generating the most traffic
CREATE OR REPLACE VIEW scope_activity_metrics AS
SELECT 
    s.name as scope_name,
    s.type as scope_type,
    COUNT(l.id) as traffic_volume
FROM 
    public.routing_logs l
JOIN 
    public.user_roles ur ON l.recipient_id = ur.user_id
JOIN 
    public.ai_scopes s ON ur.scope_id = s.id
GROUP BY 
    1, 2
ORDER BY 
    3 DESC;

-- 3. Policy Conflict Audit
-- Identify cases where policies are frequently triggering on 'sent' decisions (potential friction)
CREATE OR REPLACE VIEW policy_conflict_audit_v1 AS
SELECT 
    p.name as policy_name,
    p.action,
    COUNT(l.id) as trigger_count
FROM 
    public.policy_decision_logs l
JOIN 
    public.ai_policies p ON l.policy_id = p.id
WHERE 
    l.created_at > NOW() - INTERVAL '7 days'
GROUP BY 
    1, 2
ORDER BY 
    3 DESC;
