-- Stage I: AI Reliability & Assurance Schema

-- 1. AI Failure Logs
-- Tracks operational failures when the AI cannot produce a valid decision in time or with confidence.
CREATE TABLE IF NOT EXISTS public.ai_failure_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    error_type TEXT NOT NULL CHECK (error_type IN ('TIMEOUT', 'DRIFT_SPIKE', 'DATA_MISSING', 'LOW_CONFIDENCE', 'SYSTEM_ERROR')),
    fallback_strategy TEXT NOT NULL CHECK (fallback_strategy IN ('FORCE_DELIVER', 'SAFE_SILENT', 'RULE_BASED', 'LAST_KNOWN_STABLE')),
    latency_ms INTEGER, -- How many ms elapsed before the failure occurred
    details JSONB DEFAULT '{}'::jsonb, -- Context: {"trigger": "timeout_800ms", "attempts": 1}
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. AI Reliability Configuration
-- Stores SLA limits and confidence thresholds per user (or global defaults via separate mechanisms).
CREATE TABLE IF NOT EXISTS public.ai_reliability_config (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    max_execution_ms INTEGER DEFAULT 800, -- Hard SLA timeout in milliseconds
    min_confidence_score FLOAT DEFAULT 0.4, -- Minimum score required to trust the AI's utility calculation
    circuit_breaker_enabled BOOLEAN DEFAULT true, -- If true, continuous failures trigger a temporary "Safe Mode"
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- RLS Policies

-- Failure Logs: Users can see their own failures (for transparency/debugging)
ALTER TABLE public.ai_failure_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users view own failure logs" ON public.ai_failure_logs;
CREATE POLICY "Users view own failure logs" ON public.ai_failure_logs
    FOR SELECT USING (auth.uid() = user_id);

-- Reliability Config: Users can view and edit their own config
ALTER TABLE public.ai_reliability_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users view own reliability config" ON public.ai_reliability_config;
CREATE POLICY "Users view own reliability config" ON public.ai_reliability_config
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users update own reliability config" ON public.ai_reliability_config;
CREATE POLICY "Users update own reliability config" ON public.ai_reliability_config
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users insert own reliability config" ON public.ai_reliability_config;
CREATE POLICY "Users insert own reliability config" ON public.ai_reliability_config
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_ai_failure_logs_user_created ON public.ai_failure_logs(user_id, created_at DESC);
