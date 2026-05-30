/*
  STRESS TEST SIMULATION SCRIPT
  =============================
  Target: 1000 Messages/min, 2000 Reactions/min
  
  Instructions:
  1. Run this script in Supabase SQL Editor.
  2. Call the function: SELECT run_stress_test_batch(1000);
  3. Monitor database CPU and Logs.
*/

-- 1. Setup a dedicated Stress Test Chat to avoid spamming real users
DO $$
DECLARE
  v_chat_id uuid;
  v_user1 uuid := '00000000-0000-0000-0000-000000000001'; -- Dummy User 1
  v_user2 uuid := '00000000-0000-0000-0000-000000000002'; -- Dummy User 2
BEGIN
  -- Ensure dummy users exist (if auth.users allows, otherwise rely on existing or skip FK checks if possible, 
  -- but usually we need real FKs. We will assume for this mock test we can use random UUIDs if constraints allow,
  -- OR better: We pick a random REAL user to be safe if constraints are strict).
  -- For safety/simplicity in this script, we will try to find 2 real users.
  
  SELECT id INTO v_user1 FROM auth.users LIMIT 1;
  SELECT id INTO v_user2 FROM auth.users OFFSET 1 LIMIT 1;
  
  IF v_user1 IS NULL OR v_user2 IS NULL THEN
    RAISE NOTICE 'Not enough users to run stress test properly.';
    RETURN;
  END IF;

  -- Create or Get Stress Chat
  INSERT INTO public.conversations (is_group, group_name, creator_id)
  VALUES (true, 'STRESS_TEST_ZONE', v_user1)
  RETURNING id INTO v_chat_id;

  -- Add participants
  INSERT INTO public.conversation_participants (conversation_id, user_id)
  VALUES (v_chat_id, v_user1), (v_chat_id, v_user2)
  ON CONFLICT DO NOTHING;
  
  RAISE NOTICE 'Stress Test Chat Created: %', v_chat_id;
END $$;

-- 2. Function to Run Batch Load
CREATE OR REPLACE FUNCTION run_stress_test_batch(p_iterations int)
RETURNS void AS $$
DECLARE
  v_chat_id uuid;
  v_user_id uuid;
  v_msg_id uuid;
  v_emojis text[] := ARRAY['👍', '❤️', '😂', '😮', '😢', '🔥'];
  i integer;
BEGIN
  -- Get the stress chat ID
  SELECT id INTO v_chat_id FROM public.conversations WHERE name = 'STRESS_TEST_ZONE' LIMIT 1;
  
  IF v_chat_id IS NULL THEN
    RAISE EXCEPTION 'Stress chat not found. Run setup block first.';
  END IF;

  -- Get a user
  SELECT user_id INTO v_user_id FROM public.conversation_participants WHERE conversation_id = v_chat_id LIMIT 1;

  FOR i IN 1..p_iterations LOOP
    -- A. INSERT MESSAGE
    INSERT INTO public.messages (chat_id, sender_id, text, type, status)
    VALUES (
      v_chat_id, 
      v_user_id, 
      'Stress Test Message ' || i || ' - ' || gen_random_uuid(), 
      'text', 
      'sent'
    )
    RETURNING id INTO v_msg_id;

    -- B. TOGGLE REACTION (2x per message on average to hit 2000 target vs 1000 msgs)
    PERFORM public.fn_toggle_reaction_v4(v_msg_id, v_chat_id, v_user_id, v_emojis[1 + (i % 6)]);
    
    -- Occasional second reaction (simulate race or high activity)
    IF i % 2 = 0 THEN
       PERFORM public.fn_toggle_reaction_v4(v_msg_id, v_chat_id, v_user_id, '🚀');
    END IF;
    
  END LOOP;
END;
$$ LANGUAGE plpgsql;
