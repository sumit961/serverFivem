-- ============================================================
--  cm-house | Migration 005
--  Features drive everything.
--
--  The admin no longer picks an interior and a garage independently. They
--  declare WHAT THE PROPERTY IS -- type, garden, pool, helipad -- and the
--  interior set, garage size, star rating and price all derive from that.
--
--  Templates are keyed by the feature signature. Build the first
--  "house+garden+pool" and you walk its interior once; every later property
--  with the same signature reuses it silently, forever.
--
--  Safe to run repeatedly.
-- ============================================================

-- ---------- Property features ----------
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_houses' AND COLUMN_NAME='has_garden');
SET @s := IF(@c=0,
 'ALTER TABLE `cm_houses`
    ADD COLUMN `has_garden`  TINYINT(1) NOT NULL DEFAULT 0 AFTER `house_type`,
    ADD COLUMN `has_pool`    TINYINT(1) NOT NULL DEFAULT 0 AFTER `has_garden`,
    ADD COLUMN `has_helipad` TINYINT(1) NOT NULL DEFAULT 0 AFTER `has_pool`,
    ADD COLUMN `star_rating` TINYINT    NOT NULL DEFAULT 1 AFTER `has_helipad`',
 'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ---------- The camera that frames the property ----------
-- No PNG is ever written. We store where the camera stood and re-render the
-- view live whenever the menu opens: nothing to host, nothing to break.
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_houses' AND COLUMN_NAME='photo_cam');
SET @s := IF(@c=0,
 'ALTER TABLE `cm_houses` ADD COLUMN `photo_cam` JSON DEFAULT NULL',
 'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ============================================================
--  Interior templates keyed by FEATURE SIGNATURE.
--  signature = "house|garden|pool"  -- sorted, so it is stable.
--  Look up by signature: hit means reuse, miss means walk it once.
-- ============================================================
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_interior_templates'
             AND COLUMN_NAME='signature');
SET @s := IF(@c=0,
 'ALTER TABLE `cm_house_interior_templates`
    ADD COLUMN `signature` VARCHAR(64) DEFAULT NULL AFTER `label`,
    ADD INDEX `idx_signature` (`signature`)',
 'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ============================================================
--  Garage templates keyed by CAPACITY.
--  Seven slots means seven positions someone parked at. The size is the key:
--  build a 7-car garage once, and every later 7-car property reuses it.
-- ============================================================
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_house_garage_templates'
             AND COLUMN_NAME='is_default');
SET @s := IF(@c=0,
 'ALTER TABLE `cm_house_garage_templates`
    ADD COLUMN `is_default` TINYINT(1) NOT NULL DEFAULT 1 AFTER `capacity`,
    ADD INDEX `idx_capacity` (`capacity`, `is_default`)',
 'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- ============================================================
--  Feature-driven pricing and rating.
--  Editable in-game through the admin panel rather than hardcoded in Lua.
-- ============================================================
CREATE TABLE IF NOT EXISTS `cm_house_pricing` (
  `id`            INT AUTO_INCREMENT PRIMARY KEY,
  `feature_key`   VARCHAR(32) NOT NULL,
  `label`         VARCHAR(48) NOT NULL,
  `price_add`     INT NOT NULL DEFAULT 0,
  `star_add`      TINYINT NOT NULL DEFAULT 0,
  `garage_min`    TINYINT NOT NULL DEFAULT 0,   -- forces at least this many slots
  UNIQUE KEY `uq_feature` (`feature_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `cm_house_pricing` (`feature_key`,`label`,`price_add`,`star_add`,`garage_min`) VALUES
  ('type_trailer',   'Trailer',        40000,  0, 0),
  ('type_apartment', 'Apartment',     120000,  0, 0),
  ('type_house',     'House',         250000,  1, 0),
  ('type_villa',     'Villa',         600000,  2, 0),
  ('type_mansion',   'Mansion',      1200000,  3, 0),
  ('garden',         'Garden',         80000,  0, 0),
  ('pool',           'Swimming pool', 150000,  0, 0),
  ('helipad',        'Helipad',       400000,  0, 0)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

-- ---------- Garage sizes ----------
CREATE TABLE IF NOT EXISTS `cm_house_garage_sizes` (
  `capacity`   TINYINT PRIMARY KEY,
  `label`      VARCHAR(32) NOT NULL,
  `price_add`  INT NOT NULL DEFAULT 0,
  `selectable` TINYINT(1) NOT NULL DEFAULT 1   -- 14 and 24 are upgrades, not choices
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `cm_house_garage_sizes` (`capacity`,`label`,`price_add`,`selectable`) VALUES
  (1,  '1 car',            25000, 1),
  (2,  '2 cars',           50000, 1),
  (3,  '3 cars',           80000, 1),
  (4,  '4 cars',          120000, 1),
  (7,  '7 cars',          250000, 1),
  (14, '14 cars',         600000, 0),   -- upgrade only
  (24, '24 cars',        1200000, 0)    -- upgrade only
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `selectable` = VALUES(`selectable`);

-- ============================================================
--  Backfill: give existing rows a rating so nothing reads as 0 stars.
-- ============================================================
UPDATE `cm_houses` SET `star_rating` = 1 WHERE `star_rating` = 0 OR `star_rating` IS NULL;
UPDATE `cm_houses` SET `has_helipad` = 1 WHERE `helipad_coords` IS NOT NULL;

SELECT 'cm-house migration 005 (features) complete' AS status;
