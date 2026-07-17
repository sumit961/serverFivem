-- One shared overhead symbol for every member of a family.
-- Safe to run more than once on MariaDB/MySQL versions supporting IF NOT EXISTS.
ALTER TABLE `cm_families`
  ADD COLUMN IF NOT EXISTS `symbol` VARCHAR(16) NOT NULL DEFAULT 'shield' AFTER `color`;

