-- EMS v5.3.0: resumable mission stages and medicine-sale reconciliation.
-- Safe to run more than once on MySQL 8+.

ALTER TABLE cm_ems_mission_runs
    ADD COLUMN IF NOT EXISTS stage_index INT UNSIGNED NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS expires_at DATETIME NULL;

CREATE TABLE IF NOT EXISTS cm_ems_medicine_sales (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    operation_key VARCHAR(128) NOT NULL,
    seller_cid VARCHAR(64) NOT NULL,
    buyer_cid VARCHAR(64) NOT NULL,
    item_name VARCHAR(64) NOT NULL,
    price INT UNSIGNED NOT NULL DEFAULT 0,
    stock_units INT UNSIGNED NOT NULL DEFAULT 0,
    status ENUM('initiated','paid','stock_consumed','completed','failed','refunded','refund_pending') NOT NULL,
    failure_reason VARCHAR(160) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uniq_cm_ems_medicine_sale_operation (operation_key),
    KEY idx_cm_ems_medicine_sale_reconcile (status, updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
