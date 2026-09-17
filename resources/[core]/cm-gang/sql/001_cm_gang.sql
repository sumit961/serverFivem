-- cm-gang v0.1.0 | additive fixed-slot schema and one-time seeds
-- Apply manually to a non-production database first. Safe to rerun: existing
-- gang identity and rank customization is never overwritten.

CREATE TABLE IF NOT EXISTS `cm_gangs` (
  `gang_id` VARCHAR(16) NOT NULL,
  `display_name` VARCHAR(64) NOT NULL,
  `short_tag` VARCHAR(12) NOT NULL,
  `color` VARCHAR(9) NOT NULL DEFAULT '#67e8f9',
  `logo_asset` VARCHAR(96) NULL,
  `art_asset` VARCHAR(96) NULL,
  `leader_character_id` VARCHAR(64) NULL,
  `enabled` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`gang_id`),
  CONSTRAINT `chk_cm_gangs_fixed_id` CHECK (`gang_id` IN ('gang_1','gang_2','gang_3','gang_4'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_gang_ranks` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `gang_id` VARCHAR(16) NOT NULL,
  `tier` TINYINT UNSIGNED NOT NULL,
  `name` VARCHAR(48) NOT NULL,
  `permissions` JSON NOT NULL,
  `is_leader_rank` TINYINT(1) NOT NULL DEFAULT 0,
  `leader_rank_slot` VARCHAR(16) GENERATED ALWAYS AS (CASE WHEN `is_leader_rank` = 1 THEN `gang_id` ELSE NULL END) STORED,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_gang_rank_tier` (`gang_id`, `tier`),
  UNIQUE KEY `uniq_gang_rank_name` (`gang_id`, `name`),
  UNIQUE KEY `uniq_gang_rank_identity` (`gang_id`, `id`),
  UNIQUE KEY `uniq_gang_leader_rank` (`leader_rank_slot`),
  KEY `idx_gang_ranks_gang` (`gang_id`),
  CONSTRAINT `fk_gang_ranks_gang` FOREIGN KEY (`gang_id`) REFERENCES `cm_gangs` (`gang_id`),
  CONSTRAINT `chk_gang_rank_tier` CHECK (`tier` BETWEEN 1 AND 100),
  CONSTRAINT `chk_gang_rank_leader` CHECK (`is_leader_rank` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_gang_members` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `gang_id` VARCHAR(16) NOT NULL,
  `character_id` VARCHAR(64) NOT NULL,
  `rank_id` BIGINT UNSIGNED NOT NULL,
  `is_leader` TINYINT(1) NOT NULL DEFAULT 0,
  `leader_member_slot` VARCHAR(16) GENERATED ALWAYS AS (CASE WHEN `is_leader` = 1 THEN `gang_id` ELSE NULL END) STORED,
  `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_gang_member_character` (`character_id`),
  UNIQUE KEY `uniq_gang_leader_member` (`leader_member_slot`),
  KEY `idx_gang_members_gang` (`gang_id`),
  KEY `idx_gang_members_rank` (`rank_id`),
  CONSTRAINT `fk_gang_members_gang` FOREIGN KEY (`gang_id`) REFERENCES `cm_gangs` (`gang_id`),
  CONSTRAINT `fk_gang_members_rank` FOREIGN KEY (`gang_id`, `rank_id`) REFERENCES `cm_gang_ranks` (`gang_id`, `id`),
  CONSTRAINT `chk_gang_member_leader` CHECK (`is_leader` IN (0,1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_gang_invites` (
  `invite_id` CHAR(36) NOT NULL,
  `gang_id` VARCHAR(16) NOT NULL,
  `actor_character_id` VARCHAR(64) NOT NULL,
  `target_character_id` VARCHAR(64) NOT NULL,
  `entry_rank_id` BIGINT UNSIGNED NOT NULL,
  `status` ENUM('pending','accepted','declined','expired','cancelled') NOT NULL DEFAULT 'pending',
  `expires_at` TIMESTAMP NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `resolved_at` TIMESTAMP NULL,
  `pending_target_slot` VARCHAR(64) GENERATED ALWAYS AS (CASE WHEN `status` = 'pending' THEN `target_character_id` ELSE NULL END) STORED,
  PRIMARY KEY (`invite_id`),
  UNIQUE KEY `uniq_gang_pending_target` (`pending_target_slot`),
  KEY `idx_gang_invites_gang_time` (`gang_id`, `created_at`),
  KEY `idx_gang_invites_expiry` (`status`, `expires_at`),
  CONSTRAINT `fk_gang_invites_gang` FOREIGN KEY (`gang_id`) REFERENCES `cm_gangs` (`gang_id`),
  CONSTRAINT `fk_gang_invites_rank` FOREIGN KEY (`gang_id`, `entry_rank_id`) REFERENCES `cm_gang_ranks` (`gang_id`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_gang_activity` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `event_uid` VARCHAR(96) NOT NULL,
  `gang_id` VARCHAR(16) NOT NULL,
  `action` VARCHAR(64) NOT NULL,
  `status` VARCHAR(16) NOT NULL DEFAULT 'success',
  `actor_character_id` VARCHAR(64) NULL,
  `target_character_id` VARCHAR(64) NULL,
  `vehicle_id` BIGINT UNSIGNED NULL,
  `detail` JSON NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_gang_activity_uid` (`event_uid`),
  KEY `idx_gang_activity_gang_time` (`gang_id`, `created_at`),
  KEY `idx_gang_activity_action_time` (`action`, `created_at`),
  KEY `idx_gang_activity_actor` (`actor_character_id`),
  KEY `idx_gang_activity_target` (`target_character_id`),
  KEY `idx_gang_activity_vehicle` (`vehicle_id`),
  CONSTRAINT `fk_gang_activity_gang` FOREIGN KEY (`gang_id`) REFERENCES `cm_gangs` (`gang_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_gang_facilities` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `gang_id` VARCHAR(16) NOT NULL,
  `facility_type` ENUM('headquarters','armory','stash','fleet') NOT NULL,
  `enabled` TINYINT(1) NOT NULL DEFAULT 0,
  `npc_model` VARCHAR(64) NULL,
  `display_name` VARCHAR(64) NULL,
  `role_label` VARCHAR(64) NULL,
  `x` DECIMAL(11,4) NULL,
  `y` DECIMAL(11,4) NULL,
  `z` DECIMAL(11,4) NULL,
  `heading` DECIMAL(7,3) NULL,
  `routing_bucket` INT NOT NULL DEFAULT 0,
  `updated_by` VARCHAR(64) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_gang_facility_type` (`gang_id`, `facility_type`),
  CONSTRAINT `fk_gang_facilities_gang` FOREIGN KEY (`gang_id`) REFERENCES `cm_gangs` (`gang_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_gang_fleet_vehicles` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `gang_id` VARCHAR(16) NOT NULL,
  `catalog_id` VARCHAR(96) NOT NULL,
  `vehicle_id` BIGINT UNSIGNED NULL,
  `minimum_tier` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `enabled` TINYINT(1) NOT NULL DEFAULT 0,
  `x` DECIMAL(11,4) NULL,
  `y` DECIMAL(11,4) NULL,
  `z` DECIMAL(11,4) NULL,
  `heading` DECIMAL(7,3) NULL,
  `routing_bucket` INT NOT NULL DEFAULT 0,
  `updated_by` VARCHAR(64) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_gang_fleet_catalog` (`gang_id`, `catalog_id`),
  UNIQUE KEY `uniq_gang_fleet_vehicle_id` (`vehicle_id`),
  KEY `idx_gang_fleet_gang_enabled` (`gang_id`, `enabled`),
  CONSTRAINT `fk_gang_fleet_gang` FOREIGN KEY (`gang_id`) REFERENCES `cm_gangs` (`gang_id`),
  CONSTRAINT `chk_gang_fleet_tier` CHECK (`minimum_tier` BETWEEN 1 AND 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_gang_armory_config` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `gang_id` VARCHAR(16) NOT NULL,
  `item_id` VARCHAR(96) NOT NULL,
  `enabled` TINYINT(1) NOT NULL DEFAULT 0,
  `minimum_tier` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `issue_quantity` INT UNSIGNED NOT NULL DEFAULT 1,
  `issue_limit` INT UNSIGNED NOT NULL DEFAULT 0,
  `updated_by` VARCHAR(64) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_gang_armory_item` (`gang_id`, `item_id`),
  KEY `idx_gang_armory_gang_enabled` (`gang_id`, `enabled`),
  CONSTRAINT `fk_gang_armory_gang` FOREIGN KEY (`gang_id`) REFERENCES `cm_gangs` (`gang_id`),
  CONSTRAINT `chk_gang_armory_tier` CHECK (`minimum_tier` BETWEEN 1 AND 100),
  CONSTRAINT `chk_gang_armory_quantity` CHECK (`issue_quantity` BETWEEN 1 AND 1000)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cm_gang_migrations` (
  `migration_id` VARCHAR(64) NOT NULL,
  `checksum` CHAR(64) NULL,
  `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`migration_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO `cm_gangs` (`gang_id`, `display_name`, `short_tag`, `color`, `enabled`) VALUES
  ('gang_1', 'Gang One',   'G1', '#67e8f9', 0),
  ('gang_2', 'Gang Two',   'G2', '#67e8f9', 0),
  ('gang_3', 'Gang Three', 'G3', '#67e8f9', 0),
  ('gang_4', 'Gang Four',  'G4', '#67e8f9', 0);

INSERT IGNORE INTO `cm_gang_ranks` (`gang_id`, `tier`, `name`, `permissions`, `is_leader_rank`)
SELECT g.gang_id, seed.tier, seed.name, seed.permissions, seed.is_leader_rank
FROM `cm_gangs` g
CROSS JOIN (
  SELECT 100 tier, 'Leader' name, JSON_OBJECT('gang.view_members',true,'gang.manage_members',true,'gang.manage_ranks',true,'gang.manage_permissions',true,'gang.chat',true,'gang.vehicle',true,'gang.manage_vehicles',true,'gang.armory',true,'gang.manage_armory',true,'gang.stash',true,'gang.manage_stash',true,'gang.invite',true,'gang.search',true,'gang.rob_cash',true,'gang.rob_items',true,'gang.view_logs',true) permissions, 1 is_leader_rank
  UNION ALL SELECT 80, 'Underboss', JSON_OBJECT('gang.view_members',true,'gang.manage_members',true,'gang.chat',true,'gang.vehicle',true,'gang.manage_vehicles',true,'gang.armory',true,'gang.manage_armory',true,'gang.stash',true,'gang.manage_stash',true,'gang.invite',true,'gang.search',true,'gang.rob_cash',true,'gang.rob_items',true,'gang.view_logs',true), 0
  UNION ALL SELECT 60, 'Enforcer', JSON_OBJECT('gang.view_members',true,'gang.chat',true,'gang.vehicle',true,'gang.armory',true,'gang.stash',true,'gang.invite',true,'gang.search',true,'gang.rob_cash',true,'gang.rob_items',true), 0
  UNION ALL SELECT 40, 'Member', JSON_OBJECT('gang.view_members',true,'gang.chat',true,'gang.vehicle',true,'gang.armory',true,'gang.stash',true,'gang.search',true), 0
  UNION ALL SELECT 20, 'Recruit', JSON_OBJECT('gang.view_members',true,'gang.chat',true), 0
) seed
WHERE NOT EXISTS (
  SELECT 1 FROM `cm_gang_ranks` existing WHERE existing.gang_id = g.gang_id
);

INSERT IGNORE INTO `cm_gang_facilities` (`gang_id`, `facility_type`, `enabled`)
SELECT g.gang_id, types.facility_type, 0
FROM `cm_gangs` g
CROSS JOIN (
  SELECT 'headquarters' facility_type UNION ALL SELECT 'armory'
  UNION ALL SELECT 'stash' UNION ALL SELECT 'fleet'
) types;

INSERT IGNORE INTO `cm_gang_migrations` (`migration_id`) VALUES ('001_cm_gang');
