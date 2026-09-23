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
    legal_org VARCHAR(32) NULL,
    gang_id VARCHAR(16) NULL,
    retired TINYINT(1) NOT NULL DEFAULT 0,
    replacement_model VARCHAR(64) NULL,
    has_carplay TINYINT(1) NOT NULL DEFAULT 0,
    vehicle_type VARCHAR(8) NOT NULL DEFAULT 'land',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_category (category),
    INDEX idx_available_store (available_store),
    INDEX idx_available_server (available_server),
    INDEX idx_available_ems (available_ems),
    INDEX idx_available_police (available_police),
    INDEX idx_has_carplay (has_carplay),
    INDEX idx_vehicle_type (vehicle_type)
);

CREATE TABLE IF NOT EXISTS cm_vehicle_replacements (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    old_model VARCHAR(64) NOT NULL UNIQUE,
    new_model VARCHAR(64) NOT NULL,
    old_catalog LONGTEXT NULL,
    old_image VARCHAR(255) NULL,
    new_image VARCHAR(255) NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'applied',
    created_by VARCHAR(128) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    applied_at TIMESTAMP NULL,
    INDEX idx_replacement_new_model (new_model),
    INDEX idx_replacement_status (status)
);

CREATE TABLE IF NOT EXISTS cm_vehicle_replacement_pending (
    vehicle_id BIGINT PRIMARY KEY,
    replacement_id BIGINT NOT NULL,
    old_model VARCHAR(64) NOT NULL,
    new_model VARCHAR(64) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_pending_replacement (replacement_id),
    INDEX idx_pending_old_model (old_model)
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
