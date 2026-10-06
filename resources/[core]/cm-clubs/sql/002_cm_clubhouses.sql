-- cm-clubs V1 physical clubhouse configuration.
-- Apply through the normal migration process; the resource never runs this file.
-- Information-schema guards keep this repeatable on MySQL/MariaDB versions
-- without relying on ADD COLUMN IF NOT EXISTS support.

DROP PROCEDURE IF EXISTS cm_clubs_add_col;
DELIMITER $$
CREATE PROCEDURE cm_clubs_add_col(IN tbl VARCHAR(64), IN col VARCHAR(64), IN ddl VARCHAR(255))
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = tbl AND COLUMN_NAME = col
    ) THEN
        SET @cm_clubs_sql = CONCAT('ALTER TABLE `', tbl, '` ADD COLUMN ', ddl);
        PREPARE cm_clubs_stmt FROM @cm_clubs_sql;
        EXECUTE cm_clubs_stmt;
        DEALLOCATE PREPARE cm_clubs_stmt;
    END IF;
END $$
DELIMITER ;

CALL cm_clubs_add_col('cm_clubs', 'clubhouse_enabled', "`clubhouse_enabled` TINYINT(1) NOT NULL DEFAULT 0");
CALL cm_clubs_add_col('cm_clubs', 'clubhouse_x', "`clubhouse_x` DECIMAL(10,4) NULL");
CALL cm_clubs_add_col('cm_clubs', 'clubhouse_y', "`clubhouse_y` DECIMAL(10,4) NULL");
CALL cm_clubs_add_col('cm_clubs', 'clubhouse_z', "`clubhouse_z` DECIMAL(10,4) NULL");
CALL cm_clubs_add_col('cm_clubs', 'clubhouse_heading', "`clubhouse_heading` DECIMAL(7,3) NULL");
CALL cm_clubs_add_col('cm_clubs', 'clubhouse_npc_model', "`clubhouse_npc_model` VARCHAR(64) NULL");
CALL cm_clubs_add_col('cm_clubs', 'clubhouse_display_name', "`clubhouse_display_name` VARCHAR(64) NULL");
CALL cm_clubs_add_col('cm_clubs', 'clubhouse_interaction_label', "`clubhouse_interaction_label` VARCHAR(64) NULL");
CALL cm_clubs_add_col('cm_clubs', 'clubhouse_interaction_distance', "`clubhouse_interaction_distance` DECIMAL(5,2) NULL");
CALL cm_clubs_add_col('cm_clubs', 'clubhouse_routing_bucket', "`clubhouse_routing_bucket` INT NULL");

DROP PROCEDURE IF EXISTS cm_clubs_add_col;
