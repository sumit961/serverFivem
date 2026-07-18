-- ============================================================
-- cm-house v1.7.27 | remember which interior a player was inside
-- Safe to run repeatedly.
--
-- A player who disconnects inside a house or garage returns to those exact
-- raw coordinates on rejoin (cm-playerdata/cm-spawn already do that), but
-- that alone is not enough: an 'ipl' interior only renders once RequestIpl
-- has run for this client, and the routing bucket that keeps the room
-- private to its occupants is gone the moment they drop. This table lets
-- cm-house replay "which interior, which kind" on characterLoaded so both
-- get restored before the player ever sees the room.
-- ============================================================

CREATE TABLE IF NOT EXISTS `cm_house_last_interior` (
  `cid`        INT         NOT NULL,
  `house_id`   INT         NOT NULL,
  `kind`       ENUM('house','garage') NOT NULL,
  `updated_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`cid`),
  INDEX `idx_last_interior_house` (`house_id`),
  CONSTRAINT `fk_last_interior_house` FOREIGN KEY (`house_id`)
    REFERENCES `cm_houses`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SELECT 'cm-house migration 019 complete' AS status;
