-- cm-bank v1.7.0 — Saved Payees, Banking UX & Financial Overview
--
-- Adds saved Character ID payees (a personal nickname + favourite flag over
-- an existing recipient Character ID — never a new identifier, never a bank
-- account number). Everything else in this release (receipts, statement
-- date filter, financial dashboard, removal of transaction amount limits)
-- is server logic and NUI presentation over data that already existed —
-- no other schema change is required.
--
-- Safe to run on an existing v1.6 database: the table create is
-- IF NOT EXISTS, and no ATM data, transaction history, ownership, or
-- pending-earnings data is ever touched or deleted.

-- Nickname is a purely cosmetic personal label; the actual transfer always
-- uses recipient_character_id, the same authoritative identifier v1.4-v1.6
-- already use. UNIQUE(owner_character_id, recipient_character_id) prevents
-- saving the same recipient twice for one owner at the database level —
-- the server relies on this constraint rather than a separate check query.
CREATE TABLE IF NOT EXISTS bank_saved_payees (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    owner_character_id INT NOT NULL,
    recipient_character_id INT NOT NULL,
    nickname VARCHAR(40) NOT NULL,
    is_favourite TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_owner_recipient (owner_character_id, recipient_character_id),
    INDEX idx_payee_owner_favourite (owner_character_id, is_favourite)
);
