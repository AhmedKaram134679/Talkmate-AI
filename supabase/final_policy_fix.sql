-- FINAL POLICY FIX (Recursion & Access Denied)
-- This script overrides all previous policies to guarantee access.

BEGIN;

-- 1. Helper Function (SECURITY DEFINER is CRITICAL)
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

-- 2. Conversations Policies
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "View conversations user participates in" ON public.conversations;
CREATE POLICY "View conversations user participates in" ON public.conversations FOR SELECT
USING ( public.is_item_accessible(id) );

DROP POLICY IF EXISTS "Update conversations user participates in" ON public.conversations;
CREATE POLICY "Update conversations user participates in" ON public.conversations FOR UPDATE
USING ( public.is_item_accessible(id) );

DROP POLICY IF EXISTS "Insert conversations" ON public.conversations;
CREATE POLICY "Insert conversations" ON public.conversations FOR INSERT
WITH CHECK ( true ); -- Allow creation by anyone authenticated

-- 3. Participants Policies
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "View participants" ON public.conversation_participants;
CREATE POLICY "View participants" ON public.conversation_participants FOR SELECT
USING (
  user_id = auth.uid() OR
  public.is_item_accessible(conversation_id)
);

DROP POLICY IF EXISTS "Insert participants" ON public.conversation_participants;
CREATE POLICY "Insert participants" ON public.conversation_participants FOR INSERT
WITH CHECK ( true ); -- Allow adding participants (validated by app logic)

DROP POLICY IF EXISTS "Delete self" ON public.conversation_participants;
CREATE POLICY "Delete self" ON public.conversation_participants FOR DELETE
USING ( user_id = auth.uid() );

-- 4. Messages Policies
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "View messages in own chats" ON public.messages;
CREATE POLICY "View messages in own chats" ON public.messages FOR SELECT
USING ( public.is_item_accessible("chatId") );

DROP POLICY IF EXISTS "Send messages to own chats" ON public.messages;
CREATE POLICY "Send messages to own chats" ON public.messages FOR INSERT
WITH CHECK (
  "senderId" = auth.uid() AND
  public.is_item_accessible("chatId")
);

COMMIT;

-- Force schema reload
NOTIFY pgrst, 'reload schema';
