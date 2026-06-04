-- ==========================================
-- SOLUTION FOR REACTION RLS & MISSING FUNCTION
-- ==========================================

-- 1. Create Trigger Function with SECURITY DEFINER
-- This allows bypassing RLS on the 'reactions' table since it runs as the owner.
CREATE OR REPLACE FUNCTION public.fn_add_reaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only insert if the user is authenticated
    IF auth.uid() IS NOT NULL THEN
        INSERT INTO public.reactions (message_id, user_id, reaction, created_at)
        VALUES (NEW.id, auth.uid(), '👍', now())
        ON CONFLICT (message_id, user_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

-- 2. Verify Function registration in pg_proc
SELECT proname, proowner::regrole, pronamespace::regnamespace
FROM pg_proc 
WHERE proname = 'fn_add_reaction';

-- 3. Bind Trigger (Drop old if exists)
DROP TRIGGER IF EXISTS tr_add_default_reaction ON public.messages;

CREATE TRIGGER tr_add_default_reaction
AFTER INSERT ON public.messages
FOR EACH ROW
EXECUTE FUNCTION public.fn_add_reaction();

-- 4. Secure Permissions (Best Practice)
-- Revoke from public to prevent manual calls, keep for system roles
REVOKE ALL ON FUNCTION public.fn_add_reaction() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_add_reaction() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_add_reaction() TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_add_reaction() TO authenticated;

-- 5. Debug Query using information_schema
SELECT routine_name, routine_schema, routine_type, external_language
FROM information_schema.routines
WHERE routine_name = 'fn_add_reaction' 
  AND routine_schema = 'public';

-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
