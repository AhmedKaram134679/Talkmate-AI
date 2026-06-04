-- Stage M: Cross-Device Attention Arbitration
-- This script updates the user_devices table and creates the attention scoring view.

BEGIN;

-- 1. Update user_devices table
DO $$ 
BEGIN
    -- Add last_active_at if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='user_devices' AND column_name='last_active_at') THEN
        ALTER TABLE public.user_devices ADD COLUMN last_active_at TIMESTAMPTZ DEFAULT now();
    END IF;

    -- Add device_role if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='user_devices' AND column_name='device_role') THEN
        ALTER TABLE public.user_devices ADD COLUMN device_role TEXT DEFAULT 'secondary' CHECK (device_role IN ('primary', 'secondary'));
    END IF;

    -- Ensure platform check constraint
    -- Note: This is an additive-only approach. We don't drop existing constraints unless necessary.
END $$;

-- 2. Create Attention Scoring View
-- Factors:
-- Recency (15 mins): 40 pts
-- Platform Hierarchy: 20 pts (Mobile 20, Desktop 14, Web 8)
-- Device Role: 20 pts (Primary 20, Secondary 12)
-- App State: 20 pts (Foreground 20, Background 10, Terminated 4)

CREATE OR REPLACE VIEW public.user_device_attention_scores AS
SELECT 
    ud.user_id,
    ud.fcm_token,
    ud.device_id,
    ud.platform,
    ud.device_role,
    ud.app_state,
    ud.last_active_at,
    (
        -- Recency Score (max 40)
        CASE 
            WHEN ud.last_active_at >= (now() - interval '15 minutes') THEN 40
            WHEN ud.last_active_at >= (now() - interval '1 hour') THEN 20
            WHEN ud.last_active_at >= (now() - interval '24 hours') THEN 10
            ELSE 0 
        END +
        -- Platform Score (max 20)
        CASE 
            WHEN ud.platform = 'android' OR ud.platform = 'ios' THEN 20
            WHEN ud.platform = 'windows' OR ud.platform = 'mac' THEN 14
            WHEN ud.platform = 'web' THEN 8
            ELSE 5
        END +
        -- Device Role Score (max 20)
        CASE 
            WHEN ud.device_role = 'primary' THEN 20
            ELSE 12
        END +
        -- App State Score (max 20)
        CASE 
            WHEN ud.app_state = 'resumed' THEN 20
            WHEN ud.app_state = 'inactive' THEN 10
            ELSE 4
        END
    ) as attention_score,
    -- Breakdown for logging
    JSONB_BUILD_OBJECT(
        'recency', CASE WHEN ud.last_active_at >= (now() - interval '15 minutes') THEN 40 ELSE 0 END,
        'platform', CASE WHEN ud.platform IN ('android', 'ios') THEN 20 ELSE 10 END,
        'role', CASE WHEN ud.device_role = 'primary' THEN 20 ELSE 12 END,
        'state', CASE WHEN ud.app_state = 'resumed' THEN 20 ELSE 4 END
    ) as score_breakdown
FROM 
    public.user_devices ud
WHERE 
    ud.is_active = true;

-- 3. Observability View
CREATE OR REPLACE VIEW public.arbitration_dashboard AS
SELECT 
    user_id,
    COUNT(device_id) as total_devices,
    MAX(attention_score) as peak_attention,
    AVG(attention_score) as avg_attention
FROM 
    public.user_device_attention_scores
GROUP BY 
    user_id;

COMMIT;
