-- Add mute_until column for duration-based muting
ALTER TABLE conversation_participants 
ADD COLUMN IF NOT EXISTS mute_until TIMESTAMPTZ DEFAULT NULL;

COMMENT ON COLUMN conversation_participants.mute_until IS 'If set, notifications are muted until this timestamp. NULL means not muted (unless is_muted is true for indefinite).';

-- Update trigger to respect mute_until would be in the edge function logic mostly, 
-- but let's ensure we have an index on it if we query active mutes often.
CREATE INDEX IF NOT EXISTS idx_participants_mute_until ON conversation_participants (mute_until);
