-- ==========================================
-- NUCLEAR FIX: COLUMN NAMING UNIFICATION
-- Fixes chatId -> chat_id and senderId -> sender_id
-- ==========================================

BEGIN;

-- 1. Fix seed_message_delivery
CREATE OR REPLACE FUNCTION public.seed_message_delivery()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.message_delivery (message_id, user_id, device_id, status)
  SELECT NEW.id, ud.user_id, ud.device_id, 'sent'
  FROM public.conversation_participants cp
  JOIN public.user_devices ud ON ud.user_id = cp.user_id
  WHERE cp.conversation_id = NEW.chat_id
    AND cp.user_id <> NEW.sender_id
    AND ud.device_id IS NOT NULL;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Fix mark_chat_read (Universal Multi-Device Version from ARCH V6)
CREATE OR REPLACE FUNCTION public.mark_chat_read(
  p_chat_id text,
  p_device_id text -- kept for signature compatibility
)
RETURNS void AS $$
DECLARE
    v_user_id uuid := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN RETURN; END IF;

    -- Note: We update for ALL devices of the current user
    UPDATE public.message_delivery md
    SET status = 'read',
        read_at = now()
    FROM public.messages m
    WHERE m.chat_id = p_chat_id::uuid
      AND md.message_id = m.id
      AND md.user_id = v_user_id
      AND md.status <> 'read';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Fix sync_analytics_trigger
CREATE OR REPLACE FUNCTION public.sync_analytics_trigger()
RETURNS trigger AS $$
DECLARE
  v_chat_id uuid;
  v_sender_id uuid;
  v_receiver_id uuid;
BEGIN
  IF (TG_OP = 'INSERT') THEN
    SELECT chat_id, sender_id
    INTO v_chat_id, v_sender_id
    FROM public.messages 
    WHERE id = NEW.message_id;

    v_receiver_id := NEW.user_id;

    INSERT INTO public.message_analytics (
      message_id,
      chat_id,
      sender_id,
      receiver_id,
      device_id,
      status,
      delivered_at,
      read_at
    ) VALUES (
      NEW.message_id,
      v_chat_id,
      v_sender_id,
      v_receiver_id,
      NEW.device_id,
      NEW.status,
      NEW.delivered_at,
      NEW.read_at
    );
  ELSIF (TG_OP = 'UPDATE') THEN
    UPDATE public.message_analytics
    SET status = NEW.status,
        delivered_at = NEW.delivered_at,
        read_at = NEW.read_at,
        updated_at = now()
    WHERE message_id = NEW.message_id 
      AND device_id = NEW.device_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Fix on_participant_removed_cleanup
CREATE OR REPLACE FUNCTION public.on_participant_removed_cleanup()
RETURNS trigger AS $$
BEGIN
    DELETE FROM public.message_delivery
    WHERE user_id = OLD.user_id
      AND message_id IN (
          SELECT id FROM public.messages WHERE chat_id = OLD.conversation_id
      );
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;

NOTIFY pgrst, 'reload schema';
