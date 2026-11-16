-- Migration: 20261116193000_remediate_call_integrity.sql
-- Description: Targeted remediation for public.calls INSERT identity validation, 
--              call state machine completion, and trigger privilege hardening.

-- Step 1: Replace fn_protect_calls_integrity() with hardened trigger function
CREATE OR REPLACE FUNCTION public.fn_protect_calls_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role text := coalesce(auth.role(), '');
  v_uid uuid := auth.uid();
  v_old_status text;
  v_new_status text;
  v_old_sender uuid;
  v_old_receiver uuid;
  v_new_sender uuid;
  v_new_receiver uuid;
BEGIN
  -- Strict Service Role Bypass
  -- Only bypass when executing under the trusted service_role
  IF v_role = 'service_role' OR current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  -----------------------------------------------------------------------------
  -- 1. INSERT Validation (BEFORE INSERT)
  -----------------------------------------------------------------------------
  IF TG_OP = 'INSERT' THEN
    -- A. Validate initial status: must be 'ringing'
    v_new_status := lower(coalesce(NEW.status, ''));
    IF v_new_status IS DISTINCT FROM 'ringing' THEN
      RAISE EXCEPTION 'Initial call status must be ringing (got: %)', NEW.status USING ERRCODE = '42501';
    END IF;
    NEW.status := 'ringing';

    -- B. Validate Sender Identifiers
    -- At least one of sender_id or caller_id must equal auth.uid()
    IF (NEW.sender_id IS NULL AND NEW.caller_id IS NULL) THEN
      RAISE EXCEPTION 'Call must specify sender_id or caller_id matching authenticated user' USING ERRCODE = '42501';
    END IF;

    IF (NEW.sender_id IS NOT NULL AND NEW.sender_id IS DISTINCT FROM v_uid) OR
       (NEW.caller_id IS NOT NULL AND NEW.caller_id IS DISTINCT FROM v_uid) THEN
      RAISE EXCEPTION 'Sender identity does not match authenticated user' USING ERRCODE = '42501';
    END IF;

    -- If both are non-NULL, they must be identical
    IF (NEW.sender_id IS NOT NULL AND NEW.caller_id IS NOT NULL AND NEW.sender_id IS DISTINCT FROM NEW.caller_id) THEN
      RAISE EXCEPTION 'Mismatched sender_id and caller_id on call insert' USING ERRCODE = '42501';
    END IF;

    -- Synchronize sender columns
    IF NEW.sender_id IS NULL THEN
      NEW.sender_id := NEW.caller_id;
    ELSIF NEW.caller_id IS NULL THEN
      NEW.caller_id := NEW.sender_id;
    END IF;

    -- C. Validate Receiver Identifiers
    -- At least one receiver identifier must be non-NULL
    IF (NEW.receiver_id IS NULL AND NEW.callee_id IS NULL) THEN
      RAISE EXCEPTION 'Call must specify receiver_id or callee_id' USING ERRCODE = '42501';
    END IF;

    -- If both are non-NULL, they must be identical
    IF (NEW.receiver_id IS NOT NULL AND NEW.callee_id IS NOT NULL AND NEW.receiver_id IS DISTINCT FROM NEW.callee_id) THEN
      RAISE EXCEPTION 'Mismatched receiver_id and callee_id on call insert' USING ERRCODE = '42501';
    END IF;

    -- Synchronize receiver columns
    IF NEW.receiver_id IS NULL THEN
      NEW.receiver_id := NEW.callee_id;
    ELSIF NEW.callee_id IS NULL THEN
      NEW.callee_id := NEW.receiver_id;
    END IF;

    RETURN NEW;
  END IF;

  -----------------------------------------------------------------------------
  -- 2. UPDATE Validation (BEFORE UPDATE)
  -----------------------------------------------------------------------------
  v_old_status := lower(coalesce(OLD.status, ''));
  v_new_status := lower(coalesce(NEW.status, ''));
  v_old_sender := coalesce(OLD.sender_id, OLD.caller_id);
  v_old_receiver := coalesce(OLD.receiver_id, OLD.callee_id);

  -- A. Protect Primary Key
  IF NEW.id IS DISTINCT FROM OLD.id THEN
    RAISE EXCEPTION 'Cannot modify call id' USING ERRCODE = '42501';
  END IF;

  -- B. Protect Call Creation Timestamp
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Cannot modify call created_at timestamp' USING ERRCODE = '42501';
  END IF;

  -- C. Protect Call Type
  IF NEW.type IS DISTINCT FROM OLD.type THEN
    RAISE EXCEPTION 'Cannot modify call type' USING ERRCODE = '42501';
  END IF;

  -- D. Protect Participant Identities (sender_id, caller_id, receiver_id, callee_id)
  IF (NEW.sender_id IS DISTINCT FROM OLD.sender_id) OR
     (NEW.caller_id IS DISTINCT FROM OLD.caller_id) THEN
    RAISE EXCEPTION 'Cannot modify call caller/sender identity' USING ERRCODE = '42501';
  END IF;

  IF (NEW.receiver_id IS DISTINCT FROM OLD.receiver_id) OR
     (NEW.callee_id IS DISTINCT FROM OLD.callee_id) THEN
    RAISE EXCEPTION 'Cannot modify call receiver/callee identity' USING ERRCODE = '42501';
  END IF;

  -- E. Synchronize dual column pairs if one is updated while the other is NULL
  IF NEW.sender_id IS NULL AND NEW.caller_id IS NOT NULL THEN
    NEW.sender_id := NEW.caller_id;
  ELSIF NEW.caller_id IS NULL AND NEW.sender_id IS NOT NULL THEN
    NEW.caller_id := NEW.sender_id;
  END IF;

  IF NEW.receiver_id IS NULL AND NEW.callee_id IS NOT NULL THEN
    NEW.receiver_id := NEW.callee_id;
  ELSIF NEW.callee_id IS NULL AND NEW.receiver_id IS NOT NULL THEN
    NEW.callee_id := NEW.receiver_id;
  END IF;

  -- F. Validate Status Transitions (Call Lifecycle State Machine)
  IF v_new_status IS DISTINCT FROM v_old_status THEN
    -- Disallow unknown target statuses
    IF v_new_status NOT IN ('ringing', 'accepted', 'ongoing', 'ended', 'rejected', 'missed', 'failed') THEN
      RAISE EXCEPTION 'Invalid target call status %', v_new_status USING ERRCODE = '42501';
    END IF;

    -- Disallow transitions from unknown origin statuses
    IF v_old_status NOT IN ('ringing', 'accepted', 'ongoing', 'ended', 'rejected', 'missed', 'failed') THEN
      RAISE EXCEPTION 'Invalid source call status %', v_old_status USING ERRCODE = '42501';
    END IF;

    -- Disallow reopening terminal calls
    IF v_old_status IN ('ended', 'rejected', 'missed', 'failed') THEN
      RAISE EXCEPTION 'Cannot modify call in terminal status %', v_old_status USING ERRCODE = '42501';
    END IF;

    -- Lifecycle rules from ringing:
    IF v_old_status = 'ringing' THEN
      -- Allowed target statuses: accepted, ongoing, ended, rejected, missed, failed
      IF v_new_status NOT IN ('accepted', 'ongoing', 'ended', 'rejected', 'missed', 'failed') THEN
        RAISE EXCEPTION 'Invalid transition from ringing to %', v_new_status USING ERRCODE = '42501';
      END IF;

      -- Only callee/receiver can accept or reject an incoming call
      -- Must have a valid authenticated identity
      IF v_new_status IN ('accepted', 'rejected') THEN
        IF v_uid IS NULL OR v_uid IS DISTINCT FROM v_old_receiver THEN
          RAISE EXCEPTION 'Only call receiver can % the call', v_new_status USING ERRCODE = '42501';
        END IF;
      END IF;

    -- Lifecycle rules from accepted:
    ELSIF v_old_status = 'accepted' THEN
      -- Allowed target statuses: ongoing, ended, failed
      IF v_new_status NOT IN ('ongoing', 'ended', 'failed') THEN
        RAISE EXCEPTION 'Invalid transition from accepted to %', v_new_status USING ERRCODE = '42501';
      END IF;

    -- Lifecycle rules from ongoing:
    ELSIF v_old_status = 'ongoing' THEN
      -- Allowed target statuses: ended, failed
      IF v_new_status NOT IN ('ended', 'failed') THEN
        RAISE EXCEPTION 'Invalid transition from ongoing to %', v_new_status USING ERRCODE = '42501';
      END IF;
    END IF;

    -- Normalize status to lowercase
    NEW.status := v_new_status;
  END IF;

  RETURN NEW;
END;
$$;

-- Step 2: Bind Trigger for BEFORE INSERT OR UPDATE
DROP TRIGGER IF EXISTS tr_protect_calls_integrity ON public.calls;
CREATE TRIGGER tr_protect_calls_integrity
BEFORE INSERT OR UPDATE ON public.calls
FOR EACH ROW
EXECUTE FUNCTION public.fn_protect_calls_integrity();

-- Step 3: Hardened RLS INSERT Policy
DROP POLICY IF EXISTS "Users can create calls" ON public.calls;
CREATE POLICY "Users can create calls" ON public.calls
  FOR INSERT
  TO authenticated
  WITH CHECK (
    -- At least one sender identifier must match auth.uid()
    (
      (sender_id IS NOT NULL AND sender_id = auth.uid()) OR
      (caller_id IS NOT NULL AND caller_id = auth.uid())
    )
    -- Neither sender identifier may mismatch auth.uid()
    AND (sender_id IS NULL OR sender_id = auth.uid())
    AND (caller_id IS NULL OR caller_id = auth.uid())
    -- If both are non-NULL, they must be equal
    AND (sender_id IS NULL OR caller_id IS NULL OR sender_id = caller_id)
    -- At least one receiver identifier must be non-NULL
    AND (receiver_id IS NOT NULL OR callee_id IS NOT NULL)
    -- If both are non-NULL, they must be equal
    AND (receiver_id IS NULL OR callee_id IS NULL OR receiver_id = callee_id)
    -- Initial status must be ringing if provided
    AND (status IS NULL OR lower(status) = 'ringing')
  );

-- Step 4: Revoke Public Execute from trigger function
REVOKE ALL ON FUNCTION public.fn_protect_calls_integrity() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_protect_calls_integrity() FROM anon;
REVOKE ALL ON FUNCTION public.fn_protect_calls_integrity() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_protect_calls_integrity() TO postgres, service_role;
