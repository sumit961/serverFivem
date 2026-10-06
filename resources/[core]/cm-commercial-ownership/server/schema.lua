-- cm-commercial-ownership/server/schema.lua
-- Additive, idempotent schema for the business employment foundation (mirrors sql/001_business_foundation.sql).
-- Nothing here drops, truncates or rewrites existing data.

CMB = CMB or {}
CMB.schemaReady = false

local STATEMENTS = {
    [[CREATE TABLE IF NOT EXISTS cm_business_state (
        business_type VARCHAR(24) NOT NULL,
        business_id   VARCHAR(64) NOT NULL,
        owner_character_id BIGINT NULL,
        epoch INT NOT NULL DEFAULT 1,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (business_type, business_id)
    )]],
    [[CREATE TABLE IF NOT EXISTS cm_business_ranks (
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
    )]],
    [[CREATE TABLE IF NOT EXISTS cm_business_employees (
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
    )]],
    [[CREATE TABLE IF NOT EXISTS cm_business_activity (
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
    )]],
    [[CREATE TABLE IF NOT EXISTS cm_business_transactions (
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
    )]],
    [[CREATE TABLE IF NOT EXISTS cm_business_supply_orders (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        reference VARCHAR(16) NOT NULL,
        business_type VARCHAR(24) NOT NULL,
        business_id   VARCHAR(64) NOT NULL,
        requested_by BIGINT NOT NULL,
        status ENUM('pending_payment','awaiting_fulfillment','claimed','in_transit','delivering','delivered','cancelled','failed') NOT NULL,
        units INT NOT NULL,
        subtotal BIGINT NOT NULL,
        fee BIGINT NOT NULL DEFAULT 0,
        total BIGINT NOT NULL,
        fulfillment_mode VARCHAR(16) NOT NULL DEFAULT 'external',
        cargo_class VARCHAR(24) NOT NULL DEFAULT 'general',
        urgency VARCHAR(12) NOT NULL DEFAULT 'normal',
        idempotency_key VARCHAR(100) NULL,
        owner_epoch INT NOT NULL DEFAULT 1,
        provider VARCHAR(48) NULL,
        provider_ref VARCHAR(64) NULL,
        claim_expires_at DATETIME NULL,
        transit_deadline DATETIME NULL,
        contract_ref VARCHAR(16) NULL,
        refunded_at DATETIME NULL,
        refund_amount BIGINT NOT NULL DEFAULT 0,
        end_reason VARCHAR(40) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        accepted_at DATETIME NULL,
        dispatched_at DATETIME NULL,
        delivered_at DATETIME NULL,
        cancelled_at DATETIME NULL,
        failed_at DATETIME NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        metadata TEXT NULL,
        UNIQUE KEY uq_supply_reference (reference),
        UNIQUE KEY uq_supply_idempotency (idempotency_key),
        KEY idx_supply_business (business_type, business_id, status),
        KEY idx_supply_status (status, claim_expires_at),
        KEY idx_supply_contract (contract_ref)
    )]],
    [[CREATE TABLE IF NOT EXISTS cm_business_supply_order_lines (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        order_id BIGINT NOT NULL,
        item_id VARCHAR(64) NOT NULL,
        label VARCHAR(120) NOT NULL,
        category VARCHAR(60) NULL,
        quantity INT NOT NULL,
        unit_retail INT NOT NULL,
        unit_cost INT NOT NULL,
        line_total BIGINT NOT NULL,
        UNIQUE KEY uq_supply_line (order_id, item_id)
    )]],
    [[CREATE TABLE IF NOT EXISTS cm_business_supply_events (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        order_id BIGINT NOT NULL,
        kind VARCHAR(32) NOT NULL,
        actor_character_id BIGINT NULL,
        provider VARCHAR(48) NULL,
        journal_key VARCHAR(24) NULL,
        amount BIGINT NULL,
        metadata TEXT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_supply_journal (order_id, journal_key),
        KEY idx_supply_event_order (order_id, id)
    )]],
    [[CREATE TABLE IF NOT EXISTS cm_business_material_stock (
        business_type VARCHAR(24) NOT NULL,
        business_id   VARCHAR(64) NOT NULL,
        material_id   VARCHAR(64) NOT NULL,
        quantity BIGINT UNSIGNED NOT NULL DEFAULT 0,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (business_type, business_id, material_id)
    )]],
    [[CREATE TABLE IF NOT EXISTS cm_business_material_events (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        reference VARCHAR(64) NOT NULL,
        business_type VARCHAR(24) NOT NULL,
        business_id   VARCHAR(64) NOT NULL,
        material_id   VARCHAR(64) NOT NULL,
        delta BIGINT NOT NULL,
        resulting_quantity BIGINT UNSIGNED NOT NULL,
        event_type VARCHAR(24) NOT NULL,
        source_resource VARCHAR(48) NULL,
        character_id BIGINT NULL,
        journal_key VARCHAR(120) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY uq_material_journal (journal_key),
        KEY idx_material_event_business (business_type, business_id, id),
        KEY idx_material_event_reference (reference)
    )]],
    [[CREATE TABLE IF NOT EXISTS cm_business_material_demands (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        reference VARCHAR(16) NOT NULL,
        idempotency_key VARCHAR(120) NULL,
        business_type VARCHAR(24) NOT NULL,
        business_id   VARCHAR(64) NOT NULL,
        material_id   VARCHAR(64) NOT NULL,
        quantity_required INT UNSIGNED NOT NULL,
        quantity_fulfilled INT UNSIGNED NOT NULL DEFAULT 0,
        quantity_reserved INT UNSIGNED NOT NULL DEFAULT 0,
        status ENUM('open','published','partially_fulfilled','fulfilled','cancelled','expired') NOT NULL DEFAULT 'open',
        category VARCHAR(24) NOT NULL DEFAULT 'business_need',
        deadline_epoch BIGINT NULL,
        publish_requested TINYINT(1) NOT NULL DEFAULT 0,
        contract_ref VARCHAR(24) NULL,
        created_by BIGINT NULL,
        created_epoch BIGINT NOT NULL,
        completed_epoch BIGINT NULL,
        end_reason VARCHAR(40) NULL,
        UNIQUE KEY uq_material_demand_ref (reference),
        UNIQUE KEY uq_material_demand_idem (idempotency_key),
        KEY idx_material_demand_business (business_type, business_id, status),
        KEY idx_material_demand_deadline (status, deadline_epoch)
    )]],
    [[CREATE TABLE IF NOT EXISTS cm_business_material_deliveries (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        reference VARCHAR(40) NOT NULL,
        demand_id BIGINT NOT NULL,
        demand_reference VARCHAR(16) NOT NULL,
        business_type VARCHAR(24) NOT NULL,
        business_id   VARCHAR(64) NOT NULL,
        character_id BIGINT NOT NULL,
        material_id   VARCHAR(64) NOT NULL,
        quantity INT UNSIGNED NOT NULL,
        contract_ref VARCHAR(24) NULL,
        inventory_reference VARCHAR(64) NOT NULL,
        payload VARCHAR(200) NOT NULL,
        status ENUM('prepared','inventory_committed','completed','cancelled','failed') NOT NULL DEFAULT 'prepared',
        failure_reason VARCHAR(40) NULL,
        created_epoch BIGINT NOT NULL,
        updated_epoch BIGINT NOT NULL,
        completed_epoch BIGINT NULL,
        UNIQUE KEY uq_material_delivery_ref (reference),
        UNIQUE KEY uq_material_delivery_inventory (inventory_reference),
        KEY idx_material_delivery_demand (demand_id, status),
        KEY idx_material_delivery_open (status, updated_epoch)
    )]],
}

function CMB.EnsureSchema()
    if CMB.schemaReady then return true end
    if not MySQL then return false end
    for _, sql in ipairs(STATEMENTS) do
        local ok, err = pcall(function() MySQL.query.await(sql) end)
        if not ok then
            print(('[cm-commercial-ownership] DATABASE NOT READY: business foundation schema failed (%s). Apply sql/001_business_foundation.sql.'):format(tostring(err)))
            return false
        end
    end
    -- v2.2: generic contract broker link (additive; existing databases created the table without it).
    pcall(function()
        if not MySQL.scalar.await("SHOW COLUMNS FROM cm_business_supply_orders LIKE 'contract_ref'") then
            MySQL.query.await('ALTER TABLE cm_business_supply_orders ADD COLUMN contract_ref VARCHAR(16) NULL')
            MySQL.query.await('ALTER TABLE cm_business_supply_orders ADD KEY idx_supply_contract (contract_ref)')
        end
    end)
    CMB.schemaReady = true
    return true
end

CreateThread(function()
    Wait(500)
    CMB.EnsureSchema()
end)
