ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS component_id INT NULL AFTER sort_order;
ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS drawable_id INT NULL AFTER component_id;
ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS texture_id INT NOT NULL DEFAULT 0 AFTER drawable_id;
ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS gender VARCHAR(12) NOT NULL DEFAULT 'both' AFTER texture_id;

-- Wearable armor vests use GTA component 9.
-- Example:
-- UPDATE cm_gun_catalog SET component_id=9, drawable_id=12, texture_id=0, gender='male' WHERE item_name='armor_heavy';
