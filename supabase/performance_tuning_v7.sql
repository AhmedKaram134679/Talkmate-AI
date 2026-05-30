/*
  PERFORMANCE TUNING V7 (MIGRATION)
  =================================
  Permanent application of Stress Test Optimizations.
  
  Instructions:
  1. Run this script in Supabase SQL Editor to prepare for high scale.
*/

-- 1. Indexing Reaction Toggles for O(1) Performance
CREATE INDEX IF NOT EXISTS idx_reactions_lookup 
ON public.reactions (message_id, user_id);

-- 2. Indexing Message Retrieval for Chat View
CREATE INDEX IF NOT EXISTS idx_messages_chat_created_desc 
ON public.messages (chat_id, created_at DESC);

-- 3. Optimization for Presence/Delivery Logic
CREATE INDEX IF NOT EXISTS idx_delivery_optimization 
ON public.message_delivery (user_id, status)
WHERE status != 'read';

-- 4. Unread Badge Count Optimization
CREATE INDEX IF NOT EXISTS idx_participants_lookup 
ON public.conversation_participants (user_id, conversation_id);

-- 5. Data Integrity: Prevent Logic Race Conditions
-- Ensure a user can only have one reaction record per message-emoji pair
-- (or per message if single-reaction logic is preferred, but V4 allows multi-emoji toggles if different types)
-- Adding constraint for safety.
ALTER TABLE public.reactions 
ADD CONSTRAINT unique_reaction_per_user_emoji 
UNIQUE (message_id, user_id, emoji);
