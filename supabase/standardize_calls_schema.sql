-- [Stage C9] Unified Calls Schema
-- Standardizes the 'calls' table to use 'sender_id' and 'receiver_id'

-- 1. Ensure columns exist with correct types
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='calls' AND column_name='sender_id') THEN
    ALTER TABLE public.calls ADD COLUMN sender_id uuid DEFAULT auth.uid();
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='calls' AND column_name='receiver_id') THEN
    ALTER TABLE public.calls ADD COLUMN receiver_id uuid;
  END IF;
  
  -- Ensure caller_id/callee_id exist for backward compatibility if it's a fresh table
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='calls' AND column_name='caller_id') THEN
    ALTER TABLE public.calls ADD COLUMN caller_id uuid;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='calls' AND column_name='callee_id') THEN
    ALTER TABLE public.calls ADD COLUMN callee_id uuid;
  END IF;

  -- [Stage R-Stability] Add is_video for push-handler compatibility
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='calls' AND column_name='is_video') THEN
    ALTER TABLE public.calls ADD COLUMN is_video BOOLEAN GENERATED ALWAYS AS (type = 'video') STORED;
  END IF;
END $$;

-- 2. Migrate data (Copy old data to new columns)
UPDATE public.calls 
SET sender_id = caller_id 
WHERE sender_id IS NULL AND caller_id IS NOT NULL;

UPDATE public.calls 
SET receiver_id = callee_id 
WHERE receiver_id IS NULL AND callee_id IS NOT NULL;

-- 2.1 Set defaults and constraints for reliability
ALTER TABLE public.calls ALTER COLUMN sender_id SET DEFAULT auth.uid();
-- Relax legacy constraints to prevent 'violates not-null constraint' during transition
ALTER TABLE public.calls ALTER COLUMN caller_id DROP NOT NULL;
ALTER TABLE public.calls ALTER COLUMN callee_id DROP NOT NULL;
-- We don't SET NOT NULL yet on new columns to avoid blocking existing NULL rows if any remained, 
-- but the app should always send them now.

-- 3. Nuke and Re-create RLS Policies
-- This ensures no conflicting old policies remain hidden
DO $$
DECLARE
    policy_name text;
BEGIN
    FOR policy_name IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'calls' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.calls', policy_name);
    END LOOP;
END $$;

ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;

-- Creation policy: Allow any authenticated user to start a call as the sender
CREATE POLICY "Users can create calls" ON public.calls
  FOR INSERT 
  TO authenticated 
  WITH CHECK (auth.uid() = sender_id OR sender_id IS NULL); -- IS NULL allows fallback to default auth.uid()

-- Viewing policy: Participants or authorized roles
CREATE POLICY "Participants can view calls" ON public.calls
  FOR SELECT 
  TO authenticated
  USING (auth.uid() = sender_id OR auth.uid() = receiver_id OR auth.uid() = caller_id OR auth.uid() = callee_id);

-- Update policy: Only participants can update status
CREATE POLICY "Participants can update calls" ON public.calls
  FOR UPDATE 
  TO authenticated
  USING (auth.uid() = sender_id OR auth.uid() = receiver_id OR auth.uid() = caller_id OR auth.uid() = callee_id);

-- 4. Realtime
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND schemaname = 'public' 
    AND tablename = 'calls'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.calls;
  END IF;
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;
