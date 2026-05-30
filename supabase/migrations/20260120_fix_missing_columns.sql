-- Add missing UI/UX state columns to conversation_participants
ALTER TABLE public.conversation_participants 
ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS is_muted BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT false;

-- Add group description to conversations
ALTER TABLE public.conversations
ADD COLUMN IF NOT EXISTS group_description TEXT;

-- Update comments
COMMENT ON COLUMN public.conversation_participants.is_pinned IS 'Whether the user has pinned this chat to the top';
COMMENT ON COLUMN public.conversation_participants.is_muted IS 'Whether the user has muted this chat (indefinite if true)';
COMMENT ON COLUMN public.conversation_participants.is_archived IS 'Whether the user has moved this chat to the archive';
COMMENT ON COLUMN public.conversations.group_description IS 'Optional detailed description of the group chat';
