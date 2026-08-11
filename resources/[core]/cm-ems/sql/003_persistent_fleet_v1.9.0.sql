ALTER TABLE `cm_ems_fleet_vehicles`
  ADD COLUMN IF NOT EXISTS `vehicle_id` BIGINT UNSIGNED NULL AFTER `model`;

SET @cm_ems_fleet_index = (
  SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_ems_fleet_vehicles'
    AND INDEX_NAME = 'uniq_cm_ems_fleet_vehicle_id'
);
SET @cm_ems_fleet_index_sql = IF(@cm_ems_fleet_index = 0,
  'CREATE UNIQUE INDEX `uniq_cm_ems_fleet_vehicle_id` ON `cm_ems_fleet_vehicles` (`vehicle_id`)',
  'SELECT 1');
PREPARE cm_ems_fleet_stmt FROM @cm_ems_fleet_index_sql;
EXECUTE cm_ems_fleet_stmt;
DEALLOCATE PREPARE cm_ems_fleet_stmt;
