-- Stage C: AI-driven Smart Notifications Database Layer
-- Purpose: Support utility scoring, engagement tracking, and AI-pilot settings.

-- 1. AI Notification Settings (User-level)
CREATE TABLE IF NOT EXISTS public.notification_ai_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    is_enabled BOOLEAN NOT NULL DEFAULT false, -- The "AI Auto-Pilot" toggle
    adaptive_mode BOOLEAN NOT NULL DEFAULT true,
    sensitivity FLOAT NOT NULL DEFAULT 0.5, -- 0.0 to 1.0 (Higher means more aggressive silencing)
    preferred_digest_time TIME WITHOUT TIME ZONE DEFAULT '18:00',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- 2. User Notification Engagement (Behavior Tracking)
-- Tracks how a user interacts with different message types/chats
CREATE TABLE IF NOT EXISTS public.user_notification_engagement (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    chat_id UUID, -- NULL means global engagement for that type
    content_type TEXT NOT NULL, -- 'text', 'image', 'call', etc.
    total_received INTEGER NOT NULL DEFAULT 0,
    total_opened INTEGER NOT NULL DEFAULT 0,
    total_dismissed INTEGER NOT NULL DEFAULT 0,
    last_interacted_at TIMESTAMPTZ,
    UNIQUE(user_id, chat_id, content_type)
);

-- 3. AI Decision Logs (Telemetry v3)
-- Why did the AI choose this delivery path?
CREATE TABLE IF NOT EXISTS public.ai_decision_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    routing_log_id UUID REFERENCES public.routing_logs(id),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    utility_score FLOAT NOT NULL,
    factor_engagement FLOAT,
    factor_priority FLOAT,
    factor_recency FLOAT,
    final_decision TEXT NOT NULL, -- 'sent', 'silent', 'digest'
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. RLS & Security
ALTER TABLE public.notification_ai_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_notification_engagement ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own AI settings" 
    ON public.notification_ai_settings FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update their own AI settings" 
    ON public.notification_ai_settings FOR UPDATE USING (auth.uid() = user_id);

-- 5. Helper: Initialize AI Settings for New Users
CREATE OR REPLACE FUNCTION public.handle_new_user_ai_settings()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.notification_ai_settings (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_profile_created_init_ai_settings ON public.profiles;
CREATE TRIGGER on_profile_created_init_ai_settings
    AFTER INSERT ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_ai_settings();

-- Backfill existing users
INSERT INTO public.notification_ai_settings (user_id)
SELECT id FROM public.profiles
ON CONFLICT (user_id) DO NOTHING;

-- 6. Helper: Update Engagement Stats
CREATE OR REPLACE FUNCTION public.track_notification_engagement(
    p_user_id UUID,
    p_chat_id UUID,
    p_content_type TEXT,
    p_action TEXT -- 'received', 'opened', 'dismissed'
) RETURNS VOID AS $$
BEGIN
    INSERT INTO public.user_notification_engagement (user_id, chat_id, content_type, total_received, total_opened, total_dismissed)
    VALUES (
        p_user_id, 
        p_chat_id, 
        p_content_type,
        CASE WHEN p_action = 'received' THEN 1 ELSE 0 END,
        CASE WHEN p_action = 'opened' THEN 1 ELSE 0 END,
        CASE WHEN p_action = 'dismissed' THEN 1 ELSE 0 END
    )
    ON CONFLICT (user_id, chat_id, content_type) DO UPDATE SET
        total_received = user_notification_engagement.total_received + (CASE WHEN p_action = 'received' THEN 1 ELSE 0 END),
        total_opened = user_notification_engagement.total_opened + (CASE WHEN p_action = 'opened' THEN 1 ELSE 0 END),
        total_dismissed = user_notification_engagement.total_dismissed + (CASE WHEN p_action = 'dismissed' THEN 1 ELSE 0 END),
        last_interacted_at = CASE WHEN p_action != 'received' THEN now() ELSE user_notification_engagement.last_interacted_at END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
