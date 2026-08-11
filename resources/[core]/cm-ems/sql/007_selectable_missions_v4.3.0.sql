-- Optional manual migration. cm-ems creates this table automatically.
CREATE TABLE IF NOT EXISTS cm_ems_mission_runs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    character_id VARCHAR(64) NOT NULL,
    mission_id VARCHAR(64) NOT NULL,
    status ENUM('active','completed','cancelled','failed') NOT NULL DEFAULT 'active',
    route LONGTEXT NOT NULL,
    reward INT UNSIGNED NOT NULL DEFAULT 0,
    xp INT UNSIGNED NOT NULL DEFAULT 0,
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    PRIMARY KEY (id),
    KEY idx_cm_ems_mission_member (character_id, status, started_at),
    KEY idx_cm_ems_mission_cooldown (character_id, mission_id, completed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
