-- ============================================================
--  cm-family | 002 — reconcile cm_families columns
--
--  001 uses CREATE TABLE IF NOT EXISTS, so if an older/partial cm_families
--  table already existed the newer columns (tag, color, bank_balance) were
--  never added. This migration adds any missing columns without touching data.
--
--  Uses information_schema guards so it is safe to run repeatedly and on
--  MySQL/MariaDB versions without "ADD COLUMN IF NOT EXISTS".
-- ============================================================

DROP PROCEDURE IF EXISTS cm_family_add_col;
DELIMITER $$
CREATE PROCEDURE cm_family_add_col(
    IN tbl VARCHAR(64), IN col VARCHAR(64), IN ddl VARCHAR(255))
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = tbl AND COLUMN_NAME = col
    ) THEN
        SET @s = CONCAT('ALTER TABLE `', tbl, '` ADD COLUMN ', ddl);
        PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;
    END IF;
END $$
DELIMITER ;

CALL cm_family_add_col('cm_families', 'tag',          "`tag` VARCHAR(8) NULL AFTER `name`");
CALL cm_family_add_col('cm_families', 'color',        "`color` VARCHAR(9) NOT NULL DEFAULT '#00f0ff' AFTER `tag`");
CALL cm_family_add_col('cm_families', 'founder_cid',  "`founder_cid` VARCHAR(64) NOT NULL AFTER `color`");
CALL cm_family_add_col('cm_families', 'house_id',     "`house_id` INT UNSIGNED NULL AFTER `founder_cid`");
CALL cm_family_add_col('cm_families', 'bank_balance', "`bank_balance` BIGINT NOT NULL DEFAULT 0 AFTER `house_id`");
CALL cm_family_add_col('cm_families', 'created_at',   "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP");

DROP PROCEDURE IF EXISTS cm_family_add_col;
