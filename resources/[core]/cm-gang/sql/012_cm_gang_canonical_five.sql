-- cm-gang forward-safe reconciliation for databases where 001/003 were
-- already applied. This migration never deletes or rewrites membership,
-- rank, leader, permission, or invitation rows.

SET @cm_gang_check_name := (
  SELECT tc.CONSTRAINT_NAME
  FROM information_schema.TABLE_CONSTRAINTS tc
  WHERE tc.CONSTRAINT_SCHEMA = DATABASE()
    AND tc.TABLE_NAME = 'cm_gangs'
    AND tc.CONSTRAINT_TYPE = 'CHECK'
  LIMIT 1
);
SET @cm_gang_drop_sql := IF(
  @cm_gang_check_name IS NULL,
  'SELECT 1',
  CONCAT('ALTER TABLE `cm_gangs` DROP CHECK `', REPLACE(@cm_gang_check_name, '`', '``'), '`')
);
PREPARE cm_gang_drop_check FROM @cm_gang_drop_sql;
EXECUTE cm_gang_drop_check;
DEALLOCATE PREPARE cm_gang_drop_check;

ALTER TABLE `cm_gangs`
  ADD CONSTRAINT `chk_cm_gangs_fixed_id` CHECK (`gang_id` IN
    ('gang_1','gang_2','gang_3','gang_4','gang_5',
     'marabunta','bloods','ballas','families','vagos'));

-- Convert only the original placeholder rows. Any identity customized by
-- cm-admin remains untouched; IDs and all relational history stay stable.
UPDATE `cm_gangs` SET `display_name`='Marabunta', `short_tag`='MAR', `color`='#2563EB'
 WHERE `gang_id`='gang_1' AND `display_name` IN ('Gang One','Gang 1');
UPDATE `cm_gangs` SET `display_name`='Bloods', `short_tag`='BLD', `color`='#EF4444'
 WHERE `gang_id`='gang_2' AND `display_name` IN ('Gang Two','Gang 2');
UPDATE `cm_gangs` SET `display_name`='Ballas', `short_tag`='BAL', `color`='#A855F7'
 WHERE `gang_id`='gang_3' AND `display_name` IN ('Gang Three','Gang 3');
UPDATE `cm_gangs` SET `display_name`='Families', `short_tag`='FAM', `color`='#22C55E'
 WHERE `gang_id`='gang_4' AND `display_name` IN ('Gang Four','Gang 4');

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
VALUES ('012_cm_gang_canonical_five');
