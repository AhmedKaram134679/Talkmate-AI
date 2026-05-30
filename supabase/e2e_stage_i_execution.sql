-- E2E STAGE I: COST & RATE GOVERNANCE VERIFICATION
-- Objective: Validate Rate Governor, Cost Guard, and Critical Bypass.

-- 1. PREPARATION: Reset Limits for Karam
DELETE FROM public.notification_rate_limits WHERE user_id = '20f672ea-ebc9-49d1-9a8a-acd4fa703b7c';

-- 2. SCENARIO I-1: Marketing Spam Protection
-- Limit for marketing is 1 per hour.
-- First marketing message (Karam from Fathy) -> EXPECTED: sent
INSERT INTO public.messages ("senderId", "chatId", "type", "text")
VALUES ('2ae1af25-46ff-417d-b5a0-449bbbc0c1c5', 'e2e11111-1111-1111-1111-111111111111', 'marketing', 'First Offer')
RETURNING id as msg_mark_1;

-- Second marketing message (Karam from Fathy) -> EXPECTED: skipped (RATE_LIMIT_EXCEEDED)
INSERT INTO public.messages ("senderId", "chatId", "type", "text")
VALUES ('2ae1af25-46ff-417d-b5a0-449bbbc0c1c5', 'e2e11111-1111-1111-1111-111111111111', 'marketing', 'Spam Offer')
RETURNING id as msg_mark_2;

-- 3. SCENARIO I-2: Critical Bypass of Rate Limit
-- Even if Rate Limited, Calls should go through.
-- EXPECTED: sent (CRITICAL_MUST_DELIVER)
INSERT INTO public.messages ("senderId", "chatId", "type", "text")
VALUES ('2ae1af25-46ff-417d-b5a0-449bbbc0c1c5', 'e2e11111-1111-1111-1111-111111111111', 'call', 'Emergency Call')
RETURNING id as msg_call_bypass;

-- 4. SCENARIO I-3: Cost Guard Downgrade
-- Simulate High Priority Ratio (> 0.3) for Kremeto (4043be4d-3312-4fac-a0db-3b1502a0d572)
-- We insert 5 high priority logs for him recently.
INSERT INTO public.routing_logs (recipient_id, decision, priority, reason, created_at, chat_id, message_id, device_id)
SELECT 
  '4043be4d-3312-4fac-a0db-3b1502a0d572', 
  'sent', 
  'high', 
  'STANDARD_DELIVERY',
  now() - interval '1 minute',
  'e2e22222-2222-2222-2222-222222222222',
  gen_random_uuid(),
  'dev_active_1'
FROM generate_series(1, 5);

-- Send a standard message to Kremeto.
-- EXPECTED: sent, priority='normal', reason='COST_GUARD_DOWNGRADE'
INSERT INTO public.messages ("senderId", "chatId", "type", "text")
VALUES ('2ae1af25-46ff-417d-b5a0-449bbbc0c1c5', 'e2e22222-2222-2222-2222-222222222222', 'text', 'Budget Friendly Sync')
RETURNING id as msg_cost_grad;

-- 5. FINAL AUDIT
SELECT 
    created_at,
    recipient_id,
    decision,
    priority,
    reason,
    meta->'rate_limit' as rl_info,
    meta->'cost_governance' as cost_info
FROM public.routing_logs
WHERE created_at > now() - interval '5 minutes'
ORDER BY created_at DESC;
