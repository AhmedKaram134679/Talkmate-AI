-- Stage K: Intelligence Feedback Loop & Delivery Optimization
-- Purpose: Correlate decisions with outcomes and optimize delivery paths.

BEGIN;

-- 1. Decision Outcome Correlation Layer
CREATE TABLE IF NOT EXISTS public.notification_outcomes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    routing_decision TEXT NOT NULL, -- 'sent', 'throttled', 'silent'
    final_channel TEXT NOT NULL, -- 'fcm', 'inbox', 'email', 'sms'
    delivery_state TEXT NOT NULL, -- 'delivered', 'failed', 'fallback_used'
    user_action TEXT DEFAULT 'none', -- 'opened', 'dismissed', 'ignored'
    
    -- Costs (Hypothetical units)
    delivery_cost NUMERIC(10,4) DEFAULT 0.0, -- FCM=0.01, Email=0.05, SMS=0.5
    value_score NUMERIC(10,4) DEFAULT 0.0,
    
    sent_at TIMESTAMPTZ DEFAULT now(),
    delivered_at TIMESTAMPTZ,
    opened_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}',
    
    CONSTRAINT unique_message_user UNIQUE (message_id, user_id)
);

-- 2. Indices for Intelligence Queries
CREATE INDEX IF NOT EXISTS idx_outcomes_user_id ON public.notification_outcomes(user_id);
CREATE INDEX IF NOT EXISTS idx_outcomes_action ON public.notification_outcomes(user_action);
CREATE INDEX IF NOT EXISTS idx_outcomes_sent_at ON public.notification_outcomes(sent_at);

-- 3. Channel Effectiveness Scoring (Rolling 7-Day / 30-Day)
-- This view calculates key performance indicators per user and channel
CREATE OR REPLACE VIEW public.user_channel_effectiveness AS
WITH rolling_stats AS (
    SELECT 
        user_id,
        final_channel,
        count(*) as total_sent,
        count(*) filter (where user_action = 'opened') as total_opened,
        count(*) filter (where user_action = 'dismissed') as total_dismissed,
        avg(extract(epoch from (opened_at - delivered_at))) filter (where opened_at is not null) as avg_time_to_open_sec
    FROM public.notification_outcomes
    WHERE sent_at > now() - interval '30 days'
    GROUP BY user_id, final_channel
)
SELECT 
    user_id,
    final_channel,
    total_sent,
    CASE WHEN total_sent > 0 THEN (total_opened::float / total_sent) ELSE 0 END as open_rate,
    CASE WHEN total_sent > 0 THEN (total_dismissed::float / total_sent) ELSE 0 END as ignore_rate,
    avg_time_to_open_sec
FROM rolling_stats;

-- 4. Delivery Intelligence Dashboard
-- Provides insights into global cost vs value performance
CREATE OR REPLACE VIEW public.delivery_intelligence_dashboard AS
SELECT 
    final_channel,
    routing_decision,
    count(*) as volume,
    avg(open_rate) as avg_open_rate,
    sum(delivery_cost) as total_cost,
    sum(value_score) as cumulative_value,
    CASE WHEN sum(delivery_cost) > 0 THEN (sum(value_score) / sum(delivery_cost)) ELSE 0 END as ROI
FROM (
    SELECT 
        o.*,
        ce.open_rate
    FROM public.notification_outcomes o
    LEFT JOIN public.user_channel_effectiveness ce ON o.user_id = ce.user_id AND o.final_channel = ce.final_channel
) sub
GROUP BY final_channel, routing_decision;

-- 5. RLS (Read-only for users to see their own outcomes if needed)
ALTER TABLE public.notification_outcomes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own outcomes" ON public.notification_outcomes
    FOR SELECT USING (auth.uid() = user_id);

-- 6. RPC: Register Engagement Event
-- Helper to update outcomes from the client or workers
CREATE OR REPLACE FUNCTION public.register_notification_engagement(
    p_message_id UUID,
    p_user_id UUID,
    p_action TEXT -- 'opened', 'dismissed'
) RETURNS VOID AS $$
BEGIN
    UPDATE public.notification_outcomes
    SET 
        user_action = p_action,
        opened_at = CASE WHEN p_action = 'opened' THEN now() ELSE opened_at END,
        value_score = CASE 
            WHEN p_action = 'opened' THEN 1.0 
            WHEN p_action = 'dismissed' THEN 0.0
            ELSE value_score 
        END
    WHERE message_id = p_message_id AND user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
