-- cm-gunstore v1.1 ammo-linked weapons upgrade
-- Keeps ammo/gun/armor rows in cm_gun_catalog and syncs definitions into cm-items.

ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS damage INT NOT NULL DEFAULT 0 AFTER armor_value;
ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS stock INT NOT NULL DEFAULT -1 AFTER damage;
ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS component_id INT NULL AFTER sort_order;
ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS drawable_id INT NULL AFTER component_id;
ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS texture_id INT NOT NULL DEFAULT 0 AFTER drawable_id;
ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS gender VARCHAR(12) NOT NULL DEFAULT 'both' AFTER texture_id;
CREATE INDEX IF NOT EXISTS idx_cm_gun_catalog_type ON cm_gun_catalog (item_type);
CREATE INDEX IF NOT EXISTS idx_cm_gun_catalog_ammo_item ON cm_gun_catalog (ammo_item);
