-- ============================================================
-- cm-family v1.0.3 | id-less cm_family_members compatibility
--
-- Safe for existing data. It intentionally DOES NOT add or require an `id`
-- column on cm_family_members. Older schemas may use character_id or a
-- composite primary key, and cm-family does not query members.id.
-- ============================================================

CREATE TABLE IF NOT EXISTS `cm_family_members` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id`    BIGINT UNSIGNED NOT NULL,
  `character_id` VARCHAR(64) NOT NULL,
  `rank_id`      BIGINT UNSIGNED NOT NULL,
  `joined_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_member_character` (`character_id`),
  KEY `idx_member_family` (`family_id`),
  KEY `idx_member_rank` (`rank_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP PROCEDURE IF EXISTS cm_family_v103_add_col;
DELIMITER $$
CREATE PROCEDURE cm_family_v103_add_col(IN tbl VARCHAR(64), IN col VARCHAR(64), IN ddl VARCHAR(512))
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

-- family_id deliberately has no AFTER `id` clause.
CALL cm_family_v103_add_col('cm_family_members', 'family_id',
  "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0");
CALL cm_family_v103_add_col('cm_family_members', 'character_id',
  "`character_id` VARCHAR(64) NOT NULL DEFAULT '' AFTER `family_id`");
CALL cm_family_v103_add_col('cm_family_members', 'rank_id',
  "`rank_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `character_id`");
CALL cm_family_v103_add_col('cm_family_members', 'joined_at',
  "`joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP");

DROP PROCEDURE IF EXISTS cm_family_v103_add_col;

DROP PROCEDURE IF EXISTS cm_family_v103_add_index;
DELIMITER $$
CREATE PROCEDURE cm_family_v103_add_index(IN tbl VARCHAR(64), IN idx VARCHAR(64), IN ddl VARCHAR(512))
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = tbl AND INDEX_NAME = idx
  ) THEN
    SET @s = CONCAT('ALTER TABLE `', tbl, '` ADD ', ddl);
    PREPARE stmt FROM @s; EXECUTE stmt; DEALLOCATE PREPARE stmt;
  END IF;
END $$
DELIMITER ;

CALL cm_family_v103_add_index('cm_family_members', 'uniq_member_character',
  'UNIQUE KEY `uniq_member_character` (`character_id`)');
CALL cm_family_v103_add_index('cm_family_members', 'idx_member_family',
  'KEY `idx_member_family` (`family_id`)');
CALL cm_family_v103_add_index('cm_family_members', 'idx_member_rank',
  'KEY `idx_member_rank` (`rank_id`)');

DROP PROCEDURE IF EXISTS cm_family_v103_add_index;
