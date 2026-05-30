/*
  UNIVERSAL VERIFICATION SETUP (ALL USERS)
  ========================================
  Since we can't easily determine the User ID of the app user from here,
  we will apply the test conditions to ALL users.
  
  WARNING: This is for Development/Testing only!
*/

DO $$
BEGIN
    -- 1. CLEAR ALL Logs (Reset Healing/Rate Limits)
    TRUNCATE TABLE public.routing_logs CASCADE;
    TRUNCATE TABLE public.notification_rate_limits CASCADE;
    -- Also clear cached stats if possible (Views update automatically)

    -- 2. Set LOW TRIST for ALL Users
    INSERT INTO public.user_trust_scores (user_id, trust_score)
    SELECT id, 20.0 FROM auth.users
    ON CONFLICT (user_id) DO UPDATE SET trust_score = 20.0;

    -- 3. Set QUIET HOURS for ALL Users (All Hours)
    INSERT INTO public.user_quiet_hours_prediction (user_id, open_hour, is_quiet_hour)
    SELECT u.id, h, true 
    FROM auth.users u, generate_series(0, 23) as h
    ON CONFLICT (user_id, open_hour) DO UPDATE SET is_quiet_hour = true;

    -- 4. Enable Feature Flags for ALL
    DELETE FROM public.ai_feature_flags WHERE feature_key = 'ai_verification_mode';
    -- No allow_users needed if we set it globally enabled
    INSERT INTO public.ai_feature_flags (feature_key, is_enabled, rollout_percentage)
    VALUES ('ai_verification_mode', true, 100);

    -- 5. Force Enable AI Settings for ALL
    INSERT INTO public.notification_ai_settings (user_id, is_enabled, adaptive_mode)
    SELECT id, true, true FROM auth.users
    ON CONFLICT (user_id) DO UPDATE SET is_enabled = true;

    RAISE NOTICE 'Universal Test Conditions Applied to All Users.';
END $$;
