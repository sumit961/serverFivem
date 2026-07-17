-- ============================================================
--  cm-house | Migration 007  |  One door, two options
--
--  The interior used to need TWO points: an exit, and a separate door to the
--  garage. Same in the garage: an entry, and a separate door back. Four
--  coordinates for what is physically one doorway each.
--
--  Now there is ONE door per room. Standing at it, E offers "Leave" and "Go
--  to the garage" -- so the second point was never anything but a duplicate of
--  the first.
--
--  The columns stay (old rows still have data in them) but they are no longer
--  written or read. house_door was NOT NULL, which would reject every new
--  garage template, so that constraint has to go.
--
--  Safe to run repeatedly.
-- ============================================================

-- house_door was NOT NULL. Nothing writes it any more, so a new garage
-- template would be rejected outright.
SET @n := (SELECT IS_NULLABLE FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME   = 'cm_house_garage_templates'
             AND COLUMN_NAME  = 'house_door');
SET @s := IF(@n = 'NO',
  'ALTER TABLE `cm_house_garage_templates` MODIFY COLUMN `house_door` JSON DEFAULT NULL',
  'SELECT "house_door already nullable" AS skipped');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- garage_door was already nullable, but make it explicit rather than assumed.
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME   = 'cm_house_interior_templates'
             AND COLUMN_NAME  = 'garage_door');
SET @s := IF(@c > 0,
  'ALTER TABLE `cm_house_interior_templates` MODIFY COLUMN `garage_door` JSON DEFAULT NULL',
  'SELECT "no garage_door column" AS skipped');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'cm-house migration 007 (one door) complete' AS status;
