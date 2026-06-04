/*
  FORCE FIX STAGE K
  =================
  Problem: 'user_channel_effectiveness' exists as a VIEW, preventing table modifiction.
  Solution: DROP the view and create the TABLE from scratch.
*/

-- 1. Drop dependencies (The view 'view_channel_scores' might depend on it if it existed, or vice versa)
DROP VIEW IF EXISTS public.view_channel_scores;

-- 2. Drop the conflicting relation (It claims to be a view, so DROP VIEW should work, but DROP TABLE CASCADE is safer for mixed signals or dependencies)
DROP VIEW IF EXISTS public.user_channel_effectiveness CASCADE;
DROP TABLE IF EXISTS public.user_channel_effectiveness CASCADE;

-- 3. Create the TABLE correctly
CREATE TABLE public.user_channel_effectiveness (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    channel TEXT NOT NULL DEFAULT 'fcm', -- 'fcm', 'email', 'sms', 'inbox'
    total_sent INTEGER DEFAULT 0,
    total_opened INTEGER DEFAULT 0,
    total_ignored INTEGER DEFAULT 0,
    last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (user_id, channel)
);

-- 4. Re-create the View that depends on the Table
CREATE OR REPLACE VIEW public.view_channel_scores AS
SELECT 
    user_id, 
    channel,
    CASE 
        WHEN total_sent = 0 THEN 0.5 -- Cold Start
        ELSE (total_opened::float / total_sent::float) 
    END as open_rate
FROM public.user_channel_effectiveness;

-- 5. Restore Permissions
ALTER TABLE public.user_channel_effectiveness ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view own effectiveness" ON public.user_channel_effectiveness FOR SELECT USING (auth.uid() = user_id);
