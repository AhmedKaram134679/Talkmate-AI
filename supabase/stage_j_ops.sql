-- Stage J: AI Operations & Continuous Improvement Schema

-- 1. AI Feature Flags
-- Controls gradual rollout of new AI logic, weights, or features.
CREATE TABLE IF NOT EXISTS public.ai_feature_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    feature_key TEXT NOT NULL UNIQUE, -- e.g., 'new_scoring_v2'
    description TEXT,
    is_enabled BOOLEAN DEFAULT false, -- Master switch
    rollout_percentage INTEGER DEFAULT 0 CHECK (rollout_percentage BETWEEN 0 AND 100),
    target_criteria JSONB DEFAULT '{}'::jsonb, -- e.g., {"role": "beta", "region": "us"}
    shadow_mode BOOLEAN DEFAULT false, -- If true, runs in background but doesn't apply decision
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. AI Shadow Comparisons
-- Stores side-by-side results of Production vs Shadow logic for analysis.
CREATE TABLE IF NOT EXISTS public.ai_shadow_comparisons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    decision_id UUID, -- Link to the actual decision made
    feature_key TEXT NOT NULL, -- Which flag caused this shadow run
    prod_decision TEXT NOT NULL,
    shadow_decision TEXT NOT NULL,
    diff_reason TEXT, -- 'prod_silent_shadow_sent'
    prod_score FLOAT,
    shadow_score FLOAT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- RLS Policies

-- Feature Flags: Read-only for authenticated users (cached in Edge Function usually, but nice to have)
ALTER TABLE public.ai_feature_flags ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public read feature flags" ON public.ai_feature_flags;
CREATE POLICY "Public read feature flags" ON public.ai_feature_flags
    FOR SELECT TO authenticated USING (true);

-- Shadow Comparisons: Users can see their own comparisons (transparency)
ALTER TABLE public.ai_shadow_comparisons ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users see own shadow comparisons" ON public.ai_shadow_comparisons;
CREATE POLICY "Users see own shadow comparisons" ON public.ai_shadow_comparisons
    FOR SELECT USING (auth.uid() = user_id);

-- System Indexes
CREATE INDEX IF NOT EXISTS idx_ai_feature_flags_key ON public.ai_feature_flags(feature_key);
CREATE INDEX IF NOT EXISTS idx_ai_shadow_comparisons_user ON public.ai_shadow_comparisons(user_id);
