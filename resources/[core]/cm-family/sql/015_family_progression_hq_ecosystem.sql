-- ============================================================
-- cm-family | migration 015 | v1.8.0
-- Persistent Family Progression, Member Contributions, Objectives,
-- HQ Upgrades, Reward History, and Bank Categories.
-- Non-destructive & safe for repeated execution.
-- ============================================================

CREATE TABLE IF NOT EXISTS `cm_family_progression` (
  `family_id`           BIGINT UNSIGNED NOT NULL,
  `level`               INT UNSIGNED NOT NULL DEFAULT 1,
  `current_xp`          BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `lifetime_reputation` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `season_reputation`   BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `updated_at`          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_member_contributions` (
  `id`                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id`             BIGINT UNSIGNED NOT NULL,
  `character_id`          VARCHAR(64) NOT NULL,
  `total_points`          BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `weekly_points`         BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `activity_points`       BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `financial_points`      BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `money_contributed`     BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `event_points`          BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `last_contribution_at`  TIMESTAMP NULL DEFAULT NULL,
  `updated_at`            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_fam_member_contrib` (`family_id`, `character_id`),
  KEY `idx_contrib_fam_weekly` (`family_id`, `weekly_points`),
  KEY `idx_contrib_fam_total` (`family_id`, `total_points`),
  KEY `idx_contrib_char` (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_objectives` (
  `id`                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `objective_key`       VARCHAR(64) NOT NULL,
  `category`            VARCHAR(32) NOT NULL DEFAULT 'general',
  `title`               VARCHAR(128) NOT NULL,
  `description`         VARCHAR(256) NOT NULL,
  `target_type`         VARCHAR(48) NOT NULL,
  `target_value`        BIGINT UNSIGNED NOT NULL DEFAULT 1,
  `reward_reputation`   INT UNSIGNED NOT NULL DEFAULT 0,
  `reward_contribution` INT UNSIGNED NOT NULL DEFAULT 0,
  `reward_treasury`     BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `is_active`           TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_obj_key` (`objective_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_objective_progress` (
  `id`             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id`      BIGINT UNSIGNED NOT NULL,
  `objective_key`  VARCHAR(64) NOT NULL,
  `week_key`       VARCHAR(16) NOT NULL,
  `current_value`  BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `completed`      TINYINT(1) NOT NULL DEFAULT 0,
  `completed_at`   TIMESTAMP NULL DEFAULT NULL,
  `reward_claimed` TINYINT(1) NOT NULL DEFAULT 0,
  `updated_at`     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_fam_obj_week` (`family_id`, `objective_key`, `week_key`),
  KEY `idx_fop_fam_week` (`family_id`, `week_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_hq_upgrades` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id`     BIGINT UNSIGNED NOT NULL,
  `upgrade_key`   VARCHAR(48) NOT NULL,
  `tier`          TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `purchased_by`  VARCHAR(64) NULL,
  `purchased_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_fam_upgrade` (`family_id`, `upgrade_key`),
  KEY `idx_hq_upgrade_fam` (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_reward_history` (
  `id`           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `unique_id`    VARCHAR(96) NOT NULL,
  `family_id`    BIGINT UNSIGNED NOT NULL,
  `reward_type`  VARCHAR(32) NOT NULL,
  `amount`       BIGINT NOT NULL DEFAULT 0,
  `source`       VARCHAR(64) NOT NULL,
  `metadata`     JSON NULL,
  `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_reward_uid` (`unique_id`),
  KEY `idx_reward_fam` (`family_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `cm_family_bank_log`
  ADD COLUMN IF NOT EXISTS `category` VARCHAR(32) NOT NULL DEFAULT 'deposit' AFTER `direction`;

