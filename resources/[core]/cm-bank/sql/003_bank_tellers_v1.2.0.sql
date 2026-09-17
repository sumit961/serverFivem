-- cm-bank: admin-placed bank teller NPCs. Applied automatically at resource
-- start via CREATE TABLE IF NOT EXISTS in server/main.lua. Run manually only
-- if the DB user lacks CREATE privileges.
--
-- Rows are added/removed in-game via /addbankteller <name> and
-- /removebankteller (both require the atm.admin.manage permission) — there
-- is no default seed data, since teller placement can't be auto-discovered
-- the way ATM props can.

CREATE TABLE IF NOT EXISTS bank_tellers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    model VARCHAR(64) NOT NULL,
    x FLOAT NOT NULL,
    y FLOAT NOT NULL,
    z FLOAT NOT NULL,
    heading FLOAT NOT NULL DEFAULT 0,
    created_by VARCHAR(64) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
