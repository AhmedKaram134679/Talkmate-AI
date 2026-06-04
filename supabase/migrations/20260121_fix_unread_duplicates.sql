-- QA REMEDIATION: Fix Unread Count duplicate counting
BEGIN;

-- 1. Fix view_user_unread_counts
-- Current logic counts every device entry as an unread item, inflating the badge.
-- New logic counts unique message_id per user.
CREATE OR REPLACE VIEW public.view_user_unread_counts AS
SELECT 
    user_id,
    count(DISTINCT message_id) as unread_total
FROM public.message_delivery
WHERE status <> 'read'
GROUP BY user_id;

-- 2. Performance index for the new DISTINCT count
CREATE INDEX IF NOT EXISTS idx_message_delivery_user_msg_unread 
ON public.message_delivery(user_id, message_id) 
WHERE status <> 'read';

COMMIT;
