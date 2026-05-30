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

-- RLS: Read-only for everyone (or specific role), Insert only by Service Role (Edge Function)
ALTER TABLE public.routing_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow Service Role to Insert Logs" 
ON public.routing_logs 
FOR INSERT 
TO service_role 
WITH CHECK (true);

CREATE POLICY "Allow Authenticated Users to Read Logs" 
ON public.routing_logs 
FOR SELECT 
TO authenticated 
USING (true); -- Ideally restrict to admin or own logs, but for debug tool we open to auth.
