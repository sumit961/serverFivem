-- ============================================================
--  cm-house | Migration 003  |  PHASE 1 -- Reusable templates
--
--  The core rule from the spec:
--    "Interior and garage layouts are configured once as reusable templates.
--     Each property stores only its unique exterior coordinates."
--
--  Before this, every house stored its own spawn/exit/wardrobe coords. Build
--  50 apartments and you walked the same room 50 times placing the same
--  wardrobe in the same corner. Now: walk it ONCE, save a template, and every
--  property that selects it inherits those points.
--
--  Safe to run repeatedly.
-- ============================================================

-- ============================================================
--  Interior templates -- walked once, reused forever
-- ============================================================
CREATE TABLE IF NOT EXISTS `cm_house_interior_templates` (
  `id`            INT AUTO_INCREMENT PRIMARY KEY,
  `key_name`      VARCHAR(48)  NOT NULL,           -- 'modern_house_l2'
  `label`         VARCHAR(64)  NOT NULL,           -- 'Modern House Level 2'
  `version`       INT          NOT NULL DEFAULT 1,
  `enabled`       TINYINT(1)   NOT NULL DEFAULT 1,

  -- Where the room physically is. Exactly one source is used.
  `source_kind`   VARCHAR(16)  NOT NULL DEFAULT 'world',  -- world | shell | ipl
  `source_ref`    VARCHAR(64)  DEFAULT NULL,              -- ipl name or shell model

  -- The points, walked once inside the room. All local to the interior.
  `entry`         JSON         NOT NULL,   -- where the player lands
  `exit_point`    JSON         NOT NULL,   -- E to leave -> back to the front door
  `garage_door`   JSON         DEFAULT NULL,  -- E to walk through into the garage
  `wardrobes`     JSON         NOT NULL DEFAULT ('[]'),  -- legacy wardrobe points
  `weapon_storages` JSON       NOT NULL DEFAULT ('[]'),  -- [{x,y,z,h}, ...]
  `stashes`       JSON         NOT NULL DEFAULT ('[]'),  -- [{x,y,z,h,label,slots}]

  -- Which property types may select this template.
  `allowed_types` JSON         NOT NULL DEFAULT ('[]'),
  `notes`         VARCHAR(255) DEFAULT NULL,

  `created_by`    INT          DEFAULT NULL,
  `created_at`    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY `uq_interior_key` (`key_name`, `version`),
  INDEX `idx_interior_enabled` (`enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
--  Garage templates
--  Capacity is NOT a number you type. It is the count of physical vehicle
--  positions you walked to and placed. A 7-car garage has exactly 7 saved
--  coordinates and 7 icons, and cannot take an 8th.
-- ============================================================
CREATE TABLE IF NOT EXISTS `cm_house_garage_templates` (
  `id`           INT AUTO_INCREMENT PRIMARY KEY,
  `key_name`     VARCHAR(48) NOT NULL,
  `label`        VARCHAR(64) NOT NULL,
  `version`      INT         NOT NULL DEFAULT 1,
  `enabled`      TINYINT(1)  NOT NULL DEFAULT 1,

  `source_kind`  VARCHAR(16) NOT NULL DEFAULT 'world',
  `source_ref`   VARCHAR(64) DEFAULT NULL,

  `player_entry` JSON        NOT NULL,   -- arriving from the house, on foot
  `house_door`   JSON        NOT NULL,   -- E to walk back into the house
  `vehicle_exit` JSON        NOT NULL,   -- drive over this to leave

  -- capacity == #slots. Enforced by a trigger below, not by trust.
  `capacity`     INT         NOT NULL DEFAULT 0,
  `notes`        VARCHAR(255) DEFAULT NULL,

  `created_by`   INT         DEFAULT NULL,
  `created_at`   TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY `uq_garage_key` (`key_name`, `version`),
  INDEX `idx_garage_enabled` (`enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------- The physical slots ----------
CREATE TABLE IF NOT EXISTS `cm_house_garage_slots` (
  `id`          INT AUTO_INCREMENT PRIMARY KEY,
  `template_id` INT         NOT NULL,
  `slot_index`  INT         NOT NULL,   -- 1..capacity
  `coords`      JSON        NOT NULL,   -- where the car sits
  `icon`        JSON        DEFAULT NULL,  -- where the E prompt floats
  UNIQUE KEY `uq_slot` (`template_id`, `slot_index`),
  CONSTRAINT `fk_slot_template` FOREIGN KEY (`template_id`)
    REFERENCES `cm_house_garage_templates`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
--  Properties now reference templates instead of carrying coords.
-- ============================================================

-- interior_template_id
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_houses'
             AND COLUMN_NAME='interior_template_id');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_houses` ADD COLUMN `interior_template_id` INT DEFAULT NULL AFTER `house_type`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- garage_template_id
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_houses'
             AND COLUMN_NAME='garage_template_id');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_houses` ADD COLUMN `garage_template_id` INT DEFAULT NULL AFTER `interior_template_id`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- vehicle_exit: where a car APPEARS outside after driving out of the garage.
-- Distinct from garage_coords, which is where you drive IN to store it.
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_houses'
             AND COLUMN_NAME='vehicle_exit');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_houses` ADD COLUMN `vehicle_exit` JSON DEFAULT NULL AFTER `helipad_coords`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- family_eligible: reserved now so cm-family never has to alter this table.
-- Apartments default to false, per spec 16.12.
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_houses'
             AND COLUMN_NAME='family_eligible');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_houses` ADD COLUMN `family_eligible` TINYINT(1) NOT NULL DEFAULT 1 AFTER `for_sale`',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- status: draft properties are not visible to players until published.
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_houses'
             AND COLUMN_NAME='status');
SET @s := IF(@c=0,
  "ALTER TABLE `cm_houses` ADD COLUMN `status` VARCHAR(16) NOT NULL DEFAULT 'published' AFTER `family_eligible`",
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- image / thumbnail, for the Phase 4 capture step.
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_houses'
             AND COLUMN_NAME='image_url');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_houses` ADD COLUMN `image_url` VARCHAR(255) DEFAULT NULL, ADD COLUMN `image_cam` JSON DEFAULT NULL',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ---------- FKs to templates ----------
SET @c := (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
           WHERE CONSTRAINT_SCHEMA=DATABASE() AND TABLE_NAME='cm_houses'
             AND CONSTRAINT_NAME='fk_house_interior_tpl');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_houses` ADD CONSTRAINT `fk_house_interior_tpl`
     FOREIGN KEY (`interior_template_id`)
     REFERENCES `cm_house_interior_templates`(`id`) ON DELETE RESTRICT',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

SET @c := (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
           WHERE CONSTRAINT_SCHEMA=DATABASE() AND TABLE_NAME='cm_houses'
             AND CONSTRAINT_NAME='fk_house_garage_tpl');
SET @s := IF(@c=0,
  'ALTER TABLE `cm_houses` ADD CONSTRAINT `fk_house_garage_tpl`
     FOREIGN KEY (`garage_template_id`)
     REFERENCES `cm_house_garage_templates`(`id`) ON DELETE RESTRICT',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ============================================================
--  Vehicle slot assignments  (Phase 3 uses these; the shape is fixed now
--  so Phase 3 does not have to alter a live table)
-- ============================================================
CREATE TABLE IF NOT EXISTS `cm_house_vehicle_slots` (
  `id`          INT AUTO_INCREMENT PRIMARY KEY,
  `house_id`    INT         NOT NULL,
  `slot_index`  INT         NOT NULL,
  `vehicle_id`  BIGINT      DEFAULT NULL,   -- cm-vehicles primary key
  `owner_class` VARCHAR(16) NOT NULL DEFAULT 'personal',  -- personal | family
  `state`       VARCHAR(16) NOT NULL DEFAULT 'EMPTY',
                -- EMPTY | ASSIGNED | SPAWNED_INSIDE | OUT | IMPOUNDED | BLOCKED
  `updated_at`  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY `uq_house_slot` (`house_id`, `slot_index`),
  -- One vehicle can occupy exactly ONE slot anywhere on the server. This is
  -- the duplicate-prevention the spec demands, enforced by the database
  -- rather than by remembering to check.
  UNIQUE KEY `uq_vehicle_once` (`vehicle_id`),
  INDEX `idx_slot_state` (`state`),
  CONSTRAINT `fk_vslot_house` FOREIGN KEY (`house_id`)
    REFERENCES `cm_houses`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
--  Access: keys, guests, and later family/org grants.
--  Replaces cm_house_keys, which could only express "has a key".
-- ============================================================
CREATE TABLE IF NOT EXISTS `cm_house_access` (
  `id`         INT AUTO_INCREMENT PRIMARY KEY,
  `house_id`   INT         NOT NULL,
  `cid`        INT         NOT NULL,
  `kind`       VARCHAR(16) NOT NULL DEFAULT 'key',   -- key | guest | staff
  `granted_by` INT         DEFAULT NULL,
  `expires_at` TIMESTAMP   NULL DEFAULT NULL,        -- NULL = permanent
  `created_at` TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_access` (`house_id`, `cid`, `kind`),
  INDEX `idx_access_cid` (`cid`),
  CONSTRAINT `fk_access_house` FOREIGN KEY (`house_id`)
    REFERENCES `cm_houses`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
--  Repair legacy rows.
--  owner_cid = 0 is TRUTHY in Lua, so an unowned house looked owned and the
--  Buy button never appeared. NULL is the only correct "nobody owns this".
-- ============================================================
UPDATE `cm_houses` SET `owner_cid` = NULL WHERE `owner_cid` IS NOT NULL AND `owner_cid` <= 0;
UPDATE `cm_houses` SET `for_sale` = 1 WHERE `owner_cid` IS NULL AND `for_sale` = 0;

-- Apartments are never family-eligible (spec 16.2).
UPDATE `cm_houses` SET `family_eligible` = 0 WHERE `house_type` = 'apartment';

SELECT 'cm-house migration 003 (templates) complete' AS status;
