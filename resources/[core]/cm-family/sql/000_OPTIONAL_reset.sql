-- ============================================================
--  cm-family | OPTIONAL clean reset
--
--  Run this ONLY if you have no family data to preserve. It drops every
--  cm-family table so 001_cm_family.sql can recreate them correctly. This is
--  the simplest fix when a partial/stale cm_families table caused
--  "Unknown column 'tag'".
--
--  Order matters: children before parents (FKs), though DROP ... CASCADE-free
--  here relies on dropping child tables first.
-- ============================================================

DROP TABLE IF EXISTS `cm_family_bank_log`;
DROP TABLE IF EXISTS `cm_family_log`;
DROP TABLE IF EXISTS `cm_family_vehicle_access`;
DROP TABLE IF EXISTS `cm_family_invites`;
DROP TABLE IF EXISTS `cm_family_members`;
DROP TABLE IF EXISTS `cm_family_ranks`;
DROP TABLE IF EXISTS `cm_families`;

-- After running this, run 001_cm_family.sql again.
