-- cm-pets adoption-center configuration.
-- Apply manually after 001_cm_pets.sql. cm-pets never migrates automatically.
-- No production center is seeded: enabled remains false and coordinates are
-- nullable until an authorized cm-admin integration configures a center.

CREATE TABLE IF NOT EXISTS cm_pet_adoption_centers (
    center_id VARCHAR(32) NOT NULL,
    display_name VARCHAR(64) NOT NULL,
    interaction_label VARCHAR(64) NOT NULL,
    npc_model VARCHAR(64) NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 0,
    x DECIMAL(10,4) NULL,
    y DECIMAL(10,4) NULL,
    z DECIMAL(10,4) NULL,
    heading DECIMAL(7,3) NULL,
    interaction_distance DECIMAL(4,2) NOT NULL DEFAULT 2.50,
    routing_bucket INT NULL,
    created_by_character_id VARCHAR(64) NULL,
    updated_by_character_id VARCHAR(64) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (center_id),
    KEY idx_cm_pet_adoption_centers_enabled (enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
