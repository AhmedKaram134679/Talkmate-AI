-- Migration: Add missing columns and triggers for Reply, Advanced Deletion, and Reactions Sync
-- This script ensures all message metadata and reactions are synchronized in real-time.

BEGIN;

-- 1. MESSAGES TABLE UPDATES
DO $$
BEGIN
  -- replyToMessageId: Stores the ID of the message being replied to
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'replyToMessageId') THEN
    ALTER TABLE public.messages ADD COLUMN "replyToMessageId" uuid REFERENCES public.messages(id);
  END IF;

  -- deleted: Boolean flag for "deleted for everyone"
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'deleted') THEN
    ALTER TABLE public.messages ADD COLUMN "deleted" boolean DEFAULT false;
  END IF;

  -- deletedByName: Name of the person who deleted the message
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'deletedByName') THEN
    ALTER TABLE public.messages ADD COLUMN "deletedByName" text;
  END IF;

  -- deletedFor: JSONB map of userIds who have deleted this message for themselves
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'deletedFor') THEN
    ALTER TABLE public.messages ADD COLUMN "deletedFor" jsonb DEFAULT '{}';
  END IF;

  -- reactions: JSONB column to store aggregated reactions for real-time sync
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'reactions') THEN
    ALTER TABLE public.messages ADD COLUMN "reactions" jsonb DEFAULT '{}';
  END IF;

END $$;

-- 2. REACTIONS TABLE UPDATES
DO $$
BEGIN
  -- chat_id: Required for RLS and grouping
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'reactions' AND column_name = 'chat_id') THEN
    ALTER TABLE public.reactions ADD COLUMN "chat_id" uuid REFERENCES public.conversations(id);
  END IF;
END $$;

-- 3. AUTOMATIC REACTIONS SYNC (TRIGGER)
-- This function aggregates all reactions for a message and updates the 'messages' table.
CREATE OR REPLACE FUNCTION public.sync_message_reactions()
RETURNS trigger AS $$
DECLARE
  target_message_id uuid;
  aggregated_reactions jsonb;
BEGIN
  -- Determine the message ID (works for INSERT/UPDATE/DELETE)
  IF (TG_OP = 'DELETE') THEN
    target_message_id := OLD.message_id;
  ELSE
    target_message_id := NEW.message_id;
  END IF;

  -- Aggregate reactions: { "userId": "emoji" }
  SELECT jsonb_object_agg(user_id, emoji)
  INTO aggregated_reactions
  FROM public.reactions
  WHERE message_id = target_message_id;

  -- Handle case where no reactions remain
  IF aggregated_reactions IS NULL THEN
    aggregated_reactions := '{}'::jsonb;
  END IF;

  -- Update the parent message
  UPDATE public.messages
  SET "reactions" = aggregated_reactions
  WHERE id = target_message_id;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create or replace the trigger
DROP TRIGGER IF EXISTS on_reaction_change ON public.reactions;
CREATE TRIGGER on_reaction_change
AFTER INSERT OR UPDATE OR DELETE ON public.reactions
FOR EACH ROW EXECUTE FUNCTION public.sync_message_reactions();

COMMIT;

-- Reload schema cache for PostgREST
NOTIFY pgrst, 'reload schema';
