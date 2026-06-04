/*
  STAGE H: POLICY ENFORCEMENT VERIFICATION
  ========================================
  
  PHASE 2: VERIFY & CLEANUP
  Run this AFTER sending a test message.
*/

-- 1. Check Logs (Should see 'POLICY_BLOCK')
SELECT * 
FROM public.routing_logs 
WHERE reason = 'POLICY_BLOCK' 
ORDER BY created_at DESC 
LIMIT 5;

-- 2. Cleanup
DELETE FROM public.ai_policies 
WHERE name = 'Test Block Policy';
