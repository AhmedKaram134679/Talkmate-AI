/*
  MASTER SYSTEM VERIFICATION
  ==========================
  This script sets up a test user with specific conditions to verify:
  1. Trust Score Logic (Humble Mode)
  2. Quiet Hours (Bundling)
  3. Feature Flags (Rollout)
*/

-- 1. Setup Test Data (For a fallback user if auth.uid() is null)
DO $$
DECLARE
    v_user_id UUID;
BEGIN
    -- Try to get current user, or fallback to the first user in the system
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id FROM auth.users LIMIT 1;
    END IF;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No users found in auth.users to test with!';
    END IF;

    -- Reset Trust Score to LOW (Should trigger Humble Mode)
    INSERT INTO public.user_trust_scores (user_id, trust_score)
    VALUES (v_user_id, 20.0) 
    ON CONFLICT (user_id) DO UPDATE SET trust_score = 20.0;

    -- Set CURRENT hour as Quiet Hour
    INSERT INTO public.user_quiet_hours_prediction (user_id, open_hour, is_quiet_hour)
    SELECT v_user_id, h, true 
    FROM generate_series(0, 23) as h
    ON CONFLICT (user_id, open_hour) DO UPDATE SET is_quiet_hour = true;

    -- Ensure Feature Flag is ENABLED for this user
    DELETE FROM public.ai_feature_flags WHERE feature_key = 'ai_verification_mode';
    INSERT INTO public.ai_feature_flags (feature_key, is_enabled, allow_users)
    VALUES ('ai_verification_mode', true, ARRAY[v_user_id]);
    
    RAISE NOTICE 'Test Setup Complete for User: %', v_user_id;
END $$;


-- 2. INSTRUCTIONS FOR USER:
--   a. Send a 'Marketing' notification (if possible) -> Should be SILENCED/THROTTLED due to Trust Score.
--   b. Send a 'Normal' notification -> Should be BUNDLED due to Quiet Hours.
--   c. Send a 'Critical' notification -> Should BYPASS everything.

-- 3. CHECK RESULTS (Run this block AFTER sending notifications)
/*
SELECT 
    created_at,
    priority,
    decision,
    reason,
    meta->>'trust_score' as trust_score,
    meta->>'quiet_hours_applied' as quiet_applied,
    meta->>'priority_adjustment' as adjustment
FROM public.routing_logs
ORDER BY created_at DESC
LIMIT 5;
*/

-- 4. CLEANUP (Run to restore normal state)
/*
UPDATE public.user_trust_scores SET trust_score = 80.0 WHERE user_id = auth.uid();
DELETE FROM public.user_quiet_hours_prediction WHERE user_id = auth.uid();
*/
