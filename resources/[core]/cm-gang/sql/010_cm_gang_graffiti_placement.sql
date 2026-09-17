-- cm-gang | persistent wall-space transform for admin graffiti placement
ALTER TABLE `cm_gang_graffiti`
  ADD COLUMN IF NOT EXISTS `normal_x` FLOAT NULL AFTER `heading`,
  ADD COLUMN IF NOT EXISTS `normal_y` FLOAT NULL AFTER `normal_x`,
  ADD COLUMN IF NOT EXISTS `normal_z` FLOAT NULL AFTER `normal_y`,
  ADD COLUMN IF NOT EXISTS `up_x` FLOAT NULL AFTER `normal_z`,
  ADD COLUMN IF NOT EXISTS `up_y` FLOAT NULL AFTER `up_x`,
  ADD COLUMN IF NOT EXISTS `up_z` FLOAT NULL AFTER `up_y`,
  ADD COLUMN IF NOT EXISTS `rotation` FLOAT NOT NULL DEFAULT 0 AFTER `up_z`,
  ADD COLUMN IF NOT EXISTS `placement_ready` TINYINT(1) NOT NULL DEFAULT 0 AFTER `height`;

INSERT IGNORE INTO `cm_gang_migrations` (`migration_id`) VALUES ('010_cm_gang_graffiti_placement');
