-- ============================================================
-- cm-house v1.7.5 | exactly-once weapon restore + durable house-sale payouts
-- Safe to run repeatedly. The resource also performs these additive repairs
-- automatically at startup when Config.AutoRepairSchema is enabled.
-- ============================================================

CREATE TABLE IF NOT EXISTS `cm_house_weapon_recovery` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `house_id` INT UNSIGNED NULL,
  `point_index` INT NULL,
  `character_id` VARCHAR(64) NULL,
  `src_player` INT NULL,
  `item_name` VARCHAR(128) NOT NULL,
  `amount` INT NOT NULL DEFAULT 1,
  `metadata` LONGTEXT NULL,
  `reason` VARCHAR(255) NULL,
  `resolved` TINYINT(1) NOT NULL DEFAULT 0,
  `status` VARCHAR(24) NOT NULL DEFAULT 'pending',
  `processing_token` VARCHAR(128) NULL,
  `processing_by` INT NULL,
  `processing_started_at` DATETIME NULL,
  `restored_to_cid` VARCHAR(64) NULL,
  `restored_to_src` INT NULL,
  `last_error` VARCHAR(255) NULL,
  `resolved_at` DATETIME NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_recovery_char` (`character_id`),
  KEY `idx_recovery_open` (`resolved`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_weapon_recovery'
             AND COLUMN_NAME='status');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_weapon_recovery` ADD COLUMN `status` VARCHAR(24) NOT NULL DEFAULT ''pending'' AFTER `resolved`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_weapon_recovery'
             AND COLUMN_NAME='processing_token');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_weapon_recovery` ADD COLUMN `processing_token` VARCHAR(128) NULL AFTER `status`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_weapon_recovery'
             AND COLUMN_NAME='processing_by');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_weapon_recovery` ADD COLUMN `processing_by` INT NULL AFTER `processing_token`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_weapon_recovery'
             AND COLUMN_NAME='processing_started_at');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_weapon_recovery` ADD COLUMN `processing_started_at` DATETIME NULL AFTER `processing_by`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_weapon_recovery'
             AND COLUMN_NAME='restored_to_cid');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_weapon_recovery` ADD COLUMN `restored_to_cid` VARCHAR(64) NULL AFTER `processing_started_at`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_weapon_recovery'
             AND COLUMN_NAME='restored_to_src');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_weapon_recovery` ADD COLUMN `restored_to_src` INT NULL AFTER `restored_to_cid`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_weapon_recovery'
             AND COLUMN_NAME='last_error');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_weapon_recovery` ADD COLUMN `last_error` VARCHAR(255) NULL AFTER `restored_to_src`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_weapon_recovery'
             AND COLUMN_NAME='resolved_at');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_weapon_recovery` ADD COLUMN `resolved_at` DATETIME NULL AFTER `last_error`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

UPDATE `cm_house_weapon_recovery`
SET `status` = CASE WHEN `resolved` = 1 THEN 'resolved' ELSE 'pending' END,
    `resolved_at` = CASE
      WHEN `resolved` = 1 THEN COALESCE(`resolved_at`, `created_at`)
      ELSE `resolved_at`
    END
WHERE `status` IS NULL OR `status` = '' OR (`resolved` = 1 AND `status` <> 'resolved');

CREATE TABLE IF NOT EXISTS `cm_house_sale_journal` (
  `id`                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `token`                 VARCHAR(128) NOT NULL,
  `house_id`              INT NOT NULL,
  `seller_cid`            INT NOT NULL,
  `seller_source`         INT NULL,
  `payout`                INT NOT NULL,
  `account`               VARCHAR(32) NOT NULL DEFAULT 'bank',
  `old_family_id`         INT NULL,
  `status`                VARCHAR(24) NOT NULL DEFAULT 'prepared',
  `last_error`            VARCHAR(255) NULL,
  `ownership_released_at` DATETIME NULL,
  `payment_started_at`    DATETIME NULL,
  `paid_at`               DATETIME NULL,
  `created_at`            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_house_sale_token` (`token`),
  KEY `idx_house_sale_house` (`house_id`, `status`),
  KEY `idx_house_sale_seller` (`seller_cid`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
