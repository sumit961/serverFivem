-- cm-ems v5.1.0 - shared medicine stock and supply-run history.
-- cm-ems also creates these tables automatically at startup.

CREATE TABLE IF NOT EXISTS `cm_ems_medicine_stock` (
    `stock_key` VARCHAR(32) NOT NULL,
    `current_units` INT UNSIGNED NOT NULL DEFAULT 100,
    `max_units` INT UNSIGNED NOT NULL DEFAULT 100,
    `updated_by` VARCHAR(64) NULL,
    `updated_reason` VARCHAR(80) NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`stock_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO `cm_ems_medicine_stock`
    (`stock_key`, `current_units`, `max_units`, `updated_reason`)
VALUES
    ('main', 100, 100, 'initial_setup');

CREATE TABLE IF NOT EXISTS `cm_ems_medicine_runs` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `character_id` VARCHAR(64) NOT NULL,
    `status` VARCHAR(32) NOT NULL,
    `pickup_index` TINYINT UNSIGNED NOT NULL,
    `vehicle_plate` VARCHAR(16) NULL,
    `started_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `completed_at` TIMESTAMP NULL DEFAULT NULL,
    `cancelled_at` TIMESTAMP NULL DEFAULT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_cm_ems_medicine_runs_character` (`character_id`),
    KEY `idx_cm_ems_medicine_runs_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
