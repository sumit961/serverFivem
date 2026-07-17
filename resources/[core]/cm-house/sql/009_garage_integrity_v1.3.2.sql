-- ============================================================
-- cm-house v1.3.2 | Garage condition + identity integrity
-- Safe to run repeatedly after backing up the database.
-- ============================================================

-- Full physical damage snapshot (windows, doors, tyres, flags).
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_owned_vehicles'
             AND COLUMN_NAME = 'condition_state');
SET @s := IF(@c = 0,
  'ALTER TABLE `cm_owned_vehicles` ADD COLUMN `condition_state` LONGTEXT NULL AFTER `dirt_level`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- Match cm_owned_vehicles.id (BIGINT). This prevents integer overflow from
-- breaking the authoritative vehicle identity on long-running servers.
ALTER TABLE `cm_house_vehicle_slots` MODIFY COLUMN `vehicle_id` BIGINT NULL;

SET @c := (SELECT COUNT(*) FROM information_schema.TABLES
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_house_shared_vehicles');
SET @s := IF(@c > 0,
  'ALTER TABLE `cm_house_shared_vehicles` MODIFY COLUMN `vehicle_id` BIGINT NOT NULL',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- Clean legacy duplicate physical slot rows before adding the unique key.
DELETE newer
FROM cm_house_vehicle_slots newer
INNER JOIN cm_house_vehicle_slots older
        ON older.house_id = newer.house_id
       AND older.slot_index = newer.slot_index
       AND older.id < newer.id;

-- A database vehicle may occupy only one slot. Keep its oldest assignment and
-- release every duplicate assignment without deleting the slot itself.
UPDATE cm_house_vehicle_slots duplicate_slot
INNER JOIN (
    SELECT vehicle_id, MIN(id) AS keep_id
    FROM cm_house_vehicle_slots
    WHERE vehicle_id IS NOT NULL
    GROUP BY vehicle_id
    HAVING COUNT(*) > 1
) duplicate_vehicle ON duplicate_vehicle.vehicle_id = duplicate_slot.vehicle_id
SET duplicate_slot.vehicle_id = NULL,
    duplicate_slot.owner_class = 'personal',
    duplicate_slot.assigned_by = NULL,
    duplicate_slot.assigned_at = NULL
WHERE duplicate_slot.id <> duplicate_vehicle.keep_id;

SET @c := (SELECT COUNT(*) FROM information_schema.STATISTICS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_house_vehicle_slots'
             AND INDEX_NAME = 'uq_house_slot');
SET @s := IF(@c = 0,
  'ALTER TABLE `cm_house_vehicle_slots` ADD UNIQUE KEY `uq_house_slot` (`house_id`, `slot_index`)',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SET @c := (SELECT COUNT(*) FROM information_schema.STATISTICS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_house_vehicle_slots'
             AND INDEX_NAME = 'uq_vehicle_once');
SET @s := IF(@c = 0,
  'ALTER TABLE `cm_house_vehicle_slots` ADD UNIQUE KEY `uq_vehicle_once` (`vehicle_id`)',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'cm-house migration 009 (garage integrity v1.3.2) complete' AS status;
