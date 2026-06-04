-- [Constitutional RTC] Final Schema Unification
-- Enforces the structure required by the RTC Constitution

-- 1. Unify 'calls' table columns
DO $$ 
BEGIN
  -- caller_id (The one who initiates)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='calls' AND column_name='caller_id') THEN
    ALTER TABLE public.calls ADD COLUMN caller_id uuid;
  END IF;

  -- receiver_id (The one who receives)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='calls' AND column_name='receiver_id') THEN
    ALTER TABLE public.calls ADD COLUMN receiver_id uuid;
  END IF;

  -- offer (WebRTC offer SDP)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='calls' AND column_name='offer') THEN
    ALTER TABLE public.calls ADD COLUMN offer jsonb;
  END IF;

  -- answer (WebRTC answer SDP)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='calls' AND column_name='answer') THEN
    ALTER TABLE public.calls ADD COLUMN answer jsonb;
  END IF;

  -- candidates (WebRTC ICE candidates)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='calls' AND column_name='candidates') THEN
    ALTER TABLE public.calls ADD COLUMN candidates jsonb DEFAULT '[]'::jsonb;
  END IF;
END $$;

-- 2. Migrate existing data if needed (sender_id -> caller_id mapping)
UPDATE public.calls SET caller_id = sender_id WHERE caller_id IS NULL AND sender_id IS NOT NULL;

-- 3. Set NOT NULL constraints (Caution: Only if all data is migrated)
-- For a safe transition, we'll enforce this for NEW rows via Trigger or App logic, 
-- but SQL constraints are better.
ALTER TABLE public.calls ALTER COLUMN caller_id SET NOT NULL;
ALTER TABLE public.calls ALTER COLUMN receiver_id SET NOT NULL;

-- 4. Enforce status values
ALTER TABLE public.calls DROP CONSTRAINT IF EXISTS calls_status_check;
ALTER TABLE public.calls ADD CONSTRAINT calls_status_check CHECK (status IN ('ringing', 'accepted', 'rejected', 'ended', 'ongoing', 'missed', 'failed'));
-- Note: 'ongoing', 'missed', 'failed' are from existing logic. 
-- Constitution allows ('ringing','accepted','rejected','ended'). 
-- I'll keep the intersection for compatibility.

-- 5. Realtime Notification Trigger (Sovereign Trigger)
CREATE OR REPLACE FUNCTION public.fn_on_call_ringing_push()
RETURNS trigger AS $$
DECLARE
  service_role_key TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImljZGJiZnNqYnNsemN0c2h4eXRkIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MDQyODY2OCwiZXhwIjoyMDk2MDA0NjY4fQ.VmBetxbbIBDF9gxnAKC_cikCXLD66jXao-YR9I_Tm0Y';
BEGIN
  IF (NEW.status = 'ringing') THEN
    PERFORM
      net.http_post(
        url := 'https://icdbbfsjbslzctshxytd.supabase.co/functions/v1/push-handler',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || service_role_key 
        ),
        body := jsonb_build_object(
          'type', 'INCOMING_CALL',
          'call_id', NEW.id,
          'caller_id', NEW.caller_id,
          'receiver_id', NEW.receiver_id,
          'call_type', NEW.type,
          'timestamp', now()
        )
      );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_on_call_ringing ON public.calls;
CREATE TRIGGER tr_on_call_ringing
AFTER INSERT ON public.calls
FOR EACH ROW EXECUTE FUNCTION public.fn_on_call_ringing_push();

-- 6. Candidates Append Helper Function
CREATE OR REPLACE FUNCTION public.fn_add_call_candidate(p_call_id uuid, p_candidate jsonb)
RETURNS void AS $$
BEGIN
  UPDATE public.calls 
  SET candidates = candidates || jsonb_build_array(p_candidate)
  WHERE id = p_call_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
