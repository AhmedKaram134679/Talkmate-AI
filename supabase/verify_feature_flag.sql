/*
  STAGE J: VERIFICATION (Feature Flags)
  =====================================
  
  This script tests the deterministic rollout logic.
*/

-- 1. Create a Test Flag (50% Rollout)
INSERT INTO public.ai_feature_flags (feature_key, is_enabled, rollout_percentage)
VALUES ('test_50_percent_flag', true, 50)
ON CONFLICT (feature_key) DO UPDATE SET rollout_percentage = 50;

-- 2. Test with deterministic UUIDs
-- UUID ending in ...00 should likely hash to low number (True)
-- UUID ending in ...FF could be high (False)
-- We'll just run against the current user and a few generated ones.

WITH test_users AS (
    SELECT gen_random_uuid() as uid FROM generate_series(1,5)
)
SELECT 
    uid, 
    public.check_feature_flag('test_50_percent_flag', uid) as is_enabled,
    ABS(hashtext(uid::text || 'test_50_percent_flag')) % 100 as calculated_limit
FROM test_users;

-- 3. Cleanup
DELETE FROM public.ai_feature_flags WHERE feature_key = 'test_50_percent_flag';
