CREATE TABLE IF NOT EXISTS cm_citybulletin_notices (
    notice_id VARCHAR(48) NOT NULL,
    title VARCHAR(96) NOT NULL,
    summary VARCHAR(240) NOT NULL,
    body TEXT NOT NULL,
    category VARCHAR(32) NOT NULL,
    priority VARCHAR(16) NOT NULL DEFAULT 'normal',
    published_at DATETIME NOT NULL,
    expires_at DATETIME NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    archived TINYINT(1) NOT NULL DEFAULT 0,
    pinned TINYINT(1) NOT NULL DEFAULT 0,
    created_by_character_id VARCHAR(64) NULL,
    updated_by_character_id VARCHAR(64) NULL,
    archived_by_character_id VARCHAR(64) NULL,
    archived_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (notice_id),
    KEY idx_cm_citybulletin_public_window (enabled, archived, published_at, expires_at),
    KEY idx_cm_citybulletin_category (category),
    KEY idx_cm_citybulletin_archive (archived, archived_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS cm_citybulletin_reads (
    character_id VARCHAR(64) NOT NULL,
    notice_id VARCHAR(48) NOT NULL,
    read_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (character_id, notice_id),
    KEY idx_cm_citybulletin_reads_notice (notice_id),
    CONSTRAINT fk_cm_citybulletin_read_notice
        FOREIGN KEY (notice_id) REFERENCES cm_citybulletin_notices (notice_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
