-- COMPREHENSIVE REALTIME REPAIR: MESSAGES
-- This script fixes the issue where messages only appear after app restart.

BEGIN;

--------------------------------------------------------------------------------
-- 1. FIX REPLICA IDENTITY
--------------------------------------------------------------------------------
-- This is critical for Realtime to broadcast all row data correctly.
ALTER TABLE public.messages REPLICA IDENTITY FULL;

--------------------------------------------------------------------------------
-- 2. RE-CONFIGURE REALTIME PUBLICATION
--------------------------------------------------------------------------------
-- Remove and re-add the table to ensure it's correctly registered.
DROP PUBLICATION IF EXISTS supabase_realtime;
CREATE PUBLICATION supabase_realtime;
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;

--------------------------------------------------------------------------------
-- 3. OPTIMIZE RLS FOR REALTIME
--------------------------------------------------------------------------------
-- Realtime engine can be sensitive to complex policies.
-- Let's make the policy for messages more direct.

DROP POLICY IF EXISTS "View messages in own chats" ON public.messages;

-- A more direct policy that avoids complex function calls if possible
CREATE POLICY "View messages in own chats" ON public.messages 
FOR SELECT 
USING (
  "senderId" = auth.uid() OR 
  EXISTS (
    SELECT 1 FROM public.conversation_participants 
    WHERE conversation_id = messages."chatId" 
    AND user_id = auth.uid()
  )
);

-- Ensure the participants table itself has correct RLS (Realtime might need to check it)
ALTER TABLE public.conversation_participants REPLICA IDENTITY FULL;

--------------------------------------------------------------------------------
-- 4. PERMISSIONS
--------------------------------------------------------------------------------
-- Ensure the 'authenticated' and 'anon' roles have access to the publication (standard but good to check)
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO anon;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;

COMMIT;

-- Force reload schema cache one last time
NOTIFY pgrst, 'reload schema';
