-- CM House v1.4.0 / Phase 2 reliability
-- Run after 010_security_economy_v1.3.3.sql.

SET @has_col := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_house_vehicle_slots'
    AND COLUMN_NAME = 'updated_at'
);
SET @sql := IF(@has_col = 0,
  'ALTER TABLE `cm_house_vehicle_slots` ADD COLUMN `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Remove assignments to vehicles that no longer exist.
UPDATE `cm_house_vehicle_slots` s
LEFT JOIN `cm_owned_vehicles` v ON v.id = s.vehicle_id
SET s.vehicle_id = NULL,
    s.owner_class = 'personal',
    s.assigned_by = NULL,
    s.assigned_at = NULL
WHERE s.vehicle_id IS NOT NULL AND v.id IS NULL;

-- Migration 009 and runtime reconciliation enforce:
--   uq_house_slot (house_id, slot_index)
--   uq_vehicle_once (vehicle_id)
