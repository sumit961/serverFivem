CREATE TABLE IF NOT EXISTS cm_citycalendar_events (
    event_id VARCHAR(48) NOT NULL,
    title VARCHAR(96) NOT NULL,
    description VARCHAR(255) NOT NULL DEFAULT '',
    category VARCHAR(32) NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 0,
    cancelled TINYINT(1) NOT NULL DEFAULT 0,
    start_at DATETIME NOT NULL,
    end_at DATETIME NOT NULL,
    capacity INT UNSIGNED NULL,
    rsvp_count INT UNSIGNED NOT NULL DEFAULT 0,
    x DECIMAL(10,4) NULL,
    y DECIMAL(10,4) NULL,
    z DECIMAL(10,4) NULL,
    attendance_radius DECIMAL(6,2) NULL,
    heading DECIMAL(7,3) NULL,
    colour CHAR(7) NULL,
    display_label VARCHAR(80) NULL,
    routing_bucket INT UNSIGNED NULL,
    cancellation_reason VARCHAR(160) NULL,
    cancelled_at DATETIME NULL,
    created_by_character_id VARCHAR(64) NULL,
    updated_by_character_id VARCHAR(64) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (event_id),
    KEY idx_cm_citycalendar_window (enabled, cancelled, start_at, end_at),
    KEY idx_cm_citycalendar_category (category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS cm_citycalendar_rsvps (
    event_id VARCHAR(48) NOT NULL,
    character_id VARCHAR(64) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'active',
    rsvp_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cancelled_at DATETIME NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (event_id, character_id),
    KEY idx_cm_citycalendar_rsvp_character (character_id),
    KEY idx_cm_citycalendar_rsvp_status (event_id, status),
    CONSTRAINT fk_cm_citycalendar_rsvp_event
        FOREIGN KEY (event_id) REFERENCES cm_citycalendar_events (event_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS cm_citycalendar_attendance (
    event_id VARCHAR(48) NOT NULL,
    character_id VARCHAR(64) NOT NULL,
    checked_in_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (event_id, character_id),
    KEY idx_cm_citycalendar_attendance_character (character_id),
    CONSTRAINT fk_cm_citycalendar_attendance_event
        FOREIGN KEY (event_id) REFERENCES cm_citycalendar_events (event_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
