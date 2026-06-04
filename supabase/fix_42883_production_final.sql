-- FIX: PostgrestException 42883 (operator does not exist: text ->> unknown)
-- Applying Golden Rules for JSONB handling in Triggers.
-- 1. Use to_jsonb(NEW) instead of row_to_json(NEW)
-- 2. Use explicit (record::jsonb)->>'field' casting
-- 3. Ensure all JSON operations use jsonb

BEGIN;

-- 1. REPAIR: notify_push_handler
-- Fixes the header extraction and payload conversion
CREATE OR REPLACE FUNCTION public.notify_push_handler()
RETURNS trigger AS $$
DECLARE
  headers_jsonb jsonb;
BEGIN
  -- Safely extract headers using jsonb
  BEGIN
    headers_jsonb := current_setting('request.headers')::jsonb;
  EXCEPTION WHEN OTHERS THEN
    headers_jsonb := '{}'::jsonb;
  END;

  PERFORM
    net.http_post(
      url := 'https://' || (headers_jsonb->>'host') || '/functions/v1/push-handler',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (headers_jsonb->>'authorization')
      ),
      body := jsonb_build_object(
        'type', TG_TABLE_NAME,
        'record', to_jsonb(NEW) -- Golden Rule: to_jsonb
      )
    );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. REPAIR: notify_professional_push
-- Ensures we use snake_case and to_jsonb if we ever pass the whole record
CREATE OR REPLACE FUNCTION public.notify_professional_push()
RETURNS trigger AS $$
DECLARE
  service_role_key TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImljZGJiZnNqYnNsemN0c2h4eXRkIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MDQyODY2OCwiZXhwIjoyMDk2MDA0NjY4fQ.VmBetxbbIBDF9gxnAKC_cikCXLD66jXao-YR9I_Tm0Y';
BEGIN
  PERFORM
    net.http_post(
      url := 'https://icdbbfsjbslzctshxytd.supabase.co/functions/v1/push-handler',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key
      ),
      body := jsonb_build_object(
        'type', 'message',
        'message_id', NEW.id,
        'chat_id', NEW.chat_id,
        'sender_id', NEW.sender_id,
        'content_type', NEW.type,
        'text_content', NEW.text,
        'timestamp', EXTRACT(EPOCH FROM NEW.created_at)::TEXT
      )
    );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. REPAIR: seed_message_delivery
-- Ensures we use the correct snake_case columns confirmed by the user
CREATE OR REPLACE FUNCTION public.seed_message_delivery()
RETURNS trigger AS $$
BEGIN
  -- Insert 'sent' rows for recipients
  -- chatId -> chat_id, senderId -> sender_id
  INSERT INTO public.message_delivery (message_id, user_id, device_id, status)
  SELECT NEW.id, ud.user_id, ud.device_id, 'sent'
  FROM public.conversation_participants cp
  JOIN public.user_devices ud ON ud.user_id = cp.user_id
  WHERE cp.conversation_id = NEW.chat_id
    AND cp.user_id <> NEW.sender_id
    AND ud.device_id IS NOT NULL;
    
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. REPAIR: Update any other function using ->> on potentially text columns
-- Check public.fn_update_learning_state_on_override (from routing_logs)
CREATE OR REPLACE FUNCTION public.fn_update_learning_state_on_override()
RETURNS TRIGGER AS $$
BEGIN
    -- user_override and meta cast to jsonb
    IF ((NEW.meta::jsonb)->'user_override'->>'applied') = 'true' THEN
        INSERT INTO public.user_learning_states (user_id, category, override_count_30d, last_override_at)
        VALUES (
            NEW.recipient_id, 
            COALESCE((NEW.meta::jsonb)->>'scenario', 'chat'), 
            1, 
            now()
        )
        ON CONFLICT (user_id, category) DO UPDATE SET
            override_count_30d = user_learning_states.override_count_30d + 1,
            last_override_at = now(),
            learning_paused = CASE WHEN user_learning_states.override_count_30d + 1 >= 5 THEN true ELSE user_learning_states.learning_paused END,
            reason = CASE WHEN user_learning_states.override_count_30d + 1 >= 5 THEN 'EXCESSIVE_OVERRIDES' ELSE user_learning_states.reason END;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMIT;

-- Force reload schema
NOTIFY pgrst, 'reload schema';
