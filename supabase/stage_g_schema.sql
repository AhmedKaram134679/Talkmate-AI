-- STAGE G: NOTIFICATION POLICY ENGINE & EXPERIMENTS

-- 1. Notification Segments (User Grouping)
CREATE TABLE IF NOT EXISTS public.notification_segments (
    segment_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL UNIQUE,
    description text,
    criteria jsonb NOT NULL, -- e.g. {"min_app_version": "1.2.0", "is_premium": true}
    created_at timestamptz DEFAULT now()
);

-- 2. Notification Policies (Rules)
CREATE TABLE IF NOT EXISTS public.notification_policies (
    policy_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    segment_id uuid REFERENCES public.notification_segments(segment_id),
    notification_type text, -- NULL means ALL types
    action text NOT NULL CHECK (action IN ('send', 'silent', 'delayed', 'skipped')),
    priority_override text CHECK (priority_override IN ('high', 'normal')),
    start_time time, -- Daily start time (e.g., '22:00')
    end_time time,   -- Daily end time (e.g., '08:00')
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS policies_segment_idx ON public.notification_policies (segment_id);

-- 3. A/B Experiments
CREATE TABLE IF NOT EXISTS public.ab_experiments (
    experiment_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    segment_id uuid REFERENCES public.notification_segments(segment_id),
    variant_a_config jsonb, -- Config for Control Group
    variant_b_config jsonb, -- Config for Test Group
    start_at timestamptz NOT NULL,
    end_at timestamptz,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now()
);

-- 4. A/B Assignments (Sticky Routing)
CREATE TABLE IF NOT EXISTS public.ab_assignments (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL, -- references auth.users
    experiment_id uuid REFERENCES public.ab_experiments(experiment_id),
    variant text NOT NULL CHECK (variant IN ('A', 'B')),
    assigned_at timestamptz DEFAULT now(),
    UNIQUE(user_id, experiment_id)
);

CREATE INDEX IF NOT EXISTS ab_assignments_user_idx ON public.ab_assignments (user_id);

-- 5. Feature Flags (Kill Switch)
CREATE TABLE IF NOT EXISTS public.notification_flags (
    key text PRIMARY KEY,
    value boolean DEFAULT false,
    description text,
    updated_at timestamptz DEFAULT now()
);

-- RLS Policies
ALTER TABLE public.notification_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ab_experiments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ab_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_flags ENABLE ROW LEVEL SECURITY;

-- Service Role Policies (Full Access)
DROP POLICY IF EXISTS "Service Role Full Access Segments" ON public.notification_segments;
CREATE POLICY "Service Role Full Access Segments" ON public.notification_segments USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Service Role Full Access Policies" ON public.notification_policies;
CREATE POLICY "Service Role Full Access Policies" ON public.notification_policies USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Service Role Full Access Experiments" ON public.ab_experiments;
CREATE POLICY "Service Role Full Access Experiments" ON public.ab_experiments USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Service Role Full Access Assignments" ON public.ab_assignments;
CREATE POLICY "Service Role Full Access Assignments" ON public.ab_assignments USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Service Role Full Access Flags" ON public.notification_flags;
CREATE POLICY "Service Role Full Access Flags" ON public.notification_flags USING (true) WITH CHECK (true);

-- Authenticated Read Policies (For Debug/Admin UI)
DROP POLICY IF EXISTS "Auth Read Segments" ON public.notification_segments;
CREATE POLICY "Auth Read Segments" ON public.notification_segments FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Auth Read Policies" ON public.notification_policies;
CREATE POLICY "Auth Read Policies" ON public.notification_policies FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Auth Read Experiments" ON public.ab_experiments;
CREATE POLICY "Auth Read Experiments" ON public.ab_experiments FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Auth Read Assignments" ON public.ab_assignments;
CREATE POLICY "Auth Read Assignments" ON public.ab_assignments FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Auth Read Flags" ON public.notification_flags;
CREATE POLICY "Auth Read Flags" ON public.notification_flags FOR SELECT TO authenticated USING (true);

-- Seed Initial Data
INSERT INTO public.notification_flags (key, value, description) VALUES
('global_push_enabled', true, 'Master switch for all push notifications'),
('marketing_push_enabled', true, 'Enable marketing/promo notifications')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.notification_segments (name, description, criteria) VALUES
('All Users', 'Default segment for everyone', '{}'),
('VIP Users', 'High value users', '{"is_premium": true}')
ON CONFLICT (name) DO NOTHING;
