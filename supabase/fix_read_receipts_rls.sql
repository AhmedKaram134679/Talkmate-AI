-- ==========================================
-- SECURE MESSAGE UPDATES FOR PARTICIPANTS
-- ==========================================

BEGIN;

-- 1. RPC to update message status (Read Receipts)
-- Allows recipients to mark messages as delivered/read
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
    -- Security: Only participants can update status
    IF EXISTS (
        SELECT 1 FROM public.messages m
        JOIN public.conversation_participants cp ON cp.conversation_id = m.chat_id
        WHERE m.id = p_message_id AND cp.user_id = auth.uid()
    ) THEN
        -- Optimization: Don't downgrade status (e.g. from read to delivered)
        -- We assume order: sent < delivered < read
        -- But for simplicity, we just check if it's already 'read'
        UPDATE public.messages
        SET status = p_status
        WHERE id = p_message_id 
          AND (status <> 'read' OR p_status = 'read'); -- Can always set to read, but avoid overwriting read with delivered
    ELSE
        RAISE EXCEPTION 'Access denied';
    END IF;
END;
$$;

-- 2. RPC to delete message for current user
-- Fixes RLS issues when recipient tries to update deleted_for column
CREATE OR REPLACE FUNCTION public.fn_delete_message_for_me(
    p_message_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id uuid := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- Security: Only participants can delete
    IF EXISTS (
        SELECT 1 FROM public.messages m
        JOIN public.conversation_participants cp ON cp.conversation_id = m.chat_id
        WHERE m.id = p_message_id AND cp.user_id = v_user_id
    ) THEN
        UPDATE public.messages
        SET deleted_for = COALESCE(deleted_for, '{}'::jsonb) || jsonb_build_object(v_user_id::text, true)
        WHERE id = p_message_id;
    ELSE
        RAISE EXCEPTION 'Access denied';
    END IF;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
