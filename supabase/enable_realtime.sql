-- STAGE Z-1: ENABLE REALTIME FOR UI SYNC

-- Enable Realtime for the message_delivery table to support live checkmark updates
alter publication supabase_realtime add table public.message_delivery;
