-- Durable physical-license delivery and exam operation state.

ALTER TABLE cm_character_licenses
    ADD COLUMN IF NOT EXISTS delivery_status ENUM('pending','delivered') NOT NULL DEFAULT 'pending' AFTER status,
    ADD COLUMN IF NOT EXISTS delivered_at BIGINT NULL AFTER delivery_status;

ALTER TABLE cm_license_active_tests
    ADD COLUMN IF NOT EXISTS operation_key VARCHAR(96) NULL AFTER id,
    ADD UNIQUE INDEX IF NOT EXISTS uq_cm_license_test_operation (operation_key);
