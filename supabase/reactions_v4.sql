-- ==========================================
-- PROFESSIONAL REACTIONS SYSTEM V4
-- HARDENING & ANALYTICS
-- ==========================================

BEGIN;

-- 1. Rate Limiting Infra
CREATE TABLE IF NOT EXISTS public.user_reaction_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
    message_id uuid REFERENCES public.messages(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reaction_logs_user_msg ON public.user_reaction_logs(user_id, message_id);
CREATE INDEX IF NOT EXISTS idx_reaction_logs_created_at ON public.user_reaction_logs(created_at);

-- 2. Hardened Toggle Function V4
CREATE OR REPLACE FUNCTION public.fn_toggle_reaction_v4(
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
    v_recent_count int;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

    -- Anti-Spam Check: Max 10 reaction actions per message per minute per user
    SELECT count(*) INTO v_recent_count
    FROM public.user_reaction_logs
    WHERE user_id = v_user_id 
      AND message_id = p_message_id
      AND created_at > now() - interval '1 minute';

    IF v_recent_count >= 10 THEN
        RAISE EXCEPTION 'Rate limit exceeded for this message. Please wait a moment.';
    END IF;

    -- Persistence: Log this action for rate limiting
    INSERT INTO public.user_reaction_logs (user_id, message_id)
    VALUES (v_user_id, p_message_id);

    -- Security Check: Is user a participant?
    IF NOT EXISTS (
        SELECT 1 FROM public.conversation_participants 
        WHERE conversation_id = p_chat_id AND user_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Not a participant in this conversation';
    END IF;

    -- Core Logic: Toggle/Update
    SELECT emoji INTO v_existing_emoji
    FROM public.reactions
    WHERE message_id = p_message_id AND user_id = v_user_id;

    IF v_existing_emoji IS NULL THEN
        INSERT INTO public.reactions (message_id, chat_id, user_id, emoji)
        VALUES (p_message_id, p_chat_id, v_user_id, p_emoji);
    ELSIF v_existing_emoji = p_emoji THEN
        DELETE FROM public.reactions
        WHERE message_id = p_message_id AND user_id = v_user_id;
    ELSE
        UPDATE public.reactions
        SET emoji = p_emoji, created_at = now()
        WHERE message_id = p_message_id AND user_id = v_user_id;
    END IF;

    -- Cleanup old logs (maintenance)
    DELETE FROM public.user_reaction_logs WHERE created_at < now() - interval '1 hour';
END;
$$;

-- 3. Analytics Layer
CREATE OR REPLACE VIEW public.view_most_reacted_messages AS
SELECT 
    m.id as message_id,
    m.chat_id,
    m.text,
    count(r.id) as total_reactions,
    count(DISTINCT r.emoji) as unique_emojis
FROM public.messages m
JOIN public.reactions r ON m.id = r.message_id
GROUP BY m.id, m.chat_id, m.text
ORDER BY total_reactions DESC;

CREATE OR REPLACE FUNCTION public.fn_get_chat_engagement(p_chat_id uuid)
RETURNS TABLE (
    total_messages bigint,
    total_reactions bigint,
    engagement_score numeric
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        (SELECT count(*) FROM public.messages WHERE chat_id = p_chat_id) as total_messages,
        (SELECT count(*) FROM public.reactions WHERE chat_id = p_chat_id) as total_reactions,
        round(
            (SELECT count(*)::numeric FROM public.reactions WHERE chat_id = p_chat_id) / 
            NULLIF((SELECT count(*)::numeric FROM public.messages WHERE chat_id = p_chat_id), 0),
            2
        ) as engagement_score;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Housekeeping: Auto-update V3 references if needed
-- We keep v3 trigger as is, it only needs the toggle function to change.

COMMIT;
