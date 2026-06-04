-- 1. Sync all users from auth.users to public.profiles (ensures missing rows are created)
INSERT INTO public.profiles (id, email, username)
SELECT 
  id, 
  email, 
  COALESCE(raw_user_meta_data->>'username', email)
FROM auth.users
ON CONFLICT (id) DO UPDATE
SET 
  email = EXCLUDED.email,
  username = COALESCE(public.profiles.username, EXCLUDED.username);

-- 2. Create or replace a function to sync profile email/username on auth.users changes
CREATE OR REPLACE FUNCTION public.handle_auth_user_sync()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, username)
  VALUES (new.id, new.email, new.raw_user_meta_data->>'username')
  ON CONFLICT (id) DO UPDATE
  SET 
    email = EXCLUDED.email,
    username = COALESCE(public.profiles.username, EXCLUDED.username);
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Create a trigger to automate the sync for new/updated users
DROP TRIGGER IF EXISTS on_auth_user_sync ON auth.users;
CREATE TRIGGER on_auth_user_sync
  AFTER INSERT OR UPDATE OF email, raw_user_meta_data ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_auth_user_sync();
