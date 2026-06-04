-- FIX: PostgrestException 42883 (operator does not exist: text ->> unknown)
-- Cause: Using ->> on a column or key that Postgres interprets as TEXT, or navigating missing columns.
-- Optimal Solution: Use explicit ::jsonb casting to avoid dependency errors with existing Views.

BEGIN;

-- 1. Fixed Trigger Function with Explicit Casting
-- This ensures the operator -> and ->> work even if 'meta' is TEXT.
CREATE OR REPLACE FUNCTION public.fn_update_learning_state_on_override()
RETURNS TRIGGER AS $$
BEGIN
    -- user_override is a key inside the meta JSONB column
    -- We cast meta to ::jsonb to ensure compatibility with JSON operators.
    IF ((NEW.meta::jsonb)->'user_override'->>'applied') = 'true' THEN
        INSERT INTO public.user_learning_states (user_id, category, override_count_30d, last_override_at)
        VALUES (
            NEW.recipient_id, 
            COALESCE((NEW.meta::jsonb)->>'scenario', 'chat'), 
            1, 
            now()
        )
        ON CONFLICT (user_id, category) DO UPDATE SET
            override_count_30d = user_learning_states.override_count_30d + 1,
            last_override_at = now(),
            learning_paused = CASE WHEN user_learning_states.override_count_30d + 1 >= 5 THEN true ELSE user_learning_states.learning_paused END,
            reason = CASE WHEN user_learning_states.override_count_30d + 1 >= 5 THEN 'EXCESSIVE_OVERRIDES' ELSE user_learning_states.reason END;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Re-link Trigger
DROP TRIGGER IF EXISTS tr_routing_logs_learning_guard ON public.routing_logs;
CREATE TRIGGER tr_routing_logs_learning_guard
AFTER INSERT ON public.routing_logs
FOR EACH ROW EXECUTE FUNCTION public.fn_update_learning_state_on_override();

-- 3. Update Dependent Views (Robustness)
-- Re-creating views with explicit casting to ensure they never fail regardless of column type.

-- View: system_integrity_audit
CREATE OR REPLACE VIEW public.system_integrity_audit AS
SELECT 
    l.message_id,
    l.recipient_id as user_id,
    l.decision,
    l.reason,
    (l.meta::jsonb)->>'scenario' as category,
    ((l.meta::jsonb)->'user_override'->>'applied')::boolean as override_applied,
    ((l.meta::jsonb)->'stage_o'->>'confidence_level') as ai_confidence,
    CASE 
        WHEN ((l.meta::jsonb)->'user_override'->>'applied')::boolean = true AND l.decision IN ('silent', 'throttled', 'bundled') THEN 'ALERT: OVERRIDE_VIOLATION'
        WHEN ((l.meta::jsonb)->'stage_o'->>'learning_status') = 'ACTIVE' AND (l.priority = 'critical' OR l.reason = 'CRITICAL_BYPASS') THEN 'ALERT: CRITICAL_LEARNING_VIOLATION'
        WHEN ((l.meta::jsonb)->'stage_o'->>'confidence_level') = 'LOW' AND ((l.meta::jsonb)->'stage_o'->>'learning_status') = 'ACTIVE' THEN 'ALERT: LOW_CONFIDENCE_DRIFT'
        ELSE 'OK'
    END as integrity_status
FROM public.routing_logs l
WHERE l.created_at > now() - interval '24 hours';

-- View: ai_enterprise_noise_dashboard (The one that blocked the ALTER TABLE)
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
    public.routing_logs l ON (l.meta::jsonb)->>'workspace_id' = s.id::text 
GROUP BY 
    s.id, s.name;

COMMIT;

-- Final Step: Reload PostgREST
NOTIFY pgrst, 'reload schema';
