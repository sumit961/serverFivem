-- cm-bank: player-ownable ATMs (purchase, owner fee, admin disable) and the
-- global ownership kill-switch. Applied automatically at resource start via
-- ALTER TABLE ... ADD COLUMN IF NOT EXISTS / CREATE TABLE IF NOT EXISTS in
-- server/main.lua. Run manually only if the DB user lacks ALTER/CREATE
-- privileges.

ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS owner_character_id INT NULL;
ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS owner_name VARCHAR(100) NULL;
ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS fee_percent INT NOT NULL DEFAULT 0;
ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS pending_earnings INT NOT NULL DEFAULT 0;
ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS admin_disabled TINYINT(1) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS cm_bank_settings (
    setting_key VARCHAR(64) PRIMARY KEY,
    setting_value TEXT NOT NULL,
    updated_by VARCHAR(64) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
