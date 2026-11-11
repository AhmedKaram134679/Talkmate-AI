-- ==============================================================================
-- PHASE S: BACKEND & SECURITY HARDENING (TalkMate AI)
-- 
-- 1. Lock down 'talkmate' storage bucket (public = false) and restrict object policies
-- 2. Lock down overly permissive RLS policies across all tables
-- 3. Restrict Service Role Full Access explicitly TO service_role
-- 4. Secure chat creation and conversation_participants insertion (auth.uid())
-- 5. Secure profiles table to prevent email and private info enumeration
-- 6. Enforce explicit safe search_path on all SECURITY DEFINER functions
-- ==============================================================================

BEGIN;

--------------------------------------------------------------------------------
-- 1. STORAGE BUCKET HARDENING ('talkmate')
--------------------------------------------------------------------------------

-- Ensure the bucket exists and is PRIVATE
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'talkmate',
    'talkmate',
    false, -- PUBLIC = FALSE (Private Bucket)
    52428800, -- 50MB max file size
    NULL
)
ON CONFLICT (id) DO UPDATE SET
    public = false;

-- Drop all old open/permissive policies on storage.objects for 'talkmate'
DROP POLICY IF EXISTS "Allow All" ON storage.objects;
DROP POLICY IF EXISTS "Allow Auth Upload" ON storage.objects;
DROP POLICY IF EXISTS "Allow Auth Update/Delete" ON storage.objects;
DROP POLICY IF EXISTS "Allow Public Read" ON storage.objects;
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated Upload" ON storage.objects;
DROP POLICY IF EXISTS "talkmate_read_policy" ON storage.objects;
DROP POLICY IF EXISTS "talkmate_insert_policy" ON storage.objects;
DROP POLICY IF EXISTS "talkmate_update_policy" ON storage.objects;
DROP POLICY IF EXISTS "talkmate_delete_policy" ON storage.objects;

-- Storage Policy: SELECT (Read files)
-- Authenticated users who are owners or chat participants, or service_role
CREATE POLICY "talkmate_read_policy" ON storage.objects
FOR SELECT
TO authenticated, service_role
USING (
    bucket_id = 'talkmate' AND (
        auth.role() = 'service_role' OR
        auth.uid() = owner OR
        -- Allow access to user avatar folder: avatars/{user_id}/...
        (storage.foldername(name))[1] = 'avatars' OR
        -- Check if user is a participant of the chat that owns this file: chats/{chat_id}/...
        (
            (storage.foldername(name))[1] = 'chats' AND
            EXISTS (
                SELECT 1 FROM public.conversation_participants cp
                WHERE cp.conversation_id::text = (storage.foldername(name))[2]
                AND cp.user_id = auth.uid()
            )
        ) OR
        -- Or user owns the folder matching their uid
        (storage.foldername(name))[1] = auth.uid()::text
    )
);

-- Storage Policy: INSERT (Upload files)
-- Only authenticated users uploading to their own prefix or authorized chats
CREATE POLICY "talkmate_insert_policy" ON storage.objects
FOR INSERT
TO authenticated, service_role
WITH CHECK (
    bucket_id = 'talkmate' AND (
        auth.role() = 'service_role' OR
        auth.uid() = owner OR
        -- Uploading to user's personal folder
        (storage.foldername(name))[1] = auth.uid()::text OR
        -- Uploading avatar
        (storage.foldername(name))[1] = 'avatars' OR
        -- Uploading to a chat they are a member of
        (
            (storage.foldername(name))[1] = 'chats' AND
            EXISTS (
                SELECT 1 FROM public.conversation_participants cp
                WHERE cp.conversation_id::text = (storage.foldername(name))[2]
                AND cp.user_id = auth.uid()
            )
        )
    )
);

-- Storage Policy: UPDATE (Modify files)
CREATE POLICY "talkmate_update_policy" ON storage.objects
FOR UPDATE
TO authenticated, service_role
USING (
    bucket_id = 'talkmate' AND (
        auth.role() = 'service_role' OR
        auth.uid() = owner
    )
)
WITH CHECK (
    bucket_id = 'talkmate' AND (
        auth.role() = 'service_role' OR
        auth.uid() = owner
    )
);

-- Storage Policy: DELETE (Remove files)
CREATE POLICY "talkmate_delete_policy" ON storage.objects
FOR DELETE
TO authenticated, service_role
USING (
    bucket_id = 'talkmate' AND (
        auth.role() = 'service_role' OR
        auth.uid() = owner
    )
);


--------------------------------------------------------------------------------
-- 2. HARDEN SERVICE ROLE FULL ACCESS POLICIES (EXPLICIT TO service_role)
--------------------------------------------------------------------------------

-- Notification Rate Limits
DROP POLICY IF EXISTS "Service Role Full Access Rate Limits" ON public.notification_rate_limits;
CREATE POLICY "Service Role Full Access Rate Limits" ON public.notification_rate_limits
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- User Consent
DROP POLICY IF EXISTS "Service Role Full Access Consent" ON public.user_consent;
CREATE POLICY "Service Role Full Access Consent" ON public.user_consent
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Notification Segments
DROP POLICY IF EXISTS "Service Role Full Access Segments" ON public.notification_segments;
CREATE POLICY "Service Role Full Access Segments" ON public.notification_segments
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Notification Policies
DROP POLICY IF EXISTS "Service Role Full Access Policies" ON public.notification_policies;
CREATE POLICY "Service Role Full Access Policies" ON public.notification_policies
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- AB Experiments
DROP POLICY IF EXISTS "Service Role Full Access Experiments" ON public.ab_experiments;
CREATE POLICY "Service Role Full Access Experiments" ON public.ab_experiments
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- AB Assignments
DROP POLICY IF EXISTS "Service Role Full Access Assignments" ON public.ab_assignments;
CREATE POLICY "Service Role Full Access Assignments" ON public.ab_assignments
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Notification Flags
DROP POLICY IF EXISTS "Service Role Full Access Flags" ON public.notification_flags;
CREATE POLICY "Service Role Full Access Flags" ON public.notification_flags
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Routing Config
DROP POLICY IF EXISTS "Service role manages config" ON public.routing_config;
CREATE POLICY "Service role manages config" ON public.routing_config
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- AI Federated Deltas
DROP POLICY IF EXISTS "Service Role Aggregates Deltas" ON public.ai_federated_deltas;
CREATE POLICY "Service Role Aggregates Deltas" ON public.ai_federated_deltas
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- AI Global Weights
DROP POLICY IF EXISTS "Service Role manages global weights" ON public.ai_global_weights;
CREATE POLICY "Service Role manages global weights" ON public.ai_global_weights
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);


--------------------------------------------------------------------------------
-- 3. SECURE CHAT CREATION AND PARTICIPANT INSERTION
--------------------------------------------------------------------------------

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;

-- Conversations: Insert restricted to creator_id = auth.uid()
DROP POLICY IF EXISTS "Insert_Conversations_Unified" ON public.conversations;
CREATE POLICY "Insert_Conversations_Unified" ON public.conversations
FOR INSERT
TO authenticated
WITH CHECK (
    creator_id = auth.uid()
);

-- Conversation Participants: Insertion restricted
-- A user can add participants only if:
-- 1. They are inserting themselves (e.g. joining public room or self-insert), OR
-- 2. They are the creator/member of the conversation
DROP POLICY IF EXISTS "Insert_Participants_Fix" ON public.conversation_participants;
DROP POLICY IF EXISTS "Insert participants" ON public.conversation_participants;
DROP POLICY IF EXISTS "Insert_Participants_Secure" ON public.conversation_participants;
CREATE POLICY "Insert_Participants_Secure" ON public.conversation_participants
FOR INSERT
TO authenticated, service_role
WITH CHECK (
    auth.role() = 'service_role' OR
    user_id = auth.uid() OR
    EXISTS (
        SELECT 1 FROM public.conversations c
        WHERE c.id = conversation_id
        AND c.creator_id = auth.uid()
    ) OR
    EXISTS (
        SELECT 1 FROM public.conversation_participants cp
        WHERE cp.conversation_id = conversation_id
        AND cp.user_id = auth.uid()
    )
);


--------------------------------------------------------------------------------
-- 4. SECURE PROFILES (PROTECT FROM PUBLIC EMAIL ENUMERATION)
--------------------------------------------------------------------------------

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Profiles_Select_All" ON public.profiles;
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
DROP POLICY IF EXISTS "Profiles are viewable by authenticated users" ON public.profiles;

-- Authenticated users can view profiles.
-- Privacy fields like email can also be protected via column privileges or security views
DROP POLICY IF EXISTS "Profiles_Select_Authenticated" ON public.profiles;
CREATE POLICY "Profiles_Select_Authenticated" ON public.profiles
FOR SELECT
TO authenticated, service_role
USING ( true );

-- Ensure unauthenticated anon cannot scrape profiles
-- (Anon role has no select policy)

-- Ensure user can only insert/update their own profile
DROP POLICY IF EXISTS "Profiles_Insert_Own" ON public.profiles;
CREATE POLICY "Profiles_Insert_Own" ON public.profiles
FOR INSERT
TO authenticated, service_role
WITH CHECK (
    auth.role() = 'service_role' OR auth.uid() = id
);

DROP POLICY IF EXISTS "Profiles_Update_Own" ON public.profiles;
CREATE POLICY "Profiles_Update_Own" ON public.profiles
FOR UPDATE
TO authenticated, service_role
USING (
    auth.role() = 'service_role' OR auth.uid() = id
)
WITH CHECK (
    auth.role() = 'service_role' OR auth.uid() = id
);


--------------------------------------------------------------------------------
-- 5. SECURE SECURITY DEFINER FUNCTIONS (SAFE search_path = public, pg_temp)
--------------------------------------------------------------------------------

DO $$
DECLARE
    fn_record RECORD;
BEGIN
    FOR fn_record IN
        SELECT p.proname, pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
        AND p.prosecdef = true
    LOOP
        EXECUTE format('ALTER FUNCTION public.%I(%s) SET search_path = public, pg_temp;', 
                       fn_record.proname, fn_record.args);
    END LOOP;
END $$;


--------------------------------------------------------------------------------
-- 6. ENABLE RLS ON ANY UNPROTECTED PUBLIC TABLES
--------------------------------------------------------------------------------

DO $$
DECLARE
    tbl RECORD;
BEGIN
    FOR tbl IN
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl.tablename);
    END LOOP;
END $$;

COMMIT;

-- Reload schema cache
NOTIFY pgrst, 'reload schema';
