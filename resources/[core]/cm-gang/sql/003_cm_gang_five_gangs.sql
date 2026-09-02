-- cm-gang v0.3.0 | five canonical gangs (additive, idempotent)
-- Adds Marabunta/Bloods/Ballas/Families/Vagos as new, separate cm_gangs rows.
-- The legacy gang_1..gang_4 rows, and everything belonging to them
-- (members, ranks, invites, activity, facilities, fleet, armory), are left
-- completely untouched by this migration. Use cm-admin's "Legacy Gang
-- Migration" action if you need to move a legacy gang's state onto one of
-- the five canonical ids -- nothing here does that automatically, because
-- no safe automatic mapping exists.
-- Assumes MariaDB (IF EXISTS/IF NOT EXISTS on constraints), matching the
-- MariaDB-specific syntax already relied on elsewhere in this codebase
-- (see cm-family's ADD COLUMN IF NOT EXISTS migrations).

ALTER TABLE `cm_gangs` DROP CONSTRAINT IF EXISTS `chk_cm_gangs_fixed_id`;
ALTER TABLE `cm_gangs` ADD CONSTRAINT IF NOT EXISTS `chk_cm_gangs_fixed_id`
  CHECK (`gang_id` IN ('gang_1','gang_2','gang_3','gang_4','marabunta','bloods','ballas','families','vagos'));

-- Widen the facility type enum to add the dedicated Profit Collector NPC
-- facility, alongside the existing headquarters/armory/stash/fleet types.
-- MODIFY COLUMN is naturally idempotent (safe to rerun).
ALTER TABLE `cm_gang_facilities`
  MODIFY COLUMN `facility_type` ENUM('headquarters','armory','stash','fleet','profit') NOT NULL;

INSERT IGNORE INTO `cm_gangs` (`gang_id`, `display_name`, `short_tag`, `color`, `enabled`) VALUES
  ('marabunta', 'Marabunta', 'MRB', '#2563eb', 0),
  ('bloods',    'Bloods',    'BLD', '#ef4444', 0),
  ('ballas',    'Ballas',    'BAL', '#a855f7', 0),
  ('families',  'Families',  'FAM', '#22c55e', 0),
  ('vagos',     'Vagos',     'VGS', '#eab308', 0);

INSERT IGNORE INTO `cm_gang_ranks` (`gang_id`, `tier`, `name`, `permissions`, `is_leader_rank`)
SELECT g.gang_id, seed.tier, seed.name, seed.permissions, seed.is_leader_rank
FROM `cm_gangs` g
CROSS JOIN (
  SELECT 100 tier, 'Leader' name, JSON_OBJECT(
      'gang.view_members',true,'gang.manage_members',true,'gang.manage_ranks',true,
      'gang.manage_permissions',true,'gang.chat',true,'gang.vehicle',true,
      'gang.vehicle_trunk',true,'gang.manage_vehicles',true,'gang.armory',true,
      'gang.armory_deposit',true,'gang.manage_armory',true,'gang.wardrobe',true,
      'gang.stash',true,'gang.manage_stash',true,'gang.invite',true,'gang.search',true,
      'gang.rob_cash',true,'gang.rob_items',true,'gang.view_map',true,
      'gang.set_meeting_point',true,'gang.blacklist',true,'gang.manage_blacklist',true,
      'gang.collect_profit',true,'gang.view_logs',true
    ) permissions, 1 is_leader_rank
  UNION ALL SELECT 80, 'Underboss', JSON_OBJECT(
      'gang.view_members',true,'gang.manage_members',true,'gang.manage_ranks',true,
      'gang.chat',true,'gang.vehicle',true,'gang.vehicle_trunk',true,
      'gang.manage_vehicles',true,'gang.armory',true,'gang.armory_deposit',true,
      'gang.manage_armory',true,'gang.wardrobe',true,'gang.stash',true,
      'gang.manage_stash',true,'gang.invite',true,'gang.search',true,'gang.rob_cash',true,
      'gang.rob_items',true,'gang.view_map',true,'gang.set_meeting_point',true,
      'gang.blacklist',true,'gang.manage_blacklist',true,'gang.collect_profit',true,
      'gang.view_logs',true
    ), 0
  UNION ALL SELECT 60, 'Shot Caller', JSON_OBJECT(
      'gang.view_members',true,'gang.chat',true,'gang.vehicle',true,
      'gang.vehicle_trunk',true,'gang.armory',true,'gang.armory_deposit',true,
      'gang.wardrobe',true,'gang.stash',true,'gang.manage_stash',true,'gang.invite',true,
      'gang.search',true,'gang.rob_cash',true,'gang.rob_items',true,'gang.view_map',true,
      'gang.set_meeting_point',true,'gang.blacklist',true,'gang.collect_profit',true,
      'gang.view_logs',true
    ), 0
  UNION ALL SELECT 40, 'Enforcer', JSON_OBJECT(
      'gang.view_members',true,'gang.chat',true,'gang.vehicle',true,
      'gang.vehicle_trunk',true,'gang.armory',true,'gang.armory_deposit',true,
      'gang.wardrobe',true,'gang.stash',true,'gang.invite',true,'gang.search',true,
      'gang.rob_cash',true,'gang.rob_items',true,'gang.view_map',true
    ), 0
  UNION ALL SELECT 20, 'Member', JSON_OBJECT(
      'gang.view_members',true,'gang.chat',true,'gang.vehicle',true,
      'gang.vehicle_trunk',true,'gang.armory',true,'gang.wardrobe',true,
      'gang.stash',true,'gang.search',true,'gang.view_map',true
    ), 0
  UNION ALL SELECT 10, 'Prospect', JSON_OBJECT(
      'gang.view_members',true,'gang.chat',true,'gang.stash',true
    ), 0
) seed
WHERE g.gang_id IN ('marabunta','bloods','ballas','families','vagos')
  AND NOT EXISTS (SELECT 1 FROM `cm_gang_ranks` existing WHERE existing.gang_id = g.gang_id);

INSERT IGNORE INTO `cm_gang_facilities` (`gang_id`, `facility_type`, `enabled`)
SELECT g.gang_id, types.facility_type, 0
FROM `cm_gangs` g
CROSS JOIN (
  SELECT 'headquarters' facility_type UNION ALL SELECT 'armory'
  UNION ALL SELECT 'stash' UNION ALL SELECT 'fleet' UNION ALL SELECT 'profit'
) types
WHERE g.gang_id IN ('marabunta','bloods','ballas','families','vagos');

-- Legacy gangs predate the 'profit' facility type; give them a row too so
-- schema validation and cm-admin can treat all gang ids uniformly. Never
-- overwrites an existing row.
INSERT IGNORE INTO `cm_gang_facilities` (`gang_id`, `facility_type`, `enabled`)
SELECT g.gang_id, 'profit', 0
FROM `cm_gangs` g
WHERE g.gang_id IN ('gang_1','gang_2','gang_3','gang_4');

INSERT IGNORE INTO `cm_gang_migrations` (`migration_id`) VALUES ('003_cm_gang_five_gangs');
