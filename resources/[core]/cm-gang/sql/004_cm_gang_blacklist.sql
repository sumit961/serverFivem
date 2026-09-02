-- cm-gang v0.3.0 | gang blacklist (additive, idempotent)

CREATE TABLE IF NOT EXISTS `cm_gang_blacklist` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `gang_id` VARCHAR(16) NOT NULL,
  `character_id` VARCHAR(64) NOT NULL,
  `character_name_snapshot` VARCHAR(96) NULL,
  `reason` VARCHAR(255) NULL,
  `blacklisted_by` VARCHAR(64) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` TIMESTAMP NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_gang_blacklist_member` (`gang_id`, `character_id`),
  KEY `idx_gang_blacklist_gang` (`gang_id`),
  CONSTRAINT `fk_gang_blacklist_gang` FOREIGN KEY (`gang_id`) REFERENCES `cm_gangs` (`gang_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO `cm_gang_migrations` (`migration_id`) VALUES ('004_cm_gang_blacklist');
