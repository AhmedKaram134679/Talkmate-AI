-- ==========================================
-- STAGE VI: ARCHITECTURE HARDENING
-- GHOST BADGES, RACE CONDITIONS, & INTEGRITY 
-- ==========================================

BEGIN;

--------------------------------------------------------------------------------
-- 1. REACTION INTEGRITY (Prevent Double Reactions)
--------------------------------------------------------------------------------
-- Ensure a user can only have ONE reaction record per message.
-- This prevents race conditions and "double reaction" UI artifacts.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'reactions_message_user_unique'
    ) THEN
        ALTER TABLE public.reactions ADD CONSTRAINT reactions_message_user_unique UNIQUE (message_id, user_id);
    END IF;
END $$;

--------------------------------------------------------------------------------
-- 2. GHOST BADGE RESOLUTION (Global Unread Count)
--------------------------------------------------------------------------------
-- Currently, counts per device_id which is wrong for a global badge.
-- New logic: Count distinct messages that are unread for this user.
CREATE OR REPLACE VIEW public.view_user_unread_counts AS
SELECT 
    user_id,
    count(DISTINCT message_id) as unread_total
FROM public.message_delivery
WHERE status <> 'read'
GROUP BY user_id;

-- Optimized Unread Count Function
CREATE OR REPLACE FUNCTION public.fn_get_total_unread_count(p_user_id uuid)
RETURNS bigint AS $$
DECLARE
    v_count bigint;
BEGIN
    SELECT count(DISTINCT message_id)
    INTO v_count
    FROM public.message_delivery
    WHERE user_id = p_user_id
      AND status <> 'read';
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--------------------------------------------------------------------------------
-- 3. MULTI-DEVICE READ SYNC
--------------------------------------------------------------------------------
-- When a user marks a chat as read, it should mark it read for ALL their devices
-- to ensure the "Global Badge" clears universally.
CREATE OR REPLACE FUNCTION public.mark_chat_read(
  p_chat_id text,
  p_device_id text -- kept for signature compatibility
)
RETURNS void AS $$
DECLARE
    v_user_id uuid := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN RETURN; END IF;

    UPDATE public.message_delivery md
    SET status = 'read',
        read_at = now()
    FROM public.messages m
    WHERE m."chatId" = p_chat_id::uuid
      AND md.message_id = m.id
      AND md.user_id = v_user_id
      AND md.status <> 'read';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--------------------------------------------------------------------------------
-- 4. PARTICIPANT CLEANUP TRIGGER
--------------------------------------------------------------------------------
-- Delete unread records if a user is kicked/leaves, so badges don't "ghost".
CREATE OR REPLACE FUNCTION public.on_participant_removed_cleanup()
RETURNS trigger AS $$
BEGIN
    DELETE FROM public.message_delivery
    WHERE user_id = OLD.user_id
      AND message_id IN (
          SELECT id FROM public.messages WHERE "chatId" = OLD.conversation_id
      );
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_on_participant_removed_cleanup ON public.conversation_participants;
CREATE TRIGGER tr_on_participant_removed_cleanup
AFTER DELETE ON public.conversation_participants
FOR EACH ROW EXECUTE FUNCTION public.on_participant_removed_cleanup();

--------------------------------------------------------------------------------
-- 5. PERFORMANCE INDEXING
--------------------------------------------------------------------------------
-- Support fast distinct counts and read receipt updates
CREATE INDEX IF NOT EXISTS idx_message_delivery_user_status ON public.message_delivery(user_id, status);
CREATE INDEX IF NOT EXISTS idx_message_delivery_msg_user ON public.message_delivery(message_id, user_id);

COMMIT;

NOTIFY pgrst, 'reload schema';
