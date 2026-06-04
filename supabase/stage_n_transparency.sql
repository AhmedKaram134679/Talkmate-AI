-- Stage N: Transparency & Human-in-the-Loop
-- This script creates the fine-grained preferences table to support user overrides.

BEGIN;

-- 1. Create Fine-Grained Preferences Table
CREATE TABLE IF NOT EXISTS public.user_notification_settings_fine_grained (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    notification_type text NOT NULL, -- 'chat', 'call', 'marketing', 'system', etc.
    preferred_device_id text, -- Specific device_id from user_devices
    force_delivery boolean DEFAULT false, -- Bypass Quiet Hours / Bundling
    allow_bundling boolean DEFAULT true,
    allow_quiet_override boolean DEFAULT false, -- Specific opt-in for night
    updated_at timestamptz DEFAULT now(),
    
    -- Ensure one record per user per notification type
    UNIQUE(user_id, notification_type)
);

-- 2. Enable RLS
ALTER TABLE public.user_notification_settings_fine_grained ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies
DROP POLICY IF EXISTS "Users can manage their own fine-grained settings" ON public.user_notification_settings_fine_grained;
CREATE POLICY "Users can manage their own fine-grained settings" 
ON public.user_notification_settings_fine_grained 
FOR ALL 
USING (auth.uid() = user_id);

-- 4. Index for Performance
CREATE INDEX IF NOT EXISTS idx_user_fine_grained_prefs_user_id ON public.user_notification_settings_fine_grained(user_id);

COMMIT;
