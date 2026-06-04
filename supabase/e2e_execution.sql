-- E2E TEST EXECUTION (STAGES Y-H) - REFINED SENIOR EDITION
-- Objective: Traceable scenario execution and deep auditing.

-- SCENARIO 1: Consent Guard (Marketing to AhmedKaram - Opted Out)
-- EXPECTED: decision='skipped', reason='FLAG_DISABLED' or 'consent_missing'
INSERT INTO public.messages ("senderId", "chatId", "type", "text")
VALUES ('2ae1af25-46ff-417d-b5a0-449bbbc0c1c5', 'e2e11111-1111-1111-1111-111111111111', 'marketing', 'Special Offer!')
RETURNING id as scenario_1_msg_id;

-- SCENARIO 2: DND Active (Normal Message to AhmedKaram - DND ON)
-- EXPECTED: decision='sent', priority='normal' (silenced)
INSERT INTO public.messages ("senderId", "chatId", "type", "text")
VALUES ('2ae1af25-46ff-417d-b5a0-449bbbc0c1c5', 'e2e11111-1111-1111-1111-111111111111', 'text', 'Hello?')
RETURNING id as scenario_2_msg_id;

-- SCENARIO 3: DND Bypass (Critical/Call to AhmedKaram - DND ON)
-- EXPECTED: decision='sent', priority='high' (bypass)
INSERT INTO public.messages ("senderId", "chatId", "type", "text")
VALUES ('2ae1af25-46ff-417d-b5a0-449bbbc0c1c5', 'e2e11111-1111-1111-1111-111111111111', 'call', 'Incoming Call')
RETURNING id as scenario_3_msg_id;

-- SCENARIO 4: Fatigue Cooldown (AhmedKaramFathy - RECENTLY THROTTLED)
-- EXPECTED: decision='throttled', reason='HEALING_COOLDOWN_ACTIVE'
INSERT INTO public.messages ("senderId", "chatId", "type", "text")
VALUES ('20f672ea-ebc9-49d1-9a8a-acd4fa703b7c', 'e2e33333-3333-3333-3333-333333333333', 'text', 'Traceable Update')
RETURNING id as scenario_4_msg_id;

-- SCENARIO 5: Multi-Device Sync (Multiple devices for Kremeto)
-- EXPECTED: 2 routing_logs entries (one per device)
INSERT INTO public.messages ("senderId", "chatId", "type", "text")
VALUES ('2ae1af25-46ff-417d-b5a0-449bbbc0c1c5', 'e2e22222-2222-2222-2222-222222222222', 'text', 'Sync Multi-Device')
RETURNING id as scenario_5_msg_id;

-- 5. ENHANCED AUDIT QUERY (Last 10 Minutes)
SELECT 
    created_at,
    recipient_id,
    decision,
    priority,
    reason,
    meta->>'rule' as rule_applied,
    meta->'adaptive_stats' as stats_snapshot,
    device_id
FROM public.routing_logs
WHERE created_at > now() - interval '10 minutes'
ORDER BY created_at DESC;
