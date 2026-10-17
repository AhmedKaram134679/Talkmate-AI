-- [Stage R-Stability] Call Ringing Push Trigger
-- Automatically triggers push-handler when a call enters 'ringing' state

CREATE OR REPLACE FUNCTION public.notify_call_ringing_push()
RETURNS trigger AS $$
DECLARE
  service_role_key TEXT;
BEGIN
  SELECT decrypted_secret INTO service_role_key 
  FROM vault.decrypted_secrets 
  WHERE name = 'service_role_key' 
  LIMIT 1;

  IF service_role_key IS NULL THEN
    service_role_key := current_setting('app.settings.service_role_key', true);
  END IF;

  -- Only trigger for NEW calls with ringing status
  IF (NEW.status = 'ringing') THEN
    PERFORM
      net.http_post(
        url := 'https://icdbbfsjbslzctshxytd.supabase.co/functions/v1/push-handler',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || COALESCE(service_role_key, '')
        ),
        body := jsonb_build_object(
          'type', 'call_ringing',
          'call_id', NEW.id,
          'sender_id', NEW.sender_id,
          'receiver_id', NEW.receiver_id,
          'is_video', NEW.is_video,
          'timestamp', EXTRACT(EPOCH FROM NEW.created_at)::TEXT
        )
      );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_call_inserted_ringing ON public.calls;
CREATE TRIGGER on_call_inserted_ringing
AFTER INSERT ON public.calls
FOR EACH ROW EXECUTE FUNCTION public.notify_call_ringing_push();
