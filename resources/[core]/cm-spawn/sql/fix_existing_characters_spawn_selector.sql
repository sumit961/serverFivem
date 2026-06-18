-- Use this only for existing/test characters that should see the spawn selector.
-- New characters should stay has_spawned = 0 so they spawn directly at hotel first time.

-- Option A: mark one character as already spawned (replace 12 with your character id)
UPDATE characters SET has_spawned = 1 WHERE id = 12;

-- Option B: mark all existing characters as already spawned
-- UPDATE characters SET has_spawned = 1;
