-- cm-gunstore v1.2: gun/ammo definitions are now managed by cm-weapons.
-- This table only stores shop price, stock, and store visibility.

ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS ammo_key VARCHAR(40) NULL AFTER ammo_item;
ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS pickup_hash BIGINT NOT NULL DEFAULT 0 AFTER ammo_key;
ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS drop_model VARCHAR(80) NULL AFTER pickup_hash;
ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS magazine_size INT NOT NULL DEFAULT 0 AFTER damage;
CREATE INDEX IF NOT EXISTS idx_cm_gun_catalog_enabled ON cm_gun_catalog (enabled);
