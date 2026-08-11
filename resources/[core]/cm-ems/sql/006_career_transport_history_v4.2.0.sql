-- Optional manual migration. cm-ems also creates these tables automatically.
CREATE TABLE IF NOT EXISTS cm_ems_employee_progress (
    character_id VARCHAR(64) NOT NULL,
    xp INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (character_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_ems_incident_events (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    incident_id BIGINT UNSIGNED NOT NULL,
    actor_cid VARCHAR(64) NULL,
    actor_name VARCHAR(96) NULL,
    event_type VARCHAR(48) NOT NULL,
    detail LONGTEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_cm_ems_incident_events_incident (incident_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
