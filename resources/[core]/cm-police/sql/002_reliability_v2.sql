-- CM Police reliability v2: additive, repeatable migration.
CREATE TABLE IF NOT EXISTS cm_police_schema_migrations (
    migration_key VARCHAR(64) NOT NULL,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (migration_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_police_operations (
    operation_id VARCHAR(128) NOT NULL,
    operation_type VARCHAR(48) NOT NULL,
    character_id VARCHAR(64) NULL,
    vehicle_id BIGINT UNSIGNED NULL,
    amount BIGINT NOT NULL DEFAULT 0,
    status ENUM('pending','completed','refunded','reconciliation_required') NOT NULL DEFAULT 'pending',
    context LONGTEXT NULL,
    result LONGTEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    PRIMARY KEY (operation_id),
    KEY idx_cm_police_operations_status (status, created_at),
    KEY idx_cm_police_operations_character (character_id, created_at),
    KEY idx_cm_police_operations_vehicle (vehicle_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO cm_police_schema_migrations (migration_key)
VALUES ('v2_central_readiness_and_operations')
ON DUPLICATE KEY UPDATE migration_key = VALUES(migration_key);
