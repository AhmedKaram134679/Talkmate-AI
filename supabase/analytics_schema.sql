-- STAGE B: ANALYTICS & INSIGHTS SCHEMA

-- 1. Analytics Table (Historical Data)
CREATE TABLE IF NOT EXISTS public.message_analytics (
  analytics_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.messages(id),
  chat_id uuid NOT NULL, -- Denormalized for query speed
  sender_id uuid NOT NULL,
  receiver_id uuid NOT NULL, -- Derived from user_devices or message data
  device_id text NOT NULL,
  status text NOT NULL CHECK (status IN ('sent','delivered','read')),
  delivered_at timestamptz,
  read_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Index for fast reporting
CREATE INDEX IF NOT EXISTS idx_analytics_created_at ON public.message_analytics(created_at);
CREATE INDEX IF NOT EXISTS idx_analytics_chat_device ON public.message_analytics(chat_id, device_id);

-- 2. Trigger Function to Sync from message_delivery
CREATE OR REPLACE FUNCTION public.sync_analytics_trigger()
RETURNS trigger AS $$
DECLARE
  v_chat_id uuid;
  v_sender_id uuid;
  v_receiver_id uuid;
BEGIN
  -- On INSERT (New delivery row created)
  IF (TG_OP = 'INSERT') THEN
    -- Fetch denormalized data from messages table
    SELECT "chatId", "senderId"
    INTO v_chat_id, v_sender_id
    FROM public.messages 
    WHERE id = NEW.message_id;

    v_receiver_id := NEW.user_id; -- The recipient is known in message_delivery

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
  
  -- On UPDATE (Status changed to delivered/read)
  ELSIF (TG_OP = 'UPDATE') THEN
    -- Update existing analytics row for this message/device combo
    -- Note: We match on message_id + device_id. 
    -- If multiple rows exist (unlikely), we update the latest or specific one. 
    -- Assuming 1:1 mapping ideally, but analytics is append-only log conceptually?
    -- Actually, let's update the existing record to mirror the current state.
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

-- 3. Trigger Definition
DROP TRIGGER IF EXISTS on_message_delivery_sync ON public.message_delivery;
CREATE TRIGGER on_message_delivery_sync
AFTER INSERT OR UPDATE ON public.message_delivery
FOR EACH ROW EXECUTE FUNCTION public.sync_analytics_trigger();

-- 4. Reporting Views / RPCs

-- Daily Stats View
CREATE OR REPLACE VIEW public.analytics_daily_stats AS
SELECT 
  date_trunc('day', created_at) as report_date,
  count(*) as total_messages,
  count(*) FILTER (WHERE status = 'delivered' OR status = 'read') as total_delivered,
  count(*) FILTER (WHERE status = 'read') as total_read
FROM public.message_analytics
GROUP BY 1
ORDER BY 1 DESC;

-- RPC: Get Device Performance (For Admin/Debug)
CREATE OR REPLACE FUNCTION public.get_device_report(p_user_id uuid)
RETURNS TABLE (
  device_id text,
  total_sent bigint,
  total_delivered bigint,
  total_read bigint
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ma.device_id,
    count(*) as total_sent,
    count(*) FILTER (WHERE ma.status = 'delivered' OR ma.status = 'read') as total_delivered,
    count(*) FILTER (WHERE ma.status = 'read') as total_read
  FROM public.message_analytics ma
  WHERE ma.receiver_id = p_user_id
  GROUP BY ma.device_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
