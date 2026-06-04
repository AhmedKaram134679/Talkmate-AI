-- Migration: Add local_id column to messages table
-- Purpose: Fix Sync Engine errors and enable idempotent message delivery

-- 1. Add the column if it doesn't exist
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS local_id TEXT;

-- 2. Create an index to speed up sync lookups
CREATE INDEX IF NOT EXISTS idx_messages_local_id 
ON public.messages (local_id);

-- 3. Add a description
COMMENT ON COLUMN public.messages.local_id IS 'Client-generated ID for idempotency and offline tracking';

-- NOTE: After running this, run 'NOTIFY pgrst, ''reload schema'';' if needed, 
-- although Supabase usually detects schema changes automatically.

