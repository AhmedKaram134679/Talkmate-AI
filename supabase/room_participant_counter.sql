-- [Stage R-Stability] Room Participant Counter Synchronization
-- This script adds a persistent counter to the 'rooms' table and automates it via triggers.

-- 1. Add column to rooms table
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='rooms' AND column_name='participant_count') THEN
    ALTER TABLE public.rooms ADD COLUMN participant_count int DEFAULT 0;
  END IF;
END $$;

-- 2. Create function to update count (Self-healing logic)
CREATE OR REPLACE FUNCTION public.sync_room_participant_count() 
RETURNS TRIGGER AS $$
BEGIN
  -- We recalculate the actual count for the room(s) affected
  -- This is more robust than increment/decrement which can drift
  
  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    UPDATE public.rooms 
    SET participant_count = (
      SELECT count(*) 
      FROM public.room_participants 
      WHERE room_id = NEW.room_id
    )
    WHERE id = NEW.room_id;
  END IF;

  IF (TG_OP = 'DELETE' OR TG_OP = 'UPDATE') THEN
    UPDATE public.rooms 
    SET participant_count = (
      SELECT count(*) 
      FROM public.room_participants 
      WHERE room_id = OLD.room_id
    )
    WHERE id = OLD.room_id;
  END IF;
  
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Create trigger on room_participants (Covering all events)
DROP TRIGGER IF EXISTS on_room_participant_change ON public.room_participants;
CREATE TRIGGER on_room_participant_change
AFTER INSERT OR DELETE OR UPDATE ON public.room_participants
FOR EACH ROW EXECUTE FUNCTION public.sync_room_participant_count();

-- 4. Initial Global Sync (Run once to fix existing errors)
UPDATE public.rooms r
SET participant_count = (
  SELECT count(*) 
  FROM public.room_participants 
  WHERE room_id = r.id
);
