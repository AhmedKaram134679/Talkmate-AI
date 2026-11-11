-- STAGE E: OBSERVABILITY & DEBUGGING

-- Create routing_logs table
CREATE TABLE IF NOT EXISTS public.routing_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    message_id uuid, -- Can be null if log happens before message persist (unlikely but safe)
    chat_id uuid,
    device_id text,
    recipient_id uuid,
    decision text NOT NULL CHECK (decision IN ('sent', 'silent', 'skipped', 'failed')),
    priority text CHECK (priority IN ('high', 'normal')),
    reason text, -- e.g., 'DND_ACTIVE', 'FOREGROUND_ACTIVE'
    meta jsonb, -- Snapshot of device state
    created_at timestamptz DEFAULT now()
);

-- Index for timeline queries
CREATE INDEX IF NOT EXISTS routing_logs_timeline_idx ON public.routing_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS routing_logs_message_idx ON public.routing_logs (message_id);
CREATE INDEX IF NOT EXISTS routing_logs_device_idx ON public.routing_logs (device_id);

-- RLS: users read only their own logs, inserts only by Service Role (Edge Function)
ALTER TABLE public.routing_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow Service Role to Insert Logs" ON public.routing_logs;
CREATE POLICY "Allow Service Role to Insert Logs"
ON public.routing_logs
FOR INSERT
TO service_role
WITH CHECK (true);

-- Was: USING (true) for every authenticated user, which exposed all users'
-- routing decisions. Now each user sees only their own rows (plus 'system' rows).
DROP POLICY IF EXISTS "Allow Authenticated Users to Read Logs" ON public.routing_logs;
DROP POLICY IF EXISTS "routing_logs_select_own" ON public.routing_logs;
CREATE POLICY "routing_logs_select_own"
ON public.routing_logs
FOR SELECT
TO authenticated
USING (recipient_id = auth.uid() OR decision = 'system');
