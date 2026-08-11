-- These tables are normally created automatically when the resource starts
-- (via `MySQL.query CREATE TABLE IF NOT EXISTS` calls inside each module).
-- This file is provided so you can install them manually if you prefer.
--
-- Safe to re-run: every statement uses `CREATE TABLE IF NOT EXISTS`.

CREATE TABLE IF NOT EXISTS `p_policejob_outfits` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(64) NOT NULL,
    `job` VARCHAR(50) NOT NULL,
    `grades` JSON NOT NULL,
    `gender` VARCHAR(10) NOT NULL,
    `licenses` JSON DEFAULT NULL,
    `skin` LONGTEXT NOT NULL,
    `created_by` VARCHAR(100) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_job_gender` (`job`, `gender`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `p_policejob_bands` (
    `identifier` VARCHAR(60) NOT NULL,
    `name` VARCHAR(50) NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `p_policejob_k9` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `identifier` VARCHAR(60) NOT NULL,
    `playerId` INT,
    `breed` VARCHAR(50),
    `name` VARCHAR(50),
    `health` INT DEFAULT 200,
    `armor` INT DEFAULT 50,
    `active` TINYINT(1) DEFAULT 0,
    `spawned_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `active_k9` (`identifier`, `active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `p_policejob_cctv` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(50) NOT NULL,
    `model` VARCHAR(50) NOT NULL,
    `coords` LONGTEXT NOT NULL,
    `rotation` LONGTEXT NOT NULL,
    `jobs` LONGTEXT NOT NULL,
    `broken` TINYINT(1) DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `p_policejob_prison_sentences` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `identifier` VARCHAR(60) NOT NULL,
    `player_name` VARCHAR(100) NOT NULL,
    `officer_name` VARCHAR(100) DEFAULT NULL,
    `officer_id` INT DEFAULT NULL,
    `reason` TEXT,
    `sentence_time` INT NOT NULL DEFAULT 0,
    `remaining_time` INT NOT NULL DEFAULT 0,
    `cell_id` INT DEFAULT NULL,
    `is_community_service` TINYINT(1) DEFAULT 0,
    `is_solitary` TINYINT(1) DEFAULT 0,
    `solitary_until` INT DEFAULT 0,
    `status` ENUM('active','released','escaped') DEFAULT 'active',
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `released_at` TIMESTAMP NULL DEFAULT NULL,
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `p_policejob_prison_jobs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `job_id` VARCHAR(50) NOT NULL,
    `label` VARCHAR(100) NOT NULL,
    `description` TEXT,
    `payment` INT DEFAULT 0,
    `duration` INT DEFAULT 30,
    `time_reduction` INT DEFAULT 0,
    `locations` LONGTEXT,
    `animation_dict` VARCHAR(100),
    `animation_clip` VARCHAR(100),
    `created_by` VARCHAR(60),
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `p_policejob_speedcams` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `cam_name` VARCHAR(100) NOT NULL UNIQUE,
    `model_name` VARCHAR(100) NOT NULL,
    `coords_x` FLOAT NOT NULL,
    `coords_y` FLOAT NOT NULL,
    `coords_z` FLOAT NOT NULL,
    `heading` FLOAT NOT NULL,
    `speed_limit` INT NOT NULL,
    `cam_distance` INT NOT NULL,
    `fine` INT NOT NULL,
    `fine_multiplier` TINYINT(1) NOT NULL DEFAULT 0,
    `blip_enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `screen_effect` TINYINT(1) NOT NULL DEFAULT 1,
    `light_effect` TINYINT(1) NOT NULL DEFAULT 1,
    `sensors` LONGTEXT NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `police_mugshots` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `url` LONGTEXT NOT NULL,
    `suspect` VARCHAR(100) NOT NULL,
    `dob` VARCHAR(20) DEFAULT NULL,
    `officer` VARCHAR(100) NOT NULL,
    `description` TEXT,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
