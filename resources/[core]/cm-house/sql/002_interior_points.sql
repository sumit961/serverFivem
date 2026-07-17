-- ============================================================
--  cm-house | Migration 002
--  Adds the hand-placed interior points.
--
--  001 uses CREATE TABLE IF NOT EXISTS, which silently does NOTHING when the
--  table already exists -- so re-running it never adds a new column. This file
--  upgrades a table that is already there.
--
--  Safe to run repeatedly: every step checks the catalog first.
-- ============================================================

-- ---------- cm_houses: interior_spawn ----------
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME   = 'cm_houses'
             AND COLUMN_NAME  = 'interior_spawn');
SET @s := IF(@c = 0,
  'ALTER TABLE `cm_houses` ADD COLUMN `interior_spawn` JSON DEFAULT NULL AFTER `garage_interior_key`',
  'SELECT "interior_spawn exists" AS skipped');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ---------- cm_houses: interior_exit ----------
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME   = 'cm_houses'
             AND COLUMN_NAME  = 'interior_exit');
SET @s := IF(@c = 0,
  'ALTER TABLE `cm_houses` ADD COLUMN `interior_exit` JSON DEFAULT NULL AFTER `interior_spawn`',
  'SELECT "interior_exit exists" AS skipped');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ---------- cm_houses: garage_exit ----------
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME   = 'cm_houses'
             AND COLUMN_NAME  = 'garage_exit');
SET @s := IF(@c = 0,
  'ALTER TABLE `cm_houses` ADD COLUMN `garage_exit` JSON DEFAULT NULL AFTER `interior_exit`',
  'SELECT "garage_exit exists" AS skipped');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ---------- cm_house_wardrobes: coords ----------
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME   = 'cm_house_wardrobes'
             AND COLUMN_NAME  = 'coords');
SET @s := IF(@c = 0,
  'ALTER TABLE `cm_house_wardrobes` ADD COLUMN `coords` JSON DEFAULT NULL AFTER `label`',
  'SELECT "coords exists" AS skipped');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ---------- cm_house_wardrobes: inv_id must be a string ----------
-- It holds an address like "12:2", not a number. An earlier revision typed it
-- INT, which throws on the very first insert.
SET @t := (SELECT DATA_TYPE FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME   = 'cm_house_wardrobes'
             AND COLUMN_NAME  = 'inv_id');
SET @s := IF(@t = 'int',
  'ALTER TABLE `cm_house_wardrobes` MODIFY COLUMN `inv_id` VARCHAR(32) NOT NULL',
  'SELECT "inv_id already a string" AS skipped');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ---------- cm_houses: label must be a string ----------
SET @t := (SELECT DATA_TYPE FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME   = 'cm_houses'
             AND COLUMN_NAME  = 'label');
SET @s := IF(@t = 'int',
  'ALTER TABLE `cm_houses` MODIFY COLUMN `label` VARCHAR(64) DEFAULT NULL',
  'SELECT "label already a string" AS skipped');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'cm-house migration 002 complete' AS status;
