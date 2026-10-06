-- cm-gang forward migration: add the fifth fixed persistence slot.
--
-- gang_1..gang_4 retain their IDs and all existing membership/rank/leader
-- rows. The old named IDs are historical recovery rows and remain allowed by
-- the compatibility check; they are not part of the active Config.GangIds.

ALTER TABLE `cm_gangs`
  DROP CHECK `chk_cm_gangs_fixed_id`;

ALTER TABLE `cm_gangs`
  ADD CONSTRAINT `chk_cm_gangs_fixed_id` CHECK (`gang_id` IN
    ('gang_1','gang_2','gang_3','gang_4','gang_5',
     'marabunta','bloods','ballas','families','vagos'));

INSERT IGNORE INTO `cm_gangs` (`gang_id`, `display_name`, `short_tag`, `color`, `enabled`)
VALUES ('gang_5', 'Vagos', 'VAG', '#EAB308', 0);

INSERT IGNORE INTO `cm_gang_ranks` (`gang_id`, `tier`, `name`, `permissions`, `is_leader_rank`)
SELECT 'gang_5', seed.tier, seed.name, seed.permissions, seed.is_leader_rank
FROM (
  SELECT 100 tier, 'Leader' name, JSON_OBJECT('gang.view_members',true,'gang.manage_members',true,'gang.manage_ranks',true,'gang.manage_permissions',true,'gang.chat',true,'gang.vehicle',true,'gang.manage_vehicles',true,'gang.armory',true,'gang.manage_armory',true,'gang.stash',true,'gang.manage_stash',true,'gang.invite',true,'gang.view_logs',true) permissions, 1 is_leader_rank
  UNION ALL SELECT 80, 'Underboss', JSON_OBJECT('gang.view_members',true,'gang.manage_members',true,'gang.chat',true,'gang.vehicle',true,'gang.manage_vehicles',true,'gang.armory',true,'gang.manage_armory',true,'gang.stash',true,'gang.manage_stash',true,'gang.invite',true,'gang.view_logs',true), 0
  UNION ALL SELECT 60, 'Enforcer', JSON_OBJECT('gang.view_members',true,'gang.chat',true,'gang.vehicle',true,'gang.armory',true,'gang.stash',true,'gang.invite',true), 0
  UNION ALL SELECT 40, 'Member', JSON_OBJECT('gang.view_members',true,'gang.chat',true,'gang.vehicle',true,'gang.armory',true,'gang.stash',true), 0
  UNION ALL SELECT 20, 'Recruit', JSON_OBJECT('gang.view_members',true,'gang.chat',true), 0
) seed
WHERE NOT EXISTS (
  SELECT 1 FROM `cm_gang_ranks` existing
  WHERE existing.gang_id = 'gang_5' AND existing.tier = seed.tier
);

INSERT IGNORE INTO `cm_gang_facilities` (`gang_id`, `facility_type`, `enabled`)
VALUES ('gang_5','headquarters',0), ('gang_5','armory',0),
       ('gang_5','stash',0), ('gang_5','fleet',0);

INSERT IGNORE INTO `cm_gang_migrations` (`migration_id`)
VALUES ('003_cm_gang_five_gangs');
