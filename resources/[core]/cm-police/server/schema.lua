local expected = {
    operations = true,
    core = true, citations = true, booking = true, impound = true,
    barricades = true, mdt = true, dispatch = true, armory = true,
    alpr = true, wardrobe = true,
}
local completed = {}
local schemaFailed = false
local schemaFailure
local operationSequence = 0
local operationLocks = {}

function AcquirePoliceOperationLock(key, owner, timeoutMs)
    key = tostring(key or '')
    if key == '' then return false end
    local now = GetGameTimer()
    local current = operationLocks[key]
    if current and now < current.expiresAt then return false end
    operationLocks[key] = { owner = owner, expiresAt = now + (tonumber(timeoutMs) or 15000) }
    return true
end

function ReleasePoliceOperationLock(key, owner)
    key = tostring(key or '')
    local current = operationLocks[key]
    if current and (owner == nil or current.owner == owner) then operationLocks[key] = nil return true end
    return false
end

function PoliceSchemaMarkReady(name)
    if expected[name] then completed[name] = true end
end

function PoliceSchemaMarkFailed(name, reason)
    schemaFailed = true
    schemaFailure = ('%s: %s'):format(tostring(name), tostring(reason or 'unknown schema error'))
    print(('[cm-police] CRITICAL schema initialization failed: %s'):format(schemaFailure))
end

function PoliceDatabaseReady()
    if schemaFailed then return false, schemaFailure end
    for name in pairs(expected) do
        if not completed[name] then return false, ('%s schema is still starting'):format(name) end
    end
    return true
end

function PoliceDatabaseStatus()
    local pending = {}
    for name in pairs(expected) do if not completed[name] then pending[#pending + 1] = name end end
    table.sort(pending)
    return { ready = #pending == 0 and not schemaFailed, failed = schemaFailed, failure = schemaFailure, pending = pending }
end

function BuildPoliceDiagnostics()
    local status = PoliceDatabaseStatus()
    status.operationCounts = {}
    if status.ready then
        local rows = MySQL.query.await('SELECT status, COUNT(*) AS total FROM cm_police_operations GROUP BY status') or {}
        for _, row in ipairs(rows) do status.operationCounts[tostring(row.status)] = tonumber(row.total) or 0 end
    end
    status.operationLocks = 0
    for _ in pairs(operationLocks) do status.operationLocks = status.operationLocks + 1 end
    return status
end

exports('GetPoliceDiagnostics', BuildPoliceDiagnostics)

function AwaitPoliceDatabase(timeoutMs)
    local deadline = GetGameTimer() + (tonumber(timeoutMs) or 15000)
    repeat
        local ok, reason = PoliceDatabaseReady()
        if ok or schemaFailed then return ok, reason end
        Wait(25)
    until GetGameTimer() >= deadline
    return false, 'Police database initialization timed out'
end

function BeginPoliceOperation(operationType, characterId, vehicleId, amount, context)
    operationSequence = operationSequence + 1
    local operationId = ('%s:%s:%s:%s:%s'):format(
        tostring(operationType), tostring(characterId or 'system'), os.time(), GetGameTimer(), operationSequence)
    local inserted = MySQL.insert.await([[
        INSERT INTO cm_police_operations
            (operation_id, operation_type, character_id, vehicle_id, amount, status, context)
        VALUES (?, ?, ?, ?, ?, 'pending', ?)
    ]], { operationId, operationType, characterId or false, vehicleId or false, amount or 0, json.encode(context or {}) })
    return inserted and operationId or nil
end

function FinishPoliceOperation(operationId, status, detail)
    if not operationId then return false end
    local allowed = { completed = true, refunded = true, reconciliation_required = true }
    if not allowed[status] then return false end
    return tonumber(MySQL.update.await([[
        UPDATE cm_police_operations
        SET status = ?, result = ?, completed_at = NOW()
        WHERE operation_id = ? AND status = 'pending'
    ]], { status, json.encode(detail or {}), operationId })) == 1
end

CreateThread(function()
    local called, failure = xpcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_schema_migrations (
            migration_key VARCHAR(64) NOT NULL,
            applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (migration_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_operations (
            operation_id VARCHAR(128) NOT NULL,
            operation_type VARCHAR(48) NOT NULL,
            character_id VARCHAR(64) NULL,
            vehicle_id BIGINT UNSIGNED NULL,
            amount BIGINT NOT NULL DEFAULT 0,
            status ENUM('pending','completed','refunded','reconciliation_required') NOT NULL DEFAULT 'pending',
            context LONGTEXT NULL,
            result LONGTEXT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            completed_at TIMESTAMP NULL,
            PRIMARY KEY (operation_id),
            KEY idx_cm_police_operations_status (status, created_at),
            KEY idx_cm_police_operations_character (character_id, created_at),
            KEY idx_cm_police_operations_vehicle (vehicle_id, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        MySQL.insert.await([[INSERT INTO cm_police_schema_migrations (migration_key)
            VALUES ('v2_central_readiness_and_operations')
            ON DUPLICATE KEY UPDATE migration_key = VALUES(migration_key)]])
        MySQL.update.await([[UPDATE cm_police_operations
            SET status = 'reconciliation_required',
                result = ?, completed_at = NOW()
            WHERE status = 'pending']], { json.encode({ reason = 'resource_restart_during_operation' }) })
    end, debug.traceback)
    if not called then return PoliceSchemaMarkFailed('operations', failure) end
    PoliceSchemaMarkReady('operations')
end)
