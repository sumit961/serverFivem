-- 002_clothing_outfits.sql
-- Persistent outfit presets / wardrobe system for nv_cloth

CREATE TABLE IF NOT EXISTS `cm_clothing_outfits` (
  `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `character_id` VARCHAR(64) NOT NULL,
  `outfit_name` VARCHAR(64) NOT NULL,
  `gender` VARCHAR(16) NOT NULL DEFAULT 'male',
  `components_json` LONGTEXT NOT NULL,
  `props_json` LONGTEXT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uniq_char_outfit` (`character_id`, `outfit_name`),
  INDEX `idx_char_id` (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

