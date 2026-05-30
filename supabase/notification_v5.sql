-- ==========================================
-- PROFESSIONAL NOTIFICATION & BADGE SYSTEM V5
-- BACKEND-CALCULATED UNREAD COUNTERS & ANALYTICS
-- ==========================================

BEGIN;

-- 1. Unread Count Function (Global)
-- This function calculates the total number of unread messages across all chats
-- for a specific user, based on the message_delivery table.
CREATE OR REPLACE FUNCTION public.fn_get_total_unread_count(p_user_id uuid)
RETURNS bigint AS $$
DECLARE
    v_count bigint;
BEGIN
    SELECT count(*)
    INTO v_count
    FROM public.message_delivery
    WHERE user_id = p_user_id
      AND status <> 'read';
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Optimized View for Dashboard
CREATE OR REPLACE VIEW public.view_user_unread_counts AS
SELECT 
    user_id,
    count(*) as unread_total
FROM public.message_delivery
WHERE status <> 'read'
GROUP BY user_id;

-- 3. Notification Analytics Table
-- Tracks the lifecycle of a notification: delivered, opened, dismissed.
CREATE TABLE IF NOT EXISTS public.notification_analytics (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
    event_type text NOT NULL CHECK (event_type IN ('delivered', 'opened', 'dismissed', 'received')),
    platform text,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notification_analytics_user ON public.notification_analytics(user_id);
CREATE INDEX IF NOT EXISTS idx_notification_analytics_event ON public.notification_analytics(event_type);
CREATE INDEX IF NOT EXISTS idx_notification_analytics_created ON public.notification_analytics(created_at);

-- 4. Enable Realtime for Badge Sync
-- This allows Flutter to subscribe to changes in message_delivery
-- and update the app badge locally when another device marks a chat as read.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables 
            WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'message_delivery'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.message_delivery;
        END IF;
    END IF;
END $$;

-- 5. Helper RPC for Analytics logging (Flutter -> Supabase)
CREATE OR REPLACE FUNCTION public.fn_log_notification_event(
    p_message_id uuid,
    p_event_type text,
    p_platform text,
    p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void AS $$
BEGIN
    INSERT INTO public.notification_analytics (user_id, message_id, event_type, platform, metadata)
    VALUES (auth.uid(), p_message_id, p_event_type, p_platform, p_metadata);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
