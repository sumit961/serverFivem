-- cm-commercial-ownership business employment foundation (additive, idempotent).
-- Applied automatically by server/schema.lua; kept here as the reviewable reference.
-- Ownership + business_balance stay in each business's own table. No second treasury.

CREATE TABLE IF NOT EXISTS cm_business_state (
    business_type VARCHAR(24) NOT NULL,
    business_id   VARCHAR(64) NOT NULL,
    owner_character_id BIGINT NULL,
    epoch INT NOT NULL DEFAULT 1,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (business_type, business_id)
);

CREATE TABLE IF NOT EXISTS cm_business_ranks (
    id INT AUTO_INCREMENT PRIMARY KEY,
    business_type VARCHAR(24) NOT NULL,
    business_id   VARCHAR(64) NOT NULL,
    name VARCHAR(32) NOT NULL,
    tier INT NOT NULL,
    permissions TEXT NOT NULL,
    pay_amount INT NOT NULL DEFAULT 0,
    is_entry TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_business_rank_name (business_type, business_id, name),
    KEY idx_business_rank (business_type, business_id)
);

CREATE TABLE IF NOT EXISTS cm_business_employees (
    id INT AUTO_INCREMENT PRIMARY KEY,
    business_type VARCHAR(24) NOT NULL,
    business_id   VARCHAR(64) NOT NULL,
    character_id BIGINT NOT NULL,
    rank_id INT NOT NULL,
    display_name VARCHAR(120) NULL,
    hired_by BIGINT NULL,
    hired_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_paid_at DATETIME NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_business_employee (business_type, business_id, character_id),
    KEY idx_employee_character (character_id),
    KEY idx_employee_rank (rank_id)
);

CREATE TABLE IF NOT EXISTS cm_business_activity (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    business_type VARCHAR(24) NOT NULL,
    business_id   VARCHAR(64) NOT NULL,
    action VARCHAR(40) NOT NULL,
    actor_character_id BIGINT NULL,
    target_character_id BIGINT NULL,
    amount BIGINT NULL,
    metadata TEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_business_activity (business_type, business_id, id)
);

-- Ledger for every foundation-mediated balance movement. idempotency_key is UNIQUE.
CREATE TABLE IF NOT EXISTS cm_business_transactions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    business_type VARCHAR(24) NOT NULL,
    business_id   VARCHAR(64) NOT NULL,
    direction ENUM('credit','debit') NOT NULL,
    amount BIGINT NOT NULL,
    kind VARCHAR(32) NOT NULL,
    reason VARCHAR(100) NOT NULL,
    idempotency_key VARCHAR(120) NOT NULL,
    actor_character_id BIGINT NULL,
    target_character_id BIGINT NULL,
    status ENUM('applied','pending','settled','refunded') NOT NULL DEFAULT 'applied',
    balance_after BIGINT NULL,
    metadata TEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_business_tx_key (idempotency_key),
    KEY idx_business_tx (business_type, business_id, id)
);
