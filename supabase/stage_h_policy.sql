-- Stage H: Policy & Identity Layer (Pre-AI Gate)

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
    priority INTEGER NOT NULL DEFAULT 0, -- Higher number = higher priority
    rules JSONB NOT NULL DEFAULT '{}'::jsonb, -- e.g., {"time_range": "9-17", "source_type": "channel"}
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
    learning_rate FLOAT DEFAULT 0.1, -- How fast this profile adapts
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Policy Decision Logs (Audit Trail)
-- Linked to the main decision log, but specific to the policy gate outcome
CREATE TABLE IF NOT EXISTS public.policy_decision_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    decision_id UUID, -- Can be null if blocked before AI decision exists
    user_id UUID NOT NULL REFERENCES auth.users(id),
    policy_id UUID REFERENCES public.ai_policies(id),
    action_taken TEXT NOT NULL,
    trigger_context JSONB DEFAULT '{}'::jsonb, -- Snapshot of what triggered the policy
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- RLS Policies

-- Scopes: Visible to members
ALTER TABLE public.ai_scopes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Scopes visible to members" ON public.ai_scopes;
CREATE POLICY "Scopes visible to members" ON public.ai_scopes
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.user_roles ur 
            WHERE ur.scope_id = public.ai_scopes.id 
            AND ur.user_id = auth.uid()
        )
        OR type = 'personal' -- Implicitly personal scopes might be handled differently, but generally linked via roles
    );

-- Roles: Users can see their own roles
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users see own roles" ON public.user_roles;
CREATE POLICY "Users see own roles" ON public.user_roles
    FOR SELECT USING (user_id = auth.uid());

-- Policies: Visible to scope members
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

-- Scope Profiles: Visible to scope members
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

-- Helper Function to fetch effective policies for a user
CREATE OR REPLACE FUNCTION get_effective_policies(p_user_id UUID, p_scope_id UUID)
RETURNS TABLE (
    policy_id UUID,
    action TEXT,
    priority INTEGER,
    rules JSONB
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    -- This is a simplified version. In a real complex org, we'd traverse up the tree (Scope -> Parent Scope -> Org).
    -- For now, we fetch policies for the direct scope.
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
