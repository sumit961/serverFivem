-- CM License System — Database Operations
--
-- Schema source of truth: the statements in Database.Init below. sql/001 is the
-- same schema for manual installs; sql/002+ are migrations for databases that
-- were created by an earlier version.

Database = {}

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS cm_license_types (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- A license type may own several routes; the exam draws one at random.
    [[CREATE TABLE IF NOT EXISTS cm_license_routes (
        id INT PRIMARY KEY AUTO_INCREMENT,
        license_type_id INT NOT NULL,
        label VARCHAR(100),
        vehicle_spawn JSON NOT NULL,
        enabled BOOLEAN NOT NULL DEFAULT true,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id) ON DELETE CASCADE,
        INDEX idx_license_type_id (license_type_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS cm_license_checkpoints (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS cm_character_licenses (
        id INT PRIMARY KEY AUTO_INCREMENT,
        character_id INT NOT NULL,
        license_type_id INT NOT NULL,
        issued_at BIGINT NOT NULL,
        expires_at BIGINT NOT NULL,
        status ENUM('active', 'expired', 'revoked') NOT NULL DEFAULT 'active',
        delivery_status ENUM('pending', 'delivered') NOT NULL DEFAULT 'pending',
        delivered_at BIGINT,
        revoked_at BIGINT,
        revoked_by INT,
        revoke_reason VARCHAR(255),
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (license_type_id) REFERENCES cm_license_types(id) ON DELETE RESTRICT,
        UNIQUE KEY unique_character_license (character_id, license_type_id),
        INDEX idx_character_id (character_id),
        INDEX idx_license_type_id (license_type_id),
        INDEX idx_expires_at (expires_at),
        INDEX idx_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS cm_license_active_tests (
        id INT PRIMARY KEY AUTO_INCREMENT,
        character_id INT NOT NULL,
        license_type_id INT NOT NULL,
        route_id INT,
        test_started_at BIGINT NOT NULL,
        test_began_at BIGINT,
        test_ended_at BIGINT,
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
        INDEX idx_character_id (character_id),
        INDEX idx_status (status),
        INDEX idx_started_at (test_started_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

-- Columns added after the first release. Applied here so an existing install
-- does not need the sql/ migrations run by hand.
local COLUMN_PATCHES = {
    { table = 'cm_character_licenses', column = 'delivery_status',
      sql = "ALTER TABLE cm_character_licenses ADD COLUMN delivery_status ENUM('pending','delivered') NOT NULL DEFAULT 'pending' AFTER status" },
    { table = 'cm_character_licenses', column = 'delivered_at',
      sql = 'ALTER TABLE cm_character_licenses ADD COLUMN delivered_at BIGINT NULL AFTER delivery_status' },
    { table = 'cm_license_active_tests', column = 'test_began_at',
      sql = 'ALTER TABLE cm_license_active_tests ADD COLUMN test_began_at BIGINT NULL AFTER test_started_at' },
    { table = 'cm_license_active_tests', column = 'test_ended_at',
      sql = 'ALTER TABLE cm_license_active_tests ADD COLUMN test_ended_at BIGINT NULL AFTER test_began_at' },
    { table = 'cm_license_routes', column = 'label',
      sql = 'ALTER TABLE cm_license_routes ADD COLUMN label VARCHAR(100) NULL AFTER license_type_id' },
    { table = 'cm_license_routes', column = 'enabled',
      sql = 'ALTER TABLE cm_license_routes ADD COLUMN enabled BOOLEAN NOT NULL DEFAULT true AFTER vehicle_spawn' },
    { table = 'cm_license_active_tests', column = 'route_id',
      sql = 'ALTER TABLE cm_license_active_tests ADD COLUMN route_id INT NULL AFTER license_type_id' },
}

-- Indexes that must no longer exist. Dropped here so an install created by an
-- earlier version picks up multi-route support without a manual migration.
local INDEX_REMOVALS = {
    { table = 'cm_license_routes', index = 'unique_route_per_type' },
}

local function dropRetiredIndexes()
    for _, entry in ipairs(INDEX_REMOVALS) do
        local present = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?]],
            { entry.table, entry.index })
        if tonumber(present or 0) > 0 then
            local ok, err = pcall(MySQL.query.await, ('ALTER TABLE %s DROP INDEX %s'):format(entry.table, entry.index))
            if not ok then
                print(('^1[CM-License]^7 Failed to drop %s.%s: %s'):format(entry.table, entry.index, tostring(err)))
            end
        end
    end
end

local function applyColumnPatches()
    for _, patch in ipairs(COLUMN_PATCHES) do
        local present = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?]],
            { patch.table, patch.column })
        if tonumber(present or 0) == 0 then
            local ok, err = pcall(MySQL.query.await, patch.sql)
            if not ok then
                print(('^1[CM-License]^7 Failed to add %s.%s: %s'):format(patch.table, patch.column, tostring(err)))
            end
        end
    end
end

-- Seed the fixed public license types from config.
local function seedStandardTypes()
    local npc = CMLicenseConfig.NPC
    local npcCoords = json.encode({
        x = npc.Coords.x, y = npc.Coords.y, z = npc.Coords.z,
        heading = npc.Coords.heading, scenario = npc.Scenario
    })
    for licenseType, definition in pairs(CMLicenseConfig.StandardTypes or {}) do
        -- npc_coords is only seeded on insert: an admin who moved the
        -- instructor in-game must not have that undone by a restart.
        MySQL.query.await([[INSERT INTO cm_license_types
            (license_type,label,item_name,price,valid_days,vehicle_model,vehicle_category,npc_model,npc_coords,enabled)
            VALUES (?,?,?,?,?,?,?,?,?,true)
            ON DUPLICATE KEY UPDATE label=VALUES(label),item_name=VALUES(item_name),price=VALUES(price),
            valid_days=VALUES(valid_days),vehicle_model=VALUES(vehicle_model),vehicle_category=VALUES(vehicle_category),
            enabled=true]],
            { licenseType, definition.label, definition.item, definition.price, definition.days,
              definition.model, definition.category, npc.Model, npcCoords })
    end
end

-- Initialize database schema
function Database.Init()
    print('^2[CM-License]^7 Initializing database schema...')

    for _, statement in ipairs(SCHEMA) do
        MySQL.query.await(statement)
    end

    applyColumnPatches()
    dropRetiredIndexes()
    MySQL.query.await("UPDATE cm_license_routes SET label = CONCAT('Route ', id) WHERE label IS NULL")
    seedStandardTypes()

    print('^2[CM-License]^7 Database schema initialized')
end

-- Fail sessions left behind by a crash or unclean shutdown, then prune old rows.
function Database.RecoverStaleSessions()
    local recovered = MySQL.update.await([[UPDATE cm_license_active_tests
        SET status = 'failed', fail_reason = ?, test_ended_at = ?
        WHERE status IN ('waiting_start', 'in_progress', 'completing')]],
        { Constants.FAIL_REASON.SERVER_RESTART, os.time() }) or 0

    if tonumber(recovered) > 0 then
        print(('^3[CM-License]^7 Recovered %d stale test session(s) from a previous run'):format(tonumber(recovered)))
    end

    local keepDays = tonumber(CMLicenseConfig.Maintenance.KeepFinishedTestDays) or 14
    MySQL.update.await([[DELETE FROM cm_license_active_tests
        WHERE status IN ('completed', 'failed', 'cancelled') AND test_started_at < ?]],
        { os.time() - (keepDays * 86400) })

    return tonumber(recovered)
end

-- Get all license types
function Database.GetLicenseTypes()
    return MySQL.query.await('SELECT * FROM cm_license_types WHERE enabled = true ORDER BY label')
end

-- Get a single license type regardless of enabled state
function Database.GetLicenseType(typeId)
    return MySQL.single.await('SELECT * FROM cm_license_types WHERE id = ?', { typeId })
end

-- Every enabled route belonging to a license type, oldest first.
function Database.GetRoutes(typeId)
    return MySQL.query.await(
        'SELECT * FROM cm_license_routes WHERE license_type_id = ? AND enabled = true ORDER BY id',
        { typeId }) or {}
end

-- Every route including disabled ones, with checkpoint counts (admin view).
function Database.GetRoutesWithCounts(typeId)
    return MySQL.query.await([[SELECT r.*,
        (SELECT COUNT(*) FROM cm_license_checkpoints cp WHERE cp.route_id = r.id) checkpoint_count
        FROM cm_license_routes r WHERE r.license_type_id = ? ORDER BY r.id]], { typeId }) or {}
end

function Database.GetRouteById(routeId)
    return MySQL.single.await('SELECT * FROM cm_license_routes WHERE id = ?', { routeId })
end

function Database.CreateRoute(typeId, label, vehicleSpawn)
    return MySQL.insert.await(
        'INSERT INTO cm_license_routes (license_type_id, label, vehicle_spawn) VALUES (?, ?, ?)',
        { typeId, label, json.encode(vehicleSpawn) })
end

function Database.DeleteRoute(routeId)
    local affected = MySQL.update.await('DELETE FROM cm_license_routes WHERE id = ?', { routeId })
    return tonumber(affected or 0) > 0
end

function Database.SetRouteEnabled(routeId, enabled)
    local affected = MySQL.update.await('UPDATE cm_license_routes SET enabled = ? WHERE id = ?',
        { enabled and true or false, routeId })
    return tonumber(affected or 0) > 0
end

-- Get checkpoints for route
function Database.GetCheckpoints(routeId)
    return MySQL.query.await('SELECT * FROM cm_license_checkpoints WHERE route_id = ? ORDER BY sequence', { routeId })
end

-- Get checkpoint by ID
function Database.GetCheckpoint(checkpointId)
    return MySQL.single.await('SELECT * FROM cm_license_checkpoints WHERE id = ?', { checkpointId })
end

-- Get licenses for character (active and expired)
function Database.GetCharacterLicenses(characterId)
    return MySQL.query.await([[SELECT cl.*, lt.label, lt.license_type, lt.item_name
        FROM cm_character_licenses cl JOIN cm_license_types lt ON cl.license_type_id = lt.id
        WHERE cl.character_id = ? AND cl.status IN ('active', 'expired')]], { characterId })
end

-- Issue license to character
function Database.IssueLicense(characterId, licenseTypeId, validDays)
    local now = os.time()
    local expiresAt = now + (validDays * 86400)

    local affected = MySQL.update.await([[INSERT INTO cm_character_licenses
        (character_id, license_type_id, issued_at, expires_at, status, delivery_status, delivered_at, revoked_at, revoked_by, revoke_reason)
        VALUES (?, ?, ?, ?, 'active', 'pending', NULL, NULL, NULL, NULL)
        ON DUPLICATE KEY UPDATE issued_at = VALUES(issued_at), expires_at = VALUES(expires_at),
        status = 'active', delivery_status = 'pending', delivered_at = NULL,
        revoked_at = NULL, revoked_by = NULL, revoke_reason = NULL]],
        { characterId, licenseTypeId, now, expiresAt })

    return tonumber(affected or 0) > 0, expiresAt
end

function Database.MarkLicenseDelivered(characterId, licenseTypeId)
    local affected = MySQL.update.await([[UPDATE cm_character_licenses
        SET delivery_status = 'delivered', delivered_at = ?
        WHERE character_id = ? AND license_type_id = ? AND status = 'active' AND delivery_status = 'pending']],
        { os.time(), characterId, licenseTypeId })
    return tonumber(affected or 0) > 0
end

function Database.GetPendingDeliveries(characterId)
    return MySQL.query.await([[SELECT cl.*, lt.item_name, lt.license_type, lt.label, lt.valid_days
        FROM cm_character_licenses cl JOIN cm_license_types lt ON lt.id = cl.license_type_id
        WHERE cl.character_id = ? AND cl.status = 'active' AND cl.expires_at > ? AND cl.delivery_status = 'pending']],
        { characterId, os.time() }) or {}
end

-- The raw entitlement row, whatever its status (the reader above filters to
-- active/expired, which hides discarded cards).
function Database.GetCharacterLicenseRow(characterId, licenseTypeId)
    return MySQL.single.await(
        'SELECT * FROM cm_character_licenses WHERE character_id = ? AND license_type_id = ?',
        { characterId, licenseTypeId })
end

-- Re-activate a license the player discarded and has now picked back up.
-- The WHERE clause carries the safety rules: only that character's row, only a
-- discard revocation, only while the original expiry is still in the future,
-- and only when the card in hand matches the issuance still on record.
function Database.RestoreDiscardedLicense(characterId, licenseTypeId, expiresAt)
    local query = [[UPDATE cm_character_licenses
        SET status = 'active', delivery_status = 'delivered', delivered_at = ?,
            revoked_at = NULL, revoked_by = NULL, revoke_reason = NULL
        WHERE character_id = ? AND license_type_id = ?
          AND status = 'revoked' AND revoke_reason = ?
          AND expires_at > ?]]
    local values = { os.time(), characterId, licenseTypeId, Constants.DISCARD_REASON, os.time() }

    if expiresAt then
        query = query .. ' AND expires_at = ?'
        values[#values + 1] = expiresAt
    end

    local affected = MySQL.update.await(query, values)
    return tonumber(affected or 0) > 0
end

-- Most recent finished attempt for a character/type (retry cooldown)
function Database.GetLastAttempt(characterId, licenseTypeId)
    return MySQL.single.await([[SELECT status, fail_reason, test_started_at, test_ended_at
        FROM cm_license_active_tests
        WHERE character_id = ? AND license_type_id = ? AND status IN ('failed', 'cancelled')
        ORDER BY id DESC LIMIT 1]], { characterId, licenseTypeId })
end

-- Create test session
function Database.CreateTestSession(characterId, licenseTypeId, routeId, totalCheckpoints, maxMistakes)
    return MySQL.insert.await([[INSERT INTO cm_license_active_tests
        (character_id, license_type_id, route_id, test_started_at, total_checkpoints, max_mistakes, status)
        VALUES (?, ?, ?, ?, ?, ?, 'waiting_start')]],
        { characterId, licenseTypeId, routeId, os.time(), totalCheckpoints, maxMistakes })
end

-- Update test session
function Database.UpdateTestSession(testId, updates)
    local fields = {}
    local values = {}

    local allowed = { current_checkpoint = true, status = true, vehicle_netid = true,
        mistakes = true, fail_reason = true, test_began_at = true, test_ended_at = true }
    for key, value in pairs(updates or {}) do
        if not allowed[key] then return false end
        fields[#fields + 1] = key .. ' = ?'
        values[#values + 1] = value
    end

    if #fields == 0 then return false end
    values[#values + 1] = testId
    local query = 'UPDATE cm_license_active_tests SET ' .. table.concat(fields, ', ') .. ' WHERE id = ?'
    return MySQL.update.await(query, values)
end

-- End test session
function Database.EndTestSession(testId, status, failReason)
    return MySQL.update.await(
        'UPDATE cm_license_active_tests SET status = ?, fail_reason = ?, test_ended_at = ? WHERE id = ?',
        { status, failReason, os.time(), testId })
end

-- Revoke license
function Database.RevokeLicense(characterId, licenseTypeId, revokedBy, reason)
    local affected = MySQL.update.await([[UPDATE cm_character_licenses
        SET status = 'revoked', revoked_at = ?, revoked_by = ?, revoke_reason = ?
        WHERE character_id = ? AND license_type_id = ? AND status = 'active']],
        { os.time(), revokedBy, reason, characterId, licenseTypeId })
    return tonumber(affected or 0) > 0
end

-- Get expired licenses for character
function Database.GetExpiredLicenses(characterId)
    return MySQL.query.await([[SELECT cl.*, lt.item_name FROM cm_character_licenses cl
        JOIN cm_license_types lt ON cl.license_type_id = lt.id
        WHERE cl.character_id = ? AND cl.expires_at <= ? AND cl.status = 'active']],
        { characterId, os.time() })
end

-- Mark license as expired
function Database.MarkLicenseExpired(licenseId)
    local affected = MySQL.update.await(
        "UPDATE cm_character_licenses SET status = 'expired' WHERE id = ?", { licenseId })
    return tonumber(affected or 0) > 0
end

return Database
