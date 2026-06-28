CREATE TABLE IF NOT EXISTS cm_vehicle_catalog (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    model VARCHAR(64) NOT NULL UNIQUE,
    label VARCHAR(100) NOT NULL,
    category VARCHAR(64) NOT NULL DEFAULT 'Custom',
    price INT NOT NULL DEFAULT 0,
    trunk_level INT NOT NULL DEFAULT 1,
    available_store TINYINT(1) NOT NULL DEFAULT 0,
    available_server TINYINT(1) NOT NULL DEFAULT 0,
    image VARCHAR(255) NULL,
    metadata LONGTEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_category (category),
    INDEX idx_available_store (available_store),
    INDEX idx_available_server (available_server)
);
