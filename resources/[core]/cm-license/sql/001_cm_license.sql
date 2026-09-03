-- CM License System — Database Schema Migration
-- Version: 1
-- Created: 2026-09-01

-- License Types: Admin-configured test types (Driver, Boat, Air, etc)
CREATE TABLE IF NOT EXISTS cm_license_types (
    id INT PRIMARY KEY AUTO_INCREMENT,
    license_type VARCHAR(50) UNIQUE NOT NULL COMMENT 'driver, boat, air, etc',
    label VARCHAR(100) NOT NULL COMMENT 'Display name',
    item_name VARCHAR(50) NOT NULL COMMENT 'Inventory item name',
    price INT NOT NULL COMMENT 'Test fee in dollars',
    valid_days INT NOT NULL DEFAULT 30 COMMENT 'License validity period',
    vehicle_model VARCHAR(50) COMMENT 'GTA model name',
    vehicle_category VARCHAR(20) COMMENT 'ground, boat, air',
    npc_model VARCHAR(50) COMMENT 'NPC model name',
    npc_coords JSON COMMENT 'NPC spawn: {x, y, z, heading}',
    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_license_type (license_type),
    INDEX idx_enabled (enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Routes: Test routes created by admins
CREATE TABLE IF NOT EXISTS cm_license_routes (
    id INT PRIMARY KEY AUTO_INCREMENT,
    license_type_id INT NOT NULL,
    vehicle_spawn JSON NOT NULL COMMENT 'Vehicle spawn: {x, y, z, heading}',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id) ON DELETE CASCADE,
    UNIQUE KEY unique_route_per_type (license_type_id),
    INDEX idx_license_type_id (license_type_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Checkpoints: Individual route waypoints
CREATE TABLE IF NOT EXISTS cm_license_checkpoints (
    id INT PRIMARY KEY AUTO_INCREMENT,
    route_id INT NOT NULL,
    sequence INT NOT NULL COMMENT 'Order in route (1-based)',
    point_type ENUM('start', 'checkpoint', 'finish') NOT NULL DEFAULT 'checkpoint',
    x FLOAT NOT NULL,
    y FLOAT NOT NULL,
    z FLOAT NOT NULL,
    heading FLOAT COMMENT 'Vehicle heading at checkpoint',
    radius FLOAT NOT NULL DEFAULT 20.0 COMMENT 'Entry radius in meters',
    max_speed INT COMMENT 'Speed limit (km/h, null = no limit)',
    min_altitude INT COMMENT 'Minimum altitude for air tests',
    max_altitude INT COMMENT 'Maximum altitude for air tests',
    metadata JSON COMMENT 'Extra checkpoint config',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (route_id) REFERENCES cm_license_routes(id) ON DELETE CASCADE,
    UNIQUE KEY unique_route_sequence (route_id, sequence),
    INDEX idx_route_id (route_id),
    INDEX idx_point_type (point_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Character Licenses: Player license records
CREATE TABLE IF NOT EXISTS cm_character_licenses (
    id INT PRIMARY KEY AUTO_INCREMENT,
    character_id INT NOT NULL COMMENT 'Character database ID',
    license_type_id INT NOT NULL,
    issued_at BIGINT NOT NULL COMMENT 'Unix timestamp when issued',
    expires_at BIGINT NOT NULL COMMENT 'Unix timestamp when expires',
    status ENUM('active', 'expired', 'revoked') NOT NULL DEFAULT 'active',
    revoked_at BIGINT COMMENT 'When revoked (unix timestamp)',
    revoked_by INT COMMENT 'Admin character ID who revoked',
    revoke_reason VARCHAR(255) COMMENT 'Reason for revocation',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id) ON DELETE RESTRICT,
    -- Ensure one active license per character per type
    UNIQUE KEY unique_character_active_license (character_id, license_type_id, status),
    INDEX idx_character_id (character_id),
    INDEX idx_license_type_id (license_type_id),
    INDEX idx_expires_at (expires_at),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Active Test Sessions: Track ongoing exams
CREATE TABLE IF NOT EXISTS cm_license_active_tests (
    id INT PRIMARY KEY AUTO_INCREMENT,
    character_id INT NOT NULL,
    license_type_id INT NOT NULL,
    test_started_at BIGINT NOT NULL COMMENT 'Unix timestamp',
    current_checkpoint INT NOT NULL DEFAULT 0 COMMENT 'Last completed checkpoint',
    total_checkpoints INT NOT NULL COMMENT 'Total in route',
    vehicle_netid INT COMMENT 'Network ID of spawned vehicle',
    mistakes INT NOT NULL DEFAULT 0 COMMENT 'Errors accumulated',
    max_mistakes INT NOT NULL COMMENT 'Failure threshold',
    status ENUM('waiting_start', 'in_progress', 'completing', 'completed', 'failed', 'cancelled') DEFAULT 'waiting_start',
    fail_reason VARCHAR(100) COMMENT 'If failed, why',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id) ON DELETE CASCADE,
    UNIQUE KEY unique_active_test (character_id, license_type_id, status),
    INDEX idx_character_id (character_id),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Admin Permissions: Ensure these permissions exist in cm_admin_ranks
-- Recommended: Add to seed data
-- admin.manage_licenses — Create/Edit/Delete license tests
-- admin.issue_licenses — Issue licenses to players
-- admin.revoke_licenses — Revoke licenses

-- End Migration
