-- cm-pets v1.0.0
-- Apply manually on the intended database. cm-pets never runs migrations at
-- resource start and does not modify production data automatically.

CREATE TABLE IF NOT EXISTS cm_pet_types (
    type_id VARCHAR(32) NOT NULL,
    display_name VARCHAR(64) NOT NULL,
    species VARCHAR(32) NOT NULL,
    model VARCHAR(64) NOT NULL,
    description VARCHAR(255) NOT NULL DEFAULT '',
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    created_by_character_id VARCHAR(64) NULL,
    updated_by_character_id VARCHAR(64) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (type_id),
    KEY idx_cm_pet_types_enabled (enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_pets (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    character_id VARCHAR(64) NOT NULL,
    pet_type_id VARCHAR(32) NOT NULL,
    pet_name VARCHAR(32) NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    revoked TINYINT(1) NOT NULL DEFAULT 0,
    metadata_json VARCHAR(1024) NOT NULL DEFAULT '{}',
    granted_by_character_id VARCHAR(64) NULL,
    revoked_by_character_id VARCHAR(64) NULL,
    granted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMP NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cm_pets_character (character_id),
    KEY idx_cm_pets_type_state (pet_type_id, enabled, revoked),
    CONSTRAINT fk_cm_pets_type FOREIGN KEY (pet_type_id) REFERENCES cm_pet_types (type_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Repeatable catalog seed. Existing catalog rows, including admin changes to
-- enabled state or copy, are preserved on reapply.
INSERT IGNORE INTO cm_pet_types
    (type_id, display_name, species, model, description, enabled)
VALUES
    ('dog_retriever', 'Retriever', 'dog', 'a_c_retriever', 'A friendly cosmetic retriever companion.', 1),
    ('cat_house', 'House Cat', 'cat', 'a_c_cat', 'A quiet cosmetic cat companion.', 1),
    ('dog_pug', 'Pug', 'dog', 'a_c_pug', 'A small cosmetic pug companion.', 1)
