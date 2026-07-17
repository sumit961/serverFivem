-- ============================================================
--  cm-family | core schema
--
--  cm-family owns families, ranks, members, the bank and per-vehicle access
--  levels. cm-house remains the property/vehicle authority; it asks cm-family
--  one question through HasHousePermission and cm-family answers.
--
--  Rank model: each family has up to 15 ranks. `tier` is the ordering/authority
--  value (higher = more authority). The founder rank is the highest tier and
--  always holds every permission. Vehicle access uses tier >= vehicle level.
-- ============================================================

CREATE TABLE IF NOT EXISTS `cm_families` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name`          VARCHAR(64) NOT NULL,
  `tag`           VARCHAR(8) NULL,
  `color`         VARCHAR(9) NOT NULL DEFAULT '#00f0ff',
  `symbol`        VARCHAR(16) NOT NULL DEFAULT 'shield',
  `tag_visible`   TINYINT(1) NOT NULL DEFAULT 1,
  `founder_cid`   VARCHAR(64) NOT NULL,
  `house_id`      INT UNSIGNED NULL,
  `bank_balance`  BIGINT NOT NULL DEFAULT 0,
  `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_family_name` (`name`),
  KEY `idx_family_founder` (`founder_cid`),
  KEY `idx_family_house` (`house_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Ranks. `permissions` is a JSON object of boolean permission keys (see
-- shared/config.lua Config.Permissions). `tier` 1..15, unique per family.
CREATE TABLE IF NOT EXISTS `cm_family_ranks` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id`   INT UNSIGNED NOT NULL,
  `tier`        TINYINT UNSIGNED NOT NULL,
  `name`        VARCHAR(48) NOT NULL,
  `overhead_symbol` VARCHAR(16) NOT NULL DEFAULT 'shield',
  `overhead_color`  VARCHAR(9) NULL,
  `permissions` JSON NOT NULL,
  `is_founder`  TINYINT(1) NOT NULL DEFAULT 0,
  `bank_daily_limit` BIGINT NOT NULL DEFAULT 0,   -- 0 = no withdrawal, <0 = unlimited
  `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_family_tier` (`family_id`, `tier`),
  KEY `idx_rank_family` (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Members. One family per character (enforced by the unique key on character_id).
CREATE TABLE IF NOT EXISTS `cm_family_members` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id`    INT UNSIGNED NOT NULL,
  `character_id` VARCHAR(64) NOT NULL,
  `rank_id`      INT UNSIGNED NOT NULL,
  `custom_title` VARCHAR(24) NULL,
  `tag_hidden`   TINYINT(1) NOT NULL DEFAULT 0,
  `joined_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_member_character` (`character_id`),
  KEY `idx_member_family` (`family_id`),
  KEY `idx_member_rank` (`rank_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Pending invitations. Invited players accept or decline; invites can expire.
CREATE TABLE IF NOT EXISTS `cm_family_invites` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id`    INT UNSIGNED NOT NULL,
  `character_id` VARCHAR(64) NOT NULL,
  `invited_by`   VARCHAR(64) NOT NULL,
  `rank_id`      INT UNSIGNED NULL,
  `expires_at`   TIMESTAMP NULL,
  `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_invite` (`family_id`, `character_id`),
  KEY `idx_invite_character` (`character_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Per-vehicle required access level. A member may use the vehicle only when
-- their rank tier >= level. Vehicles not present here fall back to the family
-- default level in Config. cm-house owns the vehicle rows; this only records
-- the access threshold keyed by cm-house's vehicle id.
CREATE TABLE IF NOT EXISTS `cm_family_vehicle_access` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id`   INT UNSIGNED NOT NULL,
  `vehicle_id`  INT UNSIGNED NOT NULL,
  `level`       TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `updated_by`  VARCHAR(64) NULL,
  `updated_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_family_vehicle` (`family_id`, `vehicle_id`),
  KEY `idx_vaccess_family` (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Bank ledger. Every deposit/withdraw/spend is one row for a full audit trail.
CREATE TABLE IF NOT EXISTS `cm_family_bank_log` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id`    INT UNSIGNED NOT NULL,
  `character_id` VARCHAR(64) NULL,
  `direction`    ENUM('deposit','withdraw') NOT NULL,
  `amount`       BIGINT NOT NULL,
  `balance_after` BIGINT NOT NULL,
  `reason`       VARCHAR(128) NULL,
  `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_banklog_family` (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- General audit log: invites, kicks, rank changes, vehicle level changes, etc.
CREATE TABLE IF NOT EXISTS `cm_family_log` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id`    INT UNSIGNED NOT NULL,
  `actor_cid`    VARCHAR(64) NULL,
  `action`       VARCHAR(48) NOT NULL,
  `detail`       JSON NULL,
  `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_log_family` (`family_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
