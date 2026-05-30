-- Stage I Telemetry: Reliability & Assurance Metrics

-- 1. System Uptime & SLA Compliance
-- Measures the percentage of AI decisions made within the SLA limit vs Fallbacks.
CREATE OR REPLACE VIEW public.system_uptime_metrics AS
SELECT 
    DATE_TRUNC('hour', created_at) as time_window,
    COUNT(*) as total_requests,
    COUNT(*) FILTER (WHERE error_type IS NULL) as successful_ai_decisions,
    COUNT(*) FILTER (WHERE error_type = 'TIMEOUT') as timeout_failures,
    COUNT(*) FILTER (WHERE error_type = 'SYSTEM_ERROR') as system_errors,
    ROUND((COUNT(*) FILTER (WHERE error_type IS NULL)::float / NULLIF(COUNT(*), 0) * 100)::numeric, 2) as sla_compliance_rate
FROM 
    public.ai_failure_logs
RIGHT JOIN 
    generate_series(
        NOW() - INTERVAL '24 hours', 
        NOW(), 
        INTERVAL '1 hour'
    ) as time_window ON DATE_TRUNC('hour', created_at) = time_window
GROUP BY 
    1
ORDER BY 
    1 DESC;

-- 2. Fallback Rate Analysis
-- Analyzes which fallback strategies are being used and why.
CREATE OR REPLACE VIEW public.fallback_rate_analysis AS
SELECT 
    fallback_strategy,
    error_type,
    COUNT(*) as frequency,
    ROUND(AVG(latency_ms), 0) as avg_latency_at_failure
FROM 
    public.ai_failure_logs
GROUP BY 
    1, 2
ORDER BY 
    3 DESC;

-- 3. Decision Latency Histogram (Simulated via Buckets)
-- Since we don't log successful latency in failure logs, this relies on a hypothetical 'performance_logs' or assumes
-- we'd derive this from general application logs. For now, we analyze failure latency distribution.
CREATE OR REPLACE VIEW public.failure_latency_distribution AS
SELECT 
    WIDTH_BUCKET(latency_ms, 0, 2000, 10) as bucket,
    COUNT(*) as count,
    MIN(latency_ms) as min_ms,
    MAX(latency_ms) as max_ms
FROM 
    public.ai_failure_logs
GROUP BY 
    1
ORDER BY 
    1;
