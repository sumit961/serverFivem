ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS damage INT NOT NULL DEFAULT 0 AFTER armor_value;
ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS stock INT NOT NULL DEFAULT -1 AFTER damage;

-- damage = per bullet damage used in item metadata.
-- stock = -1 unlimited, 0 out of stock, positive number limited stock.
