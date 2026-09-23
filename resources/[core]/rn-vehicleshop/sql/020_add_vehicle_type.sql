-- Adds a catalog vehicle type so the single dealership resource can route
-- vehicles into the correct storefront:
--   'land' = the car showroom (default)
--   'boat' = the boat dealer
--   'air'  = the air transport dealer (helicopters + planes)
-- The type is auto-detected from the vehicle's GTA class at admin capture/save
-- time (class 14 = boat, 15/16 = aircraft), so no manual admin step is needed.

ALTER TABLE cm_vehicle_catalog
    ADD COLUMN IF NOT EXISTS vehicle_type VARCHAR(8) NOT NULL DEFAULT 'land' AFTER has_carplay;

ALTER TABLE cm_vehicle_catalog
    ADD INDEX IF NOT EXISTS idx_vehicle_type (vehicle_type);
