-- ==========================================
-- PROFESSIONAL CHAT SYSTEM: CONSOLIDATED RPCs
-- ==========================================

BEGIN;

-- 1. REACTION TOGGLE LOGIC
-- "Add if new, Remove if same, Update if different"
CREATE OR REPLACE FUNCTION public.fn_toggle_reaction(
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
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- Security Check: Is user a participant?
    IF NOT EXISTS (
        SELECT 1 FROM public.conversation_participants 
        WHERE conversation_id = p_chat_id AND user_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Not a participant';
    END IF;

    SELECT emoji INTO v_existing_emoji
    FROM public.reactions
    WHERE message_id = p_message_id AND user_id = v_user_id;

    IF v_existing_emoji IS NULL THEN
        -- Case: New Reaction
        INSERT INTO public.reactions (message_id, chat_id, user_id, emoji)
        VALUES (p_message_id, p_chat_id, v_user_id, p_emoji);
    ELSIF v_existing_emoji = p_emoji THEN
        -- Case: Toggle Off
        DELETE FROM public.reactions
        WHERE message_id = p_message_id AND user_id = v_user_id;
    ELSE
        -- Case: Update Emoji
        UPDATE public.reactions
        SET emoji = p_emoji, created_at = now()
        WHERE message_id = p_message_id AND user_id = v_user_id;
    END IF;
END;
$$;

-- 2. REACTION CACHE SYNC (TRIGGER)
-- Updates messages.reactions cache { "userId": "emoji" }
CREATE OR REPLACE FUNCTION public.sync_message_reactions_v2()
RETURNS trigger AS $$
DECLARE
    target_msg_id uuid;
    aggregated_reactions jsonb;
BEGIN
    target_msg_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.message_id ELSE NEW.message_id END;

    SELECT jsonb_object_agg(user_id, emoji)
    INTO aggregated_reactions
    FROM public.reactions
    WHERE message_id = target_msg_id;

    UPDATE public.messages
    SET reactions = COALESCE(aggregated_reactions, '{}'::jsonb)
    WHERE id = target_msg_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- APPLY TRIGGERS
DROP TRIGGER IF EXISTS on_reaction_change_v2 ON public.reactions;
CREATE TRIGGER on_reaction_change_v2
    AFTER INSERT OR UPDATE OR DELETE ON public.reactions
    FOR EACH ROW EXECUTE FUNCTION public.sync_message_reactions_v2();

-- 3. STATUS UPDATE (SINGLE)
CREATE OR REPLACE FUNCTION public.fn_update_message_status(
    p_message_id uuid,
    p_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    UPDATE public.messages
    SET status = p_status
    WHERE id = p_message_id 
      AND EXISTS (
          SELECT 1 FROM public.conversation_participants cp 
          WHERE cp.conversation_id = messages.chat_id AND cp.user_id = auth.uid()
      )
      AND (status <> 'read' OR p_status = 'read'); -- Atomic progression
END;
$$;

-- 4. MARK CHAT AS READ (BULK)
CREATE OR REPLACE FUNCTION public.fn_mark_chat_as_read(
    p_chat_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- Update messages table
    UPDATE public.messages
    SET status = 'read'
    WHERE chat_id = p_chat_id 
      AND sender_id <> auth.uid()
      AND status <> 'read';

    -- Update delivery table if it exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'message_delivery') THEN
        UPDATE public.message_delivery
        SET status = 'read', read_at = now()
        WHERE message_id IN (SELECT id FROM public.messages WHERE chat_id = p_chat_id)
          AND user_id = auth.uid()
          AND status <> 'read';
    END IF;
END;
$$;

-- 5. DELETE FOR ME
CREATE OR REPLACE FUNCTION public.fn_delete_message_for_me(
    p_message_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    UPDATE public.messages
    SET deleted_for = COALESCE(deleted_for, '{}'::jsonb) || jsonb_build_object(auth.uid()::text, true)
    WHERE id = p_message_id
      AND EXISTS (
          SELECT 1 FROM public.conversation_participants cp 
          WHERE cp.conversation_id = messages.chat_id AND cp.user_id = auth.uid()
      );
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
