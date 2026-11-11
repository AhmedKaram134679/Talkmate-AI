-- ==========================================
-- NOTIFICATION SYSTEM RECOVERY SCRIPT
-- Resolves missing 'notifications' table error
-- ==========================================

BEGIN;

-- 1. Create Notifications Table
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    title TEXT,
    body TEXT,
    data JSONB DEFAULT '{}'::jsonb,
    read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Create Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at DESC);

-- 3. Enable RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policies (same set as migrations/20261111_security_hardening_v2.sql)
DROP POLICY IF EXISTS "Users can view their own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update their own notifications" ON public.notifications;
DROP POLICY IF EXISTS "System can insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "notifications_select_own" ON public.notifications;
DROP POLICY IF EXISTS "notifications_update_own" ON public.notifications;
DROP POLICY IF EXISTS "notifications_delete_own" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_related" ON public.notifications;

CREATE POLICY "notifications_select_own" ON public.notifications
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "notifications_update_own" ON public.notifications
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "notifications_delete_own" ON public.notifications
    FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- Was: WITH CHECK (true) for every role, so anyone could create notifications
-- for any user. Now: only toward yourself, a friend, or a user who shares a
-- conversation with you. service_role bypasses RLS for server-side senders.
CREATE POLICY "notifications_insert_related" ON public.notifications
    FOR INSERT TO authenticated
    WITH CHECK (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.friends f
            WHERE (f.user_id = auth.uid() AND f.friend_id = notifications.user_id)
               OR (f.friend_id = auth.uid() AND f.user_id = notifications.user_id)
        )
        OR EXISTS (
            SELECT 1
            FROM public.conversation_participants a
            JOIN public.conversation_participants b
              ON b.conversation_id = a.conversation_id
            WHERE a.user_id = auth.uid()
              AND b.user_id = notifications.user_id
        )
    );

-- 5. Enable Realtime
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'notifications'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
        END IF;
    END IF;
END $$;

-- 6. Routing Logs Table (Telemetry)
CREATE TABLE IF NOT EXISTS public.routing_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    decision TEXT NOT NULL, -- 'sent', 'throttled', 'silent', 'digest'
    reason TEXT,
    priority TEXT DEFAULT 'normal',
    meta JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_routing_logs_recipient_id ON public.routing_logs(recipient_id);
CREATE INDEX IF NOT EXISTS idx_routing_logs_created_at ON public.routing_logs(created_at DESC);

ALTER TABLE public.routing_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own routing logs" ON public.routing_logs;
DROP POLICY IF EXISTS "routing_logs_select_own" ON public.routing_logs;
CREATE POLICY "routing_logs_select_own" ON public.routing_logs
    FOR SELECT TO authenticated
    USING (recipient_id = auth.uid() OR decision = 'system');

COMMIT;

-- Force Schema Cache Reload
NOTIFY pgrst, 'reload schema';
