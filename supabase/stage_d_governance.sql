-- Stage D: Trust, Control & AI Governance
-- Extending Stage C with Transparency, Manual Controls, and Safety.

-- 1. AI Exclusions Table (Granular Control)
-- Allows users to disable AI for specific conversations.
CREATE TABLE IF NOT EXISTS public.notification_ai_exclusions (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    chat_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, chat_id)
);

ALTER TABLE public.notification_ai_exclusions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own AI exclusions" ON public.notification_ai_exclusions
    FOR ALL USING (auth.uid() = user_id);

-- 2. AI Drift & Trust Metrics
-- Tracks user overrides (e.g., Opening a silent notification) to measure AI-User misalignment.
CREATE TABLE IF NOT EXISTS public.ai_drift_stats (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    drift_score FLOAT DEFAULT 0.0, -- 0.0 (Perfect Alignment) to 1.0 (High Disagreement)
    total_overrides INTEGER DEFAULT 0,
    total_decisions INTEGER DEFAULT 0,
    last_drift_update TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.ai_drift_stats ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own drift stats" ON public.ai_drift_stats
    FOR SELECT USING (auth.uid() = user_id);

-- 3. Governance Extensions for AI Settings
-- Adding Safe Mode and Pause duration
ALTER TABLE public.notification_ai_settings 
ADD COLUMN IF NOT EXISTS is_safe_mode BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS paused_until TIMESTAMPTZ;

-- 4. Explainability Context (Updated Logging)
-- Store human-readable keys for AI behavior transparency.
ALTER TABLE public.ai_decision_logs
ADD COLUMN IF NOT EXISTS explanation_key TEXT, -- e.g. "FREQ_MORNING_INTERACT"
ADD COLUMN IF NOT EXISTS explanation_context JSONB; -- e.g. {"open_rate": 0.9, "hour": 8}

-- 5. Global Governance Config (Admin Kill Switch)
CREATE TABLE IF NOT EXISTS public.ai_governance_config (
    key TEXT PRIMARY KEY,
    value JSONB,
    updated_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO public.ai_governance_config (key, value)
VALUES ('global_ai_kill_switch', '{"enabled": false}')
ON CONFLICT (key) DO NOTHING;

-- 6. Logic: Automated Drift Update Function
CREATE OR REPLACE FUNCTION public.track_ai_drift()
RETURNS TRIGGER AS $$
BEGIN
    -- This function would be called when a user opens a notification that was marked 'silent' by AI.
    INSERT INTO public.ai_drift_stats (user_id, total_overrides, total_decisions)
    VALUES (NEW.user_id, 1, 1)
    ON CONFLICT (user_id) DO UPDATE SET
        total_overrides = ai_drift_stats.total_overrides + 1,
        drift_score = (ai_drift_stats.total_overrides + 1)::float / GREATEST(ai_drift_stats.total_decisions, 1),
        last_drift_update = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Logic: Safe Mode Trigger
CREATE OR REPLACE FUNCTION public.check_ai_drift_limit()
RETURNS TRIGGER AS $$
BEGIN
    -- If drift score > 0.7 (70% disagreement), move user to Safe Mode automatically.
    IF NEW.drift_score > 0.7 THEN
        UPDATE public.notification_ai_settings
        SET is_safe_mode = true
        WHERE user_id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_drift_threshold_exceeded
AFTER UPDATE ON public.ai_drift_stats
FOR EACH ROW WHEN (NEW.drift_score > 0.7 AND OLD.drift_score <= 0.7)
EXECUTE FUNCTION public.check_ai_drift_limit();

COMMENT ON TABLE public.notification_ai_exclusions IS 'Allows granular user-level exclusion of AI routing per chat.';
COMMENT ON TABLE public.ai_drift_stats IS 'Tracks misalignment between AI decisions and user behavior.';
