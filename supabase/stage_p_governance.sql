-- Stage P: Production Hardening & Governance
-- This script implements the infrastructure for system-wide safety locks, audit trails, and integrity checks.

BEGIN;

-- 1. System Governance & Safety Lock
-- Stores global feature flags, kill-switches, and locked implementation thresholds.
CREATE TABLE IF NOT EXISTS public.system_governance (
    key text PRIMARY KEY,
    value jsonb NOT NULL,
    description text,
    is_locked boolean DEFAULT true, -- If true, can only be changed via Change Proposal
    updated_at timestamptz DEFAULT now()
);

-- Seed Initial Governance State
INSERT INTO public.system_governance (key, value, description, is_locked)
VALUES 
('ai_global_kill_switch', '{"enabled": false}', 'Emergency switch to disable all AI routing logic immediately.', false),
('learning_engine_config', '{
  "min_confidence_to_learn": 0.8,
  "override_freeze_threshold": 5,
  "freeze_duration_days": 30,
  "max_drift_allowed": 0.2
}', 'Strict boundaries for the continuous learning engine.', true),
('production_safety_locks', '{
  "enforce_override_supremacy": true,
  "prevent_critical_learning": true,
  "min_sla_timeout_ms": 500
}', 'Hardcoded safety constraints for production delivery.', true)
ON CONFLICT (key) DO NOTHING;

-- 2. Change Proposals & Audit Trail
-- Any change to locked governance keys or critical thresholds is recorded here.
CREATE TABLE IF NOT EXISTS public.system_change_proposals (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    key_affected text REFERENCES public.system_governance(key),
    proposed_by uuid REFERENCES auth.users(id),
    change_type text CHECK (change_type IN ('PARAMETER_UPDATE', 'FEATURE_TOGGLE', 'EMERGENCY_KILL')),
    old_value jsonb,
    new_value jsonb,
    justification text,
    applied_at timestamptz DEFAULT now()
);

-- 3. System Integrity & Trust Audit View
-- Automated checklist to detect "Black Box" decisions or missed overrides.
CREATE OR REPLACE VIEW public.system_integrity_audit AS
SELECT 
    l.message_id,
    l.recipient_id as user_id,
    l.decision,
    l.reason,
    l.meta->>'scenario' as category,
    (l.meta->'user_override'->>'applied')::boolean as override_applied,
    (l.meta->'stage_o'->>'confidence_level') as ai_confidence,
    CASE 
        WHEN (l.meta->'user_override'->>'applied')::boolean = true AND l.decision IN ('silent', 'throttled', 'bundled') THEN 'ALERT: OVERRIDE_VIOLATION'
        WHEN (l.meta->'stage_o'->>'learning_status') = 'ACTIVE' AND (l.priority = 'critical' OR l.reason = 'CRITICAL_BYPASS') THEN 'ALERT: CRITICAL_LEARNING_VIOLATION'
        WHEN (l.meta->'stage_o'->>'confidence_level') = 'LOW' AND (l.meta->'stage_o'->>'learning_status') = 'ACTIVE' THEN 'ALERT: LOW_CONFIDENCE_DRIFT'
        ELSE 'OK'
    END as integrity_status
FROM public.routing_logs l
WHERE l.created_at > now() - interval '24 hours';

-- 4. Change Control Trigger
-- Prevents direct updates to locked governance keys without a change proposal (Logic handled in backend or RPC).
-- Here we just ensure updated_at is refreshed.
CREATE OR REPLACE FUNCTION public.fn_refresh_governance_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_refresh_governance_timestamp
BEFORE UPDATE ON public.system_governance
FOR EACH ROW EXECUTE FUNCTION public.fn_refresh_governance_timestamp();

COMMIT;
