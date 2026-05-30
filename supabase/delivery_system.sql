-- STAGE Y: DELIVERY & READ RECEIPTS SYSTEM

-- 1. Message Delivery Tracking Table
CREATE TABLE IF NOT EXISTS public.message_delivery (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  device_id text NOT NULL,
  status text NOT NULL CHECK (status IN ('sent','delivered','read')),
  delivered_at timestamptz,
  read_at timestamptz,
  created_at timestamptz DEFAULT now(),
  UNIQUE (message_id, device_id)
);

-- 2. Trigger to Seed Delivery Rows (Status = 'sent')
CREATE OR REPLACE FUNCTION public.seed_message_delivery()
RETURNS trigger AS $$
BEGIN
  -- Insert a 'sent' row for each device of the message receiver(s)
  INSERT INTO public.message_delivery (message_id, user_id, device_id, status)
  SELECT NEW.id, ud.user_id, ud.device_id, 'sent'
  FROM public.conversation_participants cp
  JOIN public.user_devices ud ON ud.user_id = cp.user_id
  WHERE cp.conversation_id = NEW."chatId"
    AND cp.user_id <> NEW."senderId"
    AND ud.device_id IS NOT NULL; -- Exclude invalid devices
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_message_insert_delivery ON public.messages;
CREATE TRIGGER on_message_insert_delivery
AFTER INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.seed_message_delivery();

-- 3. RPC to Mark Chat as Read (Per Device)
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
