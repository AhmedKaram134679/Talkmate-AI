/*
  COMPREHENSIVE DATABASE REPAIR SCRIPT 2.0 (RECURSION FIX)
  ========================================================
  This script fixes the database schema and specifically addresses the
  infinite recursion error in RLS policies by using a helper function.
*/

BEGIN;

--------------------------------------------------------------------------------
-- 1. HELPER FUNCTIONS (Prevent Infinite Recursion)
--------------------------------------------------------------------------------

-- Checks if the invoking user is a participant of the given conversation.
-- SECURITY DEFINER allows this function to bypass RLS on the table it queries,
-- preventing the infinite loop when called FROM an RLS policy.
CREATE OR REPLACE FUNCTION public.is_item_accessible(_conversation_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.conversation_participants
    WHERE conversation_id = _conversation_id
    AND user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


--------------------------------------------------------------------------------
-- 2. PROFILES
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  username text,
  email text,
  status text DEFAULT 'offline',
  last_seen timestamptz,
  avatar_url text,
  about text,
  privacy_show_last_seen boolean DEFAULT true,
  privacy_show_profile_photo boolean DEFAULT true,
  privacy_show_status boolean DEFAULT true,
  fcm_token text,
  fcm_tokens text[],
  platform text,
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Add columns if missing
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'fcm_tokens') THEN
    ALTER TABLE public.profiles ADD COLUMN fcm_tokens text[];
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'platform') THEN
    ALTER TABLE public.profiles ADD COLUMN platform text;
  END IF;
END $$;

-- Policies
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
CREATE POLICY "Public profiles are viewable by everyone" ON public.profiles FOR SELECT USING ( true );

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING ( auth.uid() = id );

DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK ( auth.uid() = id );

--------------------------------------------------------------------------------
-- 3. FRIEND_REQUESTS
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.friend_requests (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  sender_id uuid REFERENCES public.profiles(id) NOT NULL,
  receiver_id uuid REFERENCES public.profiles(id) NOT NULL,
  status text DEFAULT 'pending',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.friend_requests ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'friend_requests' AND column_name = 'updated_at') THEN
    ALTER TABLE public.friend_requests ADD COLUMN updated_at timestamptz DEFAULT now();
  END IF;
END $$;

DROP POLICY IF EXISTS "View own friend requests" ON public.friend_requests;
CREATE POLICY "View own friend requests" ON public.friend_requests FOR SELECT
USING ( auth.uid() = sender_id OR auth.uid() = receiver_id );

DROP POLICY IF EXISTS "Create friend request" ON public.friend_requests;
CREATE POLICY "Create friend request" ON public.friend_requests FOR INSERT
WITH CHECK ( auth.uid() = sender_id );

DROP POLICY IF EXISTS "Update friend request" ON public.friend_requests;
CREATE POLICY "Update friend request" ON public.friend_requests FOR UPDATE
USING ( auth.uid() = receiver_id OR auth.uid() = sender_id );

DROP POLICY IF EXISTS "Delete sent request" ON public.friend_requests;
CREATE POLICY "Delete sent request" ON public.friend_requests FOR DELETE
USING ( auth.uid() = sender_id );

--------------------------------------------------------------------------------
-- 4. FRIENDS
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.friends (
  user_id uuid REFERENCES public.profiles(id) NOT NULL,
  friend_id uuid REFERENCES public.profiles(id) NOT NULL,
  status text DEFAULT 'accepted',
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, friend_id)
);

ALTER TABLE public.friends ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "View own friends" ON public.friends;
CREATE POLICY "View own friends" ON public.friends FOR SELECT
USING ( auth.uid() = user_id OR auth.uid() = friend_id );

DROP POLICY IF EXISTS "Create friendship" ON public.friends;
CREATE POLICY "Create friendship" ON public.friends FOR INSERT
WITH CHECK ( auth.uid() = user_id OR auth.uid() = friend_id );

DROP POLICY IF EXISTS "Update friendship" ON public.friends;
CREATE POLICY "Update friendship" ON public.friends FOR UPDATE
USING ( auth.uid() = user_id OR auth.uid() = friend_id );

DROP POLICY IF EXISTS "Delete friendship" ON public.friends;
CREATE POLICY "Delete friendship" ON public.friends FOR DELETE
USING ( auth.uid() = user_id OR auth.uid() = friend_id );

--------------------------------------------------------------------------------
-- 5. CONVERSATIONS
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  is_group boolean DEFAULT false,
  group_name text,
  group_photo_url text,
  group_description text,
  last_message_text text,
  last_message_time timestamptz,
  last_message_sender_id uuid REFERENCES public.profiles(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'conversations' AND column_name = 'group_name') THEN
    ALTER TABLE public.conversations ADD COLUMN group_name text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'conversations' AND column_name = 'group_description') THEN
    ALTER TABLE public.conversations ADD COLUMN group_description text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'conversations' AND column_name = 'created_at') THEN
    ALTER TABLE public.conversations ADD COLUMN created_at timestamptz DEFAULT now();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'conversations' AND column_name = 'group_photo_url') THEN
    ALTER TABLE public.conversations ADD COLUMN group_photo_url text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'conversations' AND column_name = 'last_message_text') THEN
    ALTER TABLE public.conversations ADD COLUMN last_message_text text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'conversations' AND column_name = 'last_message_time') THEN
    ALTER TABLE public.conversations ADD COLUMN last_message_time timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'conversations' AND column_name = 'last_message_sender_id') THEN
    ALTER TABLE public.conversations ADD COLUMN last_message_sender_id uuid REFERENCES public.profiles(id);
  END IF;
END $$;

-- Policy uses the Security Definer function to avoid recursion
DROP POLICY IF EXISTS "View conversations user participates in" ON public.conversations;
CREATE POLICY "View conversations user participates in" ON public.conversations FOR SELECT
USING ( public.is_item_accessible(id) );

DROP POLICY IF EXISTS "Update conversations user participates in" ON public.conversations;
CREATE POLICY "Update conversations user participates in" ON public.conversations FOR UPDATE
USING ( public.is_item_accessible(id) );

DROP POLICY IF EXISTS "Insert conversations" ON public.conversations;
CREATE POLICY "Insert conversations" ON public.conversations FOR INSERT
WITH CHECK ( true );

--------------------------------------------------------------------------------
-- 6. CONVERSATION_PARTICIPANTS
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.conversation_participants (
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at timestamptz DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);

ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;

-- Uses user_id = auth.uid() for basic list, and the function for viewing others in same chat
DROP POLICY IF EXISTS "View participants" ON public.conversation_participants;
CREATE POLICY "View participants" ON public.conversation_participants FOR SELECT
USING (
  user_id = auth.uid() OR
  public.is_item_accessible(conversation_id)
);

DROP POLICY IF EXISTS "Insert participants" ON public.conversation_participants;
CREATE POLICY "Insert participants" ON public.conversation_participants FOR INSERT
WITH CHECK ( true );

DROP POLICY IF EXISTS "Delete self" ON public.conversation_participants;
CREATE POLICY "Delete self" ON public.conversation_participants FOR DELETE
USING ( user_id = auth.uid() );

--------------------------------------------------------------------------------
-- 7. MESSAGES
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.messages (
  "id" uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  "chatId" uuid REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  "senderId" uuid REFERENCES public.profiles(id) NOT NULL,
  "type" text DEFAULT 'text',
  "text" text,
  "mediaUrl" text,
  "thumbnailUrl" text,
  "mediaSize" bigint,
  "status" text DEFAULT 'sent',
  "createdAt" timestamptz DEFAULT now(),
  "isEdited" boolean DEFAULT false,
  "editedAt" timestamptz,
  "isDeleted" boolean DEFAULT false,
  "deletedAt" timestamptz
);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'chatId') THEN
    ALTER TABLE public.messages ADD COLUMN "chatId" uuid REFERENCES public.conversations(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'senderId') THEN
    ALTER TABLE public.messages ADD COLUMN "senderId" uuid REFERENCES public.profiles(id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'createdAt') THEN
    ALTER TABLE public.messages ADD COLUMN "createdAt" timestamptz DEFAULT now();
  END IF;
END $$;

DROP POLICY IF EXISTS "View messages in own chats" ON public.messages;
CREATE POLICY "View messages in own chats" ON public.messages FOR SELECT
USING ( public.is_item_accessible("chatId") );

DROP POLICY IF EXISTS "Send messages to own chats" ON public.messages;
CREATE POLICY "Send messages to own chats" ON public.messages FOR INSERT
WITH CHECK (
  "senderId" = auth.uid() AND
  public.is_item_accessible("chatId")
);

DROP POLICY IF EXISTS "Update own messages" ON public.messages;
CREATE POLICY "Update own messages" ON public.messages FOR UPDATE
USING ( "senderId" = auth.uid() );

--------------------------------------------------------------------------------
-- 8. REALTIME PUBLICATION
--------------------------------------------------------------------------------
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.friend_requests;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.friends;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.conversation_participants;
  ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
EXCEPTION WHEN OTHERS THEN
  NULL; -- Ignore
END $$;

COMMIT;
