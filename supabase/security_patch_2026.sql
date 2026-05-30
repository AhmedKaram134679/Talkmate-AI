-- ==========================================
-- SECURITY PATCH 2026: RLS & RPC HARDENING
-- ==========================================

BEGIN;

-- 1. Tighten Reactions RLS
ALTER TABLE public.reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Enable read for all" ON public.reactions;
CREATE POLICY "Enable read for participants" ON public.reactions
FOR SELECT USING ( public.is_item_accessible(chat_id) );

-- 2. Harden fn_toggle_reaction_v4
CREATE OR REPLACE FUNCTION public.fn_toggle_reaction_v4(
    p_message_id uuid,
    p_chat_id uuid,
    p_emoji text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_emoji text;
    v_user_id uuid := auth.uid();
    v_recent_count int;
    v_is_deleted boolean;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- Security Check: Is message deleted? (AUDIT FIX)
    SELECT is_deleted INTO v_is_deleted FROM public.messages WHERE id = p_message_id;
    IF v_is_deleted THEN RAISE EXCEPTION 'Cannot react to a deleted message'; END IF;

    -- Anti-Spam Check: Max 10 reaction actions per message per minute per user
    SELECT count(*) INTO v_recent_count
    FROM public.user_reaction_logs
    WHERE user_id = v_user_id 
      AND message_id = p_message_id
      AND created_at > now() - interval '1 minute';

    IF v_recent_count >= 10 THEN
        RAISE EXCEPTION 'Rate limit exceeded for this message. Please wait a moment.';
    END IF;

    -- Log this action
    INSERT INTO public.user_reaction_logs (user_id, message_id)
    VALUES (v_user_id, p_message_id);

    -- Security Check: Is user a participant?
    IF NOT EXISTS (
        SELECT 1 FROM public.conversation_participants 
        WHERE conversation_id = p_chat_id AND user_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Not a participant in this conversation';
    END IF;

    -- Core Logic: Toggle/Update
    SELECT emoji INTO v_existing_emoji
    FROM public.reactions
    WHERE message_id = p_message_id AND user_id = v_user_id;

    IF v_existing_emoji IS NULL THEN
        INSERT INTO public.reactions (message_id, chat_id, user_id, emoji)
        VALUES (p_message_id, p_chat_id, v_user_id, p_emoji);
    ELSIF v_existing_emoji = p_emoji THEN
        DELETE FROM public.reactions
        WHERE message_id = p_message_id AND user_id = v_user_id;
    ELSE
        UPDATE public.reactions
        SET emoji = p_emoji, created_at = now()
        WHERE message_id = p_message_id AND user_id = v_user_id;
    END IF;

    -- Cleanup old logs (Async-like maintenance)
    DELETE FROM public.user_reaction_logs WHERE created_at < now() - interval '1 hour';
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
