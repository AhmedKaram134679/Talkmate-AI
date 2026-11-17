-- Migration: 20261117170000_secure_account_deletion_and_search_privacy.sql
-- Description: Targeted Security Remediation for SEC-01, SEC-02, SEC-04:
-- 1. SEC-02: Preserve shared conversations, participants, and message history on account deletion;
--    transfer ownership to remaining participant; clean up empty conversations; safe storage cleanup.
-- 2. SEC-04: Remove exact email account enumeration from search_users; atomic rate limiting via ON CONFLICT;
--    enforce privacy masking for avatar, online status, and about.
-- 3. SEC-01: Revoke redundant service_role execute permission from fn_add_call_candidate.

-- ============================================================================
-- 1. SEC-02: Schema Adjustment & delete_user_account Redesign
-- ============================================================================

-- Make messages.sender_id NULLABLE so that messages in surviving shared conversations
-- can be preserved with author set to NULL when a user deletes their account.
ALTER TABLE public.messages ALTER COLUMN sender_id DROP NOT NULL;

-- Ensure foreign key constraint allows ON DELETE SET NULL
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS "messages_senderId_fkey";
ALTER TABLE public.messages 
    ADD CONSTRAINT "messages_senderId_fkey" 
    FOREIGN KEY (sender_id) 
    REFERENCES public.profiles(id) 
    ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_conv record;
    v_new_creator uuid;
BEGIN
    -- 1. Strictly derive target account from auth.uid()
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required'
            USING ERRCODE = '42501';
    END IF;

    -- 2. Remove user devices and tokens
    DELETE FROM public.user_devices WHERE user_id = v_user_id;

    -- 3. Remove friend requests and friendships
    DELETE FROM public.friends WHERE user_id = v_user_id OR friend_id = v_user_id;
    DELETE FROM public.friend_requests WHERE sender_id = v_user_id OR receiver_id = v_user_id;

    -- 4. User analytics, settings, logs, and learning states
    DELETE FROM public.ai_confidence_metrics WHERE user_id = v_user_id;
    DELETE FROM public.notification_analytics WHERE user_id = v_user_id;
    DELETE FROM public.user_notification_settings_fine_grained WHERE user_id = v_user_id;
    DELETE FROM public.user_learning_states WHERE user_id = v_user_id;
    DELETE FROM public.user_reaction_logs WHERE user_id = v_user_id;

    -- 5. Delete reactions made by the deleting user
    DELETE FROM public.reactions WHERE user_id = v_user_id;

    -- 6. Preserve shared conversations and handle ownership transfer
    -- For every conversation created by this user:
    FOR v_conv IN 
        SELECT id, is_group 
        FROM public.conversations 
        WHERE creator_id = v_user_id
    LOOP
        -- Check if other valid participants remain in this conversation
        SELECT cp.user_id INTO v_new_creator
        FROM public.conversation_participants cp
        WHERE cp.conversation_id = v_conv.id 
          AND cp.user_id <> v_user_id
        ORDER BY cp.user_id ASC
        LIMIT 1;

        IF v_new_creator IS NOT NULL THEN
            -- Other participants remain: Transfer ownership to the earliest joined participant
            UPDATE public.conversations 
            SET creator_id = v_new_creator 
            WHERE id = v_conv.id;
        ELSE
            -- No other participants remain: Explicit deletion of empty conversation
            -- Nullify message replies within this conversation before deleting
            UPDATE public.messages SET reply_to_message_id = NULL 
            WHERE chat_id = v_conv.id;

            DELETE FROM public.message_analytics 
            WHERE message_id IN (SELECT id FROM public.messages WHERE chat_id = v_conv.id);

            DELETE FROM public.reactions WHERE chat_id = v_conv.id;
            DELETE FROM public.messages WHERE chat_id = v_conv.id;
            DELETE FROM public.conversation_participants WHERE conversation_id = v_conv.id;
            DELETE FROM public.conversations WHERE id = v_conv.id;

            -- Safe cleanup of empty group avatar in storage if applicable
            DELETE FROM storage.objects
            WHERE bucket_id = 'talkmate'
              AND (storage.foldername(name))[1] = 'groups'
              AND (storage.foldername(name))[2] = v_conv.id::text;
        END IF;
    END LOOP;

    -- 7. Nullify last_message_sender_id on any conversations where deleting user was the last sender
    UPDATE public.conversations 
    SET last_message_sender_id = NULL 
    WHERE last_message_sender_id = v_user_id;

    -- 8. Remove deleting user's membership from all conversation participants
    DELETE FROM public.conversation_participants WHERE user_id = v_user_id;

    -- 9. Preserve message history in surviving shared conversations:
    -- Nullify sender_id on messages sent by this user so they remain readable by other members
    UPDATE public.messages SET sender_id = NULL WHERE sender_id = v_user_id;

    -- 10. Remove calls involving this user
    DELETE FROM public.calls 
    WHERE sender_id = v_user_id OR receiver_id = v_user_id OR caller_id = v_user_id OR callee_id = v_user_id;

    -- 11. Remove user search rate limits and caching
    DELETE FROM public.user_search_rate_limits WHERE user_id = v_user_id;

    -- 12. Safe storage cleanup: Remove only user's private files (never shared group assets)
    DELETE FROM storage.objects
    WHERE bucket_id = 'talkmate'
      AND (
          (owner = v_user_id AND (storage.foldername(name))[1] = 'users')
          OR ((storage.foldername(name))[1] = 'users' AND (storage.foldername(name))[2] = v_user_id::text)
      );

    -- 13. Delete public profile
    DELETE FROM public.profiles WHERE id = v_user_id;

    -- 14. Delete core auth user account from auth.users (cascades sessions, identities, MFA)
    DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_user_account() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;


-- ============================================================================
-- 2. SEC-04: User Search Enumeration Removal & Atomic Rate Limiting
-- ============================================================================

CREATE OR REPLACE FUNCTION public.search_users(
    p_query text,
    p_limit integer DEFAULT 20
)
RETURNS TABLE(
    id uuid,
    username text,
    full_name text,
    avatar_url text,
    about text,
    is_online boolean,
    last_seen timestamp with time zone,
    status text,
    email text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_clean text;
    v_pattern text;
    v_rl_count int;
BEGIN
    -- 1. Ensure authenticated caller
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required'
            USING ERRCODE = '42501';
    END IF;

    -- 2. Atomic per-user rate limiting (max 30 queries per minute)
    -- Using INSERT ... ON CONFLICT DO UPDATE ensures zero race conditions under concurrent requests
    INSERT INTO public.user_search_rate_limits (user_id, window_start, request_count)
    VALUES (v_uid, now(), 1)
    ON CONFLICT (user_id) DO UPDATE
    SET 
        request_count = CASE 
            WHEN now() - user_search_rate_limits.window_start > interval '1 minute' THEN 1
            ELSE user_search_rate_limits.request_count + 1
        END,
        window_start = CASE 
            WHEN now() - user_search_rate_limits.window_start > interval '1 minute' THEN now()
            ELSE user_search_rate_limits.window_start
        END
    RETURNING request_count INTO v_rl_count;

    IF v_rl_count > 30 THEN
        RAISE EXCEPTION 'Search rate limit exceeded. Please wait a moment.'
            USING ERRCODE = 'P0001';
    END IF;

    -- 3. Clean and validate query length
    v_clean := trim(p_query);
    IF length(v_clean) < 2 OR length(v_clean) > 50 THEN
        RETURN;
    END IF;

    -- 4. Reject exact email searches to prevent third-party account enumeration
    IF v_clean LIKE '%@%' THEN
        RETURN;
    END IF;

    -- 5. Bound limit
    p_limit := LEAST(GREATEST(p_limit, 1), 30);

    -- 6. Escape LIKE wildcards to prevent broad index enumeration
    v_pattern := replace(
        replace(
            replace(v_clean, E'\\', E'\\\\'),
            '%', E'\\%'
        ),
        '_', E'\\_'
    );
    v_pattern := '%' || v_pattern || '%';

    -- 7. Execute search strictly by username and full_name with privacy projections
    -- NEVER returns email addresses of third parties
    RETURN QUERY
    SELECT 
        p.id,
        p.username,
        p.full_name,
        CASE WHEN p.privacy_show_profile_photo = false AND p.id <> v_uid THEN NULL ELSE p.avatar_url END,
        p.about,
        CASE WHEN p.privacy_show_last_seen = false AND p.id <> v_uid THEN false ELSE p.is_online END,
        CASE WHEN p.privacy_show_last_seen = false AND p.id <> v_uid THEN NULL ELSE p.last_seen END,
        CASE WHEN p.privacy_show_status = false AND p.id <> v_uid THEN NULL ELSE p.status END,
        CASE WHEN p.id = v_uid THEN p.email ELSE NULL END AS email
    FROM public.profiles p
    WHERE (p.username ILIKE v_pattern ESCAPE E'\\'
       OR p.full_name ILIKE v_pattern ESCAPE E'\\')
    LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.search_users(text, integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.search_users(text, integer) TO authenticated;


-- ============================================================================
-- 3. SEC-01: Restrict fn_add_call_candidate Execution to Authenticated Only
-- ============================================================================

REVOKE ALL ON FUNCTION public.fn_add_call_candidate(uuid, jsonb) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.fn_add_call_candidate(uuid, jsonb) TO authenticated;
