-- CM Vehicles v3.4.0 / Phase 2 persistence and reliability
-- Run after phase1_security_economy_v3.3.9.sql.
-- Idempotent on MySQL/MariaDB versions supported by oxmysql.

SET @has_col := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_owned_vehicles'
    AND COLUMN_NAME = 'location_state'
);
SET @sql := IF(@has_col = 0,
  'ALTER TABLE `cm_owned_vehicles` ADD COLUMN `location_state` VARCHAR(32) NULL AFTER `garage`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_col := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_owned_vehicles'
    AND COLUMN_NAME = 'location_ref'
);
SET @sql := IF(@has_col = 0,
  'ALTER TABLE `cm_owned_vehicles` ADD COLUMN `location_ref` VARCHAR(96) NULL AFTER `location_state`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_col := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_owned_vehicles'
    AND COLUMN_NAME = 'location_slot'
);
SET @sql := IF(@has_col = 0,
  'ALTER TABLE `cm_owned_vehicles` ADD COLUMN `location_slot` INT NULL AFTER `location_ref`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_col := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_owned_vehicles'
    AND COLUMN_NAME = 'location_updated_at'
);
SET @sql := IF(@has_col = 0,
  'ALTER TABLE `cm_owned_vehicles` ADD COLUMN `location_updated_at` TIMESTAMP NULL AFTER `location_slot`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_index := (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_owned_vehicles'
    AND INDEX_NAME = 'idx_cm_vehicle_location_state'
);
SET @sql := IF(@has_index = 0,
  'ALTER TABLE `cm_owned_vehicles` ADD INDEX `idx_cm_vehicle_location_state` (`location_state`, `location_ref`)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS `cm_vehicle_location_history` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `vehicle_id` BIGINT NOT NULL,
    `state` VARCHAR(32) NOT NULL,
    `location_ref` VARCHAR(96) NULL,
    `location_slot` INT NULL,
    `reason` VARCHAR(64) NOT NULL,
    `actor_character_id` VARCHAR(100) NULL,
    `data` LONGTEXT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_cm_vehicle_location_vehicle` (`vehicle_id`, `created_at`),
    INDEX `idx_cm_vehicle_location_history_state` (`state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_vehicle_operations` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `token` VARCHAR(128) NOT NULL,
    `vehicle_id` BIGINT NOT NULL,
    `resource_name` VARCHAR(64) NOT NULL,
    `operation_type` VARCHAR(64) NOT NULL,
    `actor_character_id` VARCHAR(100) NULL,
    `source_state` VARCHAR(32) NULL,
    `source_ref` VARCHAR(96) NULL,
    `source_slot` INT NULL,
    `target_state` VARCHAR(32) NULL,
    `target_ref` VARCHAR(96) NULL,
    `target_slot` INT NULL,
    `stage` VARCHAR(64) NOT NULL DEFAULT 'started',
    `status` VARCHAR(32) NOT NULL DEFAULT 'active',
    `details` LONGTEXT NULL,
    `started_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `expires_at` TIMESTAMP NULL,
    `completed_at` TIMESTAMP NULL,
    UNIQUE KEY `uq_cm_vehicle_operation_token` (`token`),
    INDEX `idx_cm_vehicle_operation_vehicle` (`vehicle_id`, `status`),
    INDEX `idx_cm_vehicle_operation_status` (`status`, `expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

UPDATE `cm_owned_vehicles`
SET `location_state` = CASE
        WHEN `is_stored` = 0 THEN 'OUTSIDE'
        WHEN `garage` REGEXP '^house:[0-9]+$' THEN 'HOUSE_GARAGE'
        WHEN `garage` LIKE 'impound%' THEN 'IMPOUND'
        WHEN `garage` LIKE 'police%' OR `garage` LIKE 'seized%' THEN 'POLICE_SEIZED'
        WHEN `garage` LIKE 'job:%' THEN 'JOB_GARAGE'
        WHEN `is_stored` = 1 THEN 'PUBLIC_GARAGE'
        ELSE 'OUTSIDE'
    END,
    `location_ref` = CASE
        WHEN `garage` REGEXP '^house:[0-9]+$' THEN SUBSTRING_INDEX(`garage`, ':', -1)
        WHEN `garage` IS NOT NULL AND `garage` <> '' THEN `garage`
        ELSE NULL
    END,
    `location_slot` = CASE
        WHEN `parking_id` REGEXP '^[0-9]+$' THEN CAST(`parking_id` AS UNSIGNED)
        ELSE NULL
    END,
    `location_updated_at` = NOW()
WHERE `location_state` IS NULL OR `location_state` = '';

UPDATE `cm_vehicle_operations`
SET `status` = 'recovery_required', `stage` = 'migration_found_active_operation'
WHERE `status` = 'active';
