CREATE TABLE IF NOT EXISTS cm_gun_catalog (
    id INT NOT NULL AUTO_INCREMENT,
    item_name VARCHAR(80) NOT NULL,
    item_type VARCHAR(20) NOT NULL DEFAULT 'weapon',
    label VARCHAR(120) NOT NULL,
    weapon_hash VARCHAR(80) NULL,
    ammo_item VARCHAR(80) NULL,
    pack_size INT NOT NULL DEFAULT 1,
    armor_value INT NOT NULL DEFAULT 0,
    price INT NOT NULL DEFAULT 0,
    enabled TINYINT(1) NOT NULL DEFAULT 0,
    image VARCHAR(255) NULL,
    description VARCHAR(255) NULL,
    sort_order INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cm_gun_catalog_item_name (item_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE cm_gun_catalog ADD COLUMN IF NOT EXISTS armor_value INT NOT NULL DEFAULT 0;

INSERT INTO cm_gun_catalog (item_name,item_type,label,weapon_hash,ammo_item,pack_size,armor_value,price,enabled,image,description,sort_order) VALUES
('armor_light','armor','Light Armor Vest','','',1,35,1800,1,'nui://cm-gunstore/web/images/armor_light.svg','Light protection vest. Adds 35 armor when used.',200),
('armor_heavy','armor','Heavy Armor Vest','','',1,100,4500,0,'nui://cm-gunstore/web/images/armor_heavy.svg','Heavy tactical vest. Adds 100 armor when used.',210)
ON DUPLICATE KEY UPDATE item_type=VALUES(item_type), armor_value=VALUES(armor_value), image=IF(image IS NULL OR image='',VALUES(image),image), description=IF(description IS NULL OR description='',VALUES(description),description);
