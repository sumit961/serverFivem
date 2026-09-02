-- cm-bank: rolling per-character deposit/withdraw/transfer history.
-- Applied automatically at resource start via CREATE TABLE IF NOT EXISTS in
-- server/main.lua. Run manually only if the DB user lacks CREATE privileges.

CREATE TABLE IF NOT EXISTS bank_transactions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    character_id INT NOT NULL,
    kind VARCHAR(16) NOT NULL,
    amount INT NOT NULL,
    balance_after INT NOT NULL,
    counterparty_character_id INT NULL,
    counterparty_name VARCHAR(100) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_character_created (character_id, created_at)
);
