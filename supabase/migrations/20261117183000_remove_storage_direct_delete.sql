-- Fix delete_user_account: remove direct SQL DELETE on storage.objects (Supabase blocks direct table deletes on storage)
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_conv record;
    v_new_creator uuid;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required to delete account'
            USING ERRCODE = '42501';
    END IF;

    -- 1. Remove device tokens to prevent push leaks
    DELETE FROM public.user_devices WHERE user_id = v_user_id;

    -- 2. Remove notifications targeting this user
    DELETE FROM public.notifications WHERE user_id = v_user_id;

    -- 3. Remove friend records and friend requests
    DELETE FROM public.friends WHERE user_id = v_user_id OR friend_id = v_user_id;
    DELETE FROM public.friend_requests WHERE sender_id = v_user_id OR receiver_id = v_user_id;

    -- 4. Remove user's reactions
    DELETE FROM public.reactions WHERE user_id = v_user_id;

    -- 5. Remove room memberships (for audio/video rooms)
    DELETE FROM public.room_participants WHERE user_id = v_user_id;

    -- 6. Clean up or transfer conversation ownership:
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
            -- Other participants remain: Transfer ownership to remaining participant
            UPDATE public.conversations 
            SET creator_id = v_new_creator 
            WHERE id = v_conv.id;
        ELSE
            -- No other participants remain: Explicit deletion of empty conversation
            UPDATE public.messages SET reply_to_message_id = NULL 
            WHERE chat_id = v_conv.id;

            DELETE FROM public.message_analytics 
            WHERE message_id IN (SELECT id FROM public.messages WHERE chat_id = v_conv.id);

            DELETE FROM public.reactions WHERE chat_id = v_conv.id;
            DELETE FROM public.messages WHERE chat_id = v_conv.id;
            DELETE FROM public.conversation_participants WHERE conversation_id = v_conv.id;
            DELETE FROM public.conversations WHERE id = v_conv.id;
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

    -- 12. Delete public profile
    DELETE FROM public.profiles WHERE id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_user_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;
