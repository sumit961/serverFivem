-- Multiple routes per license type: the exam picks one at random, so players
-- cannot memorise a single circuit. Portable across MySQL 8 and MariaDB.

-- A type may now own many routes.
SET @idx := (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_license_routes'
      AND INDEX_NAME = 'unique_route_per_type');
SET @sql := IF(@idx > 0, 'ALTER TABLE cm_license_routes DROP INDEX unique_route_per_type', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_license_routes'
      AND COLUMN_NAME = 'label');
SET @sql := IF(@col = 0, 'ALTER TABLE cm_license_routes ADD COLUMN label VARCHAR(100) NULL AFTER license_type_id', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_license_routes'
      AND COLUMN_NAME = 'enabled');
SET @sql := IF(@col = 0, 'ALTER TABLE cm_license_routes ADD COLUMN enabled BOOLEAN NOT NULL DEFAULT true AFTER vehicle_spawn', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- The exam session records which route was drawn.
SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_license_active_tests'
      AND COLUMN_NAME = 'route_id');
SET @sql := IF(@col = 0, 'ALTER TABLE cm_license_active_tests ADD COLUMN route_id INT NULL AFTER license_type_id', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

UPDATE cm_license_routes SET label = CONCAT('Route ', id) WHERE label IS NULL;
