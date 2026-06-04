-- FINAL SCHEMA FIX: Add creator_id & Update Policies
-- This ensures the creator of a chat can ALWAYS see it immediately after creation.

BEGIN;

-- 1. Add creator_id column if not exists
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'conversations' AND column_name = 'creator_id') THEN
    ALTER TABLE public.conversations ADD COLUMN creator_id uuid REFERENCES public.profiles(id);
  END IF;
END $$;

-- 2. Update Policy to allow Creator access
DROP POLICY IF EXISTS "View conversations user participates in" ON public.conversations;
DROP POLICY IF EXISTS "View_Conversations_Fix" ON public.conversations;

CREATE POLICY "View_Conversations_Fix" ON public.conversations FOR SELECT
USING (
  public.is_item_accessible(id) OR
  creator_id = auth.uid()
);

-- 3. Ensure Insert Policy Allows setting creator_id
DROP POLICY IF EXISTS "Insert_Conversations_Fix" ON public.conversations;
CREATE POLICY "Insert_Conversations_Fix" ON public.conversations FOR INSERT
WITH CHECK ( true );

COMMIT;

NOTIFY pgrst, 'reload schema';
