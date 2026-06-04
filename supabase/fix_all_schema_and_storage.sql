-- COMPREHENSIVE FIX: STORAGE BUCKETS + MESSAGES SCHEMA
-- This script fixes the "Bucket not found" and "Column not found" errors.

BEGIN;

--------------------------------------------------------------------------------
-- 1. STORAGE BUCKET SETUP
--------------------------------------------------------------------------------
-- Ensure the 'talkmate' bucket exists and is public
INSERT INTO storage.buckets (id, name, public)
VALUES ('talkmate', 'talkmate', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Allow Public Upload" ON storage.objects;

-- Create policy to allow anyone to read files from the bucket
CREATE POLICY "Public Access" ON storage.objects FOR SELECT
USING ( bucket_id = 'talkmate' );

-- Create policy to allow authenticated users to upload files
CREATE POLICY "Allow Auth Upload" ON storage.objects FOR INSERT
TO authenticated
WITH CHECK ( bucket_id = 'talkmate' );

-- Allow update/delete (Optional: adjust as needed for security)
CREATE POLICY "Allow Auth Update/Delete" ON storage.objects FOR ALL
TO authenticated
USING ( bucket_id = 'talkmate' );

--------------------------------------------------------------------------------
-- 2. MESSAGES TABLE SCHEMA REPAIR
--------------------------------------------------------------------------------
-- Standardize the messages table with all expected columns
DO $$
BEGIN
  -- ensure table exists first
  CREATE TABLE IF NOT EXISTS public.messages (
    "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY
  );

  -- Type
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'type') THEN
    ALTER TABLE public.messages ADD COLUMN "type" text DEFAULT 'text';
  END IF;

  -- text
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'text') THEN
    ALTER TABLE public.messages ADD COLUMN "text" text;
  END IF;

  -- chatId
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'chatId') THEN
    ALTER TABLE public.messages ADD COLUMN "chatId" uuid REFERENCES public.conversations(id) ON DELETE CASCADE;
  END IF;

  -- senderId
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'senderId') THEN
    ALTER TABLE public.messages ADD COLUMN "senderId" uuid REFERENCES public.profiles(id);
  END IF;

  -- mediaUrl
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'mediaUrl') THEN
    ALTER TABLE public.messages ADD COLUMN "mediaUrl" text;
  END IF;

  -- thumbnailUrl
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'thumbnailUrl') THEN
    ALTER TABLE public.messages ADD COLUMN "thumbnailUrl" text;
  END IF;

  -- mediaSize
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'mediaSize') THEN
    ALTER TABLE public.messages ADD COLUMN "mediaSize" bigint;
  END IF;

  -- status
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'status') THEN
    ALTER TABLE public.messages ADD COLUMN "status" text DEFAULT 'sent';
  END IF;

  -- createdAt
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'createdAt') THEN
    ALTER TABLE public.messages ADD COLUMN "createdAt" timestamptz DEFAULT now();
  END IF;

  -- isEdited
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'isEdited') THEN
    ALTER TABLE public.messages ADD COLUMN "isEdited" boolean DEFAULT false;
  END IF;

  -- editedAt
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'editedAt') THEN
    ALTER TABLE public.messages ADD COLUMN "editedAt" timestamptz;
  END IF;

  -- isDeleted
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'isDeleted') THEN
    ALTER TABLE public.messages ADD COLUMN "isDeleted" boolean DEFAULT false;
  END IF;

  -- deletedAt
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'deletedAt') THEN
    ALTER TABLE public.messages ADD COLUMN "deletedAt" timestamptz;
  END IF;

END $$;

COMMIT;

-- Reload schema cache
NOTIFY pgrst, 'reload schema';
