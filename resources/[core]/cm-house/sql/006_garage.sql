-- ============================================================
--  cm-house | Migration 006  |  PHASE 3 -- vehicle garage
--
--  THE KEY DECISION.
--
--  cm-vehicles ALREADY owns where a vehicle is:
--      cm_owned_vehicles.is_stored   -- in a garage, or out in the world
--      cm_owned_vehicles.garage      -- which garage
--      cm_owned_vehicles.parking_id
--
--  If cm-house also kept a `state` column, two systems would each believe they
--  know where a car is -- and the moment they disagree, the car exists twice.
--  That is precisely how vehicles get duplicated.
--
--  So cm_house_vehicle_slots becomes a pure SEATING CHART: which slot holds
--  which car. Whether that car is currently in the world is answered by
--  cm-vehicles, and only by cm-vehicles.
--
--  Safe to run repeatedly.
-- ============================================================

-- ---------- Slots: seating chart only ----------
-- `state` is dropped. A slot either holds a vehicle_id or it does not; the
-- vehicle's own is_stored says whether it is physically parked there.
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_vehicle_slots'
             AND COLUMN_NAME='state');
SET @s := IF(@c > 0,
  'ALTER TABLE `cm_house_vehicle_slots` DROP COLUMN `state`',
  'SELECT "state already dropped" AS skipped');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- Who assigned the car here, and when. Answers "who took my parking space".
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_vehicle_slots'
             AND COLUMN_NAME='assigned_by');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_vehicle_slots`
     ADD COLUMN `assigned_by` INT DEFAULT NULL AFTER `owner_class`,
     ADD COLUMN `assigned_at` TIMESTAMP NULL DEFAULT NULL AFTER `assigned_by`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ---------- The garage a vehicle belongs to ----------
-- cm-vehicles.garage is a free-text column. cm-house writes "house:<id>" into
-- it, so a glance at cm_owned_vehicles tells you which property a car lives
-- at without joining anything.
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_owned_vehicles'
             AND COLUMN_NAME='garage');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_owned_vehicles` ADD COLUMN `garage` VARCHAR(64) NULL',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- An index, because "everything parked at house 12" is the single most common
-- query the garage screen makes.
SET @c := (SELECT COUNT(*) FROM information_schema.STATISTICS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_owned_vehicles'
             AND INDEX_NAME='idx_garage');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_owned_vehicles` ADD INDEX `idx_garage` (`garage`)',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ============================================================
--  Family car sharing.
--  The owner flags which of their cars the family may drive. Nothing else in
--  cm-vehicles knows about families, so the flag lives here.
-- ============================================================
CREATE TABLE IF NOT EXISTS `cm_house_shared_vehicles` (
  `vehicle_id` BIGINT NOT NULL PRIMARY KEY,
  `house_id`   INT NOT NULL,
  `shared_by`  INT NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_shared_house` (`house_id`),
  CONSTRAINT `fk_shared_house` FOREIGN KEY (`house_id`)
    REFERENCES `cm_houses`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
--  Reservation reconciliation.
--  A slot remains assigned while its vehicle is outside (`is_stored = 0`).
--  Clear only missing vehicles or conflicting HOUSE storage claims.
-- ============================================================
UPDATE `cm_house_vehicle_slots` s
LEFT JOIN `cm_owned_vehicles` v ON v.id = s.vehicle_id
SET s.vehicle_id = NULL
WHERE s.vehicle_id IS NOT NULL
  AND (
        v.id IS NULL
     OR (v.is_stored = 1
         AND v.garage LIKE 'house:%'
         AND v.garage <> CONCAT('house:', s.house_id))
  );

SELECT 'cm-house migration 006 (garage) complete' AS status;
