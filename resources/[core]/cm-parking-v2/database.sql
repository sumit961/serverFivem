CREATE TABLE IF NOT EXISTS `cm_parking_spaces` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `character_id` VARCHAR(100) NOT NULL,
  `parking_id` VARCHAR(64) NOT NULL,
  `spot_index` INT NOT NULL,
  `vehicle_id` BIGINT NULL,
  `price_paid` INT NOT NULL DEFAULT 0,
  `expires_at` DATETIME NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_parking_spot` (`parking_id`, `spot_index`),
  UNIQUE KEY `uq_parking_vehicle` (`vehicle_id`),
  UNIQUE KEY `uq_character` (`character_id`),
  KEY `idx_character` (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_parking_lots` (
  `parking_id` VARCHAR(64) PRIMARY KEY,
  `owner_character_id` VARCHAR(100) NULL,
  `owner_name` VARCHAR(120) NULL,
  `price_tier` VARCHAR(20) NOT NULL DEFAULT 'normal',
  `price_per_spot` INT NOT NULL DEFAULT 2500,
  `business_balance` INT NOT NULL DEFAULT 0,
  `daily_income` INT NOT NULL DEFAULT 0,
  `weekly_income` INT NOT NULL DEFAULT 0,
  `purchased_at` DATETIME NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_owner` (`owner_character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
