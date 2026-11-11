-- SQL for robust FCM token registration (Stage Z-4: Reliability)
-- This RPC handles the cleanup of existing tokens to prevent unique constraint violations.
--
-- SECURITY: the caller is taken from auth.uid(). The p_user_id argument is kept
-- only so the existing Dart call (SupabaseUserRepository.addFcmToken) keeps
-- working; it must equal the logged-in user or the call is rejected.

CREATE OR REPLACE FUNCTION public.register_device_token(
    p_user_id uuid,
    p_fcm_token text,
    p_device_id text,
    p_platform text,
    p_web_push_subscription jsonb DEFAULT null
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
    END IF;

    IF p_user_id IS DISTINCT FROM v_uid THEN
        RAISE EXCEPTION 'p_user_id must match the authenticated user' USING ERRCODE = '42501';
    END IF;

    IF p_fcm_token IS NULL OR length(btrim(p_fcm_token)) = 0
       OR p_device_id IS NULL OR length(btrim(p_device_id)) = 0 THEN
        RAISE EXCEPTION 'p_fcm_token and p_device_id are required' USING ERRCODE = '22023';
    END IF;

    -- 1. Revoke the token from ANY other record to ensure uniqueness.
    -- SECURITY DEFINER bypasses RLS so this works even if the token previously
    -- belonged to a different user (same physical device, new login).
    DELETE FROM public.user_devices
    WHERE fcm_token = p_fcm_token
      AND (user_id <> v_uid OR device_id <> p_device_id);

    -- 2. Upsert the current user's registration for this device.
    INSERT INTO public.user_devices (
        user_id,
        fcm_token,
        device_id,
        platform,
        web_push_subscription,
        is_active,
        updated_at,
        last_active_at
    )
    VALUES (
        v_uid,
        p_fcm_token,
        p_device_id,
        p_platform,
        p_web_push_subscription,
        true,
        now(),
        now()
    )
    ON CONFLICT (user_id, device_id)
    DO UPDATE SET
        fcm_token = EXCLUDED.fcm_token,
        platform = EXCLUDED.platform,
        web_push_subscription = EXCLUDED.web_push_subscription,
        is_active = true,
        updated_at = now(),
        last_active_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.register_device_token(uuid, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_device_token(uuid, text, text, text, jsonb) TO authenticated;


-- Called by the app on logout so this device stops receiving the previous
-- user's push notifications.
CREATE OR REPLACE FUNCTION public.unregister_device_token(p_device_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '28000';
    END IF;

    DELETE FROM public.user_devices
    WHERE user_id = auth.uid()
      AND device_id = p_device_id;
END;
$$;

REVOKE ALL ON FUNCTION public.unregister_device_token(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unregister_device_token(text) TO authenticated;
