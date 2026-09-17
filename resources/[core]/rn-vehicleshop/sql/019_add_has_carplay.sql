-- CarPlay availability flag, set per catalog model from Manage Vehicles.
-- The resource also applies this idempotently at startup (ensureColumn in server.lua).

ALTER TABLE cm_vehicle_catalog
  ADD COLUMN IF NOT EXISTS has_carplay TINYINT(1) NOT NULL DEFAULT 0;

ALTER TABLE cm_vehicle_catalog
  ADD INDEX IF NOT EXISTS idx_has_carplay (has_carplay);
