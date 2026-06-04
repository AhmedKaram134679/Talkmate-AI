-- STAGE F: ADAPTIVE OPTIMIZATION & AUTO-HEALING

-- 0. Safety Fix: Ensure routing_logs has ALL required columns and correct constraints
ALTER TABLE public.routing_logs ADD COLUMN IF NOT EXISTS recipient_id uuid;
ALTER TABLE public.routing_logs ADD COLUMN IF NOT EXISTS decision text;
ALTER TABLE public.routing_logs ADD COLUMN IF NOT EXISTS priority text;
ALTER TABLE public.routing_logs ADD COLUMN IF NOT EXISTS reason text;
ALTER TABLE public.routing_logs ADD COLUMN IF NOT EXISTS meta jsonb;

-- Ensure message_id is nullable (Edge Case: Logging decision before message persistence)
ALTER TABLE public.routing_logs ALTER COLUMN message_id DROP NOT NULL;

-- Update Decision Constraint to include 'throttled'
ALTER TABLE public.routing_logs DROP CONSTRAINT IF EXISTS routing_logs_decision_check;
ALTER TABLE public.routing_logs ADD CONSTRAINT routing_logs_decision_check 
CHECK (decision IN ('sent', 'silent', 'skipped', 'failed', 'throttled'));

-- 1. Feedback Signals Table (User Interactions)
CREATE TABLE IF NOT EXISTS public.feedback_signals (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL, -- references auth.users or profiles
    message_id uuid NOT NULL, -- references messages
    signal_type text NOT NULL CHECK (signal_type IN ('opened', 'dismissed', 'ignored', 'muted')),
    source text DEFAULT 'app', -- 'app', 'system', 'manual'
    created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS feedback_signals_user_idx ON public.feedback_signals (user_id);
CREATE INDEX IF NOT EXISTS feedback_signals_created_idx ON public.feedback_signals (created_at DESC);

-- 2. Routing Configuration (Dynamic Rules)
CREATE TABLE IF NOT EXISTS public.routing_config (
    key text PRIMARY KEY,
    value jsonb NOT NULL,
    description text,
    updated_at timestamptz DEFAULT now()
);

-- Seed Default Config
INSERT INTO public.routing_config (key, value, description)
VALUES 
('auto_healing_rules', '{
  "max_ignored_streak": 3,
  "throttle_duration_hours": 1,
  "critical_open_rate_threshold": 0.1,
  "max_daily_heals": 3
}', 'Thresholds for triggering auto-healing')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- 3. Adaptive Routing Stats View (Aggregation Layer)
-- Calculates simple stats per user to be consumed by Edge Function
CREATE OR REPLACE VIEW public.adaptive_routing_stats AS
SELECT 
    r.recipient_id as user_id,
    -- Count recent ignores (last 24h)
    COUNT(*) FILTER (WHERE r.decision = 'sent' AND r.priority = 'normal' AND r.created_at > now() - interval '24 hours') as recent_normal_sent_count,
    
    -- In a real system, we would join with feedback_signals to find how many were actually opened.
    -- For now, let's assume we want to signal "fatigue" if we have Sent many BUT have low "Opened" signals.
    -- This view calculates the "Potential Fatigue".
    
    (
        SELECT COUNT(*) 
        FROM public.feedback_signals f 
        WHERE f.user_id = r.recipient_id 
          AND f.signal_type = 'opened' 
          AND f.created_at > now() - interval '7 days'
    ) as weekly_open_count,
    
    (
        SELECT COUNT(*) 
        FROM public.routing_logs l 
        WHERE l.recipient_id = r.recipient_id 
          AND l.decision = 'sent' 
          AND l.created_at > now() - interval '7 days'
    ) as weekly_sent_count

FROM public.routing_logs r
WHERE r.created_at > now() - interval '24 hours'
GROUP BY r.recipient_id;

-- RLS
ALTER TABLE public.feedback_signals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users insert own signals" ON public.feedback_signals;
CREATE POLICY "Users insert own signals" ON public.feedback_signals FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role manages config" ON public.routing_config;
CREATE POLICY "Service role manages config" ON public.routing_config USING (true) WITH CHECK (true);
