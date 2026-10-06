-- cm-clubs V1. Administrator-created social clubs only.
-- This migration is intentionally not executed by the resource at runtime.

CREATE TABLE IF NOT EXISTS cm_clubs (
    club_id VARCHAR(32) NOT NULL,
    name VARCHAR(64) NOT NULL,
    short_tag VARCHAR(12) NOT NULL,
    description VARCHAR(255) NOT NULL DEFAULT '',
    display_color CHAR(7) NOT NULL DEFAULT '#00E5FF',
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    created_by_character_id VARCHAR(64) NULL,
    updated_by_character_id VARCHAR(64) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (club_id),
    UNIQUE KEY uq_cm_clubs_tag (short_tag)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_club_ranks (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    club_id VARCHAR(32) NOT NULL,
    rank_key VARCHAR(32) NOT NULL,
    name VARCHAR(48) NOT NULL,
    tier SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    permissions JSON NOT NULL,
    is_leader_rank TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cm_club_rank_key (club_id, rank_key),
    UNIQUE KEY uq_cm_club_rank_tier (club_id, tier),
    CONSTRAINT fk_cm_club_ranks_club FOREIGN KEY (club_id) REFERENCES cm_clubs (club_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_club_members (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    club_id VARCHAR(32) NOT NULL,
    character_id VARCHAR(64) NOT NULL,
    rank_id BIGINT UNSIGNED NOT NULL,
    is_leader TINYINT(1) NOT NULL DEFAULT 0,
    status ENUM('active', 'left', 'removed') NOT NULL DEFAULT 'active',
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    left_at TIMESTAMP NULL,
    removed_by_character_id VARCHAR(64) NULL,
    active_character_key VARCHAR(64) GENERATED ALWAYS AS (CASE WHEN status = 'active' THEN character_id ELSE NULL END) STORED,
    active_club_character_key VARCHAR(96) GENERATED ALWAYS AS (CASE WHEN status = 'active' THEN CONCAT(club_id, ':', character_id) ELSE NULL END) STORED,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cm_club_active_character (active_character_key),
    UNIQUE KEY uq_cm_club_active_membership (active_club_character_key),
    KEY idx_cm_club_members_club_status (club_id, status),
    CONSTRAINT fk_cm_club_members_club FOREIGN KEY (club_id) REFERENCES cm_clubs (club_id),
    CONSTRAINT fk_cm_club_members_rank FOREIGN KEY (rank_id) REFERENCES cm_club_ranks (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_club_invites (
    invite_id CHAR(36) NOT NULL,
    club_id VARCHAR(32) NOT NULL,
    inviter_character_id VARCHAR(64) NOT NULL,
    target_character_id VARCHAR(64) NOT NULL,
    entry_rank_id BIGINT UNSIGNED NOT NULL,
    status ENUM('pending', 'accepted', 'declined', 'expired', 'cancelled') NOT NULL DEFAULT 'pending',
    expires_at DATETIME NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP NULL,
    pending_target_key VARCHAR(64) GENERATED ALWAYS AS (CASE WHEN status = 'pending' THEN target_character_id ELSE NULL END) STORED,
    PRIMARY KEY (invite_id),
    UNIQUE KEY uq_cm_club_pending_target (pending_target_key),
    KEY idx_cm_club_invites_expiry (status, expires_at),
    CONSTRAINT fk_cm_club_invites_club FOREIGN KEY (club_id) REFERENCES cm_clubs (club_id),
    CONSTRAINT fk_cm_club_invites_rank FOREIGN KEY (entry_rank_id) REFERENCES cm_club_ranks (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_club_activity (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    event_uid VARCHAR(96) NOT NULL,
    club_id VARCHAR(32) NOT NULL,
    action VARCHAR(40) NOT NULL,
    actor_character_id VARCHAR(64) NULL,
    target_character_id VARCHAR(64) NULL,
    detail JSON NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cm_club_activity_event (event_uid),
    KEY idx_cm_club_activity_club_time (club_id, created_at),
    CONSTRAINT fk_cm_club_activity_club FOREIGN KEY (club_id) REFERENCES cm_clubs (club_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
