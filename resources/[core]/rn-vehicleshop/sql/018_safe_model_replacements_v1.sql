-- Safe rn-vehicleshop model replacement migration.
-- The resource also applies these changes idempotently at startup.

ALTER TABLE cm_vehicle_catalog
  ADD COLUMN IF NOT EXISTS legal_org VARCHAR(32) NULL,
  ADD COLUMN IF NOT EXISTS gang_id VARCHAR(16) NULL,
  ADD COLUMN IF NOT EXISTS retired TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS replacement_model VARCHAR(64) NULL;

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
