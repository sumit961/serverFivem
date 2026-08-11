CREATE TABLE IF NOT EXISTS cm_vehicle_catalog (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    model VARCHAR(64) NOT NULL UNIQUE,
    label VARCHAR(100) NOT NULL,
    category VARCHAR(64) NOT NULL DEFAULT 'Custom',
    price INT NOT NULL DEFAULT 0,
    speed_kph INT NULL,
    trunk_level INT NOT NULL DEFAULT 1,
    available_store TINYINT(1) NOT NULL DEFAULT 0,
    available_server TINYINT(1) NOT NULL DEFAULT 0,
    available_ems TINYINT(1) NOT NULL DEFAULT 0,
    available_police TINYINT(1) NOT NULL DEFAULT 0,
    image VARCHAR(255) NULL,
    metadata LONGTEXT NULL,
    mods LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_category (category),
    INDEX idx_available_store (available_store),
    INDEX idx_available_server (available_server),
    INDEX idx_available_ems (available_ems),
    INDEX idx_available_police (available_police)
);

-- Safe reconciliation for catalogs populated by the old automatic runtime seed.
-- Preserve photographed/configured vehicles and unpublish only rows that have
-- never completed the admin photo workflow.
UPDATE cm_vehicle_catalog
SET available_store = 0,
    available_server = 0,
    available_ems = 0,
    available_police = 0
WHERE image IS NULL OR TRIM(image) = '';
