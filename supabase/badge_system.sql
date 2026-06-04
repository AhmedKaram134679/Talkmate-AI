-- STAGE Z-2: BADGE SYSTEM (UNREAD COUNT)

-- RPC to get unread count for a specific device
CREATE OR REPLACE FUNCTION public.get_unread_count(p_device_id text)
RETURNS bigint AS $$
BEGIN
  RETURN (
    SELECT count(*)
    FROM public.message_delivery
    WHERE device_id = p_device_id
      AND status <> 'read'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
