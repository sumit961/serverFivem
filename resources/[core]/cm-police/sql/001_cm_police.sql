-- cm-police manual install reference. Not required: server/main.lua's
-- setupDatabase() creates and seeds every one of these tables automatically
-- on first start, the same way cm-ems does. This file exists only for
-- servers that prefer to review/run schema changes by hand.

CREATE TABLE IF NOT EXISTS cm_police_organization (
    id TINYINT UNSIGNED NOT NULL DEFAULT 1,
    name VARCHAR(64) NOT NULL DEFAULT 'Police Department',
    leader_cid VARCHAR(64) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_police_ranks (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(48) NOT NULL,
    tier SMALLINT UNSIGNED NOT NULL,
    is_leader TINYINT(1) NOT NULL DEFAULT 0,
    permissions LONGTEXT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uniq_cm_police_rank_tier (tier)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_police_members (
    character_id VARCHAR(64) NOT NULL,
    rank_id BIGINT UNSIGNED NOT NULL,
    on_duty TINYINT(1) NOT NULL DEFAULT 0,
    suspended_until DATETIME NULL,
    suspension_reason VARCHAR(160) NULL,
    suspended_by VARCHAR(64) NULL,
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (character_id),
    KEY idx_cm_police_member_rank (rank_id),
    CONSTRAINT fk_cm_police_member_rank FOREIGN KEY (rank_id) REFERENCES cm_police_ranks(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_police_invites (
    character_id VARCHAR(64) NOT NULL,
    invited_by VARCHAR(64) NOT NULL,
    expires_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (character_id),
    KEY idx_cm_police_invite_expiry (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_police_outfit_presets (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    sex ENUM('male','female') NOT NULL,
    name VARCHAR(32) NOT NULL,
    outfit LONGTEXT NOT NULL,
    created_by VARCHAR(64) NULL,
    updated_by VARCHAR(64) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uniq_cm_police_outfit_preset (sex, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- What each Police member currently has picked from the wardrobe. Not a
-- persistent inventory item: this only ever drives the on-duty appearance
-- swap in client/main.lua, and is reverted to the member's own civilian
-- clothes the moment they go off duty.
CREATE TABLE IF NOT EXISTS cm_police_member_outfit (
    character_id VARCHAR(64) NOT NULL,
    preset_id BIGINT UNSIGNED NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (character_id),
    CONSTRAINT fk_cm_police_member_outfit_preset FOREIGN KEY (preset_id) REFERENCES cm_police_outfit_presets(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_police_activity (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    actor_cid VARCHAR(64) NULL,
    action VARCHAR(64) NOT NULL,
    detail LONGTEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_cm_police_activity_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Model, appearance and image come live from rn-vehicleshop's catalog
-- (GetPoliceCatalog export) -- this table only owns what's Police-specific:
-- where a vehicle spawns, whether it's a car or helicopter, the minimum
-- rank tier required to spawn it, and whether it's currently enabled.
CREATE TABLE IF NOT EXISTS cm_police_fleet_vehicles (
    model VARCHAR(64) NOT NULL,
    vehicle_id BIGINT UNSIGNED NULL,
    kind ENUM('car','helicopter') NOT NULL DEFAULT 'car',
    min_tier SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    spawn_x FLOAT NOT NULL,
    spawn_y FLOAT NOT NULL,
    spawn_z FLOAT NOT NULL,
    spawn_h FLOAT NOT NULL DEFAULT 0,
    updated_by VARCHAR(64) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (model),
    UNIQUE KEY uniq_cm_police_fleet_vehicle_id (vehicle_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Reserved for future rank/permission migrations as new features are added
-- (same convention cm-ems uses) -- empty on a fresh install.
CREATE TABLE IF NOT EXISTS cm_police_migrations (
    migration_key VARCHAR(64) NOT NULL,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (migration_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS cm_police_impound_evidence (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    vehicle_id BIGINT UNSIGNED NULL,
    target_net_id INT UNSIGNED NULL,
    plate VARCHAR(12) NOT NULL,
    officer_cid VARCHAR(64) NOT NULL,
    image_url VARCHAR(300) NOT NULL,
    message VARCHAR(500) NOT NULL,
    captured_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    used_at TIMESTAMP NULL,
    impound_id BIGINT UNSIGNED NULL,
    PRIMARY KEY (id),
    KEY idx_cm_police_impound_evidence_vehicle (vehicle_id, captured_at),
    KEY idx_cm_police_impound_evidence_entity (target_net_id, officer_cid, used_at, captured_at),
    KEY idx_cm_police_impound_evidence_ready (vehicle_id, officer_cid, used_at, captured_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
