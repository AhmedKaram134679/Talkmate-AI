-- ==========================================
-- PROFESSIONAL REACTIONS SYSTEM V3
-- ==========================================

BEGIN;

-- 1. Ensure Table Structure
CREATE TABLE IF NOT EXISTS public.reactions (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    message_id uuid REFERENCES public.messages(id) ON DELETE CASCADE,
    chat_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    emoji text NOT NULL,
    created_at timestamptz DEFAULT now(),
    UNIQUE(message_id, user_id)
);

-- 2. Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_reactions_message_id ON public.reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_reactions_chat_id ON public.reactions(chat_id);

-- 3. Atomic Toggle Function
CREATE OR REPLACE FUNCTION public.fn_toggle_reaction_v3(
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
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- Security Check: Is user a participant?
    IF NOT EXISTS (
        SELECT 1 FROM public.conversation_participants 
        WHERE conversation_id = p_chat_id AND user_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Not a participant in this conversation';
    END IF;

    -- Check for existing reaction by this user on this message
    SELECT emoji INTO v_existing_emoji
    FROM public.reactions
    WHERE message_id = p_message_id AND user_id = v_user_id;

    IF v_existing_emoji IS NULL THEN
        -- Case: New Reaction
        INSERT INTO public.reactions (message_id, chat_id, user_id, emoji)
        VALUES (p_message_id, p_chat_id, v_user_id, p_emoji);
    ELSIF v_existing_emoji = p_emoji THEN
        -- Case: Toggle Off (User clicked the same emoji)
        DELETE FROM public.reactions
        WHERE message_id = p_message_id AND user_id = v_user_id;
    ELSE
        -- Case: Update Emoji (User clicked a different emoji)
        UPDATE public.reactions
        SET emoji = p_emoji, created_at = now()
        WHERE message_id = p_message_id AND user_id = v_user_id;
    END IF;
END;
$$;

-- 4. Advanced Aggregation Cache Trigger
-- This updates messages.reactions with a structured object:
-- {
--   "counts": { "👍": 5, "❤️": 2 },
--   "user_reactions": { "user_id_1": "👍", "user_id_2": "❤️" }
-- }
CREATE OR REPLACE FUNCTION public.sync_message_reactions_v3()
RETURNS trigger AS $$
DECLARE
    v_target_msg_id uuid;
    v_agg_counts jsonb;
    v_agg_users jsonb;
BEGIN
    v_target_msg_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.message_id ELSE NEW.message_id END;

    -- Aggregate counts per emoji
    SELECT jsonb_object_agg(emoji, count)
    INTO v_agg_counts
    FROM (
        SELECT emoji, count(*) as count
        FROM public.reactions
        WHERE message_id = v_target_msg_id
        GROUP BY emoji
    ) sub;

    -- Map user_id to emoji for "my reaction" check
    SELECT jsonb_object_agg(user_id::text, emoji)
    INTO v_agg_users
    FROM public.reactions
    WHERE message_id = v_target_msg_id;

    -- Update the messages table cache
    UPDATE public.messages
    SET reactions = jsonb_build_object(
        'counts', COALESCE(v_agg_counts, '{}'::jsonb),
        'user_reactions', COALESCE(v_agg_users, '{}'::jsonb)
    )
    WHERE id = v_target_msg_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Apply Trigger
DROP TRIGGER IF EXISTS on_reaction_change_v3 ON public.reactions;
CREATE TRIGGER on_reaction_change_v3
    AFTER INSERT OR UPDATE OR DELETE ON public.reactions
    FOR EACH ROW EXECUTE FUNCTION public.sync_message_reactions_v3();

-- 6. Row Level Security
ALTER TABLE public.reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "reactions_select_policy" ON public.reactions;
CREATE POLICY "reactions_select_policy" ON public.reactions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.conversation_participants
            WHERE conversation_id = reactions.chat_id AND user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "reactions_insert_policy" ON public.reactions;
CREATE POLICY "reactions_insert_policy" ON public.reactions
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "reactions_modify_own_policy" ON public.reactions;
CREATE POLICY "reactions_modify_own_policy" ON public.reactions
    FOR ALL
    USING (auth.uid() = user_id);

-- 7. Realtime Enablement
-- Note: Requires service role or superuser to manage publications via SQL comfortably, 
-- but normally enabled via dashboard. Here we provide the command.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables 
            WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'reactions'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.reactions;
        END IF;
    END IF;
END $$;

COMMIT;
