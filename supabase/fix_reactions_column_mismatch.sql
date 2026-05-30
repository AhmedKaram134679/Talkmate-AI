-- ==========================================
-- PRODUCTION-READY REACTIONS SYSTEM (V2)
-- ==========================================

BEGIN;

-- 1. Optimized indexes for aggregation and lookup
CREATE INDEX IF NOT EXISTS idx_reactions_message_id ON public.reactions(message_id);
CREATE INDEX IF NOT EXISTS idx_reactions_composite ON public.reactions(message_id, user_id, emoji);

-- 2. REACTION TOGGLE LOGIC (RPC)
-- Use this from Flutter: supabase.rpc('fn_toggle_reaction', params: { ... })
-- Implementation: "Remove if same, Update if different, Insert if new"
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
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

    -- Find existing reaction
    SELECT emoji INTO v_existing_emoji
    FROM public.reactions
    WHERE message_id = p_message_id AND user_id = v_user_id;

    IF v_existing_emoji IS NULL THEN
        -- INSERT (New)
        INSERT INTO public.reactions (message_id, chat_id, user_id, emoji)
        VALUES (p_message_id, p_chat_id, v_user_id, p_emoji);
    ELSIF v_existing_emoji = p_emoji THEN
        -- DELETE (Toggle Off)
        DELETE FROM public.reactions
        WHERE message_id = p_message_id AND user_id = v_user_id;
    ELSE
        -- UPDATE (Change Emoji)
        UPDATE public.reactions
        SET emoji = p_emoji, created_at = now()
        WHERE message_id = p_message_id AND user_id = v_user_id;
    END IF;
END;
$$;

-- 3. REACTION CACHE SYNC (TRIGGER)
-- Updates messages.reactions cache { "userId": "emoji" } for real-time aggregation on client
CREATE OR REPLACE FUNCTION public.sync_message_reactions_v2()
RETURNS trigger AS $$
DECLARE
    target_msg_id uuid;
    aggregated_reactions jsonb;
BEGIN
    target_msg_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.message_id ELSE NEW.message_id END;

    SELECT jsonb_object_agg(user_id, emoji)
    INTO aggregated_reactions
    FROM public.reactions
    WHERE message_id = target_msg_id;

    UPDATE public.messages
    SET reactions = COALESCE(aggregated_reactions, '{}'::jsonb)
    WHERE id = target_msg_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach trigger
DROP TRIGGER IF EXISTS on_reaction_change ON public.reactions;
CREATE TRIGGER on_reaction_change
AFTER INSERT OR UPDATE OR DELETE ON public.reactions
FOR EACH ROW EXECUTE FUNCTION public.sync_message_reactions_v2();

-- 4. RLS POLICIES
ALTER TABLE public.reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "reactions_select_v2" ON public.reactions
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM public.conversation_participants
        WHERE conversation_id = reactions.chat_id AND user_id = auth.uid()
    )
);

CREATE POLICY "reactions_modify_own" ON public.reactions
FOR ALL USING ( user_id = auth.uid() );

-- 5. REALTIME REGISTRATION
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

NOTIFY pgrst, 'reload schema';
