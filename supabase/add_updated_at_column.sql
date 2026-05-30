-- Add updated_at column to friend_requests if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'friend_requests' AND column_name = 'updated_at') THEN
    ALTER TABLE public.friend_requests ADD COLUMN updated_at timestamptz DEFAULT now();
  END IF;
END $$;
