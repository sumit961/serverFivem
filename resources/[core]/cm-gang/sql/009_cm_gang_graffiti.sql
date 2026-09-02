-- cm-gang | fixed graffiti ownership and persistent hourly turf payouts
CREATE TABLE IF NOT EXISTS `cm_gang_graffiti` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(96) NOT NULL,
  `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL,
  `heading` FLOAT NOT NULL DEFAULT 0, `width` FLOAT NOT NULL DEFAULT 2.0, `height` FLOAT NOT NULL DEFAULT 1.2,
  `routing_bucket` INT NOT NULL DEFAULT 0,
  `gang_id` VARCHAR(32) NULL, `texture_key` VARCHAR(64) NULL,
  `enabled` TINYINT(1) NOT NULL DEFAULT 1,
  `updated_by_character_id` BIGINT UNSIGNED NULL,
  `updated_at` TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `idx_cm_graffiti_gang` (`gang_id`), KEY `idx_cm_graffiti_enabled` (`enabled`),
  KEY `idx_cm_graffiti_bucket` (`routing_bucket`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_gang_turf_snapshots` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `snapshot_key` VARCHAR(16) NOT NULL,
  `gang_id` VARCHAR(32) NOT NULL, `tag_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `eligible_member_count` INT UNSIGNED NOT NULL DEFAULT 0, `revenue` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), UNIQUE KEY `uniq_cm_turf_snapshot_gang` (`snapshot_key`,`gang_id`), KEY `idx_cm_turf_snapshot_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_gang_turf_claims` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `snapshot_key` VARCHAR(16) NOT NULL,
  `gang_id` VARCHAR(32) NOT NULL, `character_id` BIGINT UNSIGNED NOT NULL, `amount` BIGINT UNSIGNED NOT NULL,
  `claimed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), UNIQUE KEY `uniq_cm_turf_claim` (`snapshot_key`,`gang_id`,`character_id`),
  KEY `idx_cm_turf_claim_character` (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO `cm_gang_migrations` (`migration_id`) VALUES ('009_cm_gang_graffiti');
