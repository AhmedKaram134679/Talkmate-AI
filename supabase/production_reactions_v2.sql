-- ==========================================
-- PRODUCTION-READY REACTIONS SYSTEM (V2)
-- ==========================================

BEGIN;

--------------------------------------------------------------------------------
-- 1. TABLE ENHANCEMENTS & INDEXES
--------------------------------------------------------------------------------

-- Ensure reactions has chat_id for RLS and grouping
-- (Chat_id helps in Realtime filtering per chat)
ALTER TABLE IF EXISTS public.reactions 
ADD COLUMN IF NOT EXISTS chat_id uuid REFERENCES public.conversations(id);

-- Optimized indexes for aggregation and lookup
CREATE INDEX IF NOT EXISTS idx_reactions_message_id ON public.reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_reactions_composite ON public.reactions(message_id, user_id, emoji);

--------------------------------------------------------------------------------
-- 2. REACTION CACHE SYNC (TRIGGER)
--------------------------------------------------------------------------------
-- This function updates the 'reactions' JSONB column in 'messages' table.
-- Format: { "emoji": { "count": X, "me": boolean } } - No, "me" is per user.
-- Better Format: { "emoji": count } is simple for general display.
-- "Clicked by me" is best handled by checking if userId exists in a separate list or just using the RPC.
-- However, for the best Realtime experience, we store: 
-- { "👍": 5, "❤️": 2, "user_map": { "userId1": "👍", "userId2": "❤️" } }
-- This allows the client to know EVERYTHING in one real-time event.

CREATE OR REPLACE FUNCTION public.sync_message_reactions_v2()
RETURNS trigger AS $$
DECLARE
    target_msg_id uuid;
    summary_data jsonb;
    emoji_counts jsonb;
    user_map jsonb;
BEGIN
    target_msg_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.message_id ELSE NEW.message_id END;

    -- 1. Calculate Emoji Counts: { "👍": 5, "❤️": 2 }
    SELECT jsonb_object_agg(emoji, cnt)
    INTO emoji_counts
    FROM (
        SELECT emoji, count(*) as cnt
        FROM public.reactions
        WHERE message_id = target_msg_id
        GROUP BY emoji
    ) s;

    -- 2. Map Users to Emojis (for "my reaction" check): { "user_uuid": "👍" }
    SELECT jsonb_object_agg(user_id, emoji)
    INTO user_map
    FROM public.reactions
    WHERE message_id = target_msg_id;

    -- 3. Combine into final cache
    summary_data := jsonb_build_object(
        'counts', COALESCE(emoji_counts, '{}'::jsonb),
        'user_map', COALESCE(user_map, '{}'::jsonb)
    );

    -- Update parent message
    UPDATE public.messages
    SET reactions = summary_data
    WHERE id = target_msg_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach trigger
DROP TRIGGER IF EXISTS on_reaction_change ON public.reactions;
CREATE TRIGGER on_reaction_change
AFTER INSERT OR UPDATE OR DELETE ON public.reactions
FOR EACH ROW EXECUTE FUNCTION public.sync_message_reactions_v2();

--------------------------------------------------------------------------------
-- 3. REACTION TOGGLE LOGIC (RPC)
--------------------------------------------------------------------------------
-- Use this from Flutter: supabase.rpc('fn_toggle_reaction', params: { ... })
-- Implementation of: "Remove if same, Update if different, Insert if new"

CREATE OR REPLACE FUNCTION public.fn_toggle_reaction(
    p_message_id uuid,
    p_chat_id uuid,
    p_emoji text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_emoji text;
    v_user_id uuid := auth.uid();
BEGIN
    -- 1. Security Check
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    -- 2. Find existing reaction for this user on this message
    SELECT emoji INTO v_existing_emoji
    FROM public.reactions
    WHERE message_id = p_message_id AND user_id = v_user_id;

    IF v_existing_emoji IS NULL THEN
        -- Case: New Reaction -> INSERT
        INSERT INTO public.reactions (message_id, chat_id, user_id, emoji)
        VALUES (p_message_id, p_chat_id, v_user_id, p_emoji);
    
    ELSIF v_existing_emoji = p_emoji THEN
        -- Case: Same Emoji -> TOGGLE OFF (DELETE)
        DELETE FROM public.reactions
        WHERE message_id = p_message_id AND user_id = v_user_id;
    
    ELSE
        -- Case: Different Emoji -> UPDATE
        UPDATE public.reactions
        SET emoji = p_emoji, created_at = now()
        WHERE message_id = p_message_id AND user_id = v_user_id;
    END IF;
END;
$$;

--------------------------------------------------------------------------------
-- 4. AGGREGATION VIEW & RPC
--------------------------------------------------------------------------------
-- Useful for deep inspection or non-realtime fetch

CREATE OR REPLACE VIEW public.view_message_reactions_summary AS
SELECT 
    message_id,
    emoji,
    count(*) as reaction_count,
    array_agg(user_id) as user_ids
FROM public.reactions
GROUP BY message_id, emoji;

--------------------------------------------------------------------------------
-- 5. ACCESS SECURITY (RLS)
--------------------------------------------------------------------------------

ALTER TABLE public.reactions ENABLE ROW LEVEL SECURITY;

-- Select: Can see reactions if you can see the chat
DROP POLICY IF EXISTS "reactions_select" ON public.reactions;
CREATE POLICY "reactions_select" ON public.reactions
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.conversation_participants
        WHERE conversation_id = reactions.chat_id AND user_id = auth.uid()
    )
);

-- Delete: Can only delete your own
DROP POLICY IF EXISTS "reactions_delete_own" ON public.reactions;
CREATE POLICY "reactions_delete_own" ON public.reactions
FOR DELETE USING ( user_id = auth.uid() );

--------------------------------------------------------------------------------
-- 6. REALTIME REGISTRATION
--------------------------------------------------------------------------------
-- Add to publication if not already present
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'reactions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE reactions;
    END IF;
END $$;

COMMIT;

-- Refresh PostgREST
NOTIFY pgrst, 'reload schema';
