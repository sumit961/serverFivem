-- ============================================================
-- cm-house v1.5.0 | weapon storage and template safety
-- Safe to run repeatedly.
-- ============================================================

SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_interior_templates'
             AND COLUMN_NAME='weapon_storages');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_house_interior_templates` ADD COLUMN `weapon_storages` JSON NULL AFTER `wardrobes`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- Existing wardrobe capture points become weapon-locker points.
UPDATE cm_house_interior_templates
SET weapon_storages = wardrobes
WHERE (weapon_storages IS NULL OR JSON_LENGTH(weapon_storages) = 0)
  AND wardrobes IS NOT NULL;

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
  INDEX `idx_house_weapon_transfer_character` (`character_id`, `created_at`),
  CONSTRAINT `fk_house_weapon_transfer_house` FOREIGN KEY (`house_id`)
    REFERENCES `cm_houses`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
