-- [Stage R-Stability] Room Creation Push Trigger
-- Automatically triggers push-handler when a new room is created

CREATE OR REPLACE FUNCTION public.notify_room_created_push()
RETURNS trigger AS $$
DECLARE
  service_role_key TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5tZGNhdG96dHF1eWNjeXpheG5uIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NzA2OTIzMSwiZXhwIjoyMDgyNjQ1MjMxfQ.9vWT-tGwc3sSLCw0Qx_NZVroVXwEJTMqhMRyuoE1IZI';
BEGIN
  -- Notify for NEW rooms
  PERFORM
    net.http_post(
      url := 'https://nmdcatoztquyccyzaxnn.supabase.co/functions/v1/push-handler',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key 
      ),
      body := jsonb_build_object(
        'type', 'room_created',
        'id', NEW.id,
        'name', NEW.name,
        'created_by', NEW.created_by,
        'timestamp', EXTRACT(EPOCH FROM NEW.created_at)::TEXT
      )
    );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_room_inserted_push ON public.rooms;
CREATE TRIGGER on_room_inserted_push
AFTER INSERT ON public.rooms
FOR EACH ROW EXECUTE FUNCTION public.notify_room_created_push();
