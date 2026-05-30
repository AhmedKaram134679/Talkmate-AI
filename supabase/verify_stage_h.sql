/*
  STAGE H VERIFICATION
  ====================
  Run this to confirm that Policy & Identity tables have been populated correctly.
*/

-- 1. Check if Personal Scopes were created
SELECT 
  count(*) as total_users,
  (SELECT count(*) FROM public.ai_scopes WHERE type = 'personal') as personal_scopes_created,
  (SELECT count(*) FROM public.user_roles WHERE role = 'owner') as owners_assigned
FROM auth.users;

-- 2. Check Table Structure (Existence)
SELECT exists(SELECT 1 FROM information_schema.tables WHERE table_name = 'user_consent') as consent_table_exists;
SELECT exists(SELECT 1 FROM information_schema.tables WHERE table_name = 'ai_policies') as policies_table_exists;
