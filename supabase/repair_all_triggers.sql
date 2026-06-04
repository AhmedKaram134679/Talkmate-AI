-- COMPREHENSIVE TRIGGER & FUNCTION REPAIR (Snake vs Camel Case)
-- This script fixes all shared logical functions to use quoted "chatId" and "senderId".

BEGIN;

-- 1. Fix seed_message_delivery (delivery_system.sql)
CREATE OR REPLACE FUNCTION public.seed_message_delivery()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.message_delivery (message_id, user_id, device_id, status)
  SELECT NEW.id, ud.user_id, ud.device_id, 'sent'
  FROM public.conversation_participants cp
  JOIN public.user_devices ud ON ud.user_id = cp.user_id
  WHERE cp.conversation_id = NEW."chatId"
    AND cp.user_id <> NEW."senderId"
    AND ud.device_id IS NOT NULL;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Fix sync_analytics_trigger (analytics_schema.sql)
CREATE OR REPLACE FUNCTION public.sync_analytics_trigger()
RETURNS trigger AS $$
DECLARE
  v_chat_id uuid;
  v_sender_id uuid;
  v_receiver_id uuid;
BEGIN
  IF (TG_OP = 'INSERT') THEN
    -- Fetch denormalized data using CORRECT QUOTED Case
    SELECT "chatId", "senderId"
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

-- 3. Fix mark_chat_read (delivery_system.sql)
CREATE OR REPLACE FUNCTION public.mark_chat_read(
  p_chat_id text,
  p_device_id text
)
RETURNS void AS $$
BEGIN
  UPDATE public.message_delivery md
  SET status = 'read',
      read_at = now()
  FROM public.messages m
  WHERE m."chatId" = p_chat_id::uuid
    AND md.message_id = m.id
    AND md.device_id = p_device_id
    AND md.status <> 'read';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;

-- Reload Schema
NOTIFY pgrst, 'reload schema';
