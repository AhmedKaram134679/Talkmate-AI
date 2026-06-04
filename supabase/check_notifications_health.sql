-- 1. Check if the Edge Function trigger is firing (General Check)
SELECT * FROM net.http_request_queue ORDER BY id DESC LIMIT 10;

-- 2. Verify Trigger and Extension Health
-- Check if pg_net extension is installed
SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name = 'pg_net';

-- Check if our trigger exists on the messages table
SELECT 
    tgname as trigger_name, 
    relname as table_name,
    tgenabled as status 
FROM pg_trigger 
JOIN pg_class ON pg_trigger.tgrelid = pg_class.oid 
WHERE relname = 'messages';

-- 3. Check for recent real messages
SELECT id, sender_id, chat_id, created_at FROM public.messages ORDER BY created_at DESC LIMIT 5;

-- 4. Check the Edge Function routing decisions (Recent)
SELECT 
  created_at,
  recipient_id,
  decision,
  reason,
  meta->>'app_state' as app_state,
  meta->>'is_online' as is_online
FROM routing_logs 
ORDER BY created_at DESC 
LIMIT 10;

-- 2. Check the Edge Function routing decisions (Why was it skipped/sent?)
SELECT 
  created_at,
  recipient_id,
  decision,
  reason,
  meta->>'app_state' as app_state,
  meta->>'is_online' as is_online,
  meta->>'device_arbitration' as arbitration
FROM routing_logs 
ORDER BY created_at DESC 
LIMIT 10;

-- 3. Verify recipient device status
-- Replace 'RECIPIENT_USER_ID' with the actual user ID of the Android device
SELECT 
  user_id, 
  device_id, 
  is_active, 
  is_online, 
  app_state, 
  updated_at 
FROM user_devices 
-- WHERE user_id = 'RECIPIENT_USER_ID' 
ORDER BY updated_at DESC;
