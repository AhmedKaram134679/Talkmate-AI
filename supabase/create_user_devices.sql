-- Create a table specifically for user devices to support multiple FCM tokens per user
CREATE TABLE IF NOT EXISTS public.user_devices (
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  fcm_token text PRIMARY KEY,
  platform text,
  is_active boolean DEFAULT true,
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;

-- Allow users to manage their own devices
DROP POLICY IF EXISTS "Users can view own devices" ON public.user_devices;
CREATE POLICY "Users can view own devices" ON public.user_devices FOR SELECT
USING ( auth.uid() = user_id );

DROP POLICY IF EXISTS "Users can upsert own devices" ON public.user_devices;
CREATE POLICY "Users can upsert own devices" ON public.user_devices FOR INSERT
WITH CHECK ( auth.uid() = user_id );

DROP POLICY IF EXISTS "Users can update own devices" ON public.user_devices;
CREATE POLICY "Users can update own devices" ON public.user_devices FOR UPDATE
USING ( auth.uid() = user_id );

DROP POLICY IF EXISTS "Users can delete own devices" ON public.user_devices;
CREATE POLICY "Users can delete own devices" ON public.user_devices FOR DELETE
USING ( auth.uid() = user_id );

-- Index for faster lookup by user_id
CREATE INDEX IF NOT EXISTS user_devices_user_id_idx ON public.user_devices (user_id);
