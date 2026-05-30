-- ==========================================
-- STAGE S: NOTIFICATION EXPERIENCE & TRUST
-- ==========================================

BEGIN;

-- 1. Experience Modes Enum
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_experience_mode') THEN
        CREATE TYPE notification_experience_mode AS ENUM ('critical', 'smart', 'all');
    END IF;
END $$;

-- 2. Experience Preferences Table
CREATE TABLE IF NOT EXISTS public.user_notification_experience_prefs (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    experience_mode notification_experience_mode DEFAULT 'smart',
    is_snoozed BOOLEAN DEFAULT false,
    snooze_until TIMESTAMPTZ,
    max_hourly_notifications INTEGER DEFAULT 20,
    category_denylist JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Initialize for existing users
INSERT INTO public.user_notification_experience_prefs (user_id)
SELECT id FROM auth.users
ON CONFLICT (user_id) DO NOTHING;

-- 3. Interaction Signals Table
CREATE TABLE IF NOT EXISTS public.notification_interaction_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    message_id UUID,
    signal_type TEXT NOT NULL, -- 'click', 'dismiss_fast', 'snooze', 'mute_category'
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Trust Signal Processor (Logic Trigger)
CREATE OR REPLACE FUNCTION public.fn_process_notification_signal()
RETURNS TRIGGER AS $$
DECLARE
    v_delta FLOAT := 0;
BEGIN
    -- Implicit Learning without direct AI training
    IF NEW.signal_type = 'click' THEN
        v_delta := 2.0;
    ELSIF NEW.signal_type = 'dismiss_fast' THEN
        v_delta := -1.5;
    ELSIF NEW.signal_type = 'snooze' THEN
        v_delta := -5.0;
    ELSIF NEW.signal_type = 'mute_category' THEN
        v_delta := -10.0;
    END IF;

    -- Update Trust Score via existing Stage L infrastructure
    IF v_delta <> 0 THEN
        PERFORM public.update_trust_score(NEW.user_id, v_delta);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_on_notification_signal ON public.notification_interaction_signals;
CREATE TRIGGER tr_on_notification_signal
AFTER INSERT ON public.notification_interaction_signals
FOR EACH ROW EXECUTE FUNCTION public.fn_process_notification_signal();

-- 5. Fatigue Check Helper
CREATE OR REPLACE FUNCTION public.fn_is_user_fatigued(p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_limit INTEGER;
    v_count INTEGER;
BEGIN
    SELECT max_hourly_notifications INTO v_limit 
    FROM public.user_notification_experience_prefs 
    WHERE user_id = p_user_id;

    v_limit := COALESCE(v_limit, 20);

    SELECT count(*) INTO v_count
    FROM public.routing_logs
    WHERE recipient_id = p_user_id
      AND decision = 'sent'
      AND created_at > NOW() - INTERVAL '1 hour';

    RETURN v_count >= v_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Permissions
ALTER TABLE public.user_notification_experience_prefs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_interaction_signals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own prefs" ON public.user_notification_experience_prefs FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users update own prefs" ON public.user_notification_experience_prefs FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users insert own signals" ON public.notification_interaction_signals FOR INSERT WITH CHECK (auth.uid() = user_id);

COMMIT;

NOTIFY pgrst, 'reload schema';
