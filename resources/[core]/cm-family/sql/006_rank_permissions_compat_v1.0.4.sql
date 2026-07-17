-- ============================================================
-- cm-family v1.0.4 | legacy rank permission compatibility
--
-- Runtime v1.0.4 already detects and dual-writes an old `perms` column.
-- This optional migration only copies valid legacy JSON into `permissions`
-- where the current value is missing/invalid. It does not drop either column.
-- ============================================================

DROP PROCEDURE IF EXISTS cm_family_repair_rank_permissions;
DELIMITER $$
CREATE PROCEDURE cm_family_repair_rank_permissions()
BEGIN
    DECLARE has_permissions INT DEFAULT 0;
    DECLARE has_perms INT DEFAULT 0;

    SELECT COUNT(*) INTO has_permissions
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'cm_family_ranks'
       AND COLUMN_NAME = 'permissions';

    SELECT COUNT(*) INTO has_perms
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'cm_family_ranks'
       AND COLUMN_NAME = 'perms';

    IF has_permissions = 1 AND has_perms = 1 THEN
        SET @cm_family_sql = CONCAT(
            'UPDATE `cm_family_ranks` ',
            'SET `permissions` = `perms` ',
            'WHERE `perms` IS NOT NULL AND JSON_VALID(`perms`) = 1 ',
            'AND (`permissions` IS NULL OR JSON_VALID(`permissions`) = 0)'
        );
        PREPARE cm_family_stmt FROM @cm_family_sql;
        EXECUTE cm_family_stmt;
        DEALLOCATE PREPARE cm_family_stmt;
    END IF;
END $$
DELIMITER ;

CALL cm_family_repair_rank_permissions();
DROP PROCEDURE IF EXISTS cm_family_repair_rank_permissions;
