/*
  STAGE H: POLICY ENFORCEMENT VERIFICATION
  ========================================
  
  This script helps you verify that the new Policy System is working.
  
  PHASE 1: BLOCK YOURSELF
  Run this to create a "BLOCK" policy for your Personal Scope.
*/

DO $$
DECLARE
    v_user_id UUID;
    v_scope_id UUID;
BEGIN
    -- 1. Get your ID
    v_user_id := auth.uid(); 

    -- Fallback: If running in SQL Editor without context, pick the first user
    IF v_user_id IS NULL THEN
       SELECT id INTO v_user_id FROM auth.users LIMIT 1;
    END IF;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No users found in auth.users to test with.';
    END IF;

    -- 2. Find Personal Scope
    SELECT scope_id INTO v_scope_id
    FROM public.user_roles ur
    JOIN public.ai_scopes s ON s.id = ur.scope_id
    WHERE ur.user_id = v_user_id AND s.type = 'personal'
    LIMIT 1;

    IF v_scope_id IS NULL THEN
        RAISE EXCEPTION 'No Personal Scope found for user %', v_user_id;
    END IF;

    -- 3. Insert Blocking Policy
    INSERT INTO public.ai_policies (scope_id, name, action, priority, rules)
    VALUES (v_scope_id, 'Test Block Policy', 'BLOCK', 999, '{}');

    RAISE NOTICE '✅ BLOCK Policy Applied. Any notification sent to you should now be SKIPPED.';
END $$;
