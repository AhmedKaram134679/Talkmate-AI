-- STAGE Z-3: CONTEXT-AWARE ROUTING (user_devices enhancement)

-- Add device_id and presence columns to user_devices
ALTER TABLE public.user_devices 
ADD COLUMN IF NOT EXISTS device_id text,
ADD COLUMN IF NOT EXISTS is_online boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS last_active_at timestamptz DEFAULT now(),
ADD COLUMN IF NOT EXISTS app_state text DEFAULT 'terminated';

-- Unique constraint: A user has one entry per device_id
-- We might need to handle cases where fcm_token changes for the same device_id
ALTER TABLE public.user_devices DROP CONSTRAINT IF EXISTS user_devices_user_device_key;
ALTER TABLE public.user_devices ADD CONSTRAINT user_devices_user_device_key UNIQUE (user_id, device_id);

-- Index for routing lookups
CREATE INDEX IF NOT EXISTS user_devices_routing_idx ON public.user_devices (user_id, is_online, app_state);
