-- SQL for robust FCM token registration (Stage Z-4: Reliability)
-- This RPC handles the cleanup of existing tokens to prevent unique constraint violations.

CREATE OR REPLACE FUNCTION public.register_device_token(
    p_user_id uuid,
    p_fcm_token text,
    p_device_id text,
    p_platform text,
    p_web_push_subscription jsonb DEFAULT null
)
RETURNS void AS $$
BEGIN
    -- 1. Revoke the token from ANY other record to ensure uniqueness.
    -- Use SECURITY DEFINER to bypass RLS, allowing this cleanup even if 
    -- the token previously belonged to a different user.
    DELETE FROM public.user_devices 
    WHERE fcm_token = p_fcm_token 
      AND (user_id <> p_user_id OR device_id <> p_device_id);

    -- 2. Upsert the current user's registration for this device.
    -- If (user_id, device_id) exists, update the token.
    -- If not, insert a new record.
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
        p_user_id, 
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
$$ LANGUAGE plpgsql SECURITY DEFINER;
