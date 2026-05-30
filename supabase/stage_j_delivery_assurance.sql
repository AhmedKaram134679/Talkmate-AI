-- Stage J: Delivery Assurance & Fallback Layer Schema
-- Purpose: Ensure zero message loss and multi-channel fallback.

BEGIN;

-- 1. Notification Inbox (Persistent Store)
CREATE TABLE IF NOT EXISTS public.notification_inbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    chat_id UUID, -- For context
    message_id UUID,
    title TEXT,
    body TEXT,
    scenario TEXT DEFAULT 'chat', -- 'chat', 'system', 'marketing', 'critical'
    priority TEXT DEFAULT 'normal', -- 'normal', 'high', 'critical'
    original_decision TEXT, -- 'sent', 'throttled', 'silent'
    delivered_via TEXT DEFAULT 'inbox', -- 'fcm', 'inbox', 'email', 'sms'
    fallback_used BOOLEAN DEFAULT false,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    metadata JSONB DEFAULT '{}'
);

-- 2. Indices for Performance
CREATE INDEX IF NOT EXISTS idx_notification_inbox_user_id ON public.notification_inbox(user_id);
CREATE INDEX IF NOT EXISTS idx_notification_inbox_unread ON public.notification_inbox(user_id) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_notification_inbox_message_id ON public.notification_inbox(message_id);

-- 3. Delivery Status Machine (Extension to routing_logs)
-- We add columns to routing_logs instead of a new table to keep it centralized
ALTER TABLE public.routing_logs 
ADD COLUMN IF NOT EXISTS delivery_state TEXT DEFAULT 'pending', -- 'pending', 'sent', 'delivered', 'failed', 'fallback_used'
ADD COLUMN IF NOT EXISTS fallback_channel TEXT,
ADD COLUMN IF NOT EXISTS delivery_error JSONB;

-- 4. RLS Policies
ALTER TABLE public.notification_inbox ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own inbox" ON public.notification_inbox;
CREATE POLICY "Users can view their own inbox"
    ON public.notification_inbox FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own read status" ON public.notification_inbox;
CREATE POLICY "Users can update their own read status"
    ON public.notification_inbox FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 5. Helper View for Inbox Stats
CREATE OR REPLACE VIEW public.user_inbox_stats AS
SELECT 
    user_id,
    count(*) as total_notifications,
    count(*) filter (where read_at is null) as unread_count,
    max(created_at) as last_notification
FROM public.notification_inbox
GROUP BY user_id;

COMMIT;
