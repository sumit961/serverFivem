-- cm-gang v0.3.0 | gang vehicle trunk minimum rank (additive, idempotent)

ALTER TABLE `cm_gang_fleet_vehicles`
  ADD COLUMN IF NOT EXISTS `trunk_minimum_tier` TINYINT UNSIGNED NOT NULL DEFAULT 1 AFTER `minimum_tier`;

INSERT IGNORE INTO `cm_gang_migrations` (`migration_id`) VALUES ('005_cm_gang_fleet_trunk');
