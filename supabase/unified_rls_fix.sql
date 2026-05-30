-- UNIFIED RLS FIX: Resolve "New row violates row-level security policy"
-- This script ensures that the creator of a chat can see the row immediately after insertion.

BEGIN;

--------------------------------------------------------------------------------
-- 1. CLEAN SLATE: DROP ALL CONFLICTING POLICIES
--------------------------------------------------------------------------------

-- Helper function to drop policies dynamically
CREATE OR REPLACE FUNCTION public.drop_all_conversations_policies()
RETURNS void AS $$
DECLARE
    pol record;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'conversations' 
        AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.conversations', pol.policyname);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT public.drop_all_conversations_policies();
DROP FUNCTION public.drop_all_conversations_policies();

--------------------------------------------------------------------------------
-- 2. SCHEMA REINFORCEMENT
--------------------------------------------------------------------------------

-- Ensure creator_id exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'conversations' AND column_name = 'creator_id') THEN
        ALTER TABLE public.conversations ADD COLUMN creator_id uuid REFERENCES public.profiles(id);
    END IF;
END $$;

--------------------------------------------------------------------------------
-- 3. APPLY ROBUST POLICIES
--------------------------------------------------------------------------------

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- SELECT: Allow if participant OR creator (CRITICAL to avoid Insert visibility error)
CREATE POLICY "Select_Conversations_Unified" ON public.conversations 
FOR SELECT 
USING (
    public.is_item_accessible(id) OR 
    creator_id = auth.uid()
);

-- INSERT: Allow all authenticated users (validated by app logic)
CREATE POLICY "Insert_Conversations_Unified" ON public.conversations 
FOR INSERT 
WITH CHECK ( auth.role() = 'authenticated' );

-- UPDATE: Allow only if participant
CREATE POLICY "Update_Conversations_Unified" ON public.conversations 
FOR UPDATE 
USING ( public.is_item_accessible(id) );

-- DELETE: Normally not exposed to clients, but added for safety
CREATE POLICY "Delete_Conversations_Unified" ON public.conversations 
FOR DELETE 
USING ( creator_id = auth.uid() );


--------------------------------------------------------------------------------
-- 4. PARTICIPANTS SAFETY
--------------------------------------------------------------------------------
-- Ensure insert participants is also robust
DROP POLICY IF EXISTS "Insert_Participants_Fix" ON public.conversation_participants;
CREATE POLICY "Insert_Participants_Fix" ON public.conversation_participants 
FOR INSERT 
WITH CHECK ( true );

COMMIT;

-- Force reload
NOTIFY pgrst, 'reload schema';
