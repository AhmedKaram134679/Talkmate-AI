-- FIX MESSAGES COLUMNS: Ensure all expected columns exist with correct naming (camelCase)
-- This fixes the "Could not find column mediaSize" error.

BEGIN;

DO $$
BEGIN
  -- 1. type
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'type') THEN
    ALTER TABLE public.messages ADD COLUMN "type" text DEFAULT 'text';
  END IF;

  -- 2. chatId
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'chatId') THEN
    ALTER TABLE public.messages ADD COLUMN "chatId" uuid REFERENCES public.conversations(id) ON DELETE CASCADE;
  END IF;

  -- 3. senderId
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'senderId') THEN
    ALTER TABLE public.messages ADD COLUMN "senderId" uuid REFERENCES public.profiles(id);
  END IF;

  -- 4. mediaUrl
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'mediaUrl') THEN
    ALTER TABLE public.messages ADD COLUMN "mediaUrl" text;
  END IF;

  -- 5. thumbnailUrl
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'thumbnailUrl') THEN
    ALTER TABLE public.messages ADD COLUMN "thumbnailUrl" text;
  END IF;

  -- 6. mediaSize
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'mediaSize') THEN
    ALTER TABLE public.messages ADD COLUMN "mediaSize" bigint;
  END IF;

  -- 7. status
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'status') THEN
    ALTER TABLE public.messages ADD COLUMN "status" text DEFAULT 'sent';
  END IF;

  -- 8. createdAt
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'createdAt') THEN
    ALTER TABLE public.messages ADD COLUMN "createdAt" timestamptz DEFAULT now();
  END IF;

  -- 9. isEdited
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'isEdited') THEN
    ALTER TABLE public.messages ADD COLUMN "isEdited" boolean DEFAULT false;
  END IF;

  -- 10. editedAt
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'editedAt') THEN
    ALTER TABLE public.messages ADD COLUMN "editedAt" timestamptz;
  END IF;

  -- 11. isDeleted
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'isDeleted') THEN
    ALTER TABLE public.messages ADD COLUMN "isDeleted" boolean DEFAULT false;
  END IF;

  -- 12. deletedAt
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'deletedAt') THEN
    ALTER TABLE public.messages ADD COLUMN "deletedAt" timestamptz;
  END IF;

END $$;

COMMIT;

-- Reload schema cache
NOTIFY pgrst, 'reload schema';
