-- Forward-only, repeatable contribution and reputation ledger.
-- Membership remains owned by cm-gang; this migration only adds progression data.

CREATE TABLE IF NOT EXISTS cm_gang_progression (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    gang_id VARCHAR(16) NOT NULL,
    character_id VARCHAR(64) NOT NULL,
    contribution_points INT UNSIGNED NOT NULL DEFAULT 0,
    reputation_level SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    total_contribution_earned BIGINT UNSIGNED NOT NULL DEFAULT 0,
    last_contribution_at DATETIME NULL,
    audit_metadata LONGTEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uniq_cm_gang_progression_member (gang_id, character_id),
    KEY idx_cm_gang_progression_character (character_id),
    KEY idx_cm_gang_progression_gang (gang_id),
    CONSTRAINT fk_cm_gang_progression_gang FOREIGN KEY (gang_id) REFERENCES cm_gangs (gang_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_gang_contribution_history (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    gang_id VARCHAR(16) NOT NULL,
    character_id VARCHAR(64) NOT NULL,
    contribution_reference VARCHAR(128) NOT NULL,
    points INT UNSIGNED NOT NULL,
    source_resource VARCHAR(64) NOT NULL,
    metadata LONGTEXT NULL,
    applied TINYINT(1) NOT NULL DEFAULT 0,
    claim_token VARCHAR(96) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    applied_at DATETIME NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uniq_cm_gang_contribution_reference (contribution_reference),
    KEY idx_cm_gang_history_member (gang_id, character_id),
    KEY idx_cm_gang_history_created (created_at),
    CONSTRAINT fk_cm_gang_contribution_history_gang FOREIGN KEY (gang_id) REFERENCES cm_gangs (gang_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO cm_gang_migrations (migration_id)
VALUES ('013_cm_gang_contribution_ledger');
