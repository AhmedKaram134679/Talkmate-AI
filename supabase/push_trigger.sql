-- PROFESSIONAL PUSH NOTIFICATION TRIGGER (Stage Z-3: AI Routing)
-- This script sets up the trigger to call the Edge Function for Smart Routing.

CREATE OR REPLACE FUNCTION public.notify_professional_push()
RETURNS trigger AS $$
DECLARE
  service_role_key TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImljZGJiZnNqYnNsemN0c2h4eXRkIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MDQyODY2OCwiZXhwIjoyMDk2MDA0NjY4fQ.VmBetxbbIBDF9gxnAKC_cikCXLD66jXao-YR9I_Tm0Y';
BEGIN
  -- Call Edge Function with the Message Data
  -- The Edge Function will handle participant lookup and AI Routing (Smart Filtering)
  PERFORM
    net.http_post(
      url := 'https://icdbbfsjbslzctshxytd.supabase.co/functions/v1/push-handler',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key 
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
