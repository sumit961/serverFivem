-- CM-LAW Phase 5 Arsenal Resupply. Additive and repeatable.
-- The resource also creates these tables for development upgrades; production
-- operators may apply this migration explicitly before enabling the event.
CREATE TABLE IF NOT EXISTS cm_legal_arsenal_settings (
  setting_key VARCHAR(32) PRIMARY KEY, setting_json LONGTEXT NOT NULL,
  updated_by VARCHAR(64), updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS cm_legal_arsenal_manifest (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, item_name VARCHAR(80) NOT NULL,
  quantity INT UNSIGNED NOT NULL, crate_size INT UNSIGNED NOT NULL DEFAULT 1, value_weight INT UNSIGNED NOT NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 1, updated_by VARCHAR(64),
  UNIQUE KEY uq_arsenal_manifest_item (item_name)
);
CREATE TABLE IF NOT EXISTS cm_legal_arsenal_routes (
  route_id VARCHAR(48) PRIMARY KEY, label VARCHAR(96) NOT NULL, intel_text VARCHAR(160) NOT NULL,
  start_x DOUBLE NOT NULL, start_y DOUBLE NOT NULL, start_z DOUBLE NOT NULL, start_h FLOAT NOT NULL DEFAULT 0,
  destination_x DOUBLE NOT NULL, destination_y DOUBLE NOT NULL, destination_z DOUBLE NOT NULL,
  destination_h FLOAT NOT NULL DEFAULT 0, waypoints_json LONGTEXT NULL, routing_bucket INT NOT NULL DEFAULT 0,
  enabled TINYINT(1) NOT NULL DEFAULT 1, updated_by VARCHAR(64),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS cm_legal_arsenal_extraction_points (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, gang_id VARCHAR(32) NULL,
  x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, radius FLOAT NOT NULL DEFAULT 4,
  routing_bucket INT NOT NULL DEFAULT 0, enabled TINYINT(1) NOT NULL DEFAULT 1, updated_by VARCHAR(64),
  KEY idx_arsenal_extract_enabled (enabled)
);
CREATE TABLE IF NOT EXISTS cm_legal_arsenal_runs (
  run_id VARCHAR(80) PRIMARY KEY, state VARCHAR(32) NOT NULL, scheduled_at TIMESTAMP NULL,
  warmup_at TIMESTAMP NULL, preparation_at TIMESTAMP NULL, active_at TIMESTAMP NULL, ended_at TIMESTAMP NULL,
  route_id VARCHAR(48) NOT NULL, manifest_json LONGTEXT NOT NULL, config_snapshot LONGTEXT NOT NULL,
  vehicles_json LONGTEXT NULL, total_value BIGINT UNSIGNED NOT NULL DEFAULT 0,
  delivered_value BIGINT UNSIGNED NOT NULL DEFAULT 0, stolen_value BIGINT UNSIGNED NOT NULL DEFAULT 0,
  lost_value BIGINT UNSIGNED NOT NULL DEFAULT 0, army_stock_applied TINYINT(1) NOT NULL DEFAULT 0,
  end_reason VARCHAR(96), result_json LONGTEXT NULL, quick_available_until TIMESTAMP NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, KEY idx_arsenal_run_state (state),
  KEY idx_arsenal_run_quick (quick_available_until)
);
CREATE TABLE IF NOT EXISTS cm_legal_arsenal_cargo (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, run_id VARCHAR(80) NOT NULL,
  truck_index TINYINT UNSIGNED NOT NULL, item_name VARCHAR(80) NOT NULL, quantity INT UNSIGNED NOT NULL,
  value_weight INT UNSIGNED NOT NULL, state VARCHAR(16) NOT NULL DEFAULT 'on_truck',
  carrier_cid VARCHAR(64), carrier_source INT, extracted_gang_id VARCHAR(32),
  credit_state VARCHAR(16) NOT NULL DEFAULT 'none', credit_operation_id VARCHAR(128),
  credited_at TIMESTAMP NULL, extracted_at TIMESTAMP NULL, x DOUBLE, y DOUBLE, z DOUBLE,
  bucket INT NOT NULL DEFAULT 0, expires_at TIMESTAMP NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_arsenal_credit (credit_operation_id), KEY idx_arsenal_cargo_state (run_id,state)
);
CREATE TABLE IF NOT EXISTS cm_legal_arsenal_participants (
  run_id VARCHAR(80) NOT NULL, gang_id VARCHAR(32) NOT NULL, first_character_id VARCHAR(64) NOT NULL,
  stolen_value BIGINT UNSIGNED NOT NULL DEFAULT 0, cargo_count INT UNSIGNED NOT NULL DEFAULT 0,
  joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (run_id,gang_id)
);
CREATE TABLE IF NOT EXISTS cm_legal_arsenal_stock_ledger (
  operation_id VARCHAR(160) PRIMARY KEY, run_id VARCHAR(80) NOT NULL, item_name VARCHAR(80) NOT NULL,
  quantity INT UNSIGNED NOT NULL, direction VARCHAR(8) NOT NULL, status VARCHAR(16) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, KEY idx_arsenal_stock_run (run_id)
);
CREATE TABLE IF NOT EXISTS cm_legal_arsenal_trucks (
  run_id VARCHAR(80) NOT NULL, truck_index TINYINT UNSIGNED NOT NULL,
  breach_by_cid VARCHAR(64), breach_started_at TIMESTAMP NULL,
  unloading_by_cid VARCHAR(64), unloading_started_at TIMESTAMP NULL,
  unloaded_at TIMESTAMP NULL,
  PRIMARY KEY (run_id, truck_index)
);
ALTER TABLE cm_legal_arsenal_manifest ADD COLUMN IF NOT EXISTS crate_size INT UNSIGNED NOT NULL DEFAULT 1 AFTER quantity;
ALTER TABLE cm_legal_arsenal_routes ADD COLUMN IF NOT EXISTS waypoints_json LONGTEXT NULL AFTER destination_h;
