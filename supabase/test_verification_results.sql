/*
  STAGE I: VERIFICATION RESULTS
  =============================
  Run this AFTER sending a message while the breaker was tripped.
*/

-- 1. Check Breaker State
SELECT service_name, state, failure_count, last_failure_at 
FROM public.circuit_breakers 
WHERE service_name = 'fcm';

-- 2. Check Routing Logs for 'circuit_broken' or fallback usage
-- We look for logs created in the last 5 minutes.
SELECT 
    created_at, 
    recipient_id, 
    decision, 
    reason, 
    delivery_state 
FROM public.routing_logs 
ORDER BY created_at DESC 
LIMIT 5;

-- 3. Check DLQ (If fallback failed)
SELECT * FROM public.notification_dlq ORDER BY created_at DESC LIMIT 5;
