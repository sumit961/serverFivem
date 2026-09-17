-- cm-gang v0.3.0 | gang profit infrastructure (additive, idempotent)
-- Hourly tick + collection pool. activity_score/pending_amount default to
-- 0 and stay there until a future gang-activity/event system calls
-- AddGangProfitScore/AddGangProfit -- no invented payouts ship with this
-- migration.

CREATE TABLE IF NOT EXISTS `cm_gang_profit` (
  `gang_id` VARCHAR(16) NOT NULL,
  `activity_score` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `pending_amount` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `last_tick_at` TIMESTAMP NULL,
  `last_collected_at` TIMESTAMP NULL,
  `last_collected_by` VARCHAR(64) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`gang_id`),
  CONSTRAINT `fk_gang_profit_gang` FOREIGN KEY (`gang_id`) REFERENCES `cm_gangs` (`gang_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO `cm_gang_profit` (`gang_id`)
SELECT gang_id FROM `cm_gangs` WHERE gang_id IN ('marabunta','bloods','ballas','families','vagos');

INSERT IGNORE INTO `cm_gang_migrations` (`migration_id`) VALUES ('008_cm_gang_profit');
