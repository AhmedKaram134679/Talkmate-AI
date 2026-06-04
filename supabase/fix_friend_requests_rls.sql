-- 1. Ensure Row Level Security is enabled
ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;

-- 2. Drop potential old policies to avoid conflicts
DROP POLICY IF EXISTS "View own friend requests" ON public.friend_requests;
DROP POLICY IF EXISTS "Users can view their own friend requests" ON public.friend_requests;
DROP POLICY IF EXISTS "Create friend request" ON public.friend_requests;
DROP POLICY IF EXISTS "Users can create friend requests" ON public.friend_requests;
DROP POLICY IF EXISTS "Update friend request" ON public.friend_requests;
DROP POLICY IF EXISTS "Users can update friend requests" ON public.friend_requests;
DROP POLICY IF EXISTS "Delete sent request" ON public.friend_requests;

-- 3. Re-create policies using the CORRECT column names (sender_id, receiver_id)
CREATE POLICY "View own friend requests"
  ON public.friend_requests FOR SELECT
  USING ( (select auth.uid()) = sender_id OR (select auth.uid()) = receiver_id );

CREATE POLICY "Create friend request"
  ON public.friend_requests FOR INSERT
  WITH CHECK ( (select auth.uid()) = sender_id );

CREATE POLICY "Update friend request"
  ON public.friend_requests FOR UPDATE
  USING ( (select auth.uid()) = receiver_id OR (select auth.uid()) = sender_id );

CREATE POLICY "Delete sent request"
  ON public.friend_requests FOR DELETE
  USING ( (select auth.uid()) = sender_id );

-- 4. Enable Realtime for friend_requests table
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.friend_requests;
EXCEPTION WHEN OTHERS THEN
  NULL; -- Ignore if table is already in publication
END $$;
