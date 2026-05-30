-- DEEP CLEAN DEVICE TOKENS
-- Use this for a specific user ID to force their app to re-register from scratch.

-- Replace 'YOUR_USER_ID_HERE' with the target user ID (e.g., 20f672ea-ebc9-49d1-9a8a-acd4fa703b7c)
DELETE FROM public.user_devices 
WHERE user_id = 'YOUR_USER_ID_HERE';

-- Also clear the routing logs for a clean test state if desired
-- DELETE FROM public.routing_logs WHERE recipient_id = 'YOUR_USER_ID_HERE';
