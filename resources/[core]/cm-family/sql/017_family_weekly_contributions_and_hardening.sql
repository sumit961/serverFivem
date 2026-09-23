-- ============================================================
-- cm-family | 017_family_weekly_contributions_and_hardening.sql | v1.8.2
-- Safe, additive migration for weekly contribution tracking and
-- crash-recoverable objective processing.
-- ============================================================

-- 1. Weekly contribution tracking table
CREATE TABLE IF NOT EXISTS `cm_family_contribution_weekly` (
  `family_id`          INT UNSIGNED NOT NULL,
  `character_id`       VARCHAR(64) NOT NULL,
  `week_key`           VARCHAR(16) NOT NULL,
  `total_points`       INT NOT NULL DEFAULT 0,
  `activity_points`    INT NOT NULL DEFAULT 0,
  `financial_points`   INT NOT NULL DEFAULT 0,
  `event_points`       INT NOT NULL DEFAULT 0,
  `updated_at`         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`family_id`, `character_id`, `week_key`),
  KEY `idx_contrib_week_family` (`family_id`, `week_key`),
  KEY `idx_contrib_week_char` (`character_id`, `week_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 2. Add reward_processing_at timestamp column for crash recovery
SET @exist_processing_at = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'cm_family_objective_progress'
    AND COLUMN_NAME = 'reward_processing_at'
);

SET @stmt_processing_at = IF(@exist_processing_at = 0,
  'ALTER TABLE `cm_family_objective_progress` ADD COLUMN `reward_processing_at` TIMESTAMP NULL DEFAULT NULL AFTER `reward_state`',
  'SELECT 1'
);

PREPARE exec_stmt FROM @stmt_processing_at;
EXECUTE exec_stmt;
DEALLOCATE PREPARE exec_stmt;
