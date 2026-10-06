CREATE TABLE IF NOT EXISTS cm_discovery_landmarks (
    landmark_id VARCHAR(48) NOT NULL,
    name VARCHAR(80) NOT NULL,
    description VARCHAR(255) NOT NULL DEFAULT '',
    category VARCHAR(32) NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 0,
    x DECIMAL(10,4) NULL,
    y DECIMAL(10,4) NULL,
    z DECIMAL(10,4) NULL,
    radius DECIMAL(6,2) NULL,
    heading DECIMAL(7,3) NULL,
    blip_enabled TINYINT(1) NOT NULL DEFAULT 0,
    blip_sprite INT NULL,
    blip_color INT NULL,
    blip_scale DECIMAL(4,2) NULL,
    display_label VARCHAR(80) NULL,
    routing_bucket INT NULL,
    created_by_character_id VARCHAR(64) NULL,
    updated_by_character_id VARCHAR(64) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (landmark_id),
    KEY idx_cm_discovery_landmarks_enabled (enabled),
    KEY idx_cm_discovery_landmarks_category (category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS cm_discoveries (
    character_id VARCHAR(64) NOT NULL,
    landmark_id VARCHAR(48) NOT NULL,
    discovered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (character_id, landmark_id),
    KEY idx_cm_discoveries_landmark (landmark_id),
    CONSTRAINT fk_cm_discoveries_landmark
        FOREIGN KEY (landmark_id) REFERENCES cm_discovery_landmarks (landmark_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
