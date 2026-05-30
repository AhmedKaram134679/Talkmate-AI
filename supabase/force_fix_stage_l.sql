/*
  FORCE FIX STAGE L
  =================
  Problem: 'user_trust_scores' (and likely 'user_quiet_hours_prediction') exist as VIEWS.
  Solution: DROP the views and create the TABLES from scratch.
*/

-- 1. Drop conflicting views
DROP VIEW IF EXISTS public.user_trust_scores CASCADE;
DROP VIEW IF EXISTS public.user_quiet_hours_prediction CASCADE;

-- Also drop tables just in case to be clean (IF EXISTS)
-- We use CASCADE to remove any previous bad policies/dependencies
DROP TABLE IF EXISTS public.user_trust_scores CASCADE;
DROP TABLE IF EXISTS public.user_quiet_hours_prediction CASCADE;


-- 2. Create Trust Scores Table
CREATE TABLE public.user_trust_scores (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    trust_score FLOAT DEFAULT 50.0 CHECK (trust_score BETWEEN 0 AND 100),
    last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Create Quiet Hours Table
CREATE TABLE public.user_quiet_hours_prediction (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    open_hour INTEGER NOT NULL CHECK (open_hour BETWEEN 0 AND 23),
    is_quiet_hour BOOLEAN DEFAULT false,
    confidence_score FLOAT DEFAULT 0.0,
    PRIMARY KEY (user_id, open_hour)
);

-- 4. Re-Apply RPCs (Just to be sure they reference the new tables correctly)
CREATE OR REPLACE FUNCTION public.update_trust_score(
    p_user_id UUID,
    p_delta FLOAT
)
RETURNS FLOAT AS $$
DECLARE
    v_new_score FLOAT;
BEGIN
    INSERT INTO public.user_trust_scores (user_id, trust_score)
    VALUES (p_user_id, 50.0 + p_delta)
    ON CONFLICT (user_id) DO UPDATE SET
        trust_score = GREATEST(0, LEAST(100, user_trust_scores.trust_score + p_delta)),
        last_updated_at = NOW()
    RETURNING trust_score INTO v_new_score;
    
    RETURN v_new_score;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.calculate_quiet_hours(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
    INSERT INTO public.user_quiet_hours_prediction (user_id, open_hour, is_quiet_hour)
    SELECT 
        p_user_id, 
        h, 
        (h >= 22 OR h < 7) 
    FROM generate_series(0, 23) as h
    ON CONFLICT (user_id, open_hour) DO UPDATE SET is_quiet_hour = EXCLUDED.is_quiet_hour;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Restore Permissions
ALTER TABLE public.user_trust_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_quiet_hours_prediction ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own trust" ON public.user_trust_scores FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users view own quiet hours" ON public.user_quiet_hours_prediction FOR SELECT USING (auth.uid() = user_id);
