/*
  STRESS TEST OPTIMIZATIONS
  =========================
  Apply these indexes to ensure O(1) performance during the 1000 msg/min load.
  
  Instructions:
  1. Run the stress test baseline first (optional).
  2. If CPU > 50% or Latency > 200ms, apply these indexes.
  3. Re-run stress test to verify improvement.
*/

-- 1. Optimizing Reaction Toggles (O(1) Lookup)
-- We need to check if a user has reacted to a message very quickly.
CREATE INDEX IF NOT EXISTS idx_reactions_lookup 
ON public.reactions (message_id, user_id);

-- 2. Optimizing Message Fetching (Descending Order)
-- The chat view fetches the last 50 messages consistently.
CREATE INDEX IF NOT EXISTS idx_messages_chat_created_desc 
ON public.messages (chat_id, created_at DESC);

-- 3. Optimizing Delivery Updates
-- When a user comes online, we query message_delivery by user_id and status.
CREATE INDEX IF NOT EXISTS idx_delivery_optimization 
ON public.message_delivery (user_id, status)
WHERE status != 'read';

-- 4. Optimizing Badge Counts
-- The 'view_user_unread_counts' uses a GROUP BY on chat_id. 
-- Ensure the underlying participants table is indexed for the join.
CREATE INDEX IF NOT EXISTS idx_participants_lookup 
ON public.conversation_participants (user_id, conversation_id);

-- 5. Hardening: Prevent Race Conditions (if not already applied)
ALTER TABLE public.reactions 
ADD CONSTRAINT unique_reaction_per_user 
UNIQUE (message_id, user_id, emoji);
-- Note: V4 logic enforces single reaction per user-message regardless of emoji, 
-- but if we allow multi-emoji, this constraint is fine. 
-- If strict single reaction: UNIQUE (message_id, user_id).
