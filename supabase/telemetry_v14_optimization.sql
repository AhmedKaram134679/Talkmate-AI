-- STAGE O: TELEMETRY v14 - OPTIMIZATION INTELLIGENCE
-- Purpose: Measure the effectiveness and safety of the Autonomous Optimization Engine.

-- 1. Optimization Impact Dashboard
-- Measures the reduction in digital noise after applying AI recommendations.
CREATE OR REPLACE VIEW public.ai_optimization_impact_dashboard AS
SELECT 
    r.scope_id,
    s.name as scope_name,
    r.target_param,
    r.current_value,
    r.proposed_value,
    COUNT(audit.id) as override_count,
    ROUND(AVG(sim.noise_reduction_delta)::numeric * 100, 2) as predicted_noise_reduction_pct,
    r.applied_at
FROM 
    public.ai_optimization_recommendations r
JOIN 
    public.ai_scopes s ON s.id = r.scope_id
LEFT JOIN 
    public.ai_simulation_logs sim ON sim.recommendation_id = r.id
LEFT JOIN 
    public.ai_enterprise_audit audit ON audit.workspace_id = r.scope_id AND audit.policy_id IS NULL -- Simple proxy for optimization impact
WHERE 
    r.status = 'approved'
GROUP BY 
    r.scope_id, s.name, r.target_param, r.current_value, r.proposed_value, r.applied_at;

-- 2. Human Trust Index
-- Tracks how often AI recommendations are approved or rejected.
CREATE OR REPLACE VIEW public.ai_optimization_trust_index AS
SELECT 
    scope_id,
    status,
    COUNT(*) as total_recommendations,
    ROUND((COUNT(*)::float / SUM(COUNT(*)) OVER (PARTITION BY scope_id)::float) * 100) as percentage
FROM 
    public.ai_optimization_recommendations
GROUP BY 
    scope_id, status;

-- 3. Optimization Stability Index
-- Detects if AI is proposing too many rapid changes (thrashing).
CREATE OR REPLACE VIEW public.ai_optimization_stability AS
SELECT 
    scope_id,
    target_param,
    COUNT(*) as changes_last_30_days,
    ROUND(AVG(ABS(proposed_value - current_value))::numeric, 4) as avg_shift_magnitude
FROM 
    public.ai_optimization_recommendations
WHERE 
    status = 'approved' AND applied_at > now() - interval '30 days'
GROUP BY 
    scope_id, target_param;

-- 4. Simulation Fidelity
-- Compares simulation predictions vs. real-world telemetry (conceptual).
CREATE OR REPLACE VIEW public.ai_simulation_fidelity AS
SELECT 
    log.recommendation_id,
    log.noise_reduction_delta as predicted_reduction,
    -- In a real system, we'd join with actual noise reduction stats after application
    0.0 as actual_reduction_placeholder 
FROM 
    public.ai_simulation_logs log;
