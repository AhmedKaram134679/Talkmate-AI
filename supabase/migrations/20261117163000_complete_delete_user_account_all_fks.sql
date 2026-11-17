-- Migration: 20261117163000_complete_delete_user_account_all_fks.sql
-- Description: Complete cascading clean-up for delete_user_account covering all 18 foreign keys referencing profiles and conversations

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

    -- 4. Analytics, settings, logs, and learning states
    DELETE FROM public.ai_confidence_metrics WHERE user_id = v_user_id;
    DELETE FROM public.notification_analytics WHERE user_id = v_user_id;
    DELETE FROM public.user_notification_settings_fine_grained WHERE user_id = v_user_id;
    DELETE FROM public.user_learning_states WHERE user_id = v_user_id;
    DELETE FROM public.user_reaction_logs WHERE user_id = v_user_id;

    -- 5. Reactions: user's reactions or reactions in conversations created by user
    DELETE FROM public.reactions 
    WHERE user_id = v_user_id 
       OR chat_id IN (SELECT id FROM public.conversations WHERE creator_id = v_user_id);

    -- 6. Messages cleanup
    -- 6.a Nullify self-referencing reply_to_message_id
    UPDATE public.messages SET reply_to_message_id = NULL 
    WHERE reply_to_message_id IN (
        SELECT id FROM public.messages 
        WHERE sender_id = v_user_id 
           OR chat_id IN (SELECT id FROM public.conversations WHERE creator_id = v_user_id)
    );

    -- 6.b Dependent message analytics
    DELETE FROM public.message_analytics 
    WHERE message_id IN (
        SELECT id FROM public.messages 
        WHERE sender_id = v_user_id 
           OR chat_id IN (SELECT id FROM public.conversations WHERE creator_id = v_user_id)
    );

    -- 6.c Delete messages sent by user
    DELETE FROM public.messages WHERE sender_id = v_user_id;

    -- 7. Conversations cleanup
    -- 7.a Nullify conversations where user was last_message_sender_id
    UPDATE public.conversations SET last_message_sender_id = NULL WHERE last_message_sender_id = v_user_id;

    -- 7.b Delete participant rows and messages for conversations created by user
    DELETE FROM public.conversation_participants 
    WHERE conversation_id IN (SELECT id FROM public.conversations WHERE creator_id = v_user_id);

    DELETE FROM public.messages 
    WHERE chat_id IN (SELECT id FROM public.conversations WHERE creator_id = v_user_id);

    -- 7.c Delete conversations created by user
    DELETE FROM public.conversations WHERE creator_id = v_user_id;

    -- 8. Remove remaining conversation participation for this user
    DELETE FROM public.conversation_participants WHERE user_id = v_user_id;

    -- 9. Remove user calls
    DELETE FROM public.calls 
    WHERE sender_id = v_user_id OR receiver_id = v_user_id OR caller_id = v_user_id OR callee_id = v_user_id;

    -- 10. Remove user search rate limits and caching
    DELETE FROM public.user_search_rate_limits WHERE user_id = v_user_id;

    -- 11. Delete public profile
    DELETE FROM public.profiles WHERE id = v_user_id;

    -- 12. Delete core auth user account from auth.users (cascades sessions, identities, MFA)
    DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_user_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;
