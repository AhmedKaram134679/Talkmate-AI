/*
  STAGE K: INTELLIGENCE & OPTIMIZATION
  ====================================
  
  Enables the system to "Learn" from user behavior.
  1. Channel Effectiveness: Which channel works best?
  2. Federated Learning: Privacy-preserving weight updates.
  3. Global Weights: The "Brain" that evolves over time.
*/

-- 1. Channel Effectiveness (Per User/Channel)
CREATE TABLE IF NOT EXISTS public.user_channel_effectiveness (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    channel TEXT NOT NULL, -- 'fcm', 'email', 'sms', 'inbox'
    total_sent INTEGER DEFAULT 0,
    total_opened INTEGER DEFAULT 0,
    total_ignored INTEGER DEFAULT 0,
    last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (user_id, channel)
);

-- View for "Open Rate" calculation
CREATE OR REPLACE VIEW public.view_channel_scores AS
SELECT 
    user_id, 
    channel,
    CASE 
        WHEN total_sent = 0 THEN 0.5 -- Cold Start
        ELSE (total_opened::float / total_sent::float) 
    END as open_rate
FROM public.user_channel_effectiveness;


-- 2. Cloud-based Global Weights (The "Model")
CREATE TABLE IF NOT EXISTS public.ai_global_weights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version_id TEXT UNIQUE NOT NULL, -- e.g. 'v1.0.2'
    weights JSONB NOT NULL, -- { engagement_weight: 0.45, context_weight: 0.35 }
    is_active BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Seed initial model
INSERT INTO public.ai_global_weights (version_id, weights, is_active)
VALUES ('v1.0.0', '{"engagement_weight": 0.4, "context_weight": 0.3, "urgency_weight": 0.3}', true)
ON CONFLICT DO NOTHING;


-- 3. Federated Deltas (The "Signals")
-- Stores noisy gradients from users to update the global model.
CREATE TABLE IF NOT EXISTS public.ai_federated_deltas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    bucket_id TEXT NOT NULL, -- Time bucket (e.g. '2024-W10')
    signal_type TEXT NOT NULL, -- 'engagement_delta'
    delta_value FLOAT NOT NULL,
    noise_factor FLOAT NOT NULL, -- Recorded for audit/analysis
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- RPC: Record Feedback (Called by App when user opens/dismisses)
CREATE OR REPLACE FUNCTION public.record_notification_interaction(
    p_user_id UUID,
    p_channel TEXT,
    p_action TEXT -- 'OPENED', 'DISMISSED'
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO public.user_channel_effectiveness (user_id, channel, total_sent, total_opened, total_ignored)
    VALUES (p_user_id, p_channel, 1, 
            CASE WHEN p_action = 'OPENED' THEN 1 ELSE 0 END, 
            CASE WHEN p_action = 'DISMISSED' THEN 1 ELSE 0 END)
    ON CONFLICT (user_id, channel) DO UPDATE SET
        total_sent = user_channel_effectiveness.total_sent + 1,
        total_opened = user_channel_effectiveness.total_opened + (CASE WHEN p_action = 'OPENED' THEN 1 ELSE 0 END),
        total_ignored = user_channel_effectiveness.total_ignored + (CASE WHEN p_action = 'DISMISSED' THEN 1 ELSE 0 END),
        last_updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- RLS
ALTER TABLE public.user_channel_effectiveness ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_global_weights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_federated_deltas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own effectiveness" ON public.user_channel_effectiveness FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Auth read global weights" ON public.ai_global_weights FOR SELECT TO authenticated USING (true);
CREATE POLICY "Users insert deltas" ON public.ai_federated_deltas FOR INSERT WITH CHECK (auth.uid() = user_id);
