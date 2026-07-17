-- cm-family v1.1.0
-- Non-destructive family tag/member-title compatibility migration.

ALTER TABLE `cm_families`
  ADD COLUMN IF NOT EXISTS `tag_visible` TINYINT(1) NOT NULL DEFAULT 1 AFTER `color`;

ALTER TABLE `cm_family_members`
  ADD COLUMN IF NOT EXISTS `custom_title` VARCHAR(24) NULL AFTER `rank_id`,
  ADD COLUMN IF NOT EXISTS `tag_hidden` TINYINT(1) NOT NULL DEFAULT 0 AFTER `custom_title`;
