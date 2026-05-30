-- Stage E: Contextual Intelligence & Personalization Schema
-- Purpose: Store behavioral patterns and context-aware settings.

BEGIN;

-- 1. User Context Settings (Personalization Toggles)
CREATE TABLE IF NOT EXISTS public.user_context_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    predictive_timing_enabled BOOLEAN DEFAULT true,
    respect_driving_mode BOOLEAN DEFAULT true,
    night_mode_sensitivity FLOAT DEFAULT 0.8, -- 0.0 to 1.0
    work_hours_sensitivity FLOAT DEFAULT 0.5,
    context_weight FLOAT DEFAULT 0.5, -- How much context affects the score (0.0 to 1.0)
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. User Context Profiles (Learned Patterns)
-- Stores JSON describing peak hours and behavioral segments.
-- e.g., activity_map: {"monday": [8, 12, 18]}, usage_patterns: {"work_focus": 0.8, "social_active": 0.3}
CREATE TABLE IF NOT EXISTS public.user_context_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    activity_map JSONB DEFAULT '{}',
    usage_patterns JSONB DEFAULT '{"work_focus": 0.5, "social_interest": 0.5}',
    peak_interaction_hours INTEGER[] DEFAULT '{}',
    last_profile_rebuild TIMESTAMPTZ DEFAULT now()
);

-- Extend Settings with Fatigue Guard
ALTER TABLE public.user_context_settings
ADD COLUMN IF NOT EXISTS fatigue_threshold FLOAT DEFAULT 0.7; -- Max penalty before forcing digest


-- 3. Update AISettings for Context
ALTER TABLE public.notification_ai_settings
ADD COLUMN IF NOT EXISTS context_sensitivity FLOAT DEFAULT 0.5,
ADD COLUMN IF NOT EXISTS predictive_timing_enabled BOOLEAN DEFAULT true;

-- 4. Extend Decision Logs with Context Factors
ALTER TABLE public.ai_decision_logs
ADD COLUMN IF NOT EXISTS device_state TEXT, -- 'idle', 'driving', 'screen_on', 'unknown'
ADD COLUMN IF NOT EXISTS time_segment TEXT, -- 'morning', 'work', 'night', 'weekend'
ADD COLUMN IF NOT EXISTS context_penalty FLOAT DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS predicted_delay_minutes INTEGER DEFAULT 0;

-- 5. Helper Function: Get User Time Segment
CREATE OR REPLACE FUNCTION public.get_time_segment(hour_of_day INTEGER, is_weekend BOOLEAN)
RETURNS TEXT AS $$
BEGIN
    IF is_weekend THEN RETURN 'weekend'; END IF;
    IF hour_of_day >= 22 OR hour_of_day < 6 THEN RETURN 'night';
    ELSIF hour_of_day >= 9 AND hour_of_day < 17 THEN RETURN 'work';
    ELSE RETURN 'morning';
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- RLS
ALTER TABLE public.user_context_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_context_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage their own context settings" ON public.user_context_settings;
CREATE POLICY "Users can manage their own context settings"
    ON public.user_context_settings FOR ALL
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can view their own context profiles" ON public.user_context_profiles;
CREATE POLICY "Users can view their own context profiles"
    ON public.user_context_profiles FOR SELECT
    USING (auth.uid() = user_id);


COMMIT;
