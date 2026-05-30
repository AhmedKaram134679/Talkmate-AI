/*
  RESET TEST CONDITIONS
  =====================
  The previous test hit 'AUTO_HEAL_THROTTLED', meaning Rate Limiting blocked the message 
  before it reached the Trust Engine.
  
  This script:
  1. Clears Rate Limits for the user.
  2. Ensures AI is Enabled.
  3. Re-asserts Low Trust & Quiet Hours.
*/

DO $$
DECLARE
    v_user_id UUID;
BEGIN
    -- Get User
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN SELECT id INTO v_user_id FROM auth.users LIMIT 1; END IF;

    -- 1. Clear Rate Limits (Nuclear Option for Test)
    DELETE FROM public.notification_rate_limits WHERE user_id = v_user_id;

    -- CLEAR LOGS (Source of the View) to reset stats
    DELETE FROM public.routing_logs WHERE recipient_id = v_user_id;
    
    -- 2. Ensure AI is Enabled
    INSERT INTO public.notification_ai_settings (user_id, is_enabled, adaptive_mode)
    VALUES (v_user_id, true, true)
    ON CONFLICT (user_id) DO UPDATE SET is_enabled = true;

    -- 3. Re-Assert Low Trust (Just in case)
    UPDATE public.user_trust_scores SET trust_score = 20.0 WHERE user_id = v_user_id;

    RAISE NOTICE 'Test Conditions Reset! Rate Limits Cleared.';
END $$;
