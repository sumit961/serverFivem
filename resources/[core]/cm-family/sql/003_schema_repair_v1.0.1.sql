-- ============================================================
-- cm-family v1.0.1 manual schema repair
-- Safe to run repeatedly. Use this only when Config.Database.autoInstall cannot
-- run because the FiveM database account has no CREATE/ALTER permission.
-- ============================================================

CREATE TABLE IF NOT EXISTS `cm_families` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(64) NOT NULL,
  `tag` VARCHAR(8) NULL,
  `color` VARCHAR(9) NOT NULL DEFAULT '#00f0ff',
  `founder_cid` VARCHAR(64) NOT NULL,
  `house_id` INT UNSIGNED NULL,
  `bank_balance` BIGINT NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_family_name` (`name`),
  KEY `idx_family_founder` (`founder_cid`),
  KEY `idx_family_house` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_ranks` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id` INT UNSIGNED NOT NULL,
  `tier` TINYINT UNSIGNED NOT NULL,
  `name` VARCHAR(48) NOT NULL,
  `permissions` JSON NOT NULL,
  `is_founder` TINYINT(1) NOT NULL DEFAULT 0,
  `bank_daily_limit` BIGINT NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_family_tier` (`family_id`, `tier`),
  KEY `idx_rank_family` (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_members` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id` INT UNSIGNED NOT NULL,
  `character_id` VARCHAR(64) NOT NULL,
  `rank_id` INT UNSIGNED NOT NULL,
  `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_member_character` (`character_id`),
  KEY `idx_member_family` (`family_id`),
  KEY `idx_member_rank` (`rank_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_invites` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id` INT UNSIGNED NOT NULL,
  `character_id` VARCHAR(64) NOT NULL,
  `invited_by` VARCHAR(64) NOT NULL,
  `rank_id` INT UNSIGNED NULL,
  `expires_at` TIMESTAMP NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_invite` (`family_id`, `character_id`),
  KEY `idx_invite_character` (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_vehicle_access` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id` INT UNSIGNED NOT NULL,
  `vehicle_id` INT UNSIGNED NOT NULL,
  `level` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `updated_by` VARCHAR(64) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_family_vehicle` (`family_id`, `vehicle_id`),
  KEY `idx_vaccess_family` (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_bank_log` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id` INT UNSIGNED NOT NULL,
  `character_id` VARCHAR(64) NULL,
  `direction` ENUM('deposit','withdraw') NOT NULL,
  `amount` BIGINT NOT NULL,
  `balance_after` BIGINT NOT NULL,
  `reason` VARCHAR(128) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_banklog_family` (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_log` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id` INT UNSIGNED NOT NULL,
  `actor_cid` VARCHAR(64) NULL,
  `action` VARCHAR(48) NOT NULL,
  `detail` JSON NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_log_family` (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP PROCEDURE IF EXISTS cm_family_add_col;
DELIMITER $$
CREATE PROCEDURE cm_family_add_col(IN tbl VARCHAR(64), IN col VARCHAR(64), IN ddl VARCHAR(255))
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = tbl AND COLUMN_NAME = col
    ) THEN
        SET @s = CONCAT('ALTER TABLE `', tbl, '` ADD COLUMN ', ddl);
        PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    END IF;
END $$
DELIMITER ;

CALL cm_family_add_col('cm_families', 'tag',          "`tag` VARCHAR(8) NULL AFTER `name`");
CALL cm_family_add_col('cm_families', 'color',        "`color` VARCHAR(9) NOT NULL DEFAULT '#00f0ff' AFTER `tag`");
CALL cm_family_add_col('cm_families', 'founder_cid',  "`founder_cid` VARCHAR(64) NOT NULL DEFAULT '' AFTER `color`");
CALL cm_family_add_col('cm_families', 'house_id',     "`house_id` INT UNSIGNED NULL AFTER `founder_cid`");
CALL cm_family_add_col('cm_families', 'bank_balance', "`bank_balance` BIGINT NOT NULL DEFAULT 0 AFTER `house_id`");
CALL cm_family_add_col('cm_families', 'created_at',   "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP");
DROP PROCEDURE IF EXISTS cm_family_add_col;
