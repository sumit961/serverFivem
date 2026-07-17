-- ============================================================
-- cm-house v1.7.0
-- Remove the retired per-house garage customization/settings system.
-- Multi-exit garage templates and physical car slots remain unchanged.
-- ============================================================

DROP TABLE IF EXISTS `cm_house_garage_customizations`;

SET @has_customization_point := (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'cm_house_garage_templates'
      AND COLUMN_NAME = 'customization_point'
);
SET @drop_customization_point := IF(
    @has_customization_point > 0,
    'ALTER TABLE `cm_house_garage_templates` DROP COLUMN `customization_point`',
    'SELECT 1'
);
PREPARE cm_house_stmt FROM @drop_customization_point;
EXECUTE cm_house_stmt;
DEALLOCATE PREPARE cm_house_stmt;

SET @has_customization_anchors := (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'cm_house_garage_templates'
      AND COLUMN_NAME = 'customization_anchors'
);
SET @drop_customization_anchors := IF(
    @has_customization_anchors > 0,
    'ALTER TABLE `cm_house_garage_templates` DROP COLUMN `customization_anchors`',
    'SELECT 1'
);
PREPARE cm_house_stmt FROM @drop_customization_anchors;
EXECUTE cm_house_stmt;
DEALLOCATE PREPARE cm_house_stmt;
