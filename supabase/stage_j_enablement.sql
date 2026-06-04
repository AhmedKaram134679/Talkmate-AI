/*
  STAGE J: FEATURE FLAGS & ROLLOUTS
  =================================
  
  Enables granular control over AI features without code deploys.
  Supports:
  1. Global Toggles (On/Off)
  2. Percentage Rollouts (0-100%)
  3. Targeted Groups (Allowlist/Blocklist)
*/

-- 1. Feature Flags Table
CREATE TABLE IF NOT EXISTS public.ai_feature_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_key TEXT UNIQUE NOT NULL, -- e.g., 'ai_smart_replies', 'ai_summarization'
    description TEXT,
    is_enabled BOOLEAN DEFAULT false, -- Global Master Switch
    rollout_percentage INTEGER DEFAULT 0 CHECK (rollout_percentage BETWEEN 0 AND 100),
    allow_users UUID[] DEFAULT '{}', -- Specific users allowed (Overrides rollout)
    block_users UUID[] DEFAULT '{}', -- Specific users blocked
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Seed Initial Flags
INSERT INTO public.ai_feature_flags (feature_key, description, is_enabled, rollout_percentage) VALUES
('ai_smart_replies', 'Generates smart replies for incoming messages', true, 10), -- 10% rollout
('ai_summarization', 'Summarizes long missed conversations', true, 50),     -- 50% rollout
('ai_voice_transcription', 'Auto-transcribes voice notes', false, 0),         -- Disabled
('ai_image_analysis', 'Analyzes image content for context', true, 100)        -- Fully enabled
ON CONFLICT (feature_key) DO NOTHING;

-- 3. RPC: Check Feature Flag (Client/Edge Friendly)
-- Returns TRUE if user should have access to the feature based on rules.
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
    IF p_user_id = ANY(v_flag.block_users) THEN
        RETURN FALSE;
    END IF;

    -- 4. Allowlist Check (Overrides rollout)
    IF p_user_id = ANY(v_flag.allow_users) THEN
        RETURN TRUE;
    END IF;

    -- 5. Percentage Rollout Check
    -- Deterministic hashing: Consistent result for same user/feature
    -- Hash UUID + Feature Key -> Mod 100 
    IF v_flag.rollout_percentage > 0 THEN
        v_hashed_val := ABS(hashtext(p_user_id::text || p_feature_key)) % 100;
        IF v_hashed_val < v_flag.rollout_percentage THEN
            RETURN TRUE;
        END IF;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS
ALTER TABLE public.ai_feature_flags ENABLE ROW LEVEL SECURITY;

-- Anyone can read flags (needed for client checks), but RPC is preferred wrapper.
-- Let's allow SELECT for authenticated users to cache flags locally if needed.
CREATE POLICY "Auth users view flags" ON public.ai_feature_flags FOR SELECT TO authenticated USING (true);
