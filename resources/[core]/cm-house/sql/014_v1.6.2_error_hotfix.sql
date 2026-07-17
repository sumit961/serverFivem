-- ============================================================
-- cm-house v1.6.2 | admin JSON + missing schema error hotfix
-- Safe to run repeatedly. The resource also performs these additive repairs
-- automatically at startup; this file is provided for manual DB maintenance.
-- ============================================================

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_interior_templates'
             AND COLUMN_NAME='weapon_storages');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_interior_templates` ADD COLUMN `weapon_storages` JSON NULL AFTER `wardrobes`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

UPDATE `cm_house_interior_templates`
SET `weapon_storages` = `wardrobes`
WHERE (`weapon_storages` IS NULL OR JSON_LENGTH(`weapon_storages`) = 0)
  AND `wardrobes` IS NOT NULL;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_garage_templates'
             AND COLUMN_NAME='vehicle_exits');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_garage_templates` ADD COLUMN `vehicle_exits` JSON NULL AFTER `vehicle_exit`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_garage_templates'
             AND COLUMN_NAME='customization_point');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_garage_templates` ADD COLUMN `customization_point` JSON NULL AFTER `vehicle_exits`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_garage_templates'
             AND COLUMN_NAME='customization_anchors');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_garage_templates` ADD COLUMN `customization_anchors` JSON NULL AFTER `customization_point`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

UPDATE `cm_house_garage_templates`
SET `vehicle_exits` = JSON_ARRAY(`vehicle_exit`)
WHERE (`vehicle_exits` IS NULL OR JSON_LENGTH(`vehicle_exits`) = 0)
  AND `vehicle_exit` IS NOT NULL;

UPDATE `cm_house_garage_templates`
SET `customization_point` = `player_entry`
WHERE `customization_point` IS NULL AND `player_entry` IS NOT NULL;

UPDATE `cm_house_garage_templates`
SET `customization_anchors` = JSON_OBJECT(
  'walls', JSON_ARRAY(), 'lights', JSON_ARRAY(), 'props', JSON_ARRAY()
)
WHERE `customization_anchors` IS NULL;

CREATE TABLE IF NOT EXISTS `cm_house_weapon_transfers` (
  `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
  `house_id` INT NOT NULL,
  `storage_index` INT NOT NULL,
  `character_id` VARCHAR(64) NOT NULL,
  `direction` VARCHAR(16) NOT NULL,
  `item_name` VARCHAR(100) NOT NULL,
  `quantity` INT NOT NULL DEFAULT 1,
  `status` VARCHAR(24) NOT NULL DEFAULT 'completed',
  `details` JSON NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_house_weapon_transfer_house` (`house_id`, `created_at`),
  INDEX `idx_house_weapon_transfer_character` (`character_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_house_garage_customizations` (
  `house_id` INT NOT NULL,
  `theme_key` VARCHAR(40) NOT NULL DEFAULT 'ice_clean',
  `floor_key` VARCHAR(40) NOT NULL DEFAULT 'ice_pad',
  `wall_key` VARCHAR(40) NOT NULL DEFAULT 'cyan_wash',
  `light_key` VARCHAR(40) NOT NULL DEFAULT 'bright_white',
  `decor_key` VARCHAR(40) NOT NULL DEFAULT 'clean',
  `accent_key` VARCHAR(40) NOT NULL DEFAULT 'cyan',
  `settings` JSON NULL,
  `updated_by` VARCHAR(64) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
