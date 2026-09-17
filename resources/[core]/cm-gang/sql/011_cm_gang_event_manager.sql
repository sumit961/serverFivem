-- cm-gang | reusable event manager and Supply War persistence
-- Additive and repeatable: no existing table or row is changed or removed.
CREATE TABLE IF NOT EXISTS `cm_gang_event_config` (
  `event_type` VARCHAR(32) NOT NULL, `enabled` TINYINT(1) NOT NULL DEFAULT 0,
  `event_name` VARCHAR(96) NOT NULL DEFAULT 'Gang Supply War', `area_name` VARCHAR(96) NULL,
  `zone_x` DOUBLE NULL, `zone_y` DOUBLE NULL, `zone_z` DOUBLE NULL, `zone_radius` FLOAT NOT NULL DEFAULT 250,
  `announcement_seconds` INT UNSIGNED NOT NULL DEFAULT 60, `duration_seconds` INT UNSIGNED NOT NULL DEFAULT 1500,
  `routing_bucket` INT UNSIGNED NOT NULL DEFAULT 7100, `max_active_drops` INT UNSIGNED NOT NULL DEFAULT 2,
  `capture_seconds` INT UNSIGNED NOT NULL DEFAULT 4, `contested_capture_seconds` INT UNSIGNED NOT NULL DEFAULT 7,
  `claim_radius` FLOAT NOT NULL DEFAULT 3, `contest_radius` FLOAT NOT NULL DEFAULT 20,
  `boundary_grace_seconds` INT UNSIGNED NOT NULL DEFAULT 5, `combat_tag_seconds` INT UNSIGNED NOT NULL DEFAULT 15,
  `reentry_cooldown_seconds` INT UNSIGNED NOT NULL DEFAULT 40, `anti_farm_seconds` INT UNSIGNED NOT NULL DEFAULT 90,
  `kill_points` INT UNSIGNED NOT NULL DEFAULT 1, `config_json` LONGTEXT NULL,
  `updated_by_character_id` BIGINT UNSIGNED NULL, `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`event_type`), UNIQUE KEY `uniq_cm_gang_event_bucket` (`routing_bucket`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_gang_event_entry_points` (
  `event_type` VARCHAR(32) NOT NULL, `gang_id` VARCHAR(32) NOT NULL, `enabled` TINYINT(1) NOT NULL DEFAULT 1,
  `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL, `heading` FLOAT NOT NULL DEFAULT 0,
  `updated_by_character_id` BIGINT UNSIGNED NULL, `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`event_type`,`gang_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_gang_event_drop_locations` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `event_type` VARCHAR(32) NOT NULL, `label` VARCHAR(96) NOT NULL,
  `enabled` TINYINT(1) NOT NULL DEFAULT 1, `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL,
  `updated_by_character_id` BIGINT UNSIGNED NULL, `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `idx_cm_gang_event_drop_location` (`event_type`,`enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_gang_event_reward_config` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `event_type` VARCHAR(32) NOT NULL, `tier` VARCHAR(24) NOT NULL,
  `item_id` VARCHAR(96) NOT NULL, `enabled` TINYINT(1) NOT NULL DEFAULT 1,
  `min_quantity` INT UNSIGNED NOT NULL DEFAULT 1, `max_quantity` INT UNSIGNED NOT NULL DEFAULT 1, `weight` INT UNSIGNED NOT NULL DEFAULT 1,
  `updated_by_character_id` BIGINT UNSIGNED NULL, `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), UNIQUE KEY `uniq_cm_gang_event_reward` (`event_type`,`tier`,`item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_gang_events` (
  `event_id` VARCHAR(64) NOT NULL, `event_type` VARCHAR(32) NOT NULL, `status` VARCHAR(32) NOT NULL,
  `routing_bucket` INT UNSIGNED NOT NULL, `started_at` TIMESTAMP NULL, `live_at` TIMESTAMP NULL, `ended_at` TIMESTAMP NULL,
  `winning_gang_id` VARCHAR(32) NULL, `mvp_character_id` BIGINT UNSIGNED NULL,
  `config_snapshot` LONGTEXT NOT NULL, `final_scores` LONGTEXT NULL, `end_reason` VARCHAR(48) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`event_id`), KEY `idx_cm_gang_events_type_created` (`event_type`,`created_at`), KEY `idx_cm_gang_events_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_gang_event_players` (
  `event_id` VARCHAR(64) NOT NULL, `character_id` BIGINT UNSIGNED NOT NULL, `gang_id` VARCHAR(32) NOT NULL,
  `kills` INT UNSIGNED NOT NULL DEFAULT 0, `deaths` INT UNSIGNED NOT NULL DEFAULT 0, `drops_secured` INT UNSIGNED NOT NULL DEFAULT 0,
  `streak` INT UNSIGNED NOT NULL DEFAULT 0, `original_bucket` INT UNSIGNED NOT NULL DEFAULT 0,
  `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, `left_at` TIMESTAMP NULL, `mvp_score` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`event_id`,`character_id`), KEY `idx_cm_gang_event_players_gang` (`event_id`,`gang_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cm_gang_event_drops` (
  `event_id` VARCHAR(64) NOT NULL, `drop_id` VARCHAR(64) NOT NULL, `drop_number` INT UNSIGNED NOT NULL,
  `tier` VARCHAR(24) NOT NULL, `location_id` BIGINT UNSIGNED NOT NULL, `state` VARCHAR(24) NOT NULL,
  `spawned_at` TIMESTAMP NULL, `landed_at` TIMESTAMP NULL, `claimed_at` TIMESTAMP NULL,
  `claimed_gang_id` VARCHAR(32) NULL, `claimed_character_id` BIGINT UNSIGNED NULL,
  `reward_summary` LONGTEXT NULL, `claim_operation_id` VARCHAR(96) NULL, `net_ids` LONGTEXT NULL,
  PRIMARY KEY (`event_id`,`drop_id`), UNIQUE KEY `uniq_cm_gang_event_drop_number` (`event_id`,`drop_number`),
  UNIQUE KEY `uniq_cm_gang_event_claim_operation` (`claim_operation_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO `cm_gang_event_config` (`event_type`) VALUES ('supply_war');
INSERT IGNORE INTO `cm_gang_migrations` (`migration_id`) VALUES ('011_cm_gang_event_manager');
