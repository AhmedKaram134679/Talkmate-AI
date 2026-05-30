-- Add web_push_subscription to user_devices
ALTER TABLE public.user_devices 
ADD COLUMN IF NOT EXISTS web_push_subscription JSONB;

-- Add web_push_enabled to notification_preferences
ALTER TABLE public.notification_preferences
ADD COLUMN IF NOT EXISTS web_push_enabled BOOLEAN DEFAULT true;

-- Grant permissions (if not already handled by existing policies)
-- The user_devices table should already have RLS allowing users to update their own rows.
-- notification_preferences should also have RLS.

COMMENT ON COLUMN public.user_devices.web_push_subscription IS 'Stores VAPID subscription object for web push notifications';
COMMENT ON COLUMN public.notification_preferences.web_push_enabled IS 'Toggle for web push notifications';
