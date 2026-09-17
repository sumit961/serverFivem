-- Exam session bookkeeping: begin time, finish time and fail reasons long
-- enough to hold the constant strings. Portable across MySQL 8 and MariaDB.

SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_license_active_tests'
      AND COLUMN_NAME = 'test_began_at');
SET @sql := IF(@col = 0, 'ALTER TABLE cm_license_active_tests ADD COLUMN test_began_at BIGINT NULL AFTER test_started_at', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col := (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_license_active_tests'
      AND COLUMN_NAME = 'test_ended_at');
SET @sql := IF(@col = 0, 'ALTER TABLE cm_license_active_tests ADD COLUMN test_ended_at BIGINT NULL AFTER test_began_at', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Stale sessions left behind by an unclean shutdown before the startup sweep
-- existed. Safe to run repeatedly.
UPDATE cm_license_active_tests
   SET status = 'failed', fail_reason = 'server_restart', test_ended_at = UNIX_TIMESTAMP()
 WHERE status IN ('waiting_start', 'in_progress', 'completing');
