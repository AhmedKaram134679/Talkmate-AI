-- Stage B: User Notification Preferences Schema
-- Purpose: Store user-specific notification toggles and styles.

-- 1. Create Preferences Type
DO $$ BEGIN
    CREATE TYPE public.notification_style AS ENUM ('full', 'silent', 'digest');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Notification Preferences Table
CREATE TABLE IF NOT EXISTS public.notification_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    chats_enabled BOOLEAN NOT NULL DEFAULT true,
    groups_enabled BOOLEAN NOT NULL DEFAULT true,
    calls_enabled BOOLEAN NOT NULL DEFAULT true,
    mentions_enabled BOOLEAN NOT NULL DEFAULT true,
    pref_style public.notification_style NOT NULL DEFAULT 'full',
    dnd_enabled BOOLEAN NOT NULL DEFAULT false,
    dnd_start TIME WITHOUT TIME ZONE DEFAULT '22:00',
    dnd_end TIME WITHOUT TIME ZONE DEFAULT '08:00',
    timezone_offset INTEGER NOT NULL DEFAULT 0, -- in minutes
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- 3. RLS Policies
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own preferences"
    ON public.notification_preferences FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own preferences"
    ON public.notification_preferences FOR UPDATE
    USING (auth.uid() = user_id);

-- 4. Initialization Trigger
CREATE OR REPLACE FUNCTION public.handle_new_user_notification_prefs()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.notification_preferences (user_id)
    VALUES (NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if trigger exists on profiles or auth.users
-- Assuming we hook into profiles for consistency in this app
DROP TRIGGER IF EXISTS on_profile_created_init_prefs ON public.profiles;
CREATE TRIGGER on_profile_created_init_prefs
    AFTER INSERT ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_notification_prefs();

-- 5. Backfill existing users (Optional but recommended)
INSERT INTO public.notification_preferences (user_id)
SELECT id FROM public.profiles
ON CONFLICT (user_id) DO NOTHING;

COMMENT ON TABLE public.notification_preferences IS 'Stores granular user settings for notifications.';
