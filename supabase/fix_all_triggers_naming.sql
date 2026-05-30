-- NUCLEAR DATABASE FIX: Comprehensive Schema, Trigger, and Policy Reset
-- This script ensures all camelCase is gone and replaces it with snake_case.
-- Fixes "record 'new' has no field 'chatId'" and other schema mismatch errors.

BEGIN;

--------------------------------------------------------------------------------
-- 1. DYNAMIC CLEANUP: Drop all Triggers and Policies on core tables
--------------------------------------------------------------------------------

DO $$
DECLARE
    r record;
BEGIN
    -- Drop all triggers on messages, reactions, calls
    -- Drop all triggers on messages, reactions, calls, profiles, etc.
    FOR r IN 
        SELECT trigger_name, event_object_table 
        FROM information_schema.triggers 
        WHERE event_object_table IN (
            'messages', 'reactions', 'calls', 'profiles', 
            'conversations', 'conversation_participants', 'message_delivery'
        )
        AND trigger_schema = 'public'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', r.trigger_name, r.event_object_table);
    END LOOP;

    -- Drop all policies on core tables
    FOR r IN 
        SELECT policyname, tablename 
        FROM pg_policies 
        WHERE tablename IN (
            'messages', 'reactions', 'calls', 'profiles', 
            'conversations', 'conversation_participants', 'message_delivery'
        )
        AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', r.policyname, r.tablename);
    END LOOP;
END $$;

--------------------------------------------------------------------------------
-- 2. SCHEMA SANITY: Ensure columns are snake_case
--------------------------------------------------------------------------------

DO $$
BEGIN
    -- 1. chatId -> chat_id
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'chatId') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'chat_id') THEN
            ALTER TABLE public.messages RENAME COLUMN "chatId" TO chat_id;
        ELSE
            UPDATE public.messages SET chat_id = "chatId" WHERE chat_id IS NULL;
            ALTER TABLE public.messages DROP COLUMN "chatId";
        END IF;
    END IF;

    -- 2. senderId -> sender_id
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'senderId') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'sender_id') THEN
            ALTER TABLE public.messages RENAME COLUMN "senderId" TO sender_id;
        ELSE
            UPDATE public.messages SET sender_id = "senderId" WHERE sender_id IS NULL;
            ALTER TABLE public.messages DROP COLUMN "senderId";
        END IF;
    END IF;

    -- 3. createdAt -> created_at
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'createdAt') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'created_at') THEN
            ALTER TABLE public.messages RENAME COLUMN "createdAt" TO created_at;
        ELSE
            UPDATE public.messages SET created_at = "createdAt" WHERE created_at IS NULL;
            ALTER TABLE public.messages DROP COLUMN "createdAt";
        END IF;
    END IF;

    -- 4. isEdited -> is_edited, editedAt -> edited_at...
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'isEdited') THEN
        ALTER TABLE public.messages RENAME COLUMN "isEdited" TO is_edited;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'editedAt') THEN
        ALTER TABLE public.messages RENAME COLUMN "editedAt" TO edited_at;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'replyToMessageId') THEN
        ALTER TABLE public.messages RENAME COLUMN "replyToMessageId" TO reply_to_message_id;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'deletedByName') THEN
        ALTER TABLE public.messages RENAME COLUMN "deletedByName" TO deleted_by_name;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'deletedFor') THEN
        ALTER TABLE public.messages RENAME COLUMN "deletedFor" TO deleted_for;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'isDeleted') THEN
        ALTER TABLE public.messages RENAME COLUMN "isDeleted" TO is_deleted;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'deletedAt') THEN
        ALTER TABLE public.messages RENAME COLUMN "deletedAt" TO deleted_at;
    END IF;

    -- 5. Profiles display_name, photo_url
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'displayName') THEN
        ALTER TABLE public.profiles RENAME COLUMN "displayName" TO display_name;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'photoUrl') THEN
        ALTER TABLE public.profiles RENAME COLUMN "photoUrl" TO photo_url;
    END IF;
END $$;

--------------------------------------------------------------------------------
-- 3. FUNCTION REPAIR: Create snake_case functions
--------------------------------------------------------------------------------

-- Helper: Check Access
DROP FUNCTION IF EXISTS public.is_item_accessible(uuid) CASCADE;
CREATE OR REPLACE FUNCTION public.is_item_accessible(_chat_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = _chat_id AND user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: Seed Delivery
CREATE OR REPLACE FUNCTION public.seed_message_delivery()
RETURNS trigger AS $$
BEGIN
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

-- Trigger: Notify Push Handler (Generic)
CREATE OR REPLACE FUNCTION public.notify_push_handler()
RETURNS trigger AS $$
BEGIN
  PERFORM
    net.http_post(
      url := 'https://' || current_setting('request.headers')::json->>'host' || '/functions/v1/push-handler',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('request.headers')::json->>'authorization'
      ),
      body := jsonb_build_object(
        'type', TG_TABLE_NAME,
        'record', row_to_json(NEW)
      )
    );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: Notify Professional Push
CREATE OR REPLACE FUNCTION public.notify_professional_push()
RETURNS trigger AS $$
DECLARE
  service_role_key TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5tZGNhdG96dHF1eWNjeXpheG5uIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NzA2OTIzMSwiZXhwIjoyMDgyNjQ1MjMxfQ.9vWT-tGwc3sSLCw0Qx_NZVroVXwEJTMqhMRyuoE1IZI';
BEGIN
  PERFORM
    net.http_post(
      url := 'https://nmdcatoztquyccyzaxnn.supabase.co/functions/v1/push-handler',
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

-- Trigger: Sync Analytics (from analytics_schema.sql)
CREATE OR REPLACE FUNCTION public.sync_analytics_trigger()
RETURNS trigger AS $$
DECLARE
  v_chat_id uuid;
  v_sender_id uuid;
  v_receiver_id uuid;
BEGIN
  IF (TG_OP = 'INSERT') THEN
    SELECT chat_id, sender_id -- FIXED: Use snake_case
    INTO v_chat_id, v_sender_id
    FROM public.messages 
    WHERE id = NEW.message_id;

    v_receiver_id := NEW.user_id;

    INSERT INTO public.message_analytics (
      message_id, chat_id, sender_id, receiver_id, device_id, status, delivered_at, read_at
    ) VALUES (
      NEW.message_id, v_chat_id, v_sender_id, v_receiver_id, NEW.device_id, NEW.status, NEW.delivered_at, NEW.read_at
    );
  ELSIF (TG_OP = 'UPDATE') THEN
    UPDATE public.message_analytics
    SET status = NEW.status, delivered_at = NEW.delivered_at, read_at = NEW.read_at, updated_at = now()
    WHERE message_id = NEW.message_id AND device_id = NEW.device_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: Sync Message Reactions
CREATE OR REPLACE FUNCTION public.sync_message_reactions()
RETURNS trigger AS $$
DECLARE
  target_message_id uuid;
  aggregated_reactions jsonb;
BEGIN
  target_message_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.message_id ELSE NEW.message_id END;
  SELECT jsonb_object_agg(user_id, emoji) INTO aggregated_reactions FROM public.reactions WHERE message_id = target_message_id;
  UPDATE public.messages SET reactions = COALESCE(aggregated_reactions, '{}'::jsonb) WHERE id = target_message_id;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Mark Chat Read (Fixed)
CREATE OR REPLACE FUNCTION public.mark_chat_read(p_chat_id text, p_device_id text)
RETURNS void AS $$
BEGIN
  UPDATE public.message_delivery md
  SET status = 'read', read_at = now()
  FROM public.messages m
  WHERE m.chat_id = p_chat_id::uuid -- FIXED: Use snake_case
    AND md.message_id = m.id
    AND md.device_id = p_device_id
    AND md.status <> 'read';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--------------------------------------------------------------------------------
-- 4. TRIGGER RE-CREATION
--------------------------------------------------------------------------------

-- Messages Triggers
CREATE TRIGGER on_message_inserted
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_push_handler();

CREATE TRIGGER on_message_insert_delivery
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.seed_message_delivery();

CREATE TRIGGER on_message_inserted_professional
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_professional_push();

-- Reaction Triggers
CREATE TRIGGER on_reaction_inserted
  AFTER INSERT ON public.reactions
  FOR EACH ROW EXECUTE FUNCTION public.notify_push_handler();

-- Call Triggers
CREATE TRIGGER on_call_inserted
  AFTER INSERT ON public.calls
  FOR EACH ROW EXECUTE FUNCTION public.notify_push_handler();

-- Analytics Trigger
CREATE TRIGGER on_message_delivery_sync
  AFTER INSERT OR UPDATE ON public.message_delivery
  FOR EACH ROW EXECUTE FUNCTION public.sync_analytics_trigger();

-- Reactions Sync
CREATE TRIGGER on_reaction_change
  AFTER INSERT OR UPDATE OR DELETE ON public.reactions
  FOR EACH ROW EXECUTE FUNCTION public.sync_message_reactions();

--------------------------------------------------------------------------------
-- 5. POLICY RE-CREATION (RLS)
--------------------------------------------------------------------------------

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "msg_select" ON public.messages FOR SELECT USING ( public.is_item_accessible(chat_id) );
CREATE POLICY "msg_insert" ON public.messages FOR INSERT WITH CHECK ( sender_id = auth.uid() AND public.is_item_accessible(chat_id) );
CREATE POLICY "msg_update" ON public.messages FOR UPDATE USING ( sender_id = auth.uid() );

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "profile_select" ON public.profiles FOR SELECT USING ( true );
CREATE POLICY "profile_update" ON public.profiles FOR UPDATE USING ( id = auth.uid() );

-- Conversations (Restore missing policies dropped by cleaner)
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "conv_select" ON public.conversations FOR SELECT USING ( public.is_item_accessible(id) );
CREATE POLICY "conv_update" ON public.conversations FOR UPDATE USING ( public.is_item_accessible(id) );
CREATE POLICY "conv_insert" ON public.conversations FOR INSERT WITH CHECK ( true );

-- Participants (Restore missing policies dropped by cleaner)
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "part_select" ON public.conversation_participants FOR SELECT USING ( user_id = auth.uid() OR public.is_item_accessible(conversation_id) );
CREATE POLICY "part_insert" ON public.conversation_participants FOR INSERT WITH CHECK ( true );
CREATE POLICY "part_delete" ON public.conversation_participants FOR DELETE USING ( user_id = auth.uid() );

--------------------------------------------------------------------------------
-- 6. FINALIZATION
--------------------------------------------------------------------------------

COMMIT;

-- Force PostgREST to refresh its schema cache
NOTIFY pgrst, 'reload schema';
