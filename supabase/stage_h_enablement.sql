/*
  STAGE H: POLICY, IDENTITY & GOVERNANCE LAYER (Unified Migration)
  ================================================================
  
  This script enables the foundational RBAC (Role-Based Access Control)
  and AI Governance structures required for Stage H.

  INCLUDES:
  1. User Consent Table (Privacy).
  2. AI Scopes & User Roles (RBAC).
  3. AI Policies & Profiles (Governance).
  4. Automatic Backfill: Creates "Personal" scopes for all existing users.
*/

-- =================================================================
-- PART 1: CONSENT & PRIVACY (stage_h_schema.sql)
-- =================================================================

-- 1. Consent Management
CREATE TABLE IF NOT EXISTS public.user_consent (
    user_id uuid NOT NULL, -- references auth.users
    notification_type text NOT NULL, -- 'marketing', 'chat', 'system', 'call'
    consent_status boolean DEFAULT true,
    updated_at timestamptz DEFAULT now(),
    PRIMARY KEY (user_id, notification_type)
);

CREATE INDEX IF NOT EXISTS user_consent_user_idx ON public.user_consent (user_id);

-- 2. Data Retention & Purge Function
CREATE OR REPLACE FUNCTION public.purge_old_data(retention_days int DEFAULT 90)
RETURNS void AS $$
DECLARE
    cutoff_date timestamptz;
    deleted_logs int;
    deleted_signals int;
BEGIN
    cutoff_date := now() - (retention_days || ' days')::interval;

    -- Purge Routing Logs
    WITH deleted AS (
        DELETE FROM public.routing_logs 
        WHERE created_at < cutoff_date
        RETURNING id
    )
    SELECT count(*) INTO deleted_logs FROM deleted;

    -- Purge Feedback Signals
    WITH deleted AS (
        DELETE FROM public.feedback_signals 
        WHERE created_at < cutoff_date
        RETURNING id
    )
    SELECT count(*) INTO deleted_signals FROM deleted;

    -- Log the purge event (Privacy-safe: no PII, just counts)
    INSERT INTO public.routing_logs (
        decision, 
        reason, 
        meta
    ) VALUES (
        'system',
        'DATA_PURGE',
        jsonb_build_object(
            'retention_days', retention_days,
            'deleted_logs', deleted_logs,
            'deleted_signals', deleted_signals,
            'timestamp', now()
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Consent Check RPC
CREATE OR REPLACE FUNCTION public.check_user_consent(
    p_user_id uuid, 
    p_notification_type text
)
RETURNS boolean AS $$
DECLARE
    v_consent boolean;
BEGIN
    SELECT consent_status INTO v_consent
    FROM public.user_consent
    WHERE user_id = p_user_id AND notification_type = p_notification_type;
    
    IF v_consent IS NULL THEN
        IF p_notification_type = 'marketing' THEN
            RETURN false;
        ELSE
            RETURN true;
        END IF;
    END IF;

    RETURN v_consent;
END;
$$ LANGUAGE plpgsql STABLE;

-- RLS Policies for Consent
ALTER TABLE public.user_consent ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service Role Full Access Consent" ON public.user_consent;
CREATE POLICY "Service Role Full Access Consent" ON public.user_consent USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Auth Read Own Consent" ON public.user_consent;
CREATE POLICY "Auth Read Own Consent" ON public.user_consent 
FOR SELECT TO authenticated 
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Auth Update Own Consent" ON public.user_consent;
CREATE POLICY "Auth Update Own Consent" ON public.user_consent 
FOR UPDATE TO authenticated 
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Auth Insert Own Consent" ON public.user_consent;
CREATE POLICY "Auth Insert Own Consent" ON public.user_consent 
FOR INSERT TO authenticated 
WITH CHECK (auth.uid() = user_id);

-- Seed Initial Retention Config
INSERT INTO public.routing_config (key, value, description)
VALUES 
('data_retention_policy', '{
  "retention_days": 90,
  "purge_enabled": true
}', 'Configuration for data retention and purging')
ON CONFLICT (key) DO NOTHING;


-- =================================================================
-- PART 2: IDENTITY, SCOPES & POLICIES (stage_h_policy.sql)
-- =================================================================

-- 1. AI Scopes (Hierarchical Contexts)
CREATE TABLE IF NOT EXISTS public.ai_scopes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('personal', 'team', 'organization')),
    parent_id UUID REFERENCES public.ai_scopes(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. User Roles (Identity within Scope)
CREATE TABLE IF NOT EXISTS public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    scope_id UUID NOT NULL REFERENCES public.ai_scopes(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'member', 'guest')),
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, scope_id)
);

-- 3. AI Policies (The Rules)
CREATE TABLE IF NOT EXISTS public.ai_policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scope_id UUID NOT NULL REFERENCES public.ai_scopes(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    action TEXT NOT NULL CHECK (action IN ('ALLOW_AI', 'FORCE_SILENT', 'FORCE_DELIVER', 'BLOCK')),
    priority INTEGER NOT NULL DEFAULT 0,
    rules JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. AI Scope Profiles (Context-Specific Learning)
CREATE TABLE IF NOT EXISTS public.ai_scope_profiles (
    scope_id UUID PRIMARY KEY REFERENCES public.ai_scopes(id) ON DELETE CASCADE,
    engagement_weight FLOAT DEFAULT 0.4,
    context_weight FLOAT DEFAULT 0.3,
    urgency_weight FLOAT DEFAULT 0.3,
    learning_rate FLOAT DEFAULT 0.1,
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Policy Decision Logs
CREATE TABLE IF NOT EXISTS public.policy_decision_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    decision_id UUID,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    policy_id UUID REFERENCES public.ai_policies(id),
    action_taken TEXT NOT NULL,
    trigger_context JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- RLS Policies for Scopes/Roles
ALTER TABLE public.ai_scopes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Scopes visible to members" ON public.ai_scopes;
CREATE POLICY "Scopes visible to members" ON public.ai_scopes
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.user_roles ur 
            WHERE ur.scope_id = public.ai_scopes.id 
            AND ur.user_id = auth.uid()
        )
        OR type = 'personal' 
    );

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users see own roles" ON public.user_roles;
CREATE POLICY "Users see own roles" ON public.user_roles
    FOR SELECT USING (user_id = auth.uid());

ALTER TABLE public.ai_policies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Policies visible to scope members" ON public.ai_policies;
CREATE POLICY "Policies visible to scope members" ON public.ai_policies
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.user_roles ur 
            WHERE ur.scope_id = public.ai_policies.scope_id 
            AND ur.user_id = auth.uid()
        )
    );

ALTER TABLE public.ai_scope_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Profiles visible to scope members" ON public.ai_scope_profiles;
CREATE POLICY "Profiles visible to scope members" ON public.ai_scope_profiles
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.user_roles ur 
            WHERE ur.scope_id = public.ai_scope_profiles.scope_id 
            AND ur.user_id = auth.uid()
        )
    );

-- Helper Function
CREATE OR REPLACE FUNCTION get_effective_policies(p_user_id UUID, p_scope_id UUID)
RETURNS TABLE (
    policy_id UUID,
    action TEXT,
    priority INTEGER,
    rules JSONB
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.action,
        p.priority,
        p.rules
    FROM public.ai_policies p
    WHERE p.scope_id = p_scope_id
    AND p.is_active = true
    ORDER BY p.priority DESC;
END;
$$;

-- =================================================================
-- PART 3: BACKFILL & MIGRATION LOGIC
-- =================================================================

DO $$
DECLARE
    r RECORD;
    v_scope_id UUID;
    v_count INT := 0;
BEGIN
    -- Iterate through all existing users
    FOR r IN SELECT id, email FROM auth.users LOOP
        
        -- Check if they already have a Personal scope owned by them
        SELECT scope_id INTO v_scope_id 
        FROM public.user_roles ur
        JOIN public.ai_scopes s ON s.id = ur.scope_id
        WHERE ur.user_id = r.id 
        AND s.type = 'personal' 
        AND ur.role = 'owner';

        IF v_scope_id IS NULL THEN
            -- Create Personal Scope
            INSERT INTO public.ai_scopes (name, type)
            VALUES ('Personal Workspace', 'personal')
            RETURNING id INTO v_scope_id;

            -- Assign Owner Role
            INSERT INTO public.user_roles (user_id, scope_id, role)
            VALUES (r.id, v_scope_id, 'owner');

            -- Create Default Baseline Policy (Optional)
            -- INSERT INTO public.ai_policies (scope_id, name, action, priority, rules)
            -- VALUES (v_scope_id, 'Default Baseline', 'ALLOW_AI', 0, '{}');
            
            v_count := v_count + 1;
        END IF;

    END LOOP;

    RAISE NOTICE 'Backfill complete. Created Personal Scopes for % users.', v_count;
END $$;
