-- ADD MISSING COLUMNS TO PROFILES
-- This script fixes the "created_at column not found" error.

ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- Also ensure fcm_tokens is present as a fallback
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS fcm_tokens TEXT[];

-- Refresh schema cache hint for PostgREST
-- (In Supabase, any DDL usually triggers this, but we can add a comment to be sure)
COMMENT ON TABLE public.profiles IS 'User profiles for TalkMate AI';
