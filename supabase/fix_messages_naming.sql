-- FIX MESSAGES NAMING: Normalize camelCase columns to snake_case for consistency and Realtime fix.
-- This script renames columns in the messages table and updates related RLS policies.

BEGIN;

-- 1. Rename columns if they exist in camelCase
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'chatId') THEN
    ALTER TABLE public.messages RENAME COLUMN "chatId" TO chat_id;
  END IF;
  
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'senderId') THEN
    ALTER TABLE public.messages RENAME COLUMN "senderId" TO sender_id;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'createdAt') THEN
    ALTER TABLE public.messages RENAME COLUMN "createdAt" TO created_at;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'mediaUrl') THEN
    ALTER TABLE public.messages RENAME COLUMN "mediaUrl" TO media_url;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'thumbnailUrl') THEN
    ALTER TABLE public.messages RENAME COLUMN "thumbnailUrl" TO thumbnail_url;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'mediaSize') THEN
    ALTER TABLE public.messages RENAME COLUMN "mediaSize" TO media_size;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'isEdited') THEN
    ALTER TABLE public.messages RENAME COLUMN "isEdited" TO is_edited;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'editedAt') THEN
    ALTER TABLE public.messages RENAME COLUMN "editedAt" TO edited_at;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'isDeleted') THEN
    ALTER TABLE public.messages RENAME COLUMN "isDeleted" TO is_deleted;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'deletedAt') THEN
    ALTER TABLE public.messages RENAME COLUMN "deletedAt" TO deleted_at;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'replyToMessageId') THEN
    ALTER TABLE public.messages RENAME COLUMN "replyToMessageId" TO reply_to_message_id;
  END IF;
END $$;

--------------------------------------------------------------------------------
-- 2. RE-APPLY RLS POLICIES WITH NEW COLUMN NAMES
--------------------------------------------------------------------------------

-- Ensure helper function exists (pre-requisite for policies)
CREATE OR REPLACE FUNCTION public.is_item_accessible(_conversation_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.conversation_participants
    WHERE conversation_id = _conversation_id
    AND user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Messages Policies
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "View messages in own chats" ON public.messages;
CREATE POLICY "View messages in own chats" ON public.messages FOR SELECT
USING ( public.is_item_accessible(chat_id) );

DROP POLICY IF EXISTS "Send messages to own chats" ON public.messages;
CREATE POLICY "Send messages to own chats" ON public.messages FOR INSERT
WITH CHECK (
  sender_id = auth.uid() AND
  public.is_item_accessible(chat_id)
);

DROP POLICY IF EXISTS "Update own messages" ON public.messages;
CREATE POLICY "Update own messages" ON public.messages FOR UPDATE
USING ( sender_id = auth.uid() );

DROP POLICY IF EXISTS "Insert messages" ON public.messages;
DROP POLICY IF EXISTS "Update own messages" ON public.messages;
-- Re-defining comprehensively
CREATE POLICY "Insert messages" ON public.messages 
FOR INSERT 
WITH CHECK ( auth.uid() = sender_id );

--------------------------------------------------------------------------------
-- 3. REALTIME RE-CONFIGURATION
--------------------------------------------------------------------------------
-- This ensures Realtime uses the updated column names for broadcasting.
ALTER TABLE public.messages REPLICA IDENTITY FULL;

COMMIT;

-- Force schema reload
NOTIFY pgrst, 'reload schema';
