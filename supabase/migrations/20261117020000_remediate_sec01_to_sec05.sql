-- ============================================================================
-- Migration: 20261117020000_remediate_sec01_to_sec05.sql
-- Description: Comprehensive Security Hardening for SEC-01 through SEC-05
--   SEC-01: Harden fn_add_call_candidate with auth, participant, and status checks
--   SEC-02: Revoke broad public function execution and enforce least privilege allowlist
--   SEC-03: Restrict purge_old_data to service_role with strictly bounded retention period
--   SEC-04: Prevent profile enumeration and protect user privacy via relationship-based RLS and safe search RPC
--   SEC-05: Restrict storage read policy to user-owned folders, public avatars, and verified group/chat members
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SEC-01: Harden fn_add_call_candidate
-- ----------------------------------------------------------------------------
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
BEGIN
    -- 1. Ensure authenticated caller
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required'
            USING ERRCODE = '42501';
    END IF;

    -- 2. Validate Candidate structure and byte size (max 8KB)
    IF p_candidate IS NULL
       OR jsonb_typeof(p_candidate) <> 'object'
       OR octet_length(p_candidate::text) > 8192 THEN
        RAISE EXCEPTION 'Invalid ICE candidate payload'
            USING ERRCODE = '22023';
    END IF;

    -- 3. Atomically check participant, active status, candidate bounds (< 150), and append
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
        -- Provide precise diagnostics without leaking unauthorized data
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

-- ----------------------------------------------------------------------------
-- 2. SEC-03: Harden purge_old_data with bounds and administrative restriction
-- ----------------------------------------------------------------------------
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

    -- Purge Routing Logs
    DELETE FROM public.routing_logs 
    WHERE created_at < cutoff_date;

    -- Purge Feedback Signals
    DELETE FROM public.feedback_signals 
    WHERE created_at < cutoff_date;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. SEC-04: Protect Profiles Table & Enforce Privacy
-- ----------------------------------------------------------------------------

-- Helper function to evaluate whether a profile is legitimately accessible
CREATE OR REPLACE FUNCTION public.fn_is_profile_accessible(p_target_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
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
    -- 3. Friends
    OR EXISTS (
      SELECT 1 
      FROM public.friends f
      WHERE (f.user_id = auth.uid() AND f.friend_id = p_target_id)
         OR (f.friend_id = auth.uid() AND f.user_id = p_target_id)
    )
    -- 4. Friend requests (sender or recipient)
    OR EXISTS (
      SELECT 1 
      FROM public.friend_requests fr
      WHERE (fr.sender_id = auth.uid() AND fr.receiver_id = p_target_id)
         OR (fr.receiver_id = auth.uid() AND fr.sender_id = p_target_id)
    )
    -- 5. Active or recent call participant
    OR EXISTS (
      SELECT 1 
      FROM public.calls c
      WHERE (c.sender_id = auth.uid() OR c.caller_id = auth.uid() OR c.receiver_id = auth.uid() OR c.callee_id = auth.uid())
        AND (c.sender_id = p_target_id OR c.caller_id = p_target_id OR c.receiver_id = p_target_id OR c.callee_id = p_target_id)
    );
$$;

-- Replace open profiles_select_authenticated policy with relationship-restricted policy
DROP POLICY IF EXISTS "profiles_select_authenticated" ON public.profiles;

CREATE POLICY "profiles_select_authenticated" ON public.profiles
FOR SELECT TO authenticated
USING (
  public.fn_is_profile_accessible(id)
);

-- Secure search function to allow finding users without exposing full table to bulk harvesting
CREATE OR REPLACE FUNCTION public.search_users(
    p_query text,
    p_limit int DEFAULT 20
)
RETURNS TABLE (
    id uuid,
    username text,
    full_name text,
    avatar_url text,
    about text,
    is_online boolean,
    last_seen timestamptz,
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
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_clean := trim(p_query);
    IF length(v_clean) < 1 OR length(v_clean) > 100 THEN
        RETURN;
    END IF;

    p_limit := LEAST(GREATEST(p_limit, 1), 50);

    IF v_clean LIKE '%@%' THEN
        RETURN QUERY
        SELECT 
            p.id,
            p.username,
            p.full_name,
            p.avatar_url,
            p.about,
            p.is_online,
            CASE WHEN p.privacy_show_last_seen = false THEN NULL ELSE p.last_seen END,
            CASE WHEN p.privacy_show_status = false THEN NULL ELSE p.status END,
            p.email
        FROM public.profiles p
        WHERE lower(p.email) = lower(v_clean)
        LIMIT p_limit;
    ELSE
        RETURN QUERY
        SELECT 
            p.id,
            p.username,
            p.full_name,
            p.avatar_url,
            p.about,
            p.is_online,
            CASE WHEN p.privacy_show_last_seen = false THEN NULL ELSE p.last_seen END,
            CASE WHEN p.privacy_show_status = false THEN NULL ELSE p.status END,
            CASE WHEN p.id = v_uid THEN p.email ELSE '' END as email
        FROM public.profiles p
        WHERE p.username ILIKE ('%' || v_clean || '%')
           OR p.full_name ILIKE ('%' || v_clean || '%')
        LIMIT p_limit;
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. SEC-05: Harden Storage Read Policy on storage.objects
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "talkmate_read_policy" ON storage.objects;

CREATE POLICY "talkmate_read_policy" ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'talkmate' AND (
        -- 1. Owner can always read their own objects
        owner = auth.uid()

        -- 2. User directory: owner can read anything, others can ONLY read public profile avatars ('profile_%')
        OR (
            (storage.foldername(name))[1] = 'users' AND (
                (storage.foldername(name))[2] = auth.uid()::text
                OR storage.filename(name) LIKE 'profile_%'
            )
        )

        -- 3. Groups directory: creator or group members only
        OR (
            (storage.foldername(name))[1] = 'groups' AND (
                -- Temporary group avatar created by current user
                (storage.foldername(name))[2] IS NULL AND owner = auth.uid()
                -- Or participant of the group chat
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

-- ----------------------------------------------------------------------------
-- 5. SEC-02: Revoke Broad Privileges & Enforce Strict Allowlist
-- ----------------------------------------------------------------------------

-- Revoke broad EXECUTE privileges from PUBLIC, anon, authenticated
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

-- Revoke dangerous administrative raw SQL runner
REVOKE ALL ON FUNCTION public.run_sql(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_sql(text) TO service_role;

-- Revoke administrative purge_old_data from client
REVOKE ALL ON FUNCTION public.purge_old_data(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_data(integer) TO service_role;

-- Revoke rate limiting & reporting from normal authenticated users
REVOKE ALL ON FUNCTION public.increment_rate_limit(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_rate_limit(uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.get_device_report(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_device_report(uuid) TO service_role;

-- Client Allowlist: explicitly grant EXECUTE on verified client RPCs to authenticated (and service_role)
GRANT EXECUTE ON FUNCTION public.fn_add_call_candidate(uuid, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.register_device_token(uuid, text, text, text, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_register_device_token(uuid, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.unregister_device_token(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_get_total_unread_count(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_update_message_status(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_mark_chat_as_read(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_toggle_reaction_v4(uuid, uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_ai_weight_snapshot(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_log_notification_event(uuid, text, text, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_item_accessible(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_is_profile_accessible(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_users(text, integer) TO authenticated, service_role;
