-- Notifications Telemetry & Observability Layer
-- Purpose: Monitor Sent vs Throttled ratios, Peak Hours, and Fatigue Ranking.

-- 1. Notification Delivery Stats (Global Ratio)
CREATE OR REPLACE VIEW public.notification_delivery_stats AS
SELECT 
    decision,
    reason,
    count(*) as event_count,
    round(count(*) * 100.0 / sum(count(*)) OVER (), 2) as percentage
FROM public.routing_logs
WHERE created_at > now() - interval '7 days'
GROUP BY decision, reason;

-- 2. User Fatigue Ranking (Who is most throttled?)
CREATE OR REPLACE VIEW public.user_fatigue_ranking AS
SELECT 
    recipient_id,
    p.username,
    count(*) as throttled_count
FROM public.routing_logs l
JOIN public.profiles p ON l.recipient_id = p.id
WHERE decision = 'throttled'
  AND l.created_at > now() - interval '24 hours'
GROUP BY recipient_id, p.username
ORDER BY throttled_count DESC;

-- 3. Peak Notification Hours (Heatmap logic)
CREATE OR REPLACE VIEW public.peak_notification_hours AS
SELECT 
    EXTRACT(HOUR FROM created_at) as hour_of_day,
    decision,
    count(*) as volume
FROM public.routing_logs
WHERE created_at > now() - interval '7 days'
GROUP BY hour_of_day, decision
ORDER BY hour_of_day ASC;

-- 4. Hourly High-Priority Pressure (Cost Guard context)
CREATE OR REPLACE VIEW public.system_priority_pressure AS
SELECT 
    date_trunc('hour', created_at) as window_start,
    sum(case when priority = 'high' then 1 else 0 end) as high_prio_count,
    sum(case when priority = 'normal' then 1 else 0 end) as normal_prio_count,
    round(sum(case when priority = 'high' then 1 else 0 end)::numeric / count(*), 3) as high_prio_ratio
FROM public.routing_logs
GROUP BY window_start
ORDER BY window_start DESC;

COMMENT ON VIEW public.notification_delivery_stats IS 'Global delivery breakdown for the last 7 days.';
COMMENT ON VIEW public.user_fatigue_ranking IS 'Identifies users most affected by throttling in the last 24 hours.';
COMMENT ON VIEW public.peak_notification_hours IS 'Notification volume distributed by hour of day.';

-- --- STAGE B: PREFERENCE ANALYTICS ---

-- 1. User Preference Distribution
CREATE OR REPLACE VIEW public.user_preference_distribution AS
SELECT 
    pref_style,
    count(*) as user_count,
    round(count(*) * 100.0 / sum(count(*)) over(), 2) as percentage
FROM public.notification_preferences
GROUP BY pref_style;

-- 2. Preference Impact Summary
-- Shows how many notifications were affected by user settings
CREATE OR REPLACE VIEW public.preference_impact_summary AS
SELECT 
    reason,
    count(*) as count,
    round(count(*) * 100.0 / sum(count(*)) over(), 2) as percentage
FROM public.routing_logs
WHERE reason LIKE 'USER_PREF_%'
GROUP BY reason;

-- 3. Critical Reliability Check
-- Verifies that critical priority ALWAYS results in 'sent'
CREATE OR REPLACE VIEW public.critical_reliability_check AS
SELECT 
    priority,
    decision,
    count(*) as count
FROM public.routing_logs
WHERE priority = 'high' OR reason = 'CRITICAL_BYPASS'
GROUP BY priority, decision;

COMMENT ON VIEW public.user_preference_distribution IS 'Distribution of notification styles chosen by users.';
COMMENT ON VIEW public.preference_impact_summary IS 'Impact of user-defined preferences on notification delivery.';
COMMENT ON VIEW public.critical_reliability_check IS 'Verification that high-priority/critical messages are always sent.';
