-- Additive/idempotent five-gang catalog assignment. Apply before enabling the
-- vehicleadmin gang options. A catalog entry may belong to at most one gang.
ALTER TABLE `cm_vehicle_catalog`
  ADD COLUMN IF NOT EXISTS `gang_id` VARCHAR(16) NULL AFTER `legal_org`;
ALTER TABLE `cm_vehicle_catalog`
  ADD CONSTRAINT IF NOT EXISTS `chk_cm_vehicle_catalog_gang`
  CHECK (`gang_id` IS NULL OR `gang_id` IN ('marabunta','bloods','ballas','families','vagos'));
