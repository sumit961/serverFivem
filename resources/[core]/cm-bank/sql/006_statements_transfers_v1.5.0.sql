-- cm-bank v1.5.0 — Statements, Transfers & Banking UX
--
-- Adds: per-row status/description on bank_transactions (for statements,
-- filters, and search), supporting indexes for paginated/filtered lookups,
-- and a new bank_pending_transfers table used to deliver character-ID
-- transfers to offline recipients once cm-playerdata's exports confirmed
-- there is no supported way to credit an offline character directly.
--
-- Safe to run on an existing v1.4 database: every column add is
-- IF NOT EXISTS, every table create is IF NOT EXISTS, and no existing row
-- or column is ever altered destructively. No transaction history is
-- deleted. server/main.lua also applies these automatically at boot, so
-- running this file by hand is optional/documentation-only.

ALTER TABLE bank_transactions
    ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'completed';
    -- Existing pre-v1.5 rows default to 'completed', which matches what
    -- actually happened (only fully-committed operations were ever recorded).

ALTER TABLE bank_transactions
    ADD COLUMN IF NOT EXISTS description VARCHAR(120) NULL;
    -- Sanitized, length-capped transfer note (control characters stripped
    -- server-side). Never rendered as HTML client-side — textContent only.

ALTER TABLE bank_transactions
    ADD INDEX IF NOT EXISTS idx_transaction_id (transaction_id);

ALTER TABLE bank_transactions
    ADD INDEX IF NOT EXISTS idx_counterparty (counterparty_character_id, created_at);

ALTER TABLE bank_transactions
    ADD INDEX IF NOT EXISTS idx_kind_created (kind, created_at);

-- Offline character-ID transfer queue. A transfer to an offline recipient
-- debits the sender immediately and inserts a row here; delivery happens
-- idempotently the next time that Character ID loads (status
-- pending -> delivering -> delivered, a compare-and-set claim that can
-- never double-credit). See server/main.lua's
-- cm-playerdata:server:characterLoaded handler.
CREATE TABLE IF NOT EXISTS bank_pending_transfers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(64) NOT NULL UNIQUE,
    sender_character_id INT NOT NULL,
    sender_name VARCHAR(100) NULL,
    recipient_character_id INT NOT NULL,
    amount INT NOT NULL,
    note VARCHAR(120) NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    delivered_at TIMESTAMP NULL,
    INDEX idx_pending_recipient_status (recipient_character_id, status)
);
