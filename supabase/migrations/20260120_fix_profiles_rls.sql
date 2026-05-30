-- Reset RLS for profiles table to fix "new row violates row-level security policy"
-- This script ensures explicit policies for SELECT, INSERT, and UPDATE.

BEGIN;

-- 1. Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing policies to avoid conflicts
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Profiles are viewable by authenticated users" ON public.profiles;
DROP POLICY IF EXISTS "Individuals can create their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Individuals can update their own profile" ON public.profiles;

-- 3. Create robust policies

-- SELECT: Allow all users to view profiles (required for searching and chat)
CREATE POLICY "Profiles_Select_All" ON public.profiles
FOR SELECT USING ( true );

-- INSERT: Allow users to only insert their own row
-- This handles the case where the sync trigger might fail or for manual upserts
CREATE POLICY "Profiles_Insert_Own" ON public.profiles
FOR INSERT WITH CHECK ( auth.uid() = id );

-- UPDATE: Allow users to only update their own row
-- Explicitly added USING and WITH CHECK for clarity and security
CREATE POLICY "Profiles_Update_Own" ON public.profiles
FOR UPDATE USING ( auth.uid() = id )
WITH CHECK ( auth.uid() = id );

COMMIT;

-- Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';
