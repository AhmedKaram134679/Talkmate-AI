-- STAGE I: COST CONTROL & RATE GOVERNANCE

-- 1. Rate Limit Tracking Table
--concept: Simple sliding window or daily buckets for rate control.
CREATE TABLE IF NOT EXISTS public.notification_rate_limits (
    user_id uuid NOT NULL, -- references auth.users
    scenario text NOT NULL, -- 'chat', 'marketing', 'system'
    hourly_count int DEFAULT 0,
    daily_count int DEFAULT 0,
    last_reset_hour timestamptz DEFAULT date_trunc('hour', now()),
    last_reset_day timestamptz DEFAULT date_trunc('day', now()),
    PRIMARY KEY (user_id, scenario)
);

-- RLS for Rate Limits (Service Role only)
ALTER TABLE public.notification_rate_limits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Service Role Full Access Rate Limits" ON public.notification_rate_limits;
CREATE POLICY "Service Role Full Access Rate Limits" ON public.notification_rate_limits USING (true) WITH CHECK (true);


-- 2. Governance Config
INSERT INTO public.routing_config (key, value, description)
VALUES 
('cost_governance', '{
  "high_priority_cost_threshold": 0.3, 
  "evaluation_window_hours": 6,
  "default_hourly_limit": 20,
  "default_daily_limit": 100,
  "scenario_limits": {
    "marketing": {"hourly": 1, "daily": 3},
    "chat": {"hourly": 50, "daily": 250},
    "system": {"hourly": 10, "daily": 50}
  }
}', 'Thresholds for Rate Governing and High-Priority Cost Guards')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- 3. High Priority Ratio View (For Cost Guard)
CREATE OR REPLACE VIEW public.notification_cost_stats AS
SELECT 
    recipient_id as user_id,
    COUNT(*) FILTER (WHERE priority = 'high') as high_priority_count,
    COUNT(*) as total_count,
    CASE 
        WHEN COUNT(*) > 0 THEN (COUNT(*) FILTER (WHERE priority = 'high'))::float / COUNT(*) 
        ELSE 0 
    END as high_priority_ratio
FROM public.routing_logs
WHERE created_at > now() - interval '6 hours' -- evaluation_window
GROUP BY recipient_id;

-- 4. Global Stats (Optional for system-wide cost guard)
CREATE OR REPLACE VIEW public.system_cost_stats AS
SELECT 
    COUNT(*) FILTER (WHERE priority = 'high') as total_high_priority,
    COUNT(*) as total_count,
    (COUNT(*) FILTER (WHERE priority = 'high'))::float / NULLIF(COUNT(*), 0) as system_wide_ratio
FROM public.routing_logs
WHERE created_at > now() - interval '1 hour';

-- 5. RPC: Increment Rate Limit with Auto-Reset
CREATE OR REPLACE FUNCTION public.increment_rate_limit(
    p_user_id uuid,
    p_scenario text
) 
RETURNS void AS $$
DECLARE
    v_now timestamptz := now();
    v_hour timestamptz := date_trunc('hour', v_now);
    v_day timestamptz := date_trunc('day', v_now);
BEGIN
    INSERT INTO public.notification_rate_limits (
        user_id, 
        scenario, 
        hourly_count, 
        daily_count, 
        last_reset_hour, 
        last_reset_day
    )
    VALUES (p_user_id, p_scenario, 1, 1, v_hour, v_day)
    ON CONFLICT (user_id, scenario) DO UPDATE
    SET 
        hourly_count = CASE 
            WHEN public.notification_rate_limits.last_reset_hour < v_hour THEN 1 
            ELSE public.notification_rate_limits.hourly_count + 1 
        END,
        daily_count = CASE 
            WHEN public.notification_rate_limits.last_reset_day < v_day THEN 1 
            ELSE public.notification_rate_limits.daily_count + 1 
        END,
        last_reset_hour = CASE 
            WHEN public.notification_rate_limits.last_reset_hour < v_hour THEN v_hour 
            ELSE public.notification_rate_limits.last_reset_hour 
        END,
        last_reset_day = CASE 
            WHEN public.notification_rate_limits.last_reset_day < v_day THEN v_day 
            ELSE public.notification_rate_limits.last_reset_day 
        END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
