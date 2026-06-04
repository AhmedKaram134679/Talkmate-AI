-- [Stage R-Stability] Room Sovereignty & Visibility
-- Enhances 'rooms' table with type, visibility, and robust RLS

-- 1. Infrastructure updates
DO $$ 
BEGIN
  -- Add room type
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='rooms' AND column_name='type') THEN
    ALTER TABLE public.rooms ADD COLUMN type text DEFAULT 'voice';
  END IF;

  -- Add visibility flag
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='rooms' AND column_name='is_private') THEN
    ALTER TABLE public.rooms ADD COLUMN is_private boolean DEFAULT false;
  END IF;

  -- Add allowed users list (for private rooms)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='rooms' AND column_name='allowed_users') THEN
    ALTER TABLE public.rooms ADD COLUMN allowed_users uuid[] DEFAULT '{}';
  END IF;

  -- Add topic for specialized behavior
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='rooms' AND column_name='topic') THEN
    ALTER TABLE public.rooms ADD COLUMN topic text;
  END IF;
  
  -- Add metadata for topic/domain
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='rooms' AND column_name='metadata') THEN
    ALTER TABLE public.rooms ADD COLUMN metadata jsonb DEFAULT '{}';
  END IF;
END $$;

-- 2. RLS Overhaul
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;

-- Creation policy: Any authenticated user
DROP POLICY IF EXISTS "Users can create rooms" ON public.rooms;
CREATE POLICY "Users can create rooms" ON public.rooms
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = created_by OR created_by IS NULL);

-- Visibility policy: 
-- 1. Public rooms are visible to all authenticated users
-- 2. Private rooms are only visible to:
--    a. The creator
--    b. Users in 'allowed_users' array
DROP POLICY IF EXISTS "Users can view rooms" ON public.rooms;
CREATE POLICY "Users can view rooms" ON public.rooms
  FOR SELECT TO authenticated
  USING (
    is_private = false OR 
    auth.uid() = created_by OR 
    auth.uid() = ANY(allowed_users)
  );

-- Management policy: Only the creator can update/delete
DROP POLICY IF EXISTS "Creators can manage rooms" ON public.rooms;
CREATE POLICY "Creators can manage rooms" ON public.rooms
  FOR ALL TO authenticated
  USING (auth.uid() = created_by);

-- 3. Room Participants (Cleanup & Sovereignty)
ALTER TABLE public.room_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can join authorized rooms" ON public.room_participants;
CREATE POLICY "Users can join authorized rooms" ON public.room_participants
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.rooms 
      WHERE id = room_id AND (
        is_private = false OR 
        auth.uid() = created_by OR 
        auth.uid() = ANY(allowed_users)
      )
    )
  );
