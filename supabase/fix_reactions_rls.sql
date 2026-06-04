-- FIX: Enable RLS on reactions table and policies (CORRECTED COLUMN NAMES)
BEGIN;

-- 1. Ensure table exists (idempotent)
CREATE TABLE IF NOT EXISTS public.reactions (
  "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  "message_id" uuid REFERENCES public.messages("id") ON DELETE CASCADE,
  "user_id" uuid REFERENCES public.profiles("id") ON DELETE CASCADE,
  "chat_id" uuid REFERENCES public.conversations("id") ON DELETE CASCADE,
  "emoji" text NOT NULL,
  "created_at" timestamptz DEFAULT now()
);

-- 2. Enable RLS
ALTER TABLE public.reactions ENABLE ROW LEVEL SECURITY;

-- 3. Drop existing policies to start fresh
DROP POLICY IF EXISTS "Enable read for all" ON public.reactions;
DROP POLICY IF EXISTS "Enable insert for authenticated" ON public.reactions;
DROP POLICY IF EXISTS "Enable delete for own reactions" ON public.reactions;

-- 4. Create Policies

-- READ: Everyone can see reactions
CREATE POLICY "Enable read for all" ON public.reactions
FOR SELECT USING (true); 

-- INSERT: Authenticated users can add reactions
CREATE POLICY "Enable insert for authenticated" ON public.reactions
FOR INSERT
TO authenticated
WITH CHECK ( auth.uid() = "user_id" );

-- DELETE: Users can remove their OWN reactions
CREATE POLICY "Enable delete for own reactions" ON public.reactions
FOR DELETE
TO authenticated
USING ( auth.uid() = "user_id" );

COMMIT;

NOTIFY pgrst, 'reload schema';
