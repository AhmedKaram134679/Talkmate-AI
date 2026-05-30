-- ==========================================
-- REALTIME HARDENING & HEALTH FIX
-- Ensured all critical tables are in the publication
-- ==========================================

BEGIN;

-- 1. Ensure the publication exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

-- 2. Add all critical tables to publication
-- Using a loop for cleaner management
DO $$
DECLARE
    table_name text;
    critical_tables text[] := ARRAY['calls', 'notifications', 'message_delivery', 'messages', 'profiles', 'conversations'];
BEGIN
    FOREACH table_name IN ARRAY critical_tables LOOP
        -- Add to publication if not exists
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables 
            WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = table_name
        ) THEN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', table_name);
        END IF;

        -- Set replica identity to DEFAULT or FULL (Realtime needs it for filtering/updates)
        -- FULL ensures we get the old record in update/delete, usually safer for complex UI logic
        EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', table_name);
    END LOOP;
END $$;

-- 3. Security Check: Ensure Realtime is allowed for authenticated users
-- This is often implicit in Supabase but good to verify policies
-- [Note]: RLS policies on tables apply to Realtime too.

COMMIT;

-- Force Cache Reload
NOTIFY pgrst, 'reload schema';
