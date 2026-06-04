-- STAGE C: ADVANCED AI ROUTING (DND & Context)

-- Add DND and Timezone columns to user_devices
ALTER TABLE public.user_devices 
ADD COLUMN IF NOT EXISTS dnd_enabled boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS dnd_start_time time DEFAULT '22:00:00',
ADD COLUMN IF NOT EXISTS dnd_end_time time DEFAULT '08:00:00',
ADD COLUMN IF NOT EXISTS timezone_offset integer DEFAULT 0; -- Offset in minutes from UTC

-- Index for valid devices including DND status
CREATE INDEX IF NOT EXISTS user_devices_routing_v2_idx ON public.user_devices (user_id, is_active, dnd_enabled);
