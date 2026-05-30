-- REALTIME & RLS REPAIR: MESSAGES
-- This script ensures messages appear instantly in the chat UI.

BEGIN;

--------------------------------------------------------------------------------
-- 1. ENABLE REALTIME
--------------------------------------------------------------------------------

-- Add the messages table to the realtime publication if not already there
-- We first check if the publication exists, then add the table.
-- Typically Supabase has a 'supabase_realtime' publication by default.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

-- Enable Realtime for the messages table
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
-- Ignore error if already added
-- Note: In some Supabase versions, you might need to use:
-- ALTER TABLE public.messages SET (replica_identity = full);

--------------------------------------------------------------------------------
-- 2. FINAL RLS POLICIES (Secure + Functional)
--------------------------------------------------------------------------------

-- Ensure the 'is_item_accessible' function works with the new 'chatId'
-- We'll drop and recreation the SELECT policy to be sure.

DROP POLICY IF EXISTS "Allow everything for authenticated users" ON public.messages;
DROP POLICY IF EXISTS "View messages in own chats" ON public.messages;

-- Secure View Policy: Only see messages if you are a participant in the chat
CREATE POLICY "View messages in own chats" ON public.messages 
FOR SELECT 
USING ( public.is_item_accessible("chatId") );

-- Insert Policy: Allow authenticated users to send messages
DROP POLICY IF EXISTS "Insert messages" ON public.messages;
CREATE POLICY "Insert messages" ON public.messages 
FOR INSERT 
WITH CHECK ( auth.uid() = "senderId" );

-- Update Policy: Allow sender to update (status, isEdited, etc.)
DROP POLICY IF EXISTS "Update own messages" ON public.messages;
CREATE POLICY "Update own messages" ON public.messages 
FOR UPDATE 
USING ( auth.uid() = "senderId" );

COMMIT;

-- Force reload again
NOTIFY pgrst, 'reload schema';
