-- Migration: 20261116203000_secure_service_role_bypass.sql
-- Description: Strictly secure service_role bypass by verifying that the underlying
--              PostgreSQL database session role is genuinely authorized.
--              Eliminates reliance on user-spoofable auth.role() or session parameters.

CREATE OR REPLACE FUNCTION public.fn_protect_calls_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role_setting text := current_setting('role', true);
  v_uid uuid := auth.uid();
  v_session_user text := session_user;
  v_old_status text;
  v_new_status text;
  v_old_sender uuid;
  v_old_receiver uuid;
BEGIN
  -----------------------------------------------------------------------------
  -- 0. Trusted Service Bypass
  -----------------------------------------------------------------------------
  -- To prevent ANY authenticated user from exploiting spoofable session variables 
  -- (e.g. set_config('request.jwt.claim.role', 'service_role', true) or set_config('role', ...)),
  -- we enforce that:
  -- 1) The active role setting is 'service_role' (set by PostgREST authenticator via SET LOCAL ROLE service_role)
  -- 2) AND the user is NOT operating under the 'authenticated' or 'anon' JWT claims/roles
  -- 3) OR the connection is from a database superuser/administrator (postgres / cli_login_postgres) 
  --    with no authenticated identity claim present.
  IF (v_role_setting = 'service_role' AND auth.role() = 'service_role')
     OR (v_session_user IN ('postgres', 'cli_login_postgres') AND auth.role() IS NULL AND auth.uid() IS NULL) THEN
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

  -- F. Invariant: Existing record status must be a known, valid call status
  -- This ensures unknown source statuses cannot bypass validation even if status is unmodified
  IF v_old_status NOT IN ('ringing', 'accepted', 'ongoing', 'ended', 'rejected', 'missed', 'failed') THEN
    RAISE EXCEPTION 'Invalid existing call status: %', OLD.status USING ERRCODE = '42501';
  END IF;

  -- G. Disallow modifications to terminal calls
  -- Once terminal, neither status nor signaling/metadata columns can be altered
  IF v_old_status IN ('ended', 'rejected', 'missed', 'failed') THEN
    RAISE EXCEPTION 'Cannot modify call in terminal status %', v_old_status USING ERRCODE = '42501';
  END IF;

  -- H. Validate Status Transitions (When status changes)
  IF v_new_status IS DISTINCT FROM v_old_status THEN
    -- Disallow unknown target statuses
    IF v_new_status NOT IN ('ringing', 'accepted', 'ongoing', 'ended', 'rejected', 'missed', 'failed') THEN
      RAISE EXCEPTION 'Invalid target call status %', v_new_status USING ERRCODE = '42501';
    END IF;

    -- Lifecycle rules from ringing:
    IF v_old_status = 'ringing' THEN
      -- Allowed target statuses: accepted, ongoing, ended, rejected, missed, failed
      IF v_new_status NOT IN ('accepted', 'ongoing', 'ended', 'rejected', 'missed', 'failed') THEN
        RAISE EXCEPTION 'Invalid transition from ringing to %', v_new_status USING ERRCODE = '42501';
      END IF;

      -- Only callee/receiver can accept or reject an incoming call
      IF v_new_status IN ('accepted', 'rejected') THEN
        IF v_uid IS NULL OR v_uid IS DISTINCT FROM v_old_receiver THEN
          RAISE EXCEPTION 'Only call receiver can % the call', v_new_status USING ERRCODE = '42501';
        END IF;
      END IF;

      -- Caller cancellation: Caller can transition to ended (or missed/failed)
      -- If caller attempts to set rejected, it is blocked above

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

-- Secure Execution Grants
REVOKE ALL ON FUNCTION public.fn_protect_calls_integrity() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_protect_calls_integrity() FROM anon;
REVOKE ALL ON FUNCTION public.fn_protect_calls_integrity() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_protect_calls_integrity() TO postgres, service_role;
