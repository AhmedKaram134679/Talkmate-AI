-- PROFESSIONAL PUSH NOTIFICATION TRIGGER (Stage Z-3: AI Routing)
-- This script sets up the trigger to call the Edge Function for Smart Routing.

CREATE OR REPLACE FUNCTION public.notify_professional_push()
RETURNS trigger AS $$
DECLARE
  service_role_key TEXT;
BEGIN
  -- Read key securely from Vault or database settings if available
  SELECT decrypted_secret INTO service_role_key 
  FROM vault.decrypted_secrets 
  WHERE name = 'service_role_key' 
  LIMIT 1;

  IF service_role_key IS NULL THEN
    service_role_key := current_setting('app.settings.service_role_key', true);
  END IF;

  -- Call Edge Function with the Message Data
  -- The Edge Function will handle participant lookup and AI Routing (Smart Filtering)
  PERFORM
    net.http_post(
      url := 'https://icdbbfsjbslzctshxytd.supabase.co/functions/v1/push-handler',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || COALESCE(service_role_key, '')
      ),
      body := jsonb_build_object(
        'type', 'message',
        'message_id', NEW.id,
        'chat_id', NEW.chat_id,
        'sender_id', NEW.sender_id,
        'content_type', NEW.type,
        'text_content', NEW.text, -- Send raw text, let Edge Function format it
        'timestamp', EXTRACT(EPOCH FROM NEW.created_at)::TEXT
      )
    );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_message_inserted_professional ON public.messages;
CREATE TRIGGER on_message_inserted_professional
AFTER INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.notify_professional_push();
