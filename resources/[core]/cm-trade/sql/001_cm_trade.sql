-- cm-trade (additive, idempotent; applied automatically by server/schema.lua)
CREATE TABLE IF NOT EXISTS cm_trade_transactions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    reference VARCHAR(16) NOT NULL,
    char_a BIGINT NOT NULL,
    char_b BIGINT NOT NULL,
    cash_a BIGINT NOT NULL DEFAULT 0,
    cash_b BIGINT NOT NULL DEFAULT 0,
    item_lines INT NOT NULL DEFAULT 0,
    items_json TEXT NULL,
    status ENUM('debiting','debited','items_done','completed','rolled_back','needs_reconciliation') NOT NULL,
    detail VARCHAR(60) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    completed_at DATETIME NULL,
    UNIQUE KEY uq_trade_reference (reference),
    KEY idx_trade_status (status, updated_at),
    KEY idx_trade_char_a (char_a),
    KEY idx_trade_char_b (char_b)
);

CREATE TABLE IF NOT EXISTS cm_trade_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    session_ref VARCHAR(16) NOT NULL,
    kind VARCHAR(32) NOT NULL,
    char_a BIGINT NULL,
    char_b BIGINT NULL,
    metadata TEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_trade_event_ref (session_ref, id)
);
