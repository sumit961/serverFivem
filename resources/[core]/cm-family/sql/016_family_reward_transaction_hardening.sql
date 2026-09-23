-- ============================================================
-- cm-family | migration 016 | v1.8.1
-- Reward Transaction Hardening, Daily Financial Cap,
-- Objective Delivery State, and Concurrency Protections.
-- Non-destructive & safe for repeated execution.
-- ============================================================

CREATE TABLE IF NOT EXISTS `cm_family_contribution_daily` (
  `id`                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `family_id`          BIGINT UNSIGNED NOT NULL,
  `character_id`       VARCHAR(64) NOT NULL,
  `day_key`            VARCHAR(16) NOT NULL,
  `financial_points`   INT UNSIGNED NOT NULL DEFAULT 0,
  `money_contributed`  BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `updated_at`         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_fam_char_day` (`family_id`, `character_id`, `day_key`),
  KEY `idx_fcd_fam_day` (`family_id`, `day_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Add reward_state to cm_family_objective_progress for safe recovery
SET @c := (SELECT COUNT(*) FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='cm_family_objective_progress'
             AND COLUMN_NAME='reward_state');
SET @s := IF(@c=0,
  "ALTER TABLE `cm_family_objective_progress` ADD COLUMN `reward_state` VARCHAR(16) NOT NULL DEFAULT 'unclaimed' AFTER `completed`",
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- Ensure reward_state matches current reward_claimed state for existing rows
UPDATE `cm_family_objective_progress`
SET `reward_state` = IF(`reward_claimed` = 1, 'delivered', 'unclaimed')
WHERE `reward_state` = 'unclaimed' AND `reward_claimed` = 1;
