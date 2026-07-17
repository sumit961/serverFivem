-- cm-vehicles v3.3.9 | Phase 1 security/economy
-- The resource also applies this migration automatically at startup.

SET @has_col := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_owned_vehicles'
    AND COLUMN_NAME = 'sale_pending_token'
);
SET @sql := IF(@has_col = 0,
  'ALTER TABLE `cm_owned_vehicles` ADD COLUMN `sale_pending_token` VARCHAR(96) NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_col := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_owned_vehicles'
    AND COLUMN_NAME = 'sale_pending_at'
);
SET @sql := IF(@has_col = 0,
  'ALTER TABLE `cm_owned_vehicles` ADD COLUMN `sale_pending_at` TIMESTAMP NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

CREATE TABLE IF NOT EXISTS `cm_vehicle_pending_payouts` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `sale_token` VARCHAR(96) NOT NULL,
  `vehicle_id` BIGINT NOT NULL,
  `character_id` VARCHAR(100) NOT NULL,
  `plate` VARCHAR(16) NOT NULL,
  `amount` INT NOT NULL,
  `account` VARCHAR(32) NOT NULL DEFAULT 'cash',
  `reason` VARCHAR(64) NOT NULL,
  `status` VARCHAR(24) NOT NULL DEFAULT 'pending',
  `attempts` INT NOT NULL DEFAULT 0,
  `last_error` VARCHAR(255) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `paid_at` TIMESTAMP NULL,
  UNIQUE KEY `uq_vehicle_sale_token` (`sale_token`),
  INDEX `idx_vehicle_payout_character` (`character_id`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
