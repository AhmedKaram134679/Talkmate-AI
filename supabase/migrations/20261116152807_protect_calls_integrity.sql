-- Migration: 20261116152807_protect_calls_integrity.sql
-- Description: Protect call record integrity and enforce call lifecycle transitions.
-- 
-- 1. Enforces immutability of call identities (id, sender_id, caller_id, receiver_id, callee_id, created_at).
-- 2. Validates call status transitions (prevents reopening terminal calls or illegal status leaps).
-- 3. Enforces participant authorization on status changes.
-- 4. Tightens RLS policies on public.calls with WITH CHECK constraints.

-- Step 1: Function to enforce call record integrity and lifecycle transitions
CREATE OR REPLACE FUNCTION public.fn_protect_calls_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role text := coalesce(auth.role(), '');
  v_uid uuid := auth.uid();
  v_old_status text := lower(coalesce(OLD.status, ''));
  v_new_status text := lower(coalesce(NEW.status, ''));
  v_old_sender uuid := coalesce(OLD.sender_id, OLD.caller_id);
  v_old_receiver uuid := coalesce(OLD.receiver_id, OLD.callee_id);
BEGIN
  -- Service role and database triggers bypass these restrictions
  IF v_role = 'service_role' OR current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- 1. Protect Primary Key
  IF NEW.id IS DISTINCT FROM OLD.id THEN
    RAISE EXCEPTION 'Cannot modify call id' USING ERRCODE = '42501';
  END IF;

  -- 2. Protect Call Creation Timestamp
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Cannot modify call created_at timestamp' USING ERRCODE = '42501';
  END IF;

  -- 3. Protect Call Type
  IF NEW.type IS DISTINCT FROM OLD.type THEN
    RAISE EXCEPTION 'Cannot modify call type' USING ERRCODE = '42501';
  END IF;

  -- 4. Protect Participant Identities (sender_id, caller_id, receiver_id, callee_id)
  IF (NEW.sender_id IS DISTINCT FROM OLD.sender_id) OR
     (NEW.caller_id IS DISTINCT FROM OLD.caller_id) THEN
    RAISE EXCEPTION 'Cannot modify call caller/sender identity' USING ERRCODE = '42501';
  END IF;

  IF (NEW.receiver_id IS DISTINCT FROM OLD.receiver_id) OR
     (NEW.callee_id IS DISTINCT FROM OLD.callee_id) THEN
    RAISE EXCEPTION 'Cannot modify call receiver/callee identity' USING ERRCODE = '42501';
  END IF;

  -- 5. Synchronize dual column pairs if one is updated while the other is NULL
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

  -- 6. Validate Status Transitions (Call Lifecycle)
  IF v_new_status IS DISTINCT FROM v_old_status THEN
    -- A. Disallow reopening terminal calls
    IF v_old_status IN ('ended', 'rejected', 'missed', 'failed') THEN
      RAISE EXCEPTION 'Cannot modify call in terminal status %', v_old_status USING ERRCODE = '42501';
    END IF;

    -- B. Disallow invalid transitions
    IF v_old_status IN ('ringing', 'calling') THEN
      -- Allowed transitions from ringing: accepted, ongoing, ended, rejected, missed, failed
      IF v_new_status NOT IN ('accepted', 'ongoing', 'ended', 'rejected', 'missed', 'failed') THEN
        RAISE EXCEPTION 'Invalid transition from % to %', v_old_status, v_new_status USING ERRCODE = '42501';
      END IF;

      -- Only callee/receiver can accept or reject an incoming call
      IF v_new_status IN ('accepted', 'rejected') THEN
        IF v_uid IS NOT NULL AND v_uid IS DISTINCT FROM v_old_receiver THEN
          RAISE EXCEPTION 'Only call receiver can % the call', v_new_status USING ERRCODE = '42501';
        END IF;
      END IF;

    ELSIF v_old_status = 'accepted' THEN
      -- Allowed transitions from accepted: ongoing, ended, failed
      IF v_new_status NOT IN ('ongoing', 'ended', 'failed') THEN
        RAISE EXCEPTION 'Invalid transition from accepted to %', v_new_status USING ERRCODE = '42501';
      END IF;

    ELSIF v_old_status = 'ongoing' THEN
      -- Allowed transitions from ongoing: ended, failed
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

-- Step 2: Attach the Trigger
DROP TRIGGER IF EXISTS tr_protect_calls_integrity ON public.calls;
CREATE TRIGGER tr_protect_calls_integrity
BEFORE UPDATE ON public.calls
FOR EACH ROW
EXECUTE FUNCTION public.fn_protect_calls_integrity();

-- Step 3: Tighten RLS Policies with WITH CHECK
DROP POLICY IF EXISTS "Participants can update calls" ON public.calls;
CREATE POLICY "Participants can update calls" ON public.calls
  FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = sender_id OR 
    auth.uid() = receiver_id OR 
    auth.uid() = caller_id OR 
    auth.uid() = callee_id
  )
  WITH CHECK (
    auth.uid() = sender_id OR 
    auth.uid() = receiver_id OR 
    auth.uid() = caller_id OR 
    auth.uid() = callee_id
  );

-- Ensure Insert Policy validates sender identity
DROP POLICY IF EXISTS "Users can create calls" ON public.calls;
CREATE POLICY "Users can create calls" ON public.calls
  FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.uid() = sender_id OR sender_id IS NULL) AND
    (auth.uid() = caller_id OR caller_id IS NULL) AND
    (receiver_id IS NOT NULL OR callee_id IS NOT NULL)
  );
