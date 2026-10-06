-- cm-commercial-ownership business material balance / demand / delivery settlement (additive, idempotent).
-- Applied automatically by server/schema.lua; kept here as the reviewable reference. Nothing here drops or rewrites data.

CREATE TABLE IF NOT EXISTS cm_business_material_stock (
        business_type VARCHAR(24) NOT NULL,
        business_id   VARCHAR(64) NOT NULL,
        material_id   VARCHAR(64) NOT NULL,
        quantity BIGINT UNSIGNED NOT NULL DEFAULT 0,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (business_type, business_id, material_id)
    );

CREATE TABLE IF NOT EXISTS cm_business_material_events (
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
    );

CREATE TABLE IF NOT EXISTS cm_business_material_demands (
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
    );

CREATE TABLE IF NOT EXISTS cm_business_material_deliveries (
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
    );
