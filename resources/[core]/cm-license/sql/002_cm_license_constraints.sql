-- CM License System -- constraint correction for installations created by v1.
-- Portable across MySQL 8 and MariaDB (no DDL "IF [NOT] EXISTS" on indexes,
-- no DELIMITER blocks). Review duplicate character/type rows before applying
-- to a populated database:
--   SELECT character_id, license_type_id, COUNT(*) c FROM cm_character_licenses
--   GROUP BY character_id, license_type_id HAVING c > 1;

-- Drop the old three-column unique index if it is still present.
SET @idx := (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_character_licenses'
      AND INDEX_NAME = 'unique_character_active_license');
SET @sql := IF(@idx > 0, 'ALTER TABLE cm_character_licenses DROP INDEX unique_character_active_license', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- One authoritative row per character/type; renewals update that row.
SET @idx := (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_character_licenses'
      AND INDEX_NAME = 'unique_character_license');
SET @sql := IF(@idx = 0, 'ALTER TABLE cm_character_licenses ADD UNIQUE INDEX unique_character_license (character_id, license_type_id)', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Active tests must not be uniquely constrained: a character retakes a test.
SET @idx := (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_license_active_tests'
      AND INDEX_NAME = 'unique_active_test');
SET @sql := IF(@idx > 0, 'ALTER TABLE cm_license_active_tests DROP INDEX unique_active_test', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
