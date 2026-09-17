-- Durable physical-license delivery state.
-- Portable across MySQL 8 and MariaDB.

SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_character_licenses'
      AND COLUMN_NAME = 'delivery_status');
SET @sql := IF(@col = 0, "ALTER TABLE cm_character_licenses ADD COLUMN delivery_status ENUM('pending','delivered') NOT NULL DEFAULT 'pending' AFTER status", 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_character_licenses'
      AND COLUMN_NAME = 'delivered_at');
SET @sql := IF(@col = 0, 'ALTER TABLE cm_character_licenses ADD COLUMN delivered_at BIGINT NULL AFTER delivery_status', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
