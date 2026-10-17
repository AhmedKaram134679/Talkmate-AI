-- [Stage R-Stability] Room Creation Push Trigger
-- Automatically triggers push-handler when a new room is created

CREATE OR REPLACE FUNCTION public.notify_room_created_push()
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

  -- Notify for NEW rooms
  PERFORM
    net.http_post(
      url := 'https://icdbbfsjbslzctshxytd.supabase.co/functions/v1/push-handler',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || COALESCE(service_role_key, '')
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
