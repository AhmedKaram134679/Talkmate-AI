-- [Stage R-Stability] Call Ringing Push Trigger
-- Automatically triggers push-handler when a call enters 'ringing' state

CREATE OR REPLACE FUNCTION public.notify_call_ringing_push()
RETURNS trigger AS $$
DECLARE
  service_role_key TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImljZGJiZnNqYnNsemN0c2h4eXRkIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MDQyODY2OCwiZXhwIjoyMDk2MDA0NjY4fQ.VmBetxbbIBDF9gxnAKC_cikCXLD66jXao-YR9I_Tm0Y';
BEGIN
  -- Only trigger for NEW calls with ringing status
  IF (NEW.status = 'ringing') THEN
    PERFORM
      net.http_post(
        url := 'https://icdbbfsjbslzctshxytd.supabase.co/functions/v1/push-handler',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || service_role_key 
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
