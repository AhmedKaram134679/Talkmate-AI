-- 1. Enable RLS on friends table
ALTER TABLE public.friends ENABLE ROW LEVEL SECURITY;

-- 2. Drop potential outdated policies
DROP POLICY IF EXISTS "View own friends" ON public.friends;
DROP POLICY IF EXISTS "Create friendship" ON public.friends;
DROP POLICY IF EXISTS "Update friendship" ON public.friends;
DROP POLICY IF EXISTS "Delete friendship" ON public.friends;

-- 3. Create permissive policies for friends table
-- Allow users to view friendships where they are involved
CREATE POLICY "View own friends"
  ON public.friends FOR SELECT
  USING ( (select auth.uid()) = user_id OR (select auth.uid()) = friend_id );

-- Allow users to create a friendship row if they are one of the parties
CREATE POLICY "Create friendship"
  ON public.friends FOR INSERT
  WITH CHECK ( (select auth.uid()) = user_id OR (select auth.uid()) = friend_id );

-- Allow update (e.g. status change) if they are one of the parties
CREATE POLICY "Update friendship"
  ON public.friends FOR UPDATE
  USING ( (select auth.uid()) = user_id OR (select auth.uid()) = friend_id );

-- Allow deletion
CREATE POLICY "Delete friendship"
  ON public.friends FOR DELETE
  USING ( (select auth.uid()) = user_id OR (select auth.uid()) = friend_id );

-- 4. Enable Realtime for friends table (optional but good for sync)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.friends;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;
