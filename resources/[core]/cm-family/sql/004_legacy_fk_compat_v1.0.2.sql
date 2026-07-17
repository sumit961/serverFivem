-- ============================================================
-- cm-family v1.0.2 | legacy foreign-key compatibility repair
--
-- Fixes errno 150 when an older cm_families.id definition or table engine does
-- not exactly match a new child table's family_id foreign key.
--
-- Safe to run repeatedly. It does not delete family data and does not require
-- dropping or converting the existing cm_families table.
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

-- Child tables intentionally use indexed IDs without hard FK constraints.
-- cm-family performs child-first deletion in one application transaction.
CREATE TABLE IF NOT EXISTS `cm_family_ranks` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id` BIGINT UNSIGNED NOT NULL,
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
  `family_id` BIGINT UNSIGNED NOT NULL,
  `character_id` VARCHAR(64) NOT NULL,
  `rank_id` BIGINT UNSIGNED NOT NULL,
  `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_member_character` (`character_id`),
  KEY `idx_member_family` (`family_id`),
  KEY `idx_member_rank` (`rank_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_invites` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id` BIGINT UNSIGNED NOT NULL,
  `character_id` VARCHAR(64) NOT NULL,
  `invited_by` VARCHAR(64) NOT NULL,
  `rank_id` BIGINT UNSIGNED NULL,
  `expires_at` TIMESTAMP NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_invite` (`family_id`, `character_id`),
  KEY `idx_invite_character` (`character_id`),
  KEY `idx_invite_family` (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_vehicle_access` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id` BIGINT UNSIGNED NOT NULL,
  `vehicle_id` BIGINT UNSIGNED NOT NULL,
  `level` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `updated_by` VARCHAR(64) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_family_vehicle` (`family_id`, `vehicle_id`),
  KEY `idx_vaccess_family` (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_bank_log` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id` BIGINT UNSIGNED NOT NULL,
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
  `family_id` BIGINT UNSIGNED NOT NULL,
  `actor_cid` VARCHAR(64) NULL,
  `action` VARCHAR(48) NOT NULL,
  `detail` JSON NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_log_family` (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP PROCEDURE IF EXISTS cm_family_add_col;
DELIMITER $$
CREATE PROCEDURE cm_family_add_col(IN tbl VARCHAR(64), IN col VARCHAR(64), IN ddl VARCHAR(512))
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

CALL cm_family_add_col('cm_family_ranks', 'family_id',        "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `id`");
CALL cm_family_add_col('cm_family_ranks', 'tier',             "`tier` TINYINT UNSIGNED NOT NULL DEFAULT 1 AFTER `family_id`");
CALL cm_family_add_col('cm_family_ranks', 'name',             "`name` VARCHAR(48) NOT NULL DEFAULT 'Rank' AFTER `tier`");
CALL cm_family_add_col('cm_family_ranks', 'permissions',      "`permissions` JSON NULL AFTER `name`");
CALL cm_family_add_col('cm_family_ranks', 'is_founder',       "`is_founder` TINYINT(1) NOT NULL DEFAULT 0 AFTER `permissions`");
CALL cm_family_add_col('cm_family_ranks', 'bank_daily_limit', "`bank_daily_limit` BIGINT NOT NULL DEFAULT 0 AFTER `is_founder`");
CALL cm_family_add_col('cm_family_ranks', 'created_at',       "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP");

CALL cm_family_add_col('cm_family_members', 'family_id',    "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `id`");
CALL cm_family_add_col('cm_family_members', 'character_id', "`character_id` VARCHAR(64) NOT NULL DEFAULT '' AFTER `family_id`");
CALL cm_family_add_col('cm_family_members', 'rank_id',      "`rank_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `character_id`");
CALL cm_family_add_col('cm_family_members', 'joined_at',    "`joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP");

CALL cm_family_add_col('cm_family_invites', 'family_id',    "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `id`");
CALL cm_family_add_col('cm_family_invites', 'character_id', "`character_id` VARCHAR(64) NOT NULL DEFAULT '' AFTER `family_id`");
CALL cm_family_add_col('cm_family_invites', 'invited_by',   "`invited_by` VARCHAR(64) NOT NULL DEFAULT '' AFTER `character_id`");
CALL cm_family_add_col('cm_family_invites', 'rank_id',      "`rank_id` BIGINT UNSIGNED NULL AFTER `invited_by`");
CALL cm_family_add_col('cm_family_invites', 'expires_at',   "`expires_at` TIMESTAMP NULL AFTER `rank_id`");
CALL cm_family_add_col('cm_family_invites', 'created_at',   "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP");

DROP PROCEDURE IF EXISTS cm_family_add_col;

-- Remaining additive repairs for partial legacy child tables.
DROP PROCEDURE IF EXISTS cm_family_add_col;
DELIMITER $$
CREATE PROCEDURE cm_family_add_col(IN tbl VARCHAR(64), IN col VARCHAR(64), IN ddl VARCHAR(512))
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

CALL cm_family_add_col('cm_family_vehicle_access', 'family_id',  "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `id`");
CALL cm_family_add_col('cm_family_vehicle_access', 'vehicle_id', "`vehicle_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `family_id`");
CALL cm_family_add_col('cm_family_vehicle_access', 'level',      "`level` TINYINT UNSIGNED NOT NULL DEFAULT 1 AFTER `vehicle_id`");
CALL cm_family_add_col('cm_family_vehicle_access', 'updated_by', "`updated_by` VARCHAR(64) NULL AFTER `level`");
CALL cm_family_add_col('cm_family_vehicle_access', 'updated_at', "`updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP");

CALL cm_family_add_col('cm_family_bank_log', 'family_id',     "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `id`");
CALL cm_family_add_col('cm_family_bank_log', 'character_id',  "`character_id` VARCHAR(64) NULL AFTER `family_id`");
CALL cm_family_add_col('cm_family_bank_log', 'direction',     "`direction` ENUM('deposit','withdraw') NOT NULL DEFAULT 'deposit' AFTER `character_id`");
CALL cm_family_add_col('cm_family_bank_log', 'amount',        "`amount` BIGINT NOT NULL DEFAULT 0 AFTER `direction`");
CALL cm_family_add_col('cm_family_bank_log', 'balance_after', "`balance_after` BIGINT NOT NULL DEFAULT 0 AFTER `amount`");
CALL cm_family_add_col('cm_family_bank_log', 'reason',        "`reason` VARCHAR(128) NULL AFTER `balance_after`");
CALL cm_family_add_col('cm_family_bank_log', 'created_at',    "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP");

CALL cm_family_add_col('cm_family_log', 'family_id',  "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `id`");
CALL cm_family_add_col('cm_family_log', 'actor_cid',  "`actor_cid` VARCHAR(64) NULL AFTER `family_id`");
CALL cm_family_add_col('cm_family_log', 'action',     "`action` VARCHAR(48) NOT NULL DEFAULT 'legacy' AFTER `actor_cid`");
CALL cm_family_add_col('cm_family_log', 'detail',     "`detail` JSON NULL AFTER `action`");
CALL cm_family_add_col('cm_family_log', 'created_at', "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP");

DROP PROCEDURE IF EXISTS cm_family_add_col;

DROP PROCEDURE IF EXISTS cm_family_add_index;
DELIMITER $$
CREATE PROCEDURE cm_family_add_index(IN tbl VARCHAR(64), IN idx VARCHAR(64), IN ddl VARCHAR(512))
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = tbl AND INDEX_NAME = idx
  ) THEN
    SET @s = CONCAT('ALTER TABLE `', tbl, '` ADD ', ddl);
    PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;
  END IF;
END $$
DELIMITER ;

CALL cm_family_add_index('cm_families', 'uniq_family_name',       'UNIQUE KEY `uniq_family_name` (`name`)');
CALL cm_family_add_index('cm_families', 'idx_family_founder',     'KEY `idx_family_founder` (`founder_cid`)');
CALL cm_family_add_index('cm_families', 'idx_family_house',       'KEY `idx_family_house` (`house_id`)');
CALL cm_family_add_index('cm_family_ranks', 'uniq_family_tier',   'UNIQUE KEY `uniq_family_tier` (`family_id`, `tier`)');
CALL cm_family_add_index('cm_family_ranks', 'idx_rank_family',    'KEY `idx_rank_family` (`family_id`)');
CALL cm_family_add_index('cm_family_members', 'uniq_member_character', 'UNIQUE KEY `uniq_member_character` (`character_id`)');
CALL cm_family_add_index('cm_family_members', 'idx_member_family','KEY `idx_member_family` (`family_id`)');
CALL cm_family_add_index('cm_family_members', 'idx_member_rank',  'KEY `idx_member_rank` (`rank_id`)');
CALL cm_family_add_index('cm_family_invites', 'uniq_invite',      'UNIQUE KEY `uniq_invite` (`family_id`, `character_id`)');
CALL cm_family_add_index('cm_family_invites', 'idx_invite_character', 'KEY `idx_invite_character` (`character_id`)');
CALL cm_family_add_index('cm_family_invites', 'idx_invite_family','KEY `idx_invite_family` (`family_id`)');
CALL cm_family_add_index('cm_family_vehicle_access', 'uniq_family_vehicle', 'UNIQUE KEY `uniq_family_vehicle` (`family_id`, `vehicle_id`)');
CALL cm_family_add_index('cm_family_vehicle_access', 'idx_vaccess_family', 'KEY `idx_vaccess_family` (`family_id`)');
CALL cm_family_add_index('cm_family_bank_log', 'idx_banklog_family', 'KEY `idx_banklog_family` (`family_id`)');
CALL cm_family_add_index('cm_family_log', 'idx_log_family',       'KEY `idx_log_family` (`family_id`)');

DROP PROCEDURE IF EXISTS cm_family_add_index;
