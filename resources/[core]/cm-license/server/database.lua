-- CM License System — Database Operations

local Constants = require 'shared.constants'
local Utils = require 'shared.utils'

local Database = {}

-- Initialize database schema
function Database.Init()
    print('^2[CM-License]^7 Initializing database schema...')

    -- Create tables using raw SQL
    local schema = [[
        CREATE TABLE IF NOT EXISTS cm_license_types (
            id INT PRIMARY KEY AUTO_INCREMENT,
            license_type VARCHAR(50) UNIQUE NOT NULL,
            label VARCHAR(100) NOT NULL,
            item_name VARCHAR(50) NOT NULL,
            price INT NOT NULL,
            valid_days INT NOT NULL DEFAULT 30,
            vehicle_model VARCHAR(50),
            vehicle_category VARCHAR(20),
            npc_model VARCHAR(50),
            npc_coords JSON,
            enabled BOOLEAN NOT NULL DEFAULT true,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_license_type (license_type),
            INDEX idx_enabled (enabled)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

        CREATE TABLE IF NOT EXISTS cm_license_routes (
            id INT PRIMARY KEY AUTO_INCREMENT,
            license_type_id INT NOT NULL,
            vehicle_spawn JSON NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id) ON DELETE CASCADE,
            UNIQUE KEY unique_route_per_type (license_type_id),
            INDEX idx_license_type_id (license_type_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

        CREATE TABLE IF NOT EXISTS cm_license_checkpoints (
            id INT PRIMARY KEY AUTO_INCREMENT,
            route_id INT NOT NULL,
            sequence INT NOT NULL,
            point_type ENUM('start', 'checkpoint', 'finish') NOT NULL DEFAULT 'checkpoint',
            x FLOAT NOT NULL,
            y FLOAT NOT NULL,
            z FLOAT NOT NULL,
            heading FLOAT,
            radius FLOAT NOT NULL DEFAULT 20.0,
            max_speed INT,
            min_altitude INT,
            max_altitude INT,
            metadata JSON,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            FOREIGN KEY (route_id) REFERENCES cm_license_routes(id) ON DELETE CASCADE,
            UNIQUE KEY unique_route_sequence (route_id, sequence),
            INDEX idx_route_id (route_id),
            INDEX idx_point_type (point_type)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

        CREATE TABLE IF NOT EXISTS cm_character_licenses (
            id INT PRIMARY KEY AUTO_INCREMENT,
            character_id INT NOT NULL,
            license_type_id INT NOT NULL,
            issued_at BIGINT NOT NULL,
            expires_at BIGINT NOT NULL,
            status ENUM('active', 'expired', 'revoked') NOT NULL DEFAULT 'active',
            revoked_at BIGINT,
            revoked_by INT,
            revoke_reason VARCHAR(255),
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id) ON DELETE RESTRICT,
            UNIQUE KEY unique_character_active_license (character_id, license_type_id, status),
            INDEX idx_character_id (character_id),
            INDEX idx_license_type_id (license_type_id),
            INDEX idx_expires_at (expires_at),
            INDEX idx_status (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

        CREATE TABLE IF NOT EXISTS cm_license_active_tests (
            id INT PRIMARY KEY AUTO_INCREMENT,
            character_id INT NOT NULL,
            license_type_id INT NOT NULL,
            test_started_at BIGINT NOT NULL,
            current_checkpoint INT NOT NULL DEFAULT 0,
            total_checkpoints INT NOT NULL,
            vehicle_netid INT,
            mistakes INT NOT NULL DEFAULT 0,
            max_mistakes INT NOT NULL,
            status ENUM('waiting_start', 'in_progress', 'completing', 'completed', 'failed', 'cancelled') DEFAULT 'waiting_start',
            fail_reason VARCHAR(100),
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id) ON DELETE CASCADE,
            UNIQUE KEY unique_active_test (character_id, license_type_id, status),
            INDEX idx_character_id (character_id),
            INDEX idx_status (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]

    -- Execute each CREATE TABLE statement separately
    local statements = {
        'CREATE TABLE IF NOT EXISTS cm_license_types (id INT PRIMARY KEY AUTO_INCREMENT, license_type VARCHAR(50) UNIQUE NOT NULL, label VARCHAR(100) NOT NULL, item_name VARCHAR(50) NOT NULL, price INT NOT NULL, valid_days INT NOT NULL DEFAULT 30, vehicle_model VARCHAR(50), vehicle_category VARCHAR(20), npc_model VARCHAR(50), npc_coords JSON, enabled BOOLEAN NOT NULL DEFAULT true, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, INDEX idx_license_type (license_type), INDEX idx_enabled (enabled)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4',
        'CREATE TABLE IF NOT EXISTS cm_license_routes (id INT PRIMARY KEY AUTO_INCREMENT, license_type_id INT NOT NULL, vehicle_spawn JSON NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id) ON DELETE CASCADE, UNIQUE KEY unique_route_per_type (license_type_id), INDEX idx_license_type_id (license_type_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4',
        'CREATE TABLE IF NOT EXISTS cm_license_checkpoints (id INT PRIMARY KEY AUTO_INCREMENT, route_id INT NOT NULL, sequence INT NOT NULL, point_type ENUM(\'start\', \'checkpoint\', \'finish\') NOT NULL DEFAULT \'checkpoint\', x FLOAT NOT NULL, y FLOAT NOT NULL, z FLOAT NOT NULL, heading FLOAT, radius FLOAT NOT NULL DEFAULT 20.0, max_speed INT, min_altitude INT, max_altitude INT, metadata JSON, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, FOREIGN KEY (route_id) REFERENCES cm_license_routes(id) ON DELETE CASCADE, UNIQUE KEY unique_route_sequence (route_id, sequence), INDEX idx_route_id (route_id), INDEX idx_point_type (point_type)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4',
        'CREATE TABLE IF NOT EXISTS cm_character_licenses (id INT PRIMARY KEY AUTO_INCREMENT, character_id INT NOT NULL, license_type_id INT NOT NULL, issued_at BIGINT NOT NULL, expires_at BIGINT NOT NULL, status ENUM(\'active\', \'expired\', \'revoked\') NOT NULL DEFAULT \'active\', revoked_at BIGINT, revoked_by INT, revoke_reason VARCHAR(255), created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id) ON DELETE RESTRICT, UNIQUE KEY unique_character_active_license (character_id, license_type_id, status), INDEX idx_character_id (character_id), INDEX idx_license_type_id (license_type_id), INDEX idx_expires_at (expires_at), INDEX idx_status (status)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4',
        'CREATE TABLE IF NOT EXISTS cm_license_active_tests (id INT PRIMARY KEY AUTO_INCREMENT, character_id INT NOT NULL, license_type_id INT NOT NULL, test_started_at BIGINT NOT NULL, current_checkpoint INT NOT NULL DEFAULT 0, total_checkpoints INT NOT NULL, vehicle_netid INT, mistakes INT NOT NULL DEFAULT 0, max_mistakes INT NOT NULL, status ENUM(\'waiting_start\', \'in_progress\', \'completing\', \'completed\', \'failed\', \'cancelled\') DEFAULT \'waiting_start\', fail_reason VARCHAR(100), created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id) ON DELETE CASCADE, UNIQUE KEY unique_active_test (character_id, license_type_id, status), INDEX idx_character_id (character_id), INDEX idx_status (status)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
    }

    for _, stmt in pairs(statements) do
        MySQL.query.await(stmt)
    end

    print('^2[CM-License]^7 Database schema initialized')
end

-- Get all license types
function Database.GetLicenseTypes()
    return MySQL.query.await('SELECT * FROM cm_license_types WHERE enabled = true ORDER BY label')
end

-- Get license type by ID
function Database.GetLicenseType(typeId)
    return MySQL.single.await('SELECT * FROM cm_license_types WHERE id = ?', { typeId })
end

-- Get route for license type
function Database.GetRoute(typeId)
    return MySQL.single.await('SELECT * FROM cm_license_routes WHERE license_type_id = ?', { typeId })
end

-- Get checkpoints for route
function Database.GetCheckpoints(routeId)
    return MySQL.query.await('SELECT * FROM cm_license_checkpoints WHERE route_id = ? ORDER BY sequence', { routeId })
end

-- Get checkpoint by ID
function Database.GetCheckpoint(checkpointId)
    return MySQL.single.await('SELECT * FROM cm_license_checkpoints WHERE id = ?', { checkpointId })
end

-- Get active licenses for character
function Database.GetCharacterLicenses(characterId)
    return MySQL.query.await('SELECT cl.*, lt.label, lt.license_type, lt.item_name FROM cm_character_licenses cl JOIN cm_license_types lt ON cl.license_type_id = lt.id WHERE cl.character_id = ? AND cl.status IN ("active", "expired")', { characterId })
end

-- Check if character has active license
function Database.HasActiveLicense(characterId, licenseTypeId)
    local result = MySQL.single.await('SELECT id FROM cm_character_licenses WHERE character_id = ? AND license_type_id = ? AND status = "active" AND expires_at > ?', { characterId, licenseTypeId, os.time() })
    return result ~= nil
end

-- Issue license to character
function Database.IssueLicense(characterId, licenseTypeId, validDays)
    local now = os.time()
    local expiresAt = now + (validDays * 86400)

    -- Try to update existing expired/revoked license first
    MySQL.update.await('UPDATE cm_character_licenses SET status = "expired" WHERE character_id = ? AND license_type_id = ? AND status IN ("active", "expired")', { characterId, licenseTypeId })

    -- Insert new active license
    return MySQL.insert.await('INSERT INTO cm_character_licenses (character_id, license_type_id, issued_at, expires_at, status) VALUES (?, ?, ?, ?, "active")', { characterId, licenseTypeId, now, expiresAt })
end

-- Get active test session
function Database.GetActiveTest(characterId, licenseTypeId)
    return MySQL.single.await('SELECT * FROM cm_license_active_tests WHERE character_id = ? AND license_type_id = ? AND status IN ("waiting_start", "in_progress")', { characterId, licenseTypeId })
end

-- Create test session
function Database.CreateTestSession(characterId, licenseTypeId, totalCheckpoints, maxMistakes)
    return MySQL.insert.await('INSERT INTO cm_license_active_tests (character_id, license_type_id, test_started_at, total_checkpoints, max_mistakes, status) VALUES (?, ?, ?, ?, ?, "waiting_start")',
        { characterId, licenseTypeId, os.time(), totalCheckpoints, maxMistakes })
end

-- Update test session
function Database.UpdateTestSession(testId, updates)
    local fields = {}
    local values = {}

    for key, value in pairs(updates or {}) do
        table.insert(fields, key .. ' = ?')
        table.insert(values, value)
    end

    table.insert(values, testId)
    local query = 'UPDATE cm_license_active_tests SET ' .. table.concat(fields, ', ') .. ' WHERE id = ?'
    return MySQL.update.await(query, values)
end

-- End test session
function Database.EndTestSession(testId, status, failReason)
    return MySQL.update.await('UPDATE cm_license_active_tests SET status = ?, fail_reason = ?, updated_at = NOW() WHERE id = ?', { status, failReason, testId })
end

-- Revoke license
function Database.RevokeLicense(characterId, licenseTypeId, revokedBy, reason)
    return MySQL.update.await('UPDATE cm_character_licenses SET status = "revoked", revoked_at = ?, revoked_by = ?, revoke_reason = ? WHERE character_id = ? AND license_type_id = ? AND status = "active"',
        { os.time(), revokedBy, reason, characterId, licenseTypeId })
end

-- Get expired licenses for character
function Database.GetExpiredLicenses(characterId)
    return MySQL.query.await('SELECT cl.*, lt.item_name FROM cm_character_licenses cl JOIN cm_license_types lt ON cl.license_type_id = lt.id WHERE cl.character_id = ? AND cl.expires_at <= ? AND cl.status = "active"', { characterId, os.time() })
end

-- Mark license as expired
function Database.MarkLicenseExpired(licenseId)
    return MySQL.update.await('UPDATE cm_character_licenses SET status = "expired", updated_at = NOW() WHERE id = ?', { licenseId })
end

return Database
