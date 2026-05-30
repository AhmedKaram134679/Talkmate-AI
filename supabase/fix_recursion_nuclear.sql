-- NUCLEAR OPTION: FIX RECURSION & PERMISSIONS
-- This script dynamically drops ALL policies on the core chat tables to ensure a clean slate.

BEGIN;

-- 1. Helper Function: Drop All Policies for a Table
CREATE OR REPLACE FUNCTION public.drop_all_policies(table_name text)
RETURNS void AS $$
DECLARE
    pol record;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = table_name 
        AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, table_name);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- 2. Drop Policies on Affected Tables
SELECT public.drop_all_policies('conversations');
SELECT public.drop_all_policies('conversation_participants');
SELECT public.drop_all_policies('messages');

-- Cleanup helper function
DROP FUNCTION public.drop_all_policies(text);


-- 3. Re-create SECURITY DEFINER Helper (The Fix)
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


-- 4. Re-Apply Correct Policies

-- CONVERSATIONS
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "View_Conversations_Fix" ON public.conversations FOR SELECT
USING ( public.is_item_accessible(id) );

CREATE POLICY "Update_Conversations_Fix" ON public.conversations FOR UPDATE
USING ( public.is_item_accessible(id) );

CREATE POLICY "Insert_Conversations_Fix" ON public.conversations FOR INSERT
WITH CHECK ( true );


-- PARTICIPANTS
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "View_Participants_Fix" ON public.conversation_participants FOR SELECT
USING (
  user_id = auth.uid() OR
  public.is_item_accessible(conversation_id)
);

CREATE POLICY "Insert_Participants_Fix" ON public.conversation_participants FOR INSERT
WITH CHECK ( true );

CREATE POLICY "Delete_Participants_Fix" ON public.conversation_participants FOR DELETE
USING ( user_id = auth.uid() );


-- MESSAGES
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "View_Messages_Fix" ON public.messages FOR SELECT
USING ( public.is_item_accessible("chatId") );

CREATE POLICY "Send_Messages_Fix" ON public.messages FOR INSERT
WITH CHECK (
  "senderId" = auth.uid() AND
  public.is_item_accessible("chatId")
);


COMMIT;

-- Force schema reload
NOTIFY pgrst, 'reload schema';
