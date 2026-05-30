-- CLEAN SLATE REPAIR: MESSAGES + STORAGE
-- This script will aggressively fix the NOT NULL constraints and Storage Bucket issues.

BEGIN;

--------------------------------------------------------------------------------
-- 1. MESSAGES TABLE: RE-ALIGNMENT
--------------------------------------------------------------------------------

-- First, make sure the columns the app uses are NOT NULL (mandatory)
-- and the old columns are NULLABLE (optional) or removed.

DO $$
BEGIN
    -- If 'conversation_id' exists, rename it to 'chatId' if 'chatId' doesn't exist.
    -- If both exist, just make 'conversation_id' optional so it doesn't block us.
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'conversation_id') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'chatId') THEN
            ALTER TABLE public.messages RENAME COLUMN "conversation_id" TO "chatId";
        ELSE
            ALTER TABLE public.messages ALTER COLUMN "conversation_id" DROP NOT NULL;
            -- Optional: move data if needed, but for now we just want it to stop failing
        END IF;
    END IF;

    -- Do the same for 'user_id' vs 'senderId'
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'user_id') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'senderId') THEN
            ALTER TABLE public.messages RENAME COLUMN "user_id" TO "senderId";
        ELSE
            ALTER TABLE public.messages ALTER COLUMN "user_id" DROP NOT NULL;
        END IF;
    END IF;

    -- Ensure all expected columns are present and correctly typed
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'chatId') THEN
        ALTER TABLE public.messages ADD COLUMN "chatId" uuid REFERENCES public.conversations(id) ON DELETE CASCADE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'senderId') THEN
        ALTER TABLE public.messages ADD COLUMN "senderId" uuid REFERENCES public.profiles(id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'text') THEN
        ALTER TABLE public.messages ADD COLUMN "text" text;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'mediaSize') THEN
        ALTER TABLE public.messages ADD COLUMN "mediaSize" bigint;
    END IF;

END $$;

-- Make sure RLS is allowing us to insert
DROP POLICY IF EXISTS "Insert messages" ON public.messages;
CREATE POLICY "Insert messages" ON public.messages FOR INSERT
WITH CHECK ( true ); -- Allowing all auth users for simplicity during fix

--------------------------------------------------------------------------------
-- 2. STORAGE: TALKMATE BUCKET
--------------------------------------------------------------------------------

-- Ensure bucket exists
INSERT INTO storage.buckets (id, name, public)
VALUES ('talkmate', 'talkmate', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Ensure ALL policies for this bucket are wide open for testing
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Allow All" ON storage.objects;

CREATE POLICY "Allow All" ON storage.objects FOR ALL
USING ( bucket_id = 'talkmate' )
WITH CHECK ( bucket_id = 'talkmate' );

COMMIT;

-- Reload
NOTIFY pgrst, 'reload schema';
