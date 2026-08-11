CREATE TABLE IF NOT EXISTS `cm_ems_migrations` (
  `migration_key` VARCHAR(64) NOT NULL,
  `applied_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`migration_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET @cm_ems_chief_permissions = (
  SELECT `permissions` FROM `cm_ems_ranks`
  WHERE `name` = 'Chief Paramedic' AND `is_leader` = 0 LIMIT 1
);

UPDATE `cm_ems_ranks`
SET `permissions` = JSON_ARRAY_APPEND(
  CASE WHEN JSON_VALID(@cm_ems_chief_permissions) THEN @cm_ems_chief_permissions ELSE JSON_ARRAY() END,
  '$', 'ems.manage_ranks', '$', 'ems.manage_permissions'
)
WHERE `name` = 'Chief Paramedic'
  AND `is_leader` = 0
  AND NOT EXISTS (
    SELECT 1 FROM `cm_ems_migrations` WHERE `migration_key` = 'v1.1_chief_rank_management'
  );

INSERT IGNORE INTO `cm_ems_migrations` (`migration_key`) VALUES ('v1.1_chief_rank_management');
