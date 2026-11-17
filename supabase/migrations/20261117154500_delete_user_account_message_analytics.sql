-- Migration: 20261117154500_delete_user_account_message_analytics.sql
-- Description: Cascading clean-up for message_analytics and dependent records in delete_user_account

CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_user_id uuid := auth.uid();
BEGIN
    -- 1. Ensure authenticated caller (derives identity exclusively from auth.uid())
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required'
            USING ERRCODE = '42501';
    END IF;

    -- 2. Remove user devices and tokens
    DELETE FROM public.user_devices WHERE user_id = v_user_id;

    -- 3. Remove friend requests and friendships
    DELETE FROM public.friends WHERE user_id = v_user_id OR friend_id = v_user_id;
    DELETE FROM public.friend_requests WHERE sender_id = v_user_id OR receiver_id = v_user_id;

    -- 4. Delete dependent analytics on messages
    DELETE FROM public.message_analytics 
    WHERE message_id IN (
        SELECT id FROM public.messages 
        WHERE sender_id = v_user_id 
           OR chat_id IN (SELECT id FROM public.conversations WHERE creator_id = v_user_id)
    );

    -- 5. Delete messages sent by user
    DELETE FROM public.messages WHERE sender_id = v_user_id;

    -- 6. Delete participant rows in user's created conversations & clean up those conversations
    DELETE FROM public.conversation_participants 
    WHERE conversation_id IN (SELECT id FROM public.conversations WHERE creator_id = v_user_id);

    DELETE FROM public.messages 
    WHERE chat_id IN (SELECT id FROM public.conversations WHERE creator_id = v_user_id);

    DELETE FROM public.conversations WHERE creator_id = v_user_id;

    -- 7. Remove remaining conversation participation for this user
    DELETE FROM public.conversation_participants WHERE user_id = v_user_id;

    -- 8. Remove user calls
    DELETE FROM public.calls 
    WHERE sender_id = v_user_id OR receiver_id = v_user_id OR caller_id = v_user_id OR callee_id = v_user_id;

    -- 9. Remove user search rate limits and caching
    DELETE FROM public.user_search_rate_limits WHERE user_id = v_user_id;

    -- 10. Delete public profile
    DELETE FROM public.profiles WHERE id = v_user_id;

    -- 11. Delete core auth user account from auth.users (cascades sessions, identities, MFA)
    DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_user_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;
