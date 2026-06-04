-- Stage Q: Safe Production Rollout Architecture
-- This script implements the progressive rollout mechanism and launch observability.

BEGIN;

-- 1. Rollout Governance Configuration
-- Stores the current rollout state.
INSERT INTO public.system_governance (key, value, description, is_locked)
VALUES (
  'ai_rollout_config',
  '{
    "target_percentage": 0,
    "allowed_segments": ["internal"],
    "blacklisted_users": [],
    "whitelisted_users": [],
    "stage_locks": {
      "enable_learning": false,
      "enable_smart_bundling": false
    }
  }',
  'Controls the progressive rollout of AI features.',
  false -- SREs need to update this frequently
) ON CONFLICT (key) DO NOTHING;

-- 2. User Segmentation Logic
-- Maps users to segments based on their attributes (or ID for now).
CREATE OR REPLACE FUNCTION public.fn_get_user_segment(p_user_id uuid)
RETURNS text AS $$
DECLARE
  v_email text;
BEGIN
  -- Fetch email from auth.users (requires permission) or profiles
  -- For now, we assume 'internal' if email ends with specific domain or is in a list
  -- This is a simplified implementation. ideally linked to a user_roles table
  
  -- Optimized: In a real app, join with profiles. Here we use a placeholder logic.
  -- You can expand this to check a 'beta_testers' table.
  
  RETURN 'public'; -- Default to public
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. Deterministic Rollout Gate ("The Valve")
-- Checks if a user is allowed to access AI features based on the current config.
CREATE OR REPLACE FUNCTION public.fn_is_user_in_rollout(p_user_id uuid)
RETURNS boolean AS $$
DECLARE
  v_config jsonb;
  v_target_pct int;
  v_segment text;
  v_user_hash int;
BEGIN
  -- Fetch config (cached by Postgres usually if accessed frequently)
  SELECT value INTO v_config FROM public.system_governance WHERE key = 'ai_rollout_config';
  
  -- 1. Check Global Emergency Stop (Target = 0)
  v_target_pct := (v_config->>'target_percentage')::int;
  IF v_target_pct = 0 THEN
    -- Check Whitelist even if 0% (Enable for specific QA users)
    IF (v_config->'whitelisted_users') ? p_user_id::text THEN
        RETURN true;
    END IF;
    RETURN false;
  END IF;

  -- 2. Check Blacklist (Toxic Users)
  IF (v_config->'blacklisted_users') ? p_user_id::text THEN
    RETURN false;
  END IF;

  -- 3. Check Whitelist (VIP Bypass)
  IF (v_config->'whitelisted_users') ? p_user_id::text THEN
    RETURN true;
  END IF;

  -- 4. Check Segment Constraints
  v_segment := public.fn_get_user_segment(p_user_id);
  -- If segment is not in allowed_segments, block.
  -- Note: JSONB array check
  IF NOT ((v_config->'allowed_segments') @> to_jsonb(v_segment)) THEN
    RETURN false;
  END IF;

  -- 5. Deterministic Percentage Check
  -- abs(hashtext(uuid)) % 100 < target_pct
  v_user_hash := abs(hashtext(p_user_id::text)) % 100;
  
  IF v_user_hash < v_target_pct THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$ LANGUAGE plpgsql STABLE;

-- 4. Launch Control Center View ("The Cockpit")
-- Provides SREs with a high-level view of the system state.
CREATE OR REPLACE VIEW public.launch_control_center AS
WITH metrics AS (
    SELECT 
        COUNT(*) as total_users,
        COUNT(*) FILTER (WHERE public.fn_is_user_in_rollout(id)) as active_ai_users
    FROM auth.users
),
kill_switch AS (
    SELECT (value->>'enabled')::boolean as is_kill_switched 
    FROM public.system_governance 
    WHERE key = 'ai_global_kill_switch'
),
rollout_state AS (
    SELECT 
        (value->>'target_percentage')::int as current_percentage,
        (value->>'allowed_segments') as active_segments
    FROM public.system_governance 
    WHERE key = 'ai_rollout_config'
)
SELECT 
    r.current_percentage,
    r.active_segments,
    k.is_kill_switched as emergency_stop_active,
    m.total_users,
    m.active_ai_users,
    CASE 
        WHEN m.total_users > 0 THEN round((m.active_ai_users::numeric / m.total_users) * 100, 2)
        ELSE 0 
    END as actual_penetration_pct,
    now() as last_updated
FROM rollout_state r, kill_switch k, metrics m;

COMMIT;
