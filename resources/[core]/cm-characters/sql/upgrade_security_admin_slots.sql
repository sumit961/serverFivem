-- CM Characters security/admin slot upgrade
-- Run manually if your DB does not allow runtime ALTER statements from resources.

ALTER TABLE characters ADD COLUMN IF NOT EXISTS has_spawned TINYINT(1) NOT NULL DEFAULT 0;
ALTER TABLE characters ADD COLUMN IF NOT EXISTS playtime_minutes INT NOT NULL DEFAULT 0;
ALTER TABLE characters ADD COLUMN IF NOT EXISTS last_seen TIMESTAMP NULL DEFAULT NULL;

CREATE TABLE IF NOT EXISTS character_slot_limits (
    account_id VARCHAR(64) NOT NULL PRIMARY KEY,
    max_slots INT NOT NULL DEFAULT 2,
    reason VARCHAR(255) NULL,
    updated_by VARCHAR(64) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Add this only once. If it already exists, skip it.
ALTER TABLE characters ADD UNIQUE KEY uniq_cm_characters_account_slot (account_id, slot);
