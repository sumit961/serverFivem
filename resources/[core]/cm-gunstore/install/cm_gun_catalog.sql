-- cm-gunstore v1.8.0 install schema
-- Gun/ammo definitions live in cm-weapons.
-- Gun-store weapon/ammo prices are config-only in shared/config.lua -> Config.StoreCatalog.

CREATE TABLE IF NOT EXISTS cm_gun_catalog (
    id INT NOT NULL AUTO_INCREMENT,
    item_name VARCHAR(80) NOT NULL,
    item_type VARCHAR(20) NOT NULL DEFAULT 'weapon',
    label VARCHAR(120) NOT NULL,
    weapon_hash VARCHAR(80) NULL,
    ammo_item VARCHAR(80) NULL,
    ammo_key VARCHAR(40) NULL,
    pickup_hash BIGINT NOT NULL DEFAULT 0,
    drop_model VARCHAR(80) NULL,
    pack_size INT NOT NULL DEFAULT 1,
    armor_value INT NOT NULL DEFAULT 0,
    damage INT NOT NULL DEFAULT 0,
    magazine_size INT NOT NULL DEFAULT 0,
    stock INT NOT NULL DEFAULT -1,
    price INT NOT NULL DEFAULT 0,
    enabled TINYINT(1) NOT NULL DEFAULT 0,
    image VARCHAR(255) NULL,
    description VARCHAR(255) NULL,
    sort_order INT NOT NULL DEFAULT 0,
    component_id INT NULL,
    drawable_id INT NULL,
    texture_id INT NOT NULL DEFAULT 0,
    gender VARCHAR(12) NOT NULL DEFAULT 'both',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cm_gun_catalog_item_name (item_name),
    INDEX idx_cm_gun_catalog_type (item_type),
    INDEX idx_cm_gun_catalog_enabled (enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Default armor only. Weapons and ammo auto-sync from Config.StoreCatalog + cm-weapons on resource start.
INSERT INTO cm_gun_catalog
    (item_name,item_type,label,weapon_hash,ammo_item,ammo_key,pickup_hash,drop_model,pack_size,armor_value,damage,magazine_size,stock,price,enabled,image,description,sort_order,component_id,drawable_id,texture_id,gender)
VALUES
    ('armor_light','armor','Light Armor Vest','','',NULL,0,NULL,1,50,0,0,-1,3500,1,'images/armor_light.svg','Standard light body armor vest.',500,9,NULL,0,'both')
ON DUPLICATE KEY UPDATE
    item_type=VALUES(item_type),
    label=VALUES(label),
    armor_value=VALUES(armor_value),
    price=VALUES(price),
    image=IF(image IS NULL OR image='',VALUES(image),image),
    description=VALUES(description),
    sort_order=VALUES(sort_order),
    component_id=VALUES(component_id),
    drawable_id=VALUES(drawable_id),
    texture_id=VALUES(texture_id),
    gender=VALUES(gender);
