CREATE TABLE IF NOT EXISTS `cm_ems_organization` (
  `id` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `name` VARCHAR(64) NOT NULL DEFAULT 'Emergency Medical Services',
  `leader_cid` VARCHAR(64) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  CONSTRAINT `chk_cm_ems_singleton` CHECK (`id` = 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_ems_ranks` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(48) NOT NULL,
  `tier` SMALLINT UNSIGNED NOT NULL,
  `is_leader` TINYINT(1) NOT NULL DEFAULT 0,
  `permissions` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_cm_ems_rank_tier` (`tier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_ems_members` (
  `character_id` VARCHAR(64) NOT NULL,
  `rank_id` BIGINT UNSIGNED NOT NULL,
  `on_duty` TINYINT(1) NOT NULL DEFAULT 0,
  `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`character_id`),
  KEY `idx_cm_ems_member_rank` (`rank_id`),
  CONSTRAINT `fk_cm_ems_member_rank` FOREIGN KEY (`rank_id`) REFERENCES `cm_ems_ranks` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_ems_invites` (
  `character_id` VARCHAR(64) NOT NULL,
  `invited_by` VARCHAR(64) NOT NULL,
  `expires_at` TIMESTAMP NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`character_id`),
  KEY `idx_cm_ems_invite_expiry` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Superseded by cm_ems_outfit_presets below; left in place for old installs.
CREATE TABLE IF NOT EXISTS `cm_ems_outfits` (
  `sex` ENUM('male','female') NOT NULL,
  `outfit` LONGTEXT NOT NULL,
  `updated_by` VARCHAR(64) NOT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`sex`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_ems_outfit_presets` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `sex` ENUM('male','female') NOT NULL,
  `name` VARCHAR(32) NOT NULL,
  `outfit` LONGTEXT NOT NULL,
  `created_by` VARCHAR(64) NULL,
  `updated_by` VARCHAR(64) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_cm_ems_outfit_preset` (`sex`, `name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_ems_member_outfit` (
  `character_id` VARCHAR(64) NOT NULL,
  `preset_id` BIGINT UNSIGNED NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`character_id`),
  CONSTRAINT `fk_cm_ems_member_outfit_preset` FOREIGN KEY (`preset_id`) REFERENCES `cm_ems_outfit_presets` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_ems_activity` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `actor_cid` VARCHAR(64) NULL,
  `action` VARCHAR(64) NOT NULL,
  `detail` LONGTEXT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_cm_ems_activity_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `cm_ems_organization` (`id`, `name`) VALUES (1, 'Emergency Medical Services')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);
