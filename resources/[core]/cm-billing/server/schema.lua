-- cm-billing schema. Additive and repeatable (CREATE TABLE IF NOT EXISTS); financial history is never deleted.
-- character ids are VARCHAR(50) utf8mb4_general_ci to match characters.id. NULLable timestamps are explicit.
local S = CMBilling.Server

local OPTS = 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci'

S.Schema = {
    ([[CREATE TABLE IF NOT EXISTS cm_billing_invoices (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        public_reference VARCHAR(16) NOT NULL,
        recipient_character_id VARCHAR(50) NOT NULL,
        issuer_type ENUM('system','organization','business','character') NOT NULL,
        issuer_label VARCHAR(64) NOT NULL,
        issuer_character_id VARCHAR(50) NOT NULL DEFAULT '',
        issuer_resource VARCHAR(64) NOT NULL,
        issuer_entity_id VARCHAR(64) NOT NULL DEFAULT '',
        destination_type ENUM('city','character','family','business','organization') NOT NULL,
        destination_id VARCHAR(64) NOT NULL DEFAULT '',
        amount BIGINT UNSIGNED NOT NULL,
        label VARCHAR(80) NOT NULL,
        description VARCHAR(400) NOT NULL DEFAULT '',
        status ENUM('pending','settling','paid','voided','expired') NOT NULL DEFAULT 'pending',
        idempotency_key VARCHAR(64) NULL DEFAULT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        due_at TIMESTAMP NULL DEFAULT NULL,
        expires_at TIMESTAMP NULL DEFAULT NULL,
        paid_at TIMESTAMP NULL DEFAULT NULL,
        voided_at TIMESTAMP NULL DEFAULT NULL,
        void_reason VARCHAR(120) NOT NULL DEFAULT '',
        payment_account VARCHAR(8) NOT NULL DEFAULT '',
        settle_token VARCHAR(40) NOT NULL DEFAULT '',
        settle_started_at TIMESTAMP NULL DEFAULT NULL,
        settlement_note VARCHAR(160) NOT NULL DEFAULT '',
        metadata TEXT NULL,
        refunded_amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
        refund_reserved_amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
        refund_state ENUM('none','processing','partial','refunded') NOT NULL DEFAULT 'none',
        refunded_at TIMESTAMP NULL DEFAULT NULL,
        PRIMARY KEY (id),
        UNIQUE KEY uq_invoice_reference (public_reference),
        UNIQUE KEY uq_invoice_idempotency (issuer_resource, idempotency_key),
        KEY idx_invoice_recipient (recipient_character_id, status, id),
        KEY idx_invoice_issuer (issuer_resource, issuer_entity_id),
        KEY idx_invoice_created (created_at),
        KEY idx_invoice_expiry (status, expires_at),
        KEY idx_invoice_settling (status, settle_started_at)
    ) %s]]):format(OPTS),

    ([[CREATE TABLE IF NOT EXISTS cm_billing_events (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        invoice_id BIGINT UNSIGNED NOT NULL,
        event VARCHAR(32) NOT NULL,
        actor VARCHAR(80) NOT NULL DEFAULT '',
        detail VARCHAR(255) NOT NULL DEFAULT '',
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_event_invoice (invoice_id, id)
    ) %s]]):format(OPTS),

    -- Refund journal (see server/refund.lua). One row per refund request; the invoice row carries the locked aggregate
    -- (refund_reserved_amount = completed + in-flight, refunded_amount = completed). Never deleted.
    ([[CREATE TABLE IF NOT EXISTS cm_billing_refunds (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        provider_resource VARCHAR(64) NOT NULL,
        refund_reference VARCHAR(64) NOT NULL,
        invoice_id BIGINT UNSIGNED NOT NULL,
        invoice_reference VARCHAR(16) NOT NULL,
        payer_character_id VARCHAR(50) NOT NULL,
        payment_account VARCHAR(8) NOT NULL,
        destination_type VARCHAR(16) NOT NULL,
        destination_id VARCHAR(64) NOT NULL DEFAULT '',
        amount BIGINT UNSIGNED NOT NULL,
        amount_mode ENUM('exact','full') NOT NULL DEFAULT 'exact',
        reason VARCHAR(32) NOT NULL,
        status ENUM('pending','destination_debited','completed','needs_reconciliation','failed') NOT NULL DEFAULT 'pending',
        debit_state ENUM('none','attempting','committed','unknown') NOT NULL DEFAULT 'none',
        credit_state ENUM('none','attempting','committed','unknown') NOT NULL DEFAULT 'none',
        failure_reason VARCHAR(64) NOT NULL DEFAULT '',
        attempts INT UNSIGNED NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        completed_at TIMESTAMP NULL DEFAULT NULL,
        PRIMARY KEY (id),
        UNIQUE KEY uq_refund_provider_ref (provider_resource, refund_reference),
        KEY idx_refund_invoice (invoice_id, status),
        KEY idx_refund_status (status, updated_at)
    ) %s]]):format(OPTS),
}

-- Additive columns for databases created before the refund foundation (CREATE TABLE IF NOT EXISTS does not add them).
S.Migrations = {
    { table = 'cm_billing_invoices', column = 'refunded_amount', ddl = 'ALTER TABLE cm_billing_invoices ADD COLUMN refunded_amount BIGINT UNSIGNED NOT NULL DEFAULT 0' },
    { table = 'cm_billing_invoices', column = 'refund_reserved_amount', ddl = 'ALTER TABLE cm_billing_invoices ADD COLUMN refund_reserved_amount BIGINT UNSIGNED NOT NULL DEFAULT 0' },
    { table = 'cm_billing_invoices', column = 'refund_state', ddl = "ALTER TABLE cm_billing_invoices ADD COLUMN refund_state ENUM('none','processing','partial','refunded') NOT NULL DEFAULT 'none'" },
    { table = 'cm_billing_invoices', column = 'refunded_at', ddl = 'ALTER TABLE cm_billing_invoices ADD COLUMN refunded_at TIMESTAMP NULL DEFAULT NULL' },
}

S.SchemaReady, S.SchemaError = false, nil

function S.AwaitSchema()
    local waited = 0
    while not S.SchemaReady and not S.SchemaError and waited < 15000 do
        Wait(100)
        waited = waited + 100
    end
    return S.SchemaReady
end

CreateThread(function()
    if not MySQL then S.SchemaError = 'oxmysql unavailable' return end
    for index, statement in ipairs(S.Schema) do
        local ok, err = pcall(function() return MySQL.query.await(statement) end)
        if not ok then
            S.SchemaError = ('schema statement %d failed: %s'):format(index, tostring(err))
            print('[cm-billing] ' .. S.SchemaError)
            return
        end
    end
    for _, m in ipairs(S.Migrations) do
        local ok, err = pcall(function()
            if not MySQL.scalar.await(('SHOW COLUMNS FROM %s LIKE ?'):format(m.table), { m.column }) then MySQL.query.await(m.ddl) end
        end)
        if not ok then
            S.SchemaError = ('migration %s.%s failed: %s'):format(m.table, m.column, tostring(err))
            print('[cm-billing] ' .. S.SchemaError)
            return
        end
    end
    S.SchemaReady = true
    print(('[cm-billing] schema ready (%d tables, %d column migrations checked)'):format(#S.Schema, #S.Migrations))
end)
