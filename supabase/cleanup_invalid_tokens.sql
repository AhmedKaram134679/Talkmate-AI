-- CLEANUP INVALID TOKENS
-- This script deactivates devices with obvious invalid tokens (e.g., Web Push subscriptions in FCM column)
-- and stale devices to force clean re-registration on next app start.

-- 1. Deactivate anything that looks like a JSON Web Push subscription but is in fcm_token
UPDATE public.user_devices
SET 
  is_active = false,
  updated_at = now()
WHERE 
  fcm_token LIKE '{%' OR 
  fcm_token LIKE '%endpoint%' OR
  fcm_token LIKE '%keys%';

-- 2. Deactivate tokens that haven't been touched in 60 days
UPDATE public.user_devices
SET 
  is_active = false,
  updated_at = now()
WHERE 
  updated_at < now() - interval '60 days'
  AND is_active = true;

-- 3. Deactivate duplicates (keeping the most recent)
WITH duplicates AS (
  SELECT id,
         ROW_NUMBER() OVER (PARTITION BY user_id, device_id ORDER BY updated_at DESC) as rank
  FROM public.user_devices
  WHERE is_active = true
)
UPDATE public.user_devices
SET is_active = false
WHERE id IN (SELECT id FROM duplicates WHERE rank > 1);
