-- ============================================================
-- cm-family | 018_family_event_engine.sql
-- CM Family Event Engine — Phase 1
-- Authoritative event instances, participants, and cooldowns.
-- ============================================================

CREATE TABLE IF NOT EXISTS `cm_family_event_instances` (
  `id`                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `event_uid`           VARCHAR(96) NOT NULL,
  `event_key`           VARCHAR(64) NOT NULL,
  `state`               VARCHAR(32) NOT NULL DEFAULT 'forming',
  `initiator_family_id` BIGINT UNSIGNED NOT NULL,
  `target_family_id`    BIGINT UNSIGNED NULL,
  `winner_family_id`    BIGINT UNSIGNED NULL,
  `location_key`        VARCHAR(64) NULL,
  `routing_bucket`      INT UNSIGNED NULL,
  `started_at`          TIMESTAMP NULL DEFAULT NULL,
  `ends_at`             TIMESTAMP NULL DEFAULT NULL,
  `completed_at`        TIMESTAMP NULL DEFAULT NULL,
  `result_reason`       VARCHAR(128) NULL,
  `metadata`            JSON NULL,
  `created_at`          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_event_uid` (`event_uid`),
  KEY `idx_evt_key_state` (`event_key`, `state`),
  KEY `idx_evt_initiator` (`initiator_family_id`),
  KEY `idx_evt_target` (`target_family_id`),
  KEY `idx_evt_winner` (`winner_family_id`),
  KEY `idx_evt_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_event_participants` (
  `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `event_uid`     VARCHAR(96) NOT NULL,
  `family_id`     BIGINT UNSIGNED NOT NULL,
  `character_id`  VARCHAR(64) NOT NULL,
  `joined_at`     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `left_at`       TIMESTAMP NULL DEFAULT NULL,
  `status`        VARCHAR(32) NOT NULL DEFAULT 'active',
  `score`         INT NOT NULL DEFAULT 0,
  `contribution`  INT NOT NULL DEFAULT 0,
  `metadata`      JSON NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_event_char` (`event_uid`, `character_id`),
  KEY `idx_part_event` (`event_uid`),
  KEY `idx_part_family` (`family_id`),
  KEY `idx_part_char` (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_family_event_cooldowns` (
  `id`             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `event_key`      VARCHAR(64) NOT NULL,
  `family_id`      BIGINT UNSIGNED NOT NULL,
  `available_at`   TIMESTAMP NOT NULL,
  `last_event_uid` VARCHAR(96) NULL,
  `updated_at`     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_evt_fam_cooldown` (`event_key`, `family_id`),
  KEY `idx_cooldown_avail` (`available_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
