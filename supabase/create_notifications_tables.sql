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

-- 4. RLS Policies
DROP POLICY IF EXISTS "Users can view their own notifications" ON public.notifications;
CREATE POLICY "Users can view their own notifications" 
    ON public.notifications FOR SELECT 
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own notifications" ON public.notifications;
CREATE POLICY "Users can update their own notifications" 
    ON public.notifications FOR UPDATE 
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "System can insert notifications" ON public.notifications;
CREATE POLICY "System can insert notifications" 
    ON public.notifications FOR INSERT 
    WITH CHECK (true); -- Usually restricted to service_role in production, but open for dev

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
CREATE POLICY "Users can view their own routing logs" ON public.routing_logs FOR SELECT USING (auth.uid() = recipient_id);

COMMIT;

-- Force Schema Cache Reload
NOTIFY pgrst, 'reload schema';
