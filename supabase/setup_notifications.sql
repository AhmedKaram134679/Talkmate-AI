-- SQL for Supabase Push Notification Triggers

-- 1. Create a function to trigger the Edge Function
-- Note: Replace 'push-handler' with your function name if different.
-- Ensure the 'pg_net' extension is enabled in your Supabase dashboard.

CREATE OR REPLACE FUNCTION public.notify_push_handler()
RETURNS trigger AS $$
BEGIN
  PERFORM
    net.http_post(
      url := 'https://' || current_setting('request.headers')::json->>'host' || '/functions/v1/push-handler',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('request.headers')::json->>'authorization'
      ),
      body := jsonb_build_object(
        'type', TG_TABLE_NAME,
        'record', row_to_json(NEW)
      )
    );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Triggers for different events

-- New Message
DROP TRIGGER IF EXISTS on_message_inserted ON public.messages;
CREATE TRIGGER on_message_inserted
AFTER INSERT ON public.messages
FOR EACH ROW EXECUTE FUNCTION public.notify_push_handler();

-- New Reaction
DROP TRIGGER IF EXISTS on_reaction_inserted ON public.reactions;
CREATE TRIGGER on_reaction_inserted
AFTER INSERT ON public.reactions
FOR EACH ROW EXECUTE FUNCTION public.notify_push_handler();

-- Incoming Call
DROP TRIGGER IF EXISTS on_call_inserted ON public.calls;
CREATE TRIGGER on_call_inserted
AFTER INSERT ON public.calls
FOR EACH ROW EXECUTE FUNCTION public.notify_push_handler();
