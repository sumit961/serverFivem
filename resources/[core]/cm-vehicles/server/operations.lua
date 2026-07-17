local U = CMVehicles.Utils
local Config = CMVehicles.Config
CMVehicles.Operations = CMVehicles.Operations or {}
local O = CMVehicles.Operations

local active = {}
local ensureTable
local tableReady = false

local function allowed()
    local invoker = GetInvokingResource()
    if not invoker or invoker == GetCurrentResourceName() then return true end
    local list = Config.Operations and Config.Operations.authorizedResources or {}
    return list[invoker] == true
end

local function tokenFor(vehicleId, kind)
    return ('veh-op:%s:%s:%s:%s'):format(vehicleId, tostring(kind or 'operation'), os.time(), math.random(100000, 999999))
end

function O.Begin(vehicleId, operationType, src, details)
    if not allowed() then return false, 'resource_not_authorized' end
    vehicleId = tonumber(vehicleId)
    details = type(details) == 'table' and details or {}
    if not vehicleId then return false, 'invalid_vehicle_id' end
    if not tableReady and ensureTable then
        local tableOk, tableErr = pcall(ensureTable)
        if not tableOk then return false, 'operation_table_unavailable:' .. tostring(tableErr) end
    end

    local existing = active[vehicleId]
    if existing and existing.expiresAt > os.time() then return false, 'operation_active', existing end
    if existing then
        active[vehicleId] = nil
        pcall(function()
            MySQL.update.await([[
                UPDATE cm_vehicle_operations SET status = 'expired', stage = 'memory_lock_expired',
                    completed_at = NOW(), updated_at = NOW()
                WHERE token = ? AND status = 'active'
            ]], { existing.token })
        end)
    end

    local token = tostring(details.token or tokenFor(vehicleId, operationType))
    local ttl = math.max(15, math.min(300, tonumber(details.ttl) or 45))
    local charId = src and CMVehicles.Server.GetCharacterId(tonumber(src)) or details.actorCharacterId
    local row = CMVehicles.Location and CMVehicles.Location.Get(vehicleId) or nil
    local op = {
        token = token, vehicleId = vehicleId, type = tostring(operationType or 'operation'),
        source = tonumber(src), characterId = charId and tostring(charId) or nil,
        stage = tostring(details.stage or 'started'), status = 'active',
        expiresAt = os.time() + ttl, details = details,
    }
    active[vehicleId] = op
    local insertedOk, inserted = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO cm_vehicle_operations
                (token, vehicle_id, resource_name, operation_type, actor_character_id,
                 source_state, source_ref, source_slot, target_state, target_ref, target_slot,
                 stage, status, details, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, DATE_ADD(NOW(), INTERVAL ? SECOND))
        ]], {
            token, vehicleId, tostring(GetInvokingResource() or GetCurrentResourceName()), op.type, op.characterId,
            row and row.state or nil, row and row.ref or nil, row and row.slot or nil,
            details.targetState, details.targetRef, details.targetSlot,
            op.stage, U.Encode(details), ttl,
        })
    end)
    if not insertedOk or not inserted then
        active[vehicleId] = nil
        return false, 'operation_journal_insert_failed'
    end
    return true, token
end

function O.Advance(vehicleId, token, stage, details)
    if not allowed() then return false, 'resource_not_authorized' end
    vehicleId = tonumber(vehicleId)
    local op = active[vehicleId]
    if not op or tostring(op.token) ~= tostring(token) then return false, 'operation_not_owned' end
    op.stage = tostring(stage or op.stage)
    op.expiresAt = os.time() + 45
    if type(details) == 'table' then op.details = details end
    MySQL.update.await([[
        UPDATE cm_vehicle_operations SET stage = ?, details = ?, updated_at = NOW(),
            expires_at = DATE_ADD(NOW(), INTERVAL 45 SECOND)
        WHERE token = ? AND status = 'active'
    ]], { op.stage, U.Encode(op.details or {}), op.token })
    return true
end

local function finish(vehicleId, token, status, stage, details)
    if not allowed() then return false, 'resource_not_authorized' end
    vehicleId = tonumber(vehicleId)
    local op = active[vehicleId]
    if op and tostring(op.token) ~= tostring(token) then return false, 'operation_not_owned' end
    active[vehicleId] = nil
    MySQL.update.await([[
        UPDATE cm_vehicle_operations SET status = ?, stage = ?, details = ?,
            updated_at = NOW(), completed_at = NOW()
        WHERE token = ? AND status IN ('active','recovery_required')
    ]], { status, tostring(stage or status), U.Encode(details or (op and op.details) or {}), tostring(token) })
    if CMVehicles.Location then pcall(CMVehicles.Location.ReconcileVehicle, vehicleId) end
    return true
end

function O.Complete(vehicleId, token, stage, details)
    return finish(vehicleId, token, 'completed', stage or 'completed', details)
end
function O.Fail(vehicleId, token, stage, details)
    return finish(vehicleId, token, 'failed', stage or 'failed', details)
end
function O.IsActive(vehicleId)
    local op = active[tonumber(vehicleId)]
    if op and op.expiresAt > os.time() then return true, op end
    return false
end
function O.Recent(vehicleId, limit)
    limit = math.max(1, math.min(100, tonumber(limit) or 25))
    return MySQL.query.await(([[
        SELECT * FROM cm_vehicle_operations WHERE vehicle_id = ?
        ORDER BY id DESC LIMIT %d
    ]]):format(limit), { tonumber(vehicleId) }) or {}
end

ensureTable = function()
    if tableReady then return true end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_vehicle_operations (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            token VARCHAR(128) NOT NULL,
            vehicle_id BIGINT NOT NULL,
            resource_name VARCHAR(64) NOT NULL,
            operation_type VARCHAR(64) NOT NULL,
            actor_character_id VARCHAR(100) NULL,
            source_state VARCHAR(32) NULL,
            source_ref VARCHAR(96) NULL,
            source_slot INT NULL,
            target_state VARCHAR(32) NULL,
            target_ref VARCHAR(96) NULL,
            target_slot INT NULL,
            stage VARCHAR(64) NOT NULL DEFAULT 'started',
            status VARCHAR(32) NOT NULL DEFAULT 'active',
            details LONGTEXT NULL,
            started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            expires_at TIMESTAMP NULL,
            completed_at TIMESTAMP NULL,
            UNIQUE KEY uq_cm_vehicle_operation_token (token),
            INDEX idx_cm_vehicle_operation_vehicle (vehicle_id, status),
            INDEX idx_cm_vehicle_operation_status (status, expires_at)
        )
    ]])
    MySQL.update.await([[
        UPDATE cm_vehicle_operations
        SET status = 'recovery_required', stage = 'server_restart_interrupted', updated_at = NOW()
        WHERE status = 'active'
    ]])
    tableReady = true
    return true
end

function O.RecoverInterrupted()
    local rows = MySQL.query.await([[
        SELECT DISTINCT vehicle_id FROM cm_vehicle_operations WHERE status = 'recovery_required'
    ]]) or {}
    local recovered = 0
    for _, row in ipairs(rows) do
        local vehicleId = tonumber(row.vehicle_id)
        if vehicleId then
            if CMVehicles.Location then pcall(CMVehicles.Location.ReconcileVehicle, vehicleId) end
            MySQL.update.await([[
                UPDATE cm_vehicle_operations SET status = 'recovered', stage = 'startup_reconciled',
                    completed_at = NOW(), updated_at = NOW()
                WHERE vehicle_id = ? AND status = 'recovery_required'
            ]], { vehicleId })
            recovered = recovered + 1
        end
        Wait(0)
    end
    if recovered > 0 and CMVehicles.Spawn then
        pcall(CMVehicles.Spawn.ReconcileSpawnRegistry)
    end
    return true, { recovered = recovered }
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(350)
        ensureTable()
        Wait(1800)
        O.RecoverInterrupted()
    end)
end)

exports('BeginVehicleOperation', O.Begin)
exports('AdvanceVehicleOperation', O.Advance)
exports('CompleteVehicleOperation', O.Complete)
exports('FailVehicleOperation', O.Fail)
exports('IsVehicleOperationActive', O.IsActive)
exports('GetVehicleOperations', O.Recent)
exports('RecoverInterruptedVehicleOperations', O.RecoverInterrupted)
