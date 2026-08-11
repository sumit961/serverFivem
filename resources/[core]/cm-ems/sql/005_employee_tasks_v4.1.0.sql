-- Optional manual migration. cm-ems also creates these tables automatically.
CREATE TABLE IF NOT EXISTS cm_ems_task_progress (
    character_id VARCHAR(64) NOT NULL,
    period_type ENUM('daily','weekly') NOT NULL,
    period_key VARCHAR(24) NOT NULL,
    task_id VARCHAR(64) NOT NULL,
    progress INT UNSIGNED NOT NULL DEFAULT 0,
    claimed TINYINT(1) NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (character_id, period_type, period_key, task_id),
    KEY idx_cm_ems_tasks_period (period_type, period_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_ems_task_events (
    event_key VARCHAR(160) NOT NULL,
    character_id VARCHAR(64) NOT NULL,
    metric VARCHAR(48) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (event_key),
    KEY idx_cm_ems_task_events_member (character_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
