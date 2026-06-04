-- STAGE K: PRIVACY & FEDERATED TELEMETRY
-- Purpose: Monitor privacy health and collective learning progress.

-- 1. Privacy Health Dashboard
-- Tracks "Privacy Budget" consumption and Opt-Out rates.
CREATE OR REPLACE VIEW public.ai_privacy_health_dashboard AS
SELECT 
    -- Opt-Out Metrics
    (SELECT COUNT(*) FROM public.notification_ai_settings WHERE federated_learning_enabled = false) as total_opt_outs,
    (SELECT COUNT(*) FROM public.notification_ai_settings WHERE federated_learning_enabled = true) as active_contributors,
    
    -- Recent Privacy Logs
    (SELECT COUNT(*) FROM public.ai_privacy_logs WHERE created_at > now() - interval '24 hours') as daily_privacy_events,
    
    -- Signal Volume (Proxy for Budget Consumption)
    (SELECT COUNT(*) FROM public.ai_federated_deltas WHERE created_at > now() - interval '24 hours') as daily_signals_uploaded
;

-- 2. Federated Learning Status
-- Monitors the distribution and noise levels of uploaded deltas.
CREATE OR REPLACE VIEW public.ai_federated_learning_status AS
SELECT 
    bucket_id,
    signal_type,
    COUNT(*) as signal_count,
    AVG(noise_factor) as avg_noise_injected,
    AVG(delta_value) as avg_delta_value, -- Should be close to 0 if Global Model is good
    MIN(created_at) as first_signal_at,
    MAX(created_at) as last_signal_at
FROM 
    public.ai_federated_deltas
GROUP BY 
    bucket_id, signal_type
ORDER BY 
    bucket_id DESC, signal_type;

-- 3. Global Model Evolution
-- Tracks how weights change over versions.
CREATE OR REPLACE VIEW public.ai_global_model_evolution AS
SELECT 
    version_id,
    generation_count,
    weights,
    created_at,
    is_active
FROM 
    public.ai_global_weights
ORDER BY 
    generation_count DESC;

-- RLS for Views (Admin Only usually, or Authenticated)
-- Implicitly protected if underlying tables are protected, but good practice to specific access if needed.
-- For dashboarding, usually Service Role accesses these.
