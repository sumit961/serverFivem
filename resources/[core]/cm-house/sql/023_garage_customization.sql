-- ============================================================
-- cm-house | 023_garage_customization.sql
-- Stores per-house garage interior styling selections
-- (walls 1-5, floors 1-5, ceilings 1-5, default 1).
-- Safe to run repeatedly.
-- ============================================================

CREATE TABLE IF NOT EXISTS `cm_house_garage_customizations` (
  `house_id` INT NOT NULL PRIMARY KEY,
  `wall` TINYINT NOT NULL DEFAULT 1,
  `floor` TINYINT NOT NULL DEFAULT 1,
  `ceiling` TINYINT NOT NULL DEFAULT 1,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT `fk_garage_custom_house` FOREIGN KEY (`house_id`)
    REFERENCES `cm_houses`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

