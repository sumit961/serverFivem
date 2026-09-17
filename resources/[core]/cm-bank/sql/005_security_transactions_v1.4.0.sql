-- CM Bank v1.4.0 - Security & Transactions
-- Existing ATM rows are trusted during upgrade. New client discoveries are
-- inserted by the resource with verified=0 and require /atmverify.

ALTER TABLE bank_transactions
    ADD COLUMN IF NOT EXISTS transaction_id VARCHAR(64) NULL AFTER id,
    ADD COLUMN IF NOT EXISTS fee_amount INT NOT NULL DEFAULT 0 AFTER amount;

ALTER TABLE bank_atm_locations
    ADD COLUMN IF NOT EXISTS verified TINYINT(1) NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS cm_bank_operation_journal (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(64) NOT NULL UNIQUE,
    operation VARCHAR(32) NOT NULL,
    character_id INT NULL,
    target_character_id INT NULL,
    amount INT NOT NULL DEFAULT 0,
    status VARCHAR(24) NOT NULL,
    details LONGTEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_bank_op_character (character_id, created_at),
    INDEX idx_bank_op_status (status, created_at)
);

-- v1.4 server/main.lua also ensures these schema changes automatically at
-- resource startup, so this migration is safe to apply manually or keep as
-- versioned documentation.
