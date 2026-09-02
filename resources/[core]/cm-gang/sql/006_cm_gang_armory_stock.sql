-- cm-gang v0.3.0 | real shared armory stock pool (additive, idempotent)
-- Checkout decrements stock_quantity; deposit and the future
-- AddGangArmoryStock export increment it. issue_limit (existing column)
-- remains as an optional additional per-member cap.

ALTER TABLE `cm_gang_armory_config`
  ADD COLUMN IF NOT EXISTS `stock_quantity` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `issue_limit`;

ALTER TABLE `cm_gang_armory_issues`
  MODIFY COLUMN `status` ENUM('issued','void','returned') NOT NULL DEFAULT 'issued';

INSERT IGNORE INTO `cm_gang_migrations` (`migration_id`) VALUES ('006_cm_gang_armory_stock');
