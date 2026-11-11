-- Scope view_user_unread_counts to the calling user.
-- The view runs with its owner's privileges (it bypasses RLS), so without this
-- filter any logged-in user could read every user's unread counters.
BEGIN;

CREATE OR REPLACE VIEW public.view_user_unread_counts AS
SELECT
    user_id,
    count(DISTINCT message_id) AS unread_total
FROM public.message_delivery
WHERE status <> 'read'
  AND (user_id = auth.uid() OR auth.role() = 'service_role')
GROUP BY user_id;

REVOKE ALL ON public.view_user_unread_counts FROM anon;

COMMIT;
