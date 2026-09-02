-- cm-gang v0.3.0 | gang wardrobe outfits (additive, idempotent)

CREATE TABLE IF NOT EXISTS `cm_gang_wardrobe_outfits` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `gang_id` VARCHAR(16) NOT NULL,
  `name` VARCHAR(64) NOT NULL,
  `sex` ENUM('male','female') NOT NULL DEFAULT 'male',
  `components` JSON NOT NULL,
  `minimum_tier` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `created_by` VARCHAR(64) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_gang_wardrobe_outfit` (`gang_id`, `sex`, `name`),
  KEY `idx_gang_wardrobe_gang` (`gang_id`),
  CONSTRAINT `fk_gang_wardrobe_gang` FOREIGN KEY (`gang_id`) REFERENCES `cm_gangs` (`gang_id`),
  CONSTRAINT `chk_gang_wardrobe_tier` CHECK (`minimum_tier` BETWEEN 1 AND 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO `cm_gang_migrations` (`migration_id`) VALUES ('007_cm_gang_wardrobe');
