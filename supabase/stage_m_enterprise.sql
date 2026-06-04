-- STAGE M: ENTERPRISE AI & MULTI-TENANT PLATFORM
-- Purpose: Support hierarchical AI control and strict tenant isolation.

-- 1. Workspace-Level AI Weights (Tenant Isolation)
-- Unlike personal weights (Stage F), these are baseline weights for a specific Team/Workspace.
CREATE TABLE IF NOT EXISTS public.ai_enterprise_weights (
    workspace_id uuid PRIMARY KEY, -- References ai_scopes(id)
    engagement_weight float DEFAULT 0.4,
    context_weight float DEFAULT 0.3,
    urgency_weight float DEFAULT 0.3,
    trust_score float DEFAULT 1.0,
    is_active boolean DEFAULT true,
    updated_at timestamptz DEFAULT now()
);

-- 2. Enterprise Policy Overrides
-- Policies that can silence or force delivery across a whole organization/team.
CREATE TABLE IF NOT EXISTS public.ai_enterprise_overrides (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    scope_id uuid REFERENCES public.ai_scopes(id) ON DELETE CASCADE,
    
    -- Target segment (e.g., 'all', 'interns', 'managers')
    target_segment text DEFAULT 'all',
    
    -- Override Logic
    override_type text NOT NULL CHECK (override_type IN ('soft', 'hard')),
    action text NOT NULL CHECK (action IN ('force_silent', 'force_deliver', 'bias_shift')),
    
    -- For 'bias_shift', how much to nudge the utility score (-1.0 to 1.0)
    bias_value float DEFAULT 0.0,
    
    reason text, -- 'Global meeting day', 'Security drill'
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now()
);

-- 3. Enterprise AI Audit Trail
-- Tracks when an Enterprise Policy changed a user's personal AI decision.
CREATE TABLE IF NOT EXISTS public.ai_enterprise_audit (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    workspace_id uuid REFERENCES public.ai_scopes(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    
    policy_id uuid REFERENCES public.ai_enterprise_overrides(id),
    original_decision text,
    final_decision text,
    override_type text,
    
    metadata jsonb, -- { "chat_id": "...", "content_type": "..." }
    created_at timestamptz DEFAULT now()
);

-- RLS & SECURITY
ALTER TABLE public.ai_enterprise_weights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_enterprise_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_enterprise_audit ENABLE ROW LEVEL SECURITY;

-- Admins of a scope can manage their weights/policies
DROP POLICY IF EXISTS "Workspace admins manage weights" ON public.ai_enterprise_weights;
CREATE POLICY "Workspace admins manage weights" ON public.ai_enterprise_weights
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.user_roles 
            WHERE user_id = auth.uid() 
            AND scope_id = ai_enterprise_weights.workspace_id 
            AND role IN ('admin', 'owner')
        )
    );

DROP POLICY IF EXISTS "Workspace admins manage overrides" ON public.ai_enterprise_overrides;
CREATE POLICY "Workspace admins manage overrides" ON public.ai_enterprise_overrides
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.user_roles 
            WHERE user_id = auth.uid() 
            AND scope_id = ai_enterprise_overrides.scope_id 
            AND role IN ('admin', 'owner')
        )
    );

-- Users can view their own audit records if they are in that workspace
DROP POLICY IF EXISTS "Users view own enterprise audit" ON public.ai_enterprise_audit;
CREATE POLICY "Users view own enterprise audit" ON public.ai_enterprise_audit
    FOR SELECT USING (user_id = auth.uid());

COMMENT ON TABLE public.ai_enterprise_weights IS 'Isolated baseline weights for a specific workspace/tenant.';
COMMENT ON TABLE public.ai_enterprise_overrides IS 'Administrative rules that supersede personal AI logic.';
COMMENT ON TABLE public.ai_enterprise_audit IS 'Audit trail documenting how enterprise policies impacted user decisions.';
