-- ============================================================
-- cm-house v1.6.0 | multi-exit garages and per-house customization
-- Safe to run repeatedly.
-- ============================================================

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

-- Convert the old single exit into the new list without changing old layouts.
UPDATE cm_house_garage_templates
SET vehicle_exits = JSON_ARRAY(vehicle_exit)
WHERE (vehicle_exits IS NULL OR JSON_LENGTH(vehicle_exits) = 0)
  AND vehicle_exit IS NOT NULL;

-- Existing garages become customizable immediately at their player-entry point.
-- Re-walk the template later to move this marker and add wall/light/decor anchors.
UPDATE cm_house_garage_templates
SET customization_point = player_entry
WHERE customization_point IS NULL
  AND player_entry IS NOT NULL;

UPDATE cm_house_garage_templates
SET customization_anchors = JSON_OBJECT(
    'walls', JSON_ARRAY(),
    'lights', JSON_ARRAY(),
    'props', JSON_ARRAY()
)
WHERE customization_anchors IS NULL;

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
  PRIMARY KEY (`house_id`),
  CONSTRAINT `fk_house_garage_customization_house` FOREIGN KEY (`house_id`)
    REFERENCES `cm_houses`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
