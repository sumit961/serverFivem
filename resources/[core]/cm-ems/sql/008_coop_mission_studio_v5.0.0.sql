-- Optional manual migration. cm-ems creates these tables automatically.

CREATE TABLE IF NOT EXISTS cm_ems_mission_definitions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    mission_key VARCHAR(64) NOT NULL,
    label VARCHAR(64) NOT NULL,
    category VARCHAR(32) NOT NULL DEFAULT 'EMS',
    description VARCHAR(255) NOT NULL,
    reward INT UNSIGNED NOT NULL DEFAULT 0,
    xp INT UNSIGNED NOT NULL DEFAULT 0,
    time_limit_seconds INT UNSIGNED NULL,
    patient TINYINT(1) NOT NULL DEFAULT 1,
    automatic_emergency TINYINT(1) NOT NULL DEFAULT 0,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    stages LONGTEXT NOT NULL,
    created_by VARCHAR(64) NULL,
    updated_by VARCHAR(64) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uniq_cm_ems_mission_key (mission_key),
    KEY idx_cm_ems_mission_enabled (enabled, automatic_emergency)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_ems_mission_participants (
    run_id BIGINT UNSIGNED NOT NULL,
    character_id VARCHAR(64) NOT NULL,
    role ENUM('leader','member') NOT NULL DEFAULT 'member',
    contributed_stages INT UNSIGNED NOT NULL DEFAULT 0,
    reward_paid TINYINT(1) NOT NULL DEFAULT 0,
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (run_id, character_id),
    KEY idx_cm_ems_participant_member (character_id, joined_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_ems_public_incidents (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    mission_id VARCHAR(64) NOT NULL,
    label VARCHAR(64) NOT NULL,
    category VARCHAR(32) NOT NULL,
    description VARCHAR(255) NOT NULL,
    route LONGTEXT NOT NULL,
    reward INT UNSIGNED NOT NULL DEFAULT 0,
    xp INT UNSIGNED NOT NULL DEFAULT 0,
    time_limit_seconds INT UNSIGNED NULL,
    status ENUM('open','assigned','completed','expired','cancelled') NOT NULL DEFAULT 'open',
    run_id BIGINT UNSIGNED NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL,
    assigned_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    PRIMARY KEY (id),
    KEY idx_cm_ems_public_status (status, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
