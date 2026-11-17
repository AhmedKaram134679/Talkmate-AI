-- Migration: 20261117150000_fix_sec_functions.sql
-- Fixes for SEC-01, SEC-02, SEC-03:
-- 1. Correct purge_old_data to reference existing tables (routing_logs, feedback_signals, user_search_rate_limits).
-- 2. Correct delete_user_account to reference user_search_rate_limits instead of non-existent rate_limits.
-- 3. Robust fn_add_call_candidate with unambiguous jsonb_each key validation and clear error reporting.

-- 1. SEC-01: fn_add_call_candidate
CREATE OR REPLACE FUNCTION public.fn_add_call_candidate(
    p_call_id uuid,
    p_candidate jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_mline_str text;
BEGIN
    -- 1. Ensure authenticated caller (derives identity exclusively from auth.uid())
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required'
            USING ERRCODE = '42501';
    END IF;

    -- 2. Validate payload presence and overall length constraint (max 8KB)
    IF p_candidate IS NULL
       OR jsonb_typeof(p_candidate) IS DISTINCT FROM 'object'
       OR octet_length(p_candidate::text) > 8192 THEN
        RAISE EXCEPTION 'Invalid ICE candidate payload'
            USING ERRCODE = '22023';
    END IF;

    -- 3. Enforce structural schema validation:
    -- Required: "candidate" (non-empty string)
    IF NOT (p_candidate ? 'candidate') THEN
        RAISE EXCEPTION 'Invalid ICE candidate payload: candidate field is required'
            USING ERRCODE = '22023';
    END IF;

    IF jsonb_typeof(p_candidate -> 'candidate') IS DISTINCT FROM 'string'
       OR length(btrim(p_candidate ->> 'candidate')) = 0 THEN
        RAISE EXCEPTION 'Invalid ICE candidate payload: candidate must be a non-empty string'
            USING ERRCODE = '22023';
    END IF;

    -- Optional: "sdpMid" (string or null)
    IF p_candidate ? 'sdpMid'
       AND jsonb_typeof(p_candidate -> 'sdpMid') NOT IN ('string', 'null') THEN
        RAISE EXCEPTION 'Invalid ICE candidate payload: sdpMid must be string or null'
            USING ERRCODE = '22023';
    END IF;

    -- Optional: "sdpMLineIndex" (non-negative integer number or null)
    IF p_candidate ? 'sdpMLineIndex' THEN
        IF jsonb_typeof(p_candidate -> 'sdpMLineIndex') NOT IN ('number', 'null') THEN
            RAISE EXCEPTION 'Invalid ICE candidate payload: sdpMLineIndex must be number or null'
                USING ERRCODE = '22023';
        END IF;

        IF jsonb_typeof(p_candidate -> 'sdpMLineIndex') = 'number' THEN
            v_mline_str := p_candidate ->> 'sdpMLineIndex';
            -- Validate integer format and non-negative range
            IF v_mline_str !~ '^-?[0-9]+$' THEN
                RAISE EXCEPTION 'Invalid ICE candidate payload: sdpMLineIndex must be an integer'
                    USING ERRCODE = '22023';
            END IF;
            IF v_mline_str::bigint < 0 THEN
                RAISE EXCEPTION 'Invalid ICE candidate payload: sdpMLineIndex cannot be negative'
                    USING ERRCODE = '22023';
            END IF;
        END IF;
    END IF;

    -- Optional: "usernameFragment" (string or null)
    IF p_candidate ? 'usernameFragment'
       AND jsonb_typeof(p_candidate -> 'usernameFragment') NOT IN ('string', 'null') THEN
        RAISE EXCEPTION 'Invalid ICE candidate payload: usernameFragment must be string or null'
            USING ERRCODE = '22023';
    END IF;

    -- Reject unknown fields to prevent smuggling / unauthorized payload expansion
    IF EXISTS (
        SELECT 1 FROM jsonb_each(p_candidate) 
        WHERE key NOT IN ('candidate', 'sdpMid', 'sdpMLineIndex', 'usernameFragment')
    ) THEN
        RAISE EXCEPTION 'Invalid ICE candidate payload: unknown fields detected'
            USING ERRCODE = '22023';
    END IF;

    -- 4. Atomically verify participant authorization, active call status, and array bounds (<150)
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


-- 2. SEC-02: delete_user_account
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_user_id uuid := auth.uid();
BEGIN
    -- 1. Ensure authenticated caller (derives identity exclusively from auth.uid())
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required'
            USING ERRCODE = '42501';
    END IF;

    -- 2. Remove user devices and tokens
    DELETE FROM public.user_devices WHERE user_id = v_user_id;

    -- 3. Remove friend requests and friendships
    DELETE FROM public.friends WHERE user_id = v_user_id OR friend_id = v_user_id;
    DELETE FROM public.friend_requests WHERE sender_id = v_user_id OR receiver_id = v_user_id;

    -- 4. Remove conversation participation
    DELETE FROM public.conversation_participants WHERE user_id = v_user_id;

    -- 5. Remove user rate limits and caching
    DELETE FROM public.user_search_rate_limits WHERE user_id = v_user_id;

    -- 6. Delete public profile
    DELETE FROM public.profiles WHERE id = v_user_id;

    -- 7. Delete core auth user account from auth.users (cascades sessions, identities, MFA)
    DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_user_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;


-- 3. SEC-03: purge_old_data
CREATE OR REPLACE FUNCTION public.purge_old_data(
    retention_days int DEFAULT 90
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    cutoff_date timestamptz;
BEGIN
    -- Strictly bound retention_days to safe operational window (1 to 3650 days)
    IF retention_days IS NULL OR retention_days < 1 OR retention_days > 3650 THEN
        RAISE EXCEPTION 'Invalid retention period: must be between 1 and 3650 days'
            USING ERRCODE = '22023';
    END IF;

    cutoff_date := now() - (retention_days || ' days')::interval;

    -- Clean up ephemeral routing logs
    DELETE FROM public.routing_logs WHERE created_at < cutoff_date;

    -- Clean up feedback signals
    DELETE FROM public.feedback_signals WHERE created_at < cutoff_date;

    -- Clean up old rate limit records
    DELETE FROM public.user_search_rate_limits WHERE window_start < cutoff_date;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_old_data(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_data(int) TO service_role;
