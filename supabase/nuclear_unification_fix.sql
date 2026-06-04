-- FINAL NUCLEAR UNIFICATION: Reconcile snake_case vs camelCase and Storage Buckets
-- This script handles the "conversation_id" NOT NULL constraint and "Bucket not found" errors.

BEGIN;

--------------------------------------------------------------------------------
-- 1. STORAGE BUCKET RE-VERIFICATION
--------------------------------------------------------------------------------
-- Ensure 'talkmate' bucket exists
INSERT INTO storage.buckets (id, name, public)
VALUES ('talkmate', 'talkmate', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Ensure RLS is enabled for storage (Supabase does this by default but just in case)
-- We'll just ensure policies are robust.
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Allow Auth Upload" ON storage.objects;
DROP POLICY IF EXISTS "Allow Auth Update/Delete" ON storage.objects;

-- Select: Public access
CREATE POLICY "Public Access" ON storage.objects FOR SELECT
USING ( bucket_id = 'talkmate' );

-- Insert: Authenticated users can upload
CREATE POLICY "Allow Auth Upload" ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'talkmate' );

-- All: Authenticated users can manage their own uploads or all in 'talkmate'
CREATE POLICY "Allow Auth Update/Delete" ON storage.objects FOR ALL
TO authenticated
USING ( bucket_id = 'talkmate' );

--------------------------------------------------------------------------------
-- 2. MESSAGES TABLE: RESOLVE KEY CONFLICTS
--------------------------------------------------------------------------------
-- We need to ensure the app's 'chatId' and 'senderId' are the only REQUIRED columns.
-- If 'conversation_id' or 'user_id' exist and are NOT NULL, we must fix them.

DO $$
BEGIN
  -- A. Handle conversation_id vs chatId
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'conversation_id') THEN
    -- If chatId doesn't exist yet, rename conversation_id to chatId
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'chatId') THEN
      ALTER TABLE public.messages RENAME COLUMN "conversation_id" TO "chatId";
    ELSE
      -- Both exist? Make conversation_id nullable so it doesn't block inserts
      ALTER TABLE public.messages ALTER COLUMN "conversation_id" DROP NOT NULL;
    END IF;
  END IF;

  -- B. Handle user_id vs senderId (senderId is what the app uses)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'user_id') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'senderId') THEN
      ALTER TABLE public.messages RENAME COLUMN "user_id" TO "senderId";
    ELSE
      ALTER TABLE public.messages ALTER COLUMN "user_id" DROP NOT NULL;
    END IF;
  END IF;

  -- C. Ensure chatId and senderId are NOT NULL (since the app depends on them)
  -- But only if the table is clean. For now, let's just make sure they exist.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'chatId') THEN
    ALTER TABLE public.messages ADD COLUMN "chatId" uuid REFERENCES public.conversations(id) ON DELETE CASCADE;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'senderId') THEN
    ALTER TABLE public.messages ADD COLUMN "senderId" uuid REFERENCES public.profiles(id);
  END IF;

END $$;

COMMIT;

-- Reload schema cache to reflect column changes
NOTIFY pgrst, 'reload schema';
