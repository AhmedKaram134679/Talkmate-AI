-- ==============================================================================
-- SECURITY HARDENING V2 (TalkMate AI)  -  corrective, idempotent migration
--
-- Why this file exists:
--   20261017_phase_s_security_hardening.sql only dropped a few policies by name.
--   Older "fix_*.sql" scripts created other open policies (WITH CHECK (true),
--   USING (true) with no TO clause) that survive, and Postgres ORs permissive
--   policies together, so the old holes stayed open.
--
-- What it does:
--   0. Pre-flight checks (fails early instead of half-applying)
--   1. Drops EVERY existing policy on the sensitive tables, then recreates only
--      the intended ones (conversations, participants, messages, profiles,
--      notifications, routing_logs, storage bucket 'talkmate')
--   2. Removes anon access and closes EXECUTE on admin-only functions
--   3. Makes analytics views respect RLS of the caller
--
-- Assumes the snake_case schema used by the app (messages.chat_id / sender_id).
-- Run once in the Supabase SQL editor or via `supabase db push`.
-- ==============================================================================

BEGIN;

--------------------------------------------------------------------------------
-- 0. PRE-FLIGHT CHECKS
--------------------------------------------------------------------------------
DO $$
DECLARE
    req RECORD;
BEGIN
    IF to_regprocedure('public.is_item_accessible(uuid)') IS NULL THEN
        RAISE EXCEPTION 'public.is_item_accessible(uuid) is missing - create it before running this migration';
    END IF;

    FOR req IN
        SELECT * FROM (VALUES
            ('messages',                  'chat_id'),
            ('messages',                  'sender_id'),
            ('conversations',             'creator_id'),
            ('conversation_participants', 'conversation_id'),
            ('conversation_participants', 'user_id'),
            ('notifications',             'user_id'),
            ('routing_logs',              'recipient_id'),
            ('friends',                   'user_id'),
            ('friends',                   'friend_id')
        ) AS t(tbl, col)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name   = req.tbl
              AND column_name  = req.col
        ) THEN
            RAISE EXCEPTION 'Expected column public.%.% not found', req.tbl, req.col;
        END IF;
    END LOOP;
END $$;


--------------------------------------------------------------------------------
-- 1. DROP ALL LEGACY POLICIES ON SENSITIVE TABLES
--------------------------------------------------------------------------------
DO $$
DECLARE
    p RECORD;
BEGIN
    FOR p IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN (
              'conversations',
              'conversation_participants',
              'messages',
              'profiles',
              'notifications',
              'routing_logs'
          )
    LOOP
        EXECUTE format('DROP POLICY %I ON %I.%I', p.policyname, p.schemaname, p.tablename);
    END LOOP;

    -- Storage: drop every policy that mentions the 'talkmate' bucket
    FOR p IN
        SELECT schemaname, tablename, policyname
        FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename  = 'objects'
          AND (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ILIKE '%talkmate%'
    LOOP
        EXECUTE format('DROP POLICY %I ON %I.%I', p.policyname, p.schemaname, p.tablename);
    END LOOP;
END $$;

ALTER TABLE public.conversations             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routing_logs              ENABLE ROW LEVEL SECURITY;


--------------------------------------------------------------------------------
-- 1.a CONVERSATIONS
-- The creator must be able to read the row right after INSERT ... RETURNING,
-- before the participants rows exist (see SupabaseChatRepository.createChat).
--------------------------------------------------------------------------------
CREATE POLICY "conversations_select" ON public.conversations
FOR SELECT TO authenticated
USING ( creator_id = auth.uid() OR public.is_item_accessible(id) );

CREATE POLICY "conversations_insert" ON public.conversations
FOR INSERT TO authenticated
WITH CHECK ( creator_id = auth.uid() );

CREATE POLICY "conversations_update" ON public.conversations
FOR UPDATE TO authenticated
USING      ( public.is_item_accessible(id) )
WITH CHECK ( public.is_item_accessible(id) );

CREATE POLICY "conversations_delete" ON public.conversations
FOR DELETE TO authenticated
USING ( creator_id = auth.uid() );


--------------------------------------------------------------------------------
-- 1.b CONVERSATION PARTICIPANTS
-- INSERT: only the conversation creator, or an existing member, may add people.
-- (Uses the SECURITY DEFINER helper for the member check to avoid recursion.)
--------------------------------------------------------------------------------
CREATE POLICY "participants_select" ON public.conversation_participants
FOR SELECT TO authenticated
USING ( user_id = auth.uid() OR public.is_item_accessible(conversation_id) );

CREATE POLICY "participants_insert" ON public.conversation_participants
FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id = conversation_participants.conversation_id
          AND c.creator_id = auth.uid()
    )
    OR public.is_item_accessible(conversation_participants.conversation_id)
);

-- A user may change only their own settings (pin / mute / ...)
CREATE POLICY "participants_update_own" ON public.conversation_participants
FOR UPDATE TO authenticated
USING      ( user_id = auth.uid() )
WITH CHECK ( user_id = auth.uid() );

-- A user may leave; the conversation creator may remove members.
CREATE POLICY "participants_delete" ON public.conversation_participants
FOR DELETE TO authenticated
USING (
    user_id = auth.uid()
    OR EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id = conversation_participants.conversation_id
          AND c.creator_id = auth.uid()
    )
);


--------------------------------------------------------------------------------
-- 1.c MESSAGES
-- UPDATE had no WITH CHECK, so a sender could move a message to another chat.
--------------------------------------------------------------------------------
CREATE POLICY "messages_select" ON public.messages
FOR SELECT TO authenticated
USING ( public.is_item_accessible(chat_id) );

CREATE POLICY "messages_insert" ON public.messages
FOR INSERT TO authenticated
WITH CHECK ( sender_id = auth.uid() AND public.is_item_accessible(chat_id) );

CREATE POLICY "messages_update_own" ON public.messages
FOR UPDATE TO authenticated
USING      ( sender_id = auth.uid() )
WITH CHECK ( sender_id = auth.uid() AND public.is_item_accessible(chat_id) );


--------------------------------------------------------------------------------
-- 1.d PROFILES
-- The old "profile_select ... USING (true)" had no TO clause, so anon could
-- read every profile (including emails). Only logged-in users may read now.
-- NOTE: profiles.email is still readable by authenticated users because the app
-- searches users by exact email. Move email out of profiles when you can.
--------------------------------------------------------------------------------
CREATE POLICY "profiles_select_authenticated" ON public.profiles
FOR SELECT TO authenticated
USING ( true );

CREATE POLICY "profiles_insert_own" ON public.profiles
FOR INSERT TO authenticated
WITH CHECK ( auth.uid() = id );

CREATE POLICY "profiles_update_own" ON public.profiles
FOR UPDATE TO authenticated
USING      ( auth.uid() = id )
WITH CHECK ( auth.uid() = id );


--------------------------------------------------------------------------------
-- 1.e NOTIFICATIONS
-- The app inserts notifications for other users from the client
-- (SupabaseNotificationRepository.sendNotification), so inserts are allowed only
-- toward yourself, a friend (any status), or someone who shares a conversation
-- with you. Anyone else can no longer be spammed or phished.
-- Server-side senders use service_role, which bypasses RLS.
--------------------------------------------------------------------------------
CREATE POLICY "notifications_select_own" ON public.notifications
FOR SELECT TO authenticated
USING ( auth.uid() = user_id );

CREATE POLICY "notifications_update_own" ON public.notifications
FOR UPDATE TO authenticated
USING      ( auth.uid() = user_id )
WITH CHECK ( auth.uid() = user_id );

CREATE POLICY "notifications_delete_own" ON public.notifications
FOR DELETE TO authenticated
USING ( auth.uid() = user_id );

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


--------------------------------------------------------------------------------
-- 1.f ROUTING LOGS
-- Users read their own logs (and non-personal 'system' rows such as DATA_PURGE
-- used by the compliance screen). Inserts come from Edge Functions (service_role).
-- Behaviour change: the compliance statistics screen now counts only the
-- caller's own rejected rows, not every user's.
--------------------------------------------------------------------------------
CREATE POLICY "routing_logs_select_own" ON public.routing_logs
FOR SELECT TO authenticated
USING ( recipient_id = auth.uid() OR decision = 'system' );


--------------------------------------------------------------------------------
-- 1.g STORAGE BUCKET 'talkmate' (private)
-- Paths used by the app:
--   users/{uid}/profile_*.jpg
--   groups/temp_*.jpg                    and  groups/{chat_id}/avatar_*.jpg
--   chats/{chat_id}/users/{uid}/{folder}/{file}
-- NOTE: the app stores 24h signed URLs; see the report (they expire).
--------------------------------------------------------------------------------
UPDATE storage.buckets
SET public = false,
    file_size_limit = 52428800            -- 50 MB
WHERE id = 'talkmate';

CREATE POLICY "talkmate_read_policy" ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'talkmate' AND (
        owner = auth.uid()
        OR (storage.foldername(name))[1] IN ('users', 'groups')
        OR (
            (storage.foldername(name))[1] = 'chats' AND EXISTS (
                SELECT 1 FROM public.conversation_participants cp
                WHERE cp.conversation_id::text = (storage.foldername(name))[2]
                  AND cp.user_id = auth.uid()
            )
        )
    )
);

CREATE POLICY "talkmate_insert_policy" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'talkmate' AND (
        -- own profile photo
        (
            (storage.foldername(name))[1] = 'users'
            AND (storage.foldername(name))[2] = auth.uid()::text
        )
        -- group photo: temporary upload (no chat yet) or member of that chat
        OR (
            (storage.foldername(name))[1] = 'groups' AND (
                (storage.foldername(name))[2] IS NULL
                OR EXISTS (
                    SELECT 1 FROM public.conversation_participants cp
                    WHERE cp.conversation_id::text = (storage.foldername(name))[2]
                      AND cp.user_id = auth.uid()
                )
            )
        )
        -- chat media: chats/{chat_id}/users/{my uid}/... and I am a member
        OR (
            (storage.foldername(name))[1] = 'chats'
            AND (storage.foldername(name))[3] = 'users'
            AND (storage.foldername(name))[4] = auth.uid()::text
            AND EXISTS (
                SELECT 1 FROM public.conversation_participants cp
                WHERE cp.conversation_id::text = (storage.foldername(name))[2]
                  AND cp.user_id = auth.uid()
            )
        )
    )
);

-- The app uploads with upsert = true, which needs UPDATE on existing objects.
CREATE POLICY "talkmate_update_policy" ON storage.objects
FOR UPDATE TO authenticated
USING      ( bucket_id = 'talkmate' AND owner = auth.uid() )
WITH CHECK ( bucket_id = 'talkmate' AND owner = auth.uid() );

CREATE POLICY "talkmate_delete_policy" ON storage.objects
FOR DELETE TO authenticated
USING ( bucket_id = 'talkmate' AND owner = auth.uid() );


--------------------------------------------------------------------------------
-- 2. ANON ACCESS AND FUNCTION PRIVILEGES
-- Every RPC the client calls requires a logged-in user:
--   create_ai_weight_snapshot, delete_user_account, fn_add_call_candidate,
--   fn_log_notification_event, fn_mark_chat_as_read, fn_toggle_reaction_v4,
--   fn_update_message_status, register_device_token
-- To roll this section back:  GRANT ALL ON ALL TABLES IN SCHEMA public TO anon;
--------------------------------------------------------------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES    FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;
GRANT  EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon;

-- Server-only functions: callable by service_role only. They take a user id as a
-- parameter, so any logged-in user could otherwise act on behalf of another user.
DO $$
DECLARE
    f RECORD;
BEGIN
    FOR f IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('increment_rate_limit', 'get_device_report')
    LOOP
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', f.sig);
        EXECUTE format('GRANT  EXECUTE ON FUNCTION %s TO service_role', f.sig);
    END LOOP;
END $$;


--------------------------------------------------------------------------------
-- 3. VIEWS MUST RESPECT THE CALLER'S RLS (security_invoker, PostgreSQL 15+)
-- view_user_unread_counts is intentionally left out: the app reads it and its
-- source tables may not have per-user policies yet.
--------------------------------------------------------------------------------
DO $$
DECLARE
    v text;
BEGIN
    FOREACH v IN ARRAY ARRAY[
        'user_trust_scores',
        'user_quiet_hours_prediction',
        'user_inbox_stats',
        'user_device_attention_scores',
        'e2e_user_state'
    ]
    LOOP
        IF to_regclass('public.' || v) IS NOT NULL
           AND (SELECT relkind FROM pg_class WHERE oid = to_regclass('public.' || v)) = 'v'
        THEN
            EXECUTE format('ALTER VIEW public.%I SET (security_invoker = true)', v);
        END IF;
    END LOOP;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

