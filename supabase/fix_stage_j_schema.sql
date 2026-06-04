/*
  FIX STAGE J: ADD MISSING COLUMNS
  ================================
  It seems the table 'ai_feature_flags' existed but without the new columns.
  This script forces the addition of 'allow_users' and 'block_users'.
*/

DO $$
BEGIN
    -- Add allow_users if not exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'ai_feature_flags' AND column_name = 'allow_users') THEN
        ALTER TABLE public.ai_feature_flags ADD COLUMN allow_users UUID[] DEFAULT '{}';
    END IF;

    -- Add block_users if not exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'ai_feature_flags' AND column_name = 'block_users') THEN
        ALTER TABLE public.ai_feature_flags ADD COLUMN block_users UUID[] DEFAULT '{}';
    END IF;
END $$;

-- Re-run the function definition just in case it needs to be refreshed (though SELECT * should pick it up dynamically)
CREATE OR REPLACE FUNCTION public.check_feature_flag(
    p_feature_key TEXT,
    p_user_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_flag RECORD;
    v_hashed_val INTEGER;
BEGIN
    SELECT * INTO v_flag FROM public.ai_feature_flags WHERE feature_key = p_feature_key;

    -- 1. If flag doesn't exist, default to FALSE
    IF v_flag IS NULL THEN
        RETURN FALSE;
    END IF;

    -- 2. Master Switch OFF? -> FALSE
    IF NOT v_flag.is_enabled THEN
        RETURN FALSE;
    END IF;

    -- 3. Blocklist Check
    -- Ensure we handle NULLs just in case, though DEFAULT '{}' handles it.
    IF v_flag.block_users IS NOT NULL AND p_user_id = ANY(v_flag.block_users) THEN
        RETURN FALSE;
    END IF;

    -- 4. Allowlist Check (Overrides rollout)
    IF v_flag.allow_users IS NOT NULL AND p_user_id = ANY(v_flag.allow_users) THEN
        RETURN TRUE;
    END IF;

    -- 5. Percentage Rollout Check
    IF v_flag.rollout_percentage > 0 THEN
        v_hashed_val := ABS(hashtext(p_user_id::text || p_feature_key)) % 100;
        IF v_hashed_val < v_flag.rollout_percentage THEN
            RETURN TRUE;
        END IF;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
