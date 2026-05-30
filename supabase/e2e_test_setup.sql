-- E2E TEST DATA SETUP (STAGES Y-H) - REFINED SENIOR EDITION
-- Objective: Multi-scenario deterministic testing with safety and observability.

-- 0. Schema Reconciliation (Safety Guard for custom DB columns)
DO $$
BEGIN
    -- Fix routing_outcome if it exists and is NOT NULL
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'routing_logs' AND column_name = 'routing_outcome') THEN
        ALTER TABLE public.routing_logs ALTER COLUMN routing_outcome DROP NOT NULL;
    END IF;
    
    -- Ensure platform in user_devices is handled
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'user_devices' AND column_name = 'platform') THEN
        ALTER TABLE public.user_devices ALTER COLUMN platform DROP NOT NULL;
    END IF;
END $$;

-- 1. Setup Devices for Test Users
-- SAFETY: All tokens prefixed with TEST_ONLY_ to prevent real FCM dispatch.
INSERT INTO public.user_devices (user_id, device_id, fcm_token, dnd_enabled, dnd_start_time, dnd_end_time, is_active, platform)
VALUES 
-- AhmedKaram (Protected)
('20f672ea-ebc9-49d1-9a8a-acd4fa703b7c', 'dev_protected_1', 'TEST_ONLY_token_protected_1', true, '00:00', '23:59', true, 'android'),
-- Kremeto (Active Multi-device)
('4043be4d-3312-4fac-a0db-3b1502a0d572', 'dev_active_1', 'TEST_ONLY_token_active_1', false, null, null, true, 'android'),
('4043be4d-3312-4fac-a0db-3b1502a0d572', 'dev_active_2', 'TEST_ONLY_token_active_2', false, null, null, true, 'android'),
-- AhmedKaramFathy (Fatigued)
('2ae1af25-46ff-417d-b5a0-449bbbc0c1c5', 'dev_fatigue_1', 'TEST_ONLY_token_fatigue_1', false, null, null, true, 'android')
ON CONFLICT (user_id, device_id) 
DO UPDATE SET 
    fcm_token = EXCLUDED.fcm_token,
    is_active = true, 
    dnd_enabled = EXCLUDED.dnd_enabled;

-- 2. Set Consent Statuses
INSERT INTO public.user_consent (user_id, notification_type, consent_status)
VALUES 
('20f672ea-ebc9-49d1-9a8a-acd4fa703b7c', 'marketing', false),
('4043be4d-3312-4fac-a0db-3b1502a0d572', 'marketing', true)
ON CONFLICT (user_id, notification_type) DO UPDATE SET consent_status = EXCLUDED.consent_status;

-- 3. Simulate Deterministic Fatigue for AhmedKaramFathy
-- A. Clear previous test logs for this user
DELETE FROM public.routing_logs WHERE recipient_id = '2ae1af25-46ff-417d-b5a0-449bbbc0c1c5';

-- B. Insert 15 recent "sent" logs with NO open signals (Fatigue source)
INSERT INTO public.routing_logs (recipient_id, decision, priority, reason, created_at)
SELECT 
  '2ae1af25-46ff-417d-b5a0-449bbbc0c1c5', 
  'sent', 
  'normal', 
  'STANDARD_DELIVERY',
  now() - (interval '1 hour' * s.i)
FROM generate_series(1, 15) s(i);

-- C. Add a RECENT "throttled" log (Deterministic trigger for Auto-Healing cooldown/limit logic)
INSERT INTO public.routing_logs (recipient_id, decision, priority, reason, created_at)
VALUES ('2ae1af25-46ff-417d-b5a0-449bbbc0c1c5', 'throttled', 'normal', 'PREVIOUS_AUTO_HEAL', now() - interval '5 minutes');

-- 4. Setup Test Conversations (Required for participant lookup)
INSERT INTO public.conversations (id, is_group)
VALUES 
('e2e11111-1111-1111-1111-111111111111', false), -- Between Fathy & Karam
('e2e22222-2222-2222-2222-222222222222', false), -- Between Fathy & Kremeto
('e2e33333-3333-3333-3333-333333333333', false)  -- Between Karam & Fathy
ON CONFLICT (id) DO NOTHING;

-- 5. Join Users to Conversations
INSERT INTO public.conversation_participants (conversation_id, user_id)
VALUES 
-- Chat 1: Fathy & Karam
('e2e11111-1111-1111-1111-111111111111', '2ae1af25-46ff-417d-b5a0-449bbbc0c1c5'),
('e2e11111-1111-1111-1111-111111111111', '20f672ea-ebc9-49d1-9a8a-acd4fa703b7c'),
-- Chat 2: Fathy & Kremeto
('e2e22222-2222-2222-2222-222222222222', '2ae1af25-46ff-417d-b5a0-449bbbc0c1c5'),
('e2e22222-2222-2222-2222-222222222222', '4043be4d-3312-4fac-a0db-3b1502a0d572'),
-- Chat 3: Karam & Fathy
('e2e33333-3333-3333-3333-333333333333', '20f672ea-ebc9-49d1-9a8a-acd4fa703b7c'),
('e2e33333-3333-3333-3333-333333333333', '2ae1af25-46ff-417d-b5a0-449bbbc0c1c5')
ON CONFLICT (conversation_id, user_id) DO NOTHING;

-- 6. Create Observability View
CREATE OR REPLACE VIEW public.e2e_user_state AS
SELECT 
    p.id,
    p.username,
    COUNT(ud.device_id) as device_count,
    BOOL_OR(ud.dnd_enabled) as has_dnd_active,
    (SELECT consent_status FROM public.user_consent WHERE user_id = p.id AND notification_type = 'marketing') as marketing_consent
FROM public.profiles p
LEFT JOIN public.user_devices ud ON p.id = ud.user_id
WHERE p.id IN ('20f672ea-ebc9-49d1-9a8a-acd4fa703b7c', '4043be4d-3312-4fac-a0db-3b1502a0d572', '2ae1af25-46ff-417d-b5a0-449bbbc0c1c5')
GROUP BY p.id, p.username;

-- Final Verification
SELECT * FROM public.e2e_user_state;
