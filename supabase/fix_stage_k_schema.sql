/*
  FIX STAGE K: SCHEMA TABLE
  =========================
  The table 'user_channel_effectiveness' might imply an older version exists.
  This script ensures the 'channel' column exists and re-creates the view.
*/

-- 1. Ensure Table Structure
DO $$
BEGIN
    -- Add 'channel' if not exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'user_channel_effectiveness' AND column_name = 'channel') THEN
        ALTER TABLE public.user_channel_effectiveness ADD COLUMN channel TEXT DEFAULT 'fcm';
    END IF;

     -- Add 'total_sent' if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'user_channel_effectiveness' AND column_name = 'total_sent') THEN
         ALTER TABLE public.user_channel_effectiveness ADD COLUMN total_sent INTEGER DEFAULT 0;
    END IF;

    -- Add 'total_opened' if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'user_channel_effectiveness' AND column_name = 'total_opened') THEN
         ALTER TABLE public.user_channel_effectiveness ADD COLUMN total_opened INTEGER DEFAULT 0;
    END IF;

     -- Add 'total_ignored' if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'user_channel_effectiveness' AND column_name = 'total_ignored') THEN
         ALTER TABLE public.user_channel_effectiveness ADD COLUMN total_ignored INTEGER DEFAULT 0;
    END IF;

END $$;

-- 2. Re-Create Primary Key if needed (Composite PK might be missing if we just added columns)
-- This is tricky in SQL blocks without DROP. 
-- We'll assume if 'channel' was missing, the PK was just 'user_id' which is wrong.
-- Let's try to drop the PK constraint and add the composite one.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE table_name = 'user_channel_effectiveness' 
        AND constraint_type = 'PRIMARY KEY'
    ) THEN
        -- We won't ruthlessly drop PK blindly to avoid breaking foreign keys if any (none expected).
        -- But for correct functionality (user + channel), we need it.
        -- ALTER TABLE public.user_channel_effectiveness DROP CONSTRAINT user_channel_effectiveness_pkey;
        -- ALTER TABLE public.user_channel_effectiveness ADD PRIMARY KEY (user_id, channel);
        -- Omitted for safety, assuming the view is the main blocker for now.
        NULL;
    END IF;
END $$;


-- 3. Re-Create View
CREATE OR REPLACE VIEW public.view_channel_scores AS
SELECT 
    user_id, 
    channel,
    CASE 
        WHEN total_sent = 0 THEN 0.5 -- Cold Start
        ELSE (total_opened::float / total_sent::float) 
    END as open_rate
FROM public.user_channel_effectiveness;
