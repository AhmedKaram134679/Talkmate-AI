-- Stage L: Human-Respectful Intelligence
-- Purpose: Predictive Trust, Quiet Hours Inference, and Contextual Bundling.

BEGIN;

-- 1. User Trust Score Engine
-- Calculates trust based on consistency, complaints, and critical response.
CREATE OR REPLACE VIEW public.user_trust_scores AS
WITH trust_metrics AS (
    SELECT 
        user_id,
        count(*) as total_actions,
        count(*) filter (where user_action = 'opened') as open_count,
        count(*) filter (where user_action = 'dismissed') as dismiss_count,
        count(*) filter (where user_action = 'ignored') as ignore_count,
        -- Consistency: Variance in open times (dummy calculation for now)
        1.0 as consistency_factor 
    FROM public.notification_outcomes
    WHERE sent_at > now() - interval '30 days'
    GROUP BY user_id
)
SELECT 
    user_id,
    LEAST(100, GREATEST(0, (
        (CASE WHEN total_actions > 0 THEN (open_count::float / total_actions) * 60 ELSE 30 END) + -- Engagement Base
        (CASE WHEN total_actions > 0 THEN (1 - (dismiss_count::float / total_actions)) * 30 ELSE 15 END) + -- Respect bonus
        (consistency_factor * 10) -- Reliability bonus
    )))::NUMERIC(5,2) as trust_score
FROM trust_metrics;

-- 2. Predictive Quiet Hours (No Manual Config)
-- Inferred from rolling time buckets (last 30 days)
CREATE OR REPLACE VIEW public.user_quiet_hours_prediction AS
WITH hourly_engagement AS (
    SELECT 
        user_id,
        extract(hour from opened_at) as open_hour,
        count(*) as window_open_count
    FROM public.notification_outcomes
    WHERE opened_at > now() - interval '30 days'
    GROUP BY user_id, open_hour
),
max_engagement AS (
    SELECT user_id, max(window_open_count) as peak_count
    FROM hourly_engagement
    GROUP BY user_id
)
SELECT 
    h.user_id,
    h.open_hour,
    CASE 
        WHEN h.window_open_count < (m.peak_count * 0.1) THEN true -- If < 10% of peak, consider it a quiet hour
        ELSE false 
    END as is_quiet_hour
FROM hourly_engagement h
JOIN max_engagement m ON h.user_id = m.user_id;

-- 3. Context-Aware Notification Bundling
CREATE TABLE IF NOT EXISTS public.notification_bundles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    scenario TEXT NOT NULL, -- same context
    bundle_name TEXT,
    message_ids UUID[] DEFAULT '{}',
    is_flushed BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    flushed_at TIMESTAMPTZ,
    bundle_reason TEXT,
    
    CONSTRAINT unique_active_bundle UNIQUE (user_id, scenario, is_flushed) -- one active bundle per scenario per user
);

-- 4. Trust and Respect Dashboard
CREATE OR REPLACE VIEW public.trust_and_respect_dashboard AS
SELECT 
    avg(trust_score) as avg_global_trust,
    count(distinct user_id) as total_users_tracked,
    (SELECT count(*) FROM public.notification_bundles WHERE is_flushed = false) as active_bundles_count,
    (SELECT count(distinct user_id) FROM public.user_quiet_hours_prediction WHERE is_quiet_hour = true) as users_in_quiet_mode
FROM public.user_trust_scores;

-- 5. RPC: Flush Bundle
CREATE OR REPLACE FUNCTION public.flush_notification_bundle(p_bundle_id UUID) 
RETURNS VOID AS $$
BEGIN
    UPDATE public.notification_bundles
    SET is_flushed = true, flushed_at = now()
    WHERE id = p_bundle_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. RPC: Append to Notification Bundle
-- Finds an active bundle for the user/scenario context or creates one.
CREATE OR REPLACE FUNCTION public.append_to_notification_bundle(
    p_user_id UUID,
    p_message_id UUID,
    p_scenario TEXT,
    p_reason TEXT
) RETURNS VOID AS $$
DECLARE
    v_bundle_id UUID;
BEGIN
    -- Try to find an existing active bundle
    SELECT id INTO v_bundle_id 
    FROM public.notification_bundles 
    WHERE user_id = p_user_id 
      AND scenario = p_scenario 
      AND is_flushed = false
    LIMIT 1;

    IF v_bundle_id IS NULL THEN
        -- Create new bundle
        INSERT INTO public.notification_bundles (user_id, scenario, message_ids, bundle_reason)
        VALUES (p_user_id, p_scenario, ARRAY[p_message_id], p_reason);
    ELSE
        -- Update existing bundle
        UPDATE public.notification_bundles
        SET message_ids = array_append(message_ids, p_message_id),
            bundle_reason = p_reason -- Update reason to latest or keep history
        WHERE id = v_bundle_id;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;

