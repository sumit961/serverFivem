-- ============================================================
--  cm-house  |  Migration 001  |  Houses, keys, garages, families
--  Requires: cm-playerdata (citizenid authority), cm-inventory (stashes)
-- ============================================================

-- ---------- Families (created before houses: houses FK to family) ----------
CREATE TABLE IF NOT EXISTS `cm_families` (
  `id`         INT AUTO_INCREMENT PRIMARY KEY,
  `name`       VARCHAR(48)  NOT NULL,
  `owner_cid`  INT          NOT NULL,
  `house_id`   INT          DEFAULT NULL,
  `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_family_name` (`name`),
  INDEX `idx_family_owner` (`owner_cid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- Houses ----------
CREATE TABLE IF NOT EXISTS `cm_houses` (
  `id`                  INT AUTO_INCREMENT PRIMARY KEY,
  `house_number`        VARCHAR(16)  NOT NULL,
  `label`               VARCHAR(64)  DEFAULT NULL,
  `owner_cid`           INT          DEFAULT NULL,
  `house_type`          VARCHAR(32)  NOT NULL DEFAULT 'apartment',

  `door_coords`         JSON         NOT NULL,   -- {"x":..,"y":..,"z":..,"h":..}
  `garage_coords`       JSON         DEFAULT NULL,
  `helipad_coords`      JSON         DEFAULT NULL,

  `interior_key`        VARCHAR(64)  DEFAULT NULL,
  `garage_interior_key` VARCHAR(64)  DEFAULT NULL,

  -- Placed from INSIDE the interior, because you cannot know where a wardrobe
  -- or an exit door goes until you are standing in the room. Everything below
  -- is captured in phase 2 of /cmhouse, not guessed in config.
  `interior_spawn`      JSON         DEFAULT NULL,  -- where you land on entering
  `interior_exit`       JSON         DEFAULT NULL,  -- the way back out
  `garage_exit`         JSON         DEFAULT NULL,  -- the way out of the garage

  `garage_slots`        INT          NOT NULL DEFAULT 2,
  `wardrobe_count`      INT          NOT NULL DEFAULT 1,

  `price`               INT          NOT NULL DEFAULT 0,
  `gov_value`           INT          NOT NULL DEFAULT 0,
  `insurance`           INT          NOT NULL DEFAULT 0,
  `daily_cost`          INT          NOT NULL DEFAULT 0,
  `paid_until`          DATE         DEFAULT NULL,

  `locked`              TINYINT(1)   NOT NULL DEFAULT 1,
  `for_sale`            TINYINT(1)   NOT NULL DEFAULT 1,
  `family_id`           INT          DEFAULT NULL,
  `created_by`          INT          DEFAULT NULL,
  `created_at`          TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,

  UNIQUE KEY `uq_house_number` (`house_number`),
  INDEX `idx_house_owner`  (`owner_cid`),
  INDEX `idx_house_family` (`family_id`),
  CONSTRAINT `fk_house_family` FOREIGN KEY (`family_id`)
    REFERENCES `cm_families`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- Close the circular reference ----------
-- cm_houses.family_id -> cm_families, and cm_families.house_id -> cm_houses.
-- Each needs the other to exist first, so this one FK is added afterwards.
-- MySQL has no ADD CONSTRAINT IF NOT EXISTS, so guard against the catalog --
-- otherwise re-running this migration dies on a duplicate key name.
SET @fk_exists := (
  SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME        = 'cm_families'
    AND CONSTRAINT_NAME   = 'fk_family_house'
);

SET @sql := IF(@fk_exists = 0,
  'ALTER TABLE `cm_families`
     ADD CONSTRAINT `fk_family_house` FOREIGN KEY (`house_id`)
     REFERENCES `cm_houses`(`id`) ON DELETE SET NULL',
  'SELECT "fk_family_house already exists" AS note'
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ---------- House keys (non-family guests) ----------
CREATE TABLE IF NOT EXISTS `cm_house_keys` (
  `house_id`   INT         NOT NULL,
  `cid`        INT         NOT NULL,
  `granted_by` INT         DEFAULT NULL,
  `granted_at` TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`house_id`, `cid`),
  INDEX `idx_key_cid` (`cid`),
  CONSTRAINT `fk_key_house` FOREIGN KEY (`house_id`)
    REFERENCES `cm_houses`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- Wardrobes (each maps to a cm-inventory stash, 30 slots) ----------
-- ---------- Wardrobes ----------
-- cm-inventory has no stash registry: storage is opened on demand by
-- (owner_type, owner_id, slot_prefix) and the items live in inventory_items.
-- So a wardrobe is not an object we create -- it is an address we open.
-- inv_id is that address: "<houseId>:<slotIndex>", e.g. "12:2".
CREATE TABLE IF NOT EXISTS `cm_house_wardrobes` (
  `id`         INT AUTO_INCREMENT PRIMARY KEY,
  `house_id`   INT         NOT NULL,
  `slot_index` INT         NOT NULL,
  `inv_id`     VARCHAR(32) NOT NULL,
  `label`      VARCHAR(48) DEFAULT NULL,
  `coords`     JSON        DEFAULT NULL,   -- placed from inside the interior
  UNIQUE KEY `uq_wardrobe` (`house_id`, `slot_index`),
  UNIQUE KEY `uq_wardrobe_inv` (`inv_id`),
  CONSTRAINT `fk_wardrobe_house` FOREIGN KEY (`house_id`)
    REFERENCES `cm_houses`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- Garage contents ----------
CREATE TABLE IF NOT EXISTS `cm_house_garage` (
  `house_id`      INT         NOT NULL,
  `plate`         VARCHAR(12) NOT NULL,
  `owner_cid`     INT         NOT NULL,
  `family_shared` TINYINT(1)  NOT NULL DEFAULT 0,
  `stored`        TINYINT(1)  NOT NULL DEFAULT 1,
  `is_heli`       TINYINT(1)  NOT NULL DEFAULT 0,
  `stored_at`     TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`house_id`, `plate`),
  INDEX `idx_garage_owner` (`owner_cid`),
  CONSTRAINT `fk_garage_house` FOREIGN KEY (`house_id`)
    REFERENCES `cm_houses`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- Family ranks ----------
CREATE TABLE IF NOT EXISTS `cm_family_ranks` (
  `id`        INT AUTO_INCREMENT PRIMARY KEY,
  `family_id` INT         NOT NULL,
  `name`      VARCHAR(32) NOT NULL,
  `grade`     INT         NOT NULL,   -- 0 = owner (immutable)
  `perms`     JSON        NOT NULL,
  UNIQUE KEY `uq_rank_grade` (`family_id`, `grade`),
  CONSTRAINT `fk_rank_family` FOREIGN KEY (`family_id`)
    REFERENCES `cm_families`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- Family members (PK on cid = one family per player) ----------
CREATE TABLE IF NOT EXISTS `cm_family_members` (
  `cid`       INT         NOT NULL PRIMARY KEY,
  `family_id` INT         NOT NULL,
  `rank_id`   INT         NOT NULL,
  `joined_at` TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_member_family` (`family_id`),
  CONSTRAINT `fk_member_family` FOREIGN KEY (`family_id`)
    REFERENCES `cm_families`(`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_member_rank` FOREIGN KEY (`rank_id`)
    REFERENCES `cm_family_ranks`(`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- Unified audit log ----------
CREATE TABLE IF NOT EXISTS `cm_house_logs` (
  `id`         BIGINT AUTO_INCREMENT PRIMARY KEY,
  `house_id`   INT         DEFAULT NULL,
  `family_id`  INT         DEFAULT NULL,
  `cid`        INT         DEFAULT NULL,
  `action`     VARCHAR(32) NOT NULL,
  `detail`     JSON        DEFAULT NULL,
  `created_at` TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_log_house`  (`house_id`,  `created_at`),
  INDEX `idx_log_family` (`family_id`, `created_at`),
  INDEX `idx_log_cid`    (`cid`,       `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
