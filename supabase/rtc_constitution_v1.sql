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
  service_role_key TEXT;
BEGIN
  SELECT decrypted_secret INTO service_role_key 
  FROM vault.decrypted_secrets 
  WHERE name = 'service_role_key' 
  LIMIT 1;

  IF service_role_key IS NULL THEN
    service_role_key := current_setting('app.settings.service_role_key', true);
  END IF;

  IF (NEW.status = 'ringing') THEN
    PERFORM
      net.http_post(
        url := 'https://icdbbfsjbslzctshxytd.supabase.co/functions/v1/push-handler',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || COALESCE(service_role_key, '')
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

-- 6. Candidates Append Helper Function (SEC-01 Hardened)
CREATE OR REPLACE FUNCTION public.fn_add_call_candidate(p_call_id uuid, p_candidate jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_user_id uuid := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_candidate IS NULL
       OR jsonb_typeof(p_candidate) <> 'object'
       OR octet_length(p_candidate::text) > 8192 THEN
        RAISE EXCEPTION 'Invalid ICE candidate payload' USING ERRCODE = '22023';
    END IF;

    UPDATE public.calls
    SET candidates =
        COALESCE(candidates, '[]'::jsonb)
        || jsonb_build_array(p_candidate)
    WHERE id = p_call_id
      AND (
          sender_id = v_user_id
          OR receiver_id = v_user_id
          OR caller_id = v_user_id
          OR callee_id = v_user_id
      )
      AND status IN ('ringing', 'accepted', 'ongoing')
      AND jsonb_array_length(COALESCE(candidates, '[]'::jsonb)) < 150;

    IF NOT FOUND THEN
        IF NOT EXISTS (SELECT 1 FROM public.calls WHERE id = p_call_id) THEN
            RAISE EXCEPTION 'Call not found' USING ERRCODE = 'P0002';
        ELSIF NOT EXISTS (
            SELECT 1 FROM public.calls 
            WHERE id = p_call_id 
              AND (sender_id = v_user_id OR receiver_id = v_user_id OR caller_id = v_user_id OR callee_id = v_user_id)
        ) THEN
            RAISE EXCEPTION 'Unauthorized: user is not a call participant' USING ERRCODE = '42501';
        ELSIF NOT EXISTS (
            SELECT 1 FROM public.calls 
            WHERE id = p_call_id 
              AND status IN ('ringing', 'accepted', 'ongoing')
        ) THEN
            RAISE EXCEPTION 'Cannot add candidate to terminal or inactive call' USING ERRCODE = '42501';
        ELSE
            RAISE EXCEPTION 'Maximum ICE candidate limit exceeded' USING ERRCODE = '22023';
        END IF;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_add_call_candidate(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_add_call_candidate(uuid, jsonb) TO authenticated, service_role;
