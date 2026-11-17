-- TalkMate AI - Production-Grade Security Hardening Migration
-- Remediation for SEC-01, SEC-02, SEC-03, SEC-04, and SEC-05
-- Migration: 20261117140000_sec01_to_sec05_production_hardening.sql

-- ============================================================================
-- 1. SEC-01: ICE Candidate Structural Validation & Unauthenticated Rejection
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_add_call_candidate(
    p_call_id uuid,
    p_candidate jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_mline_str text;
BEGIN
    -- 1. Ensure authenticated caller (explicit rejection)
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required'
            USING ERRCODE = '42501';
    END IF;

    -- 2. Validate payload is an object and within 8KB byte size
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
        SELECT 1 FROM jsonb_object_keys(p_candidate) k 
        WHERE k NOT IN ('candidate', 'sdpMid', 'sdpMLineIndex', 'usernameFragment')
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


-- ============================================================================
-- 2. SEC-02: Account Deletion RPC & Explicit Default Privilege Configuration
-- ============================================================================

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
    DELETE FROM public.rate_limits WHERE user_id = v_user_id;

    -- 6. Delete public profile
    DELETE FROM public.profiles WHERE id = v_user_id;

    -- 7. Delete core auth user account from auth.users (cascades sessions, identities, MFA)
    DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

-- Secure execution permissions for delete_user_account
REVOKE ALL ON FUNCTION public.delete_user_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;

-- Configure explicit default privileges across all standard deployment roles
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE service_role IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;


-- ============================================================================
-- 3. SEC-03: Secure purge_old_data Function Permissions
-- ============================================================================

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

    -- Clean up dead-letter queue records
    DELETE FROM public.dlq_messages WHERE created_at < cutoff_date;

    -- Clean up rate limits and notifications
    DELETE FROM public.rate_limits WHERE window_start < cutoff_date;
    DELETE FROM public.notifications WHERE created_at < cutoff_date;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_old_data(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_data(int) TO service_role;


-- ============================================================================
-- 4. SEC-04: Profile Privacy, Search Enumeration Prevention, and Bounded Calls
-- ============================================================================

-- Create dedicated rate limiting table for user search
CREATE TABLE IF NOT EXISTS public.user_search_rate_limits (
    user_id uuid PRIMARY KEY,
    window_start timestamptz NOT NULL DEFAULT now(),
    request_count int NOT NULL DEFAULT 1
);

ALTER TABLE public.user_search_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.user_search_rate_limits FROM PUBLIC, anon, authenticated;

-- Hardened search_users RPC:
-- - Escapes %, _, \ with ESCAPE E'\\'
-- - Enforces min length 2, max length 50
-- - Rejects empty / wildcard-only search queries
-- - Per-user rate limiting (max 30 queries per minute)
-- - Respects privacy_show_last_seen, privacy_show_status, privacy_show_profile_photo
-- - NEVER exposes email addresses of other users
CREATE OR REPLACE FUNCTION public.search_users(
    p_query text,
    p_limit integer DEFAULT 20
)
RETURNS TABLE(
    id uuid,
    username text,
    full_name text,
    avatar_url text,
    about text,
    is_online boolean,
    last_seen timestamp with time zone,
    status text,
    email text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_clean text;
    v_pattern text;
    v_rl_window timestamptz;
    v_rl_count int;
BEGIN
    -- 1. Must be authenticated
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    -- 2. Concurrency-safe per-user rate limiting (max 30 requests / 60 seconds)
    SELECT window_start, request_count INTO v_rl_window, v_rl_count
    FROM public.user_search_rate_limits
    WHERE user_id = v_uid
    FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO public.user_search_rate_limits (user_id, window_start, request_count)
        VALUES (v_uid, now(), 1);
    ELSIF now() - v_rl_window > interval '1 minute' THEN
        UPDATE public.user_search_rate_limits
        SET window_start = now(), request_count = 1
        WHERE user_id = v_uid;
    ELSE
        IF v_rl_count >= 30 THEN
            RAISE EXCEPTION 'Search rate limit exceeded. Please wait a moment.'
                USING ERRCODE = 'P0001';
        END IF;
        UPDATE public.user_search_rate_limits
        SET request_count = request_count + 1
        WHERE user_id = v_uid;
    END IF;

    -- 3. Clean and validate query length
    v_clean := trim(p_query);
    IF length(v_clean) < 2 OR length(v_clean) > 50 THEN
        RETURN;
    END IF;

    -- 4. Bound limit
    p_limit := LEAST(GREATEST(p_limit, 1), 30);

    -- 5. Escape LIKE wildcards to prevent broad index enumeration
    v_pattern := replace(
        replace(
            replace(v_clean, E'\\', E'\\\\'),
            '%', E'\\%'
        ),
        '_', E'\\_'
    );
    v_pattern := '%' || v_pattern || '%';

    -- 6. Execute search with privacy projections and zero email leakage for third parties
    IF v_clean LIKE '%@%' THEN
        -- Targeted exact email lookup: Never return matched email to prevent harvesting
        RETURN QUERY
        SELECT 
            p.id,
            p.username,
            p.full_name,
            CASE WHEN p.privacy_show_profile_photo = false AND p.id <> v_uid THEN NULL ELSE p.avatar_url END,
            p.about,
            CASE WHEN p.privacy_show_last_seen = false AND p.id <> v_uid THEN false ELSE p.is_online END,
            CASE WHEN p.privacy_show_last_seen = false AND p.id <> v_uid THEN NULL ELSE p.last_seen END,
            CASE WHEN p.privacy_show_status = false AND p.id <> v_uid THEN NULL ELSE p.status END,
            CASE WHEN p.id = v_uid THEN p.email ELSE NULL END AS email
        FROM public.profiles p
        WHERE lower(p.email) = lower(v_clean)
        LIMIT p_limit;
    ELSE
        RETURN QUERY
        SELECT 
            p.id,
            p.username,
            p.full_name,
            CASE WHEN p.privacy_show_profile_photo = false AND p.id <> v_uid THEN NULL ELSE p.avatar_url END,
            p.about,
            CASE WHEN p.privacy_show_last_seen = false AND p.id <> v_uid THEN false ELSE p.is_online END,
            CASE WHEN p.privacy_show_last_seen = false AND p.id <> v_uid THEN NULL ELSE p.last_seen END,
            CASE WHEN p.privacy_show_status = false AND p.id <> v_uid THEN NULL ELSE p.status END,
            CASE WHEN p.id = v_uid THEN p.email ELSE NULL END AS email
        FROM public.profiles p
        WHERE (p.username ILIKE v_pattern ESCAPE E'\\'
           OR p.full_name ILIKE v_pattern ESCAPE E'\\')
        LIMIT p_limit;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.search_users(text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_users(text, integer) TO authenticated;

-- Hardened fn_is_profile_accessible:
-- - Active calls: only active statuses ('ringing', 'accepted', 'ongoing')
-- - Historical calls: only bounded recent calls within past 24 hours ('created_at >= now() - interval 24 hours')
CREATE OR REPLACE FUNCTION public.fn_is_profile_accessible(p_target_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT 
    -- 1. Own profile
    p_target_id = auth.uid()
    -- 2. Mutual conversation participant
    OR EXISTS (
      SELECT 1 
      FROM public.conversation_participants cp1
      JOIN public.conversation_participants cp2 ON cp1.conversation_id = cp2.conversation_id
      WHERE cp1.user_id = auth.uid() AND cp2.user_id = p_target_id
    )
    -- 3. Established Friends
    OR EXISTS (
      SELECT 1 
      FROM public.friends f
      WHERE (f.user_id = auth.uid() AND f.friend_id = p_target_id)
         OR (f.friend_id = auth.uid() AND f.user_id = p_target_id)
    )
    -- 4. Pending Friend requests (sender or receiver)
    OR EXISTS (
      SELECT 1 
      FROM public.friend_requests fr
      WHERE (fr.sender_id = auth.uid() AND fr.receiver_id = p_target_id)
         OR (fr.receiver_id = auth.uid() AND fr.sender_id = p_target_id)
    )
    -- 5. Active call participant OR recent call within bounded 24-hour window
    OR EXISTS (
      SELECT 1 
      FROM public.calls c
      WHERE (c.sender_id = auth.uid() OR c.caller_id = auth.uid() OR c.receiver_id = auth.uid() OR c.callee_id = auth.uid())
        AND (c.sender_id = p_target_id OR c.caller_id = p_target_id OR c.receiver_id = p_target_id OR c.callee_id = p_target_id)
        AND (
            c.status IN ('ringing', 'accepted', 'ongoing')
            OR (c.created_at >= (now() - interval '24 hours'))
        )
    );
$$;

REVOKE ALL ON FUNCTION public.fn_is_profile_accessible(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_is_profile_accessible(uuid) TO authenticated, service_role;


-- ============================================================================
-- 5. SEC-05: Storage Avatar Privacy & Group Member Lifecycle
-- ============================================================================

DROP POLICY IF EXISTS "talkmate_read_policy" ON storage.objects;

CREATE POLICY "talkmate_read_policy" ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'talkmate' AND (
        -- 1. Owner can always read their own objects
        owner = auth.uid()

        -- 2. Users directory:
        -- Owner can read anything in their own folder (users/{uid}/*)
        -- Others can ONLY read avatar images prefixed with literal 'profile_'
        -- AND ONLY IF the profile owner has privacy_show_profile_photo enabled (not false)
        OR (
            (storage.foldername(name))[1] = 'users' AND (
                (storage.foldername(name))[2] = auth.uid()::text
                OR (
                    starts_with(storage.filename(name), 'profile_')
                    AND EXISTS (
                        SELECT 1 FROM public.profiles p
                        WHERE (p.id::text = (storage.foldername(name))[2] OR p.id = objects.owner)
                          AND COALESCE(p.privacy_show_profile_photo, true) = true
                    )
                )
            )
        )

        -- 3. Groups directory:
        -- Creator can read temporary avatar during group creation
        -- Group members in conversation_participants can read groups/{chatId}/*
        OR (
            (storage.foldername(name))[1] = 'groups' AND (
                ((storage.foldername(name))[2] IS NULL AND owner = auth.uid())
                OR EXISTS (
                    SELECT 1 FROM public.conversation_participants cp
                    WHERE cp.conversation_id::text = (storage.foldername(name))[2]
                      AND cp.user_id = auth.uid()
                )
            )
        )

        -- 4. Chat attachments: conversation members only
        OR (
            (storage.foldername(name))[1] = 'chats' AND EXISTS (
                SELECT 1 FROM public.conversation_participants cp
                WHERE cp.conversation_id::text = (storage.foldername(name))[2]
                  AND cp.user_id = auth.uid()
            )
        )
    )
);
