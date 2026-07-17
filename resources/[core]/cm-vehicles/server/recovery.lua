local U = CMVehicles.Utils
local Config = CMVehicles.Config
CMVehicles.Recovery = CMVehicles.Recovery or {}
local R = CMVehicles.Recovery

local function isAdmin(src)
    src = tonumber(src)
    if not src or src <= 0 then return GetInvokingResource() ~= nil end
    local permission = tostring(Config.Recovery and Config.Recovery.adminPermission or 'vehicle.recovery')
    if GetResourceState('cm-core') == 'started' then
        local ok, allowed = pcall(function() return exports['cm-core']:ACLCheck(src, permission) end)
        if ok and allowed == true then return true end
    end
    if GetResourceState('cm-admin') == 'started' then
        local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(src, permission) end)
        if ok and allowed == true then return true end
    end
    return IsPlayerAceAllowed(src, tostring(Config.Recovery and Config.Recovery.ace or 'cmvehicles.recovery'))
end

local function resolve(identity)
    local id = tonumber(identity)
    if id then return CMVehicles.Server.GetVehicleById(id) end
    return CMVehicles.Server.GetVehicleByPlate(identity)
end

local function allEntitiesFor(vehicleId)
    vehicleId = tonumber(vehicleId)
    local out = {}
    local ok, vehicles = pcall(GetAllVehicles)
    if not ok or type(vehicles) ~= 'table' then return out end
    for _, entity in ipairs(vehicles) do
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            local id
            pcall(function() id = tonumber(Entity(entity).state.cmVehicleId) end)
            if id == vehicleId then
                local netId = 0
                pcall(function() netId = NetworkGetNetworkIdFromEntity(entity) end)
                out[#out + 1] = { entity = entity, netId = tonumber(netId) or 0 }
            end
        end
    end
    return out
end

function R.DeleteDuplicates(identity, keepNetId)
    local row = resolve(identity)
    if not row then return false, 'vehicle_not_found' end
    local list = allEntitiesFor(row.id)
    local active = CMVehicles.Server.SpawnedById and CMVehicles.Server.SpawnedById[tonumber(row.id)] or nil
    keepNetId = tonumber(keepNetId) or (active and tonumber(active.netId)) or 0
    if keepNetId <= 0 and list[1] then keepNetId = tonumber(list[1].netId) or 0 end
    local deleted, failed = 0, 0
    for _, item in ipairs(list) do
        if tonumber(item.netId) ~= keepNetId then
            local deadline = GetGameTimer() + 3000
            repeat
                pcall(DeleteEntity, item.entity)
                if not DoesEntityExist(item.entity) then break end
                Wait(0)
            until GetGameTimer() >= deadline
            if DoesEntityExist(item.entity) then failed = failed + 1 else deleted = deleted + 1 end
        end
    end
    return failed == 0, { keptNetId = keepNetId, deleted = deleted, failed = failed, found = #list }
end

function R.Diagnostics(identity)
    local row = resolve(identity)
    if not row then return nil, 'vehicle_not_found' end
    local location = CMVehicles.Location and CMVehicles.Location.Get(row.id) or nil
    local spawnedOk, spawned = false, nil
    if CMVehicles.Spawn and CMVehicles.Spawn.GetSpawnedVehicleInfo then
        spawnedOk, spawned = CMVehicles.Spawn.GetSpawnedVehicleInfo(row.id)
    end
    local assignment
    if GetResourceState('cm-house') == 'started' then
        local ok, result = pcall(function() return exports['cm-house']:GetVehicleAssignment(row.id) end)
        if ok then assignment = result end
    end
    local operations = CMVehicles.Operations and CMVehicles.Operations.Recent(row.id, 20) or {}
    local entities = allEntitiesFor(row.id)
    return {
        vehicle = row,
        location = location,
        spawned = spawnedOk and spawned or nil,
        assignment = assignment,
        operations = operations,
        entities = entities,
        duplicateCount = math.max(0, #entities - 1),
        persistence = CMVehicles.Persistence and CMVehicles.Persistence.Cache[tonumber(row.id)] or nil,
    }
end

local function appendDuplicateProblems(rows, limit)
    rows = type(rows) == 'table' and rows or {}
    local byId = {}
    for _, row in ipairs(rows) do byId[tonumber(row.id)] = row end

    local ok, entities = pcall(GetAllVehicles)
    if not ok or type(entities) ~= 'table' then return rows end
    local counts = {}
    for _, entity in ipairs(entities) do
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            local vehicleId
            pcall(function() vehicleId = tonumber(Entity(entity).state.cmVehicleId) end)
            if vehicleId then counts[vehicleId] = (counts[vehicleId] or 0) + 1 end
        end
    end

    for vehicleId, count in pairs(counts) do
        if count > 1 then
            if byId[vehicleId] then
                byId[vehicleId].duplicate_count = count - 1
            elseif #rows < limit then
                local row = CMVehicles.Server.GetVehicleById(vehicleId)
                if row then
                    row.duplicate_count = count - 1
                    rows[#rows + 1] = row
                    byId[vehicleId] = row
                end
            end
        end
    end
    return rows
end

function R.ListProblems(limit)
    limit = math.max(1, math.min(250, tonumber(limit) or 100))
    local hasHouseSlots = false
    pcall(function()
        hasHouseSlots = MySQL.scalar.await([[
            SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_house_vehicle_slots'
        ]]) == 1
    end)

    if not hasHouseSlots then
        local rows = MySQL.query.await(([[
            SELECT v.id, v.plate, v.label, v.owner_character_id, v.is_stored, v.garage,
                   v.location_state, v.location_ref, v.location_slot,
                   NULL AS assigned_house_id, NULL AS assigned_slot
            FROM cm_owned_vehicles v
            WHERE (v.location_state IS NULL)
               OR (v.is_stored = 1 AND v.garage IS NULL)
            ORDER BY v.id DESC LIMIT %d
        ]]):format(limit)) or {}
        return appendDuplicateProblems(rows, limit)
    end

    local rows = MySQL.query.await(([[
        SELECT v.id, v.plate, v.label, v.owner_character_id, v.is_stored, v.garage,
               v.location_state, v.location_ref, v.location_slot,
               s.house_id AS assigned_house_id, s.slot_index AS assigned_slot
        FROM cm_owned_vehicles v
        LEFT JOIN cm_house_vehicle_slots s ON s.vehicle_id = v.id
        WHERE
          (v.location_state IS NULL)
          OR (v.is_stored = 1 AND v.garage IS NULL)
          OR (v.location_state = 'HOUSE_GARAGE' AND s.vehicle_id IS NULL)
          OR (s.vehicle_id IS NOT NULL AND v.location_state = 'HOUSE_GARAGE'
              AND CAST(v.location_ref AS UNSIGNED) <> s.house_id)
        ORDER BY v.id DESC LIMIT %d
    ]]):format(limit)) or {}
    return appendDuplicateProblems(rows, limit)
end

function R.Action(src, identity, action, data)
    if not isAdmin(src) then return false, 'not_authorized' end
    local row = resolve(identity)
    if not row then return false, 'vehicle_not_found' end
    action = tostring(action or 'inspect'):lower()
    data = type(data) == 'table' and data or {}

    if action == 'inspect' then return true, R.Diagnostics(row.id) end
    if action == 'reconcile' then
        if CMVehicles.Location then CMVehicles.Location.ReconcileVehicle(row.id) end
        local ok, result = CMVehicles.Spawn.ReconcileSpawnRegistry()
        return ok, result
    end

    local targetStates = {
        outside = 'OUTSIDE', public = 'PUBLIC_GARAGE', impound = 'IMPOUND',
        recall = 'HOUSE_GARAGE', delete_entity = 'PENDING_DELETE',
    }
    local operationToken
    if CMVehicles.Operations and CMVehicles.Operations.Begin then
        local opOk, tokenOrReason = CMVehicles.Operations.Begin(row.id, 'admin_recovery_' .. action, src, {
            stage = 'admin_recovery_started', targetState = targetStates[action],
            targetRef = data.ref, targetSlot = data.slot, ttl = 90,
        })
        if opOk ~= true then return false, tokenOrReason or 'operation_active' end
        operationToken = tokenOrReason
    end

    local function done(ok, result)
        if operationToken and CMVehicles.Operations then
            if ok == true and CMVehicles.Operations.Complete then
                pcall(CMVehicles.Operations.Complete, row.id, operationToken,
                    'admin_recovery_completed', { action = action, result = result })
            elseif CMVehicles.Operations.Fail then
                pcall(CMVehicles.Operations.Fail, row.id, operationToken,
                    'admin_recovery_failed', { action = action, error = result })
            end
        end
        return ok, result
    end

    if action == 'duplicates' or action == 'delete_duplicates' then
        local ok, result = R.DeleteDuplicates(row.id, data.keepNetId)
        return done(ok, result)
    elseif action == 'flush' then
        local ok, result = CMVehicles.Persistence.FlushVehicle(row.id, 'admin_recovery_flush')
        return done(ok, result)
    elseif action == 'clear_assignment' then
        if GetResourceState('cm-house') ~= 'started' then return done(false, 'cm_house_not_running') end
        local ok, result = exports['cm-house']:ClearVehicleAssignment(row.id, 'admin_recovery', CMVehicles.Server.GetCharacterId(src))
        return done(ok, result)
    elseif action == 'outside' then
        if CMVehicles.Persistence then pcall(CMVehicles.Persistence.FlushVehicle, row.id, 'admin_mark_outside') end
        if CMVehicles.Spawn then pcall(CMVehicles.Spawn.DeleteVehicle, row.id) end
        local ok, result = CMVehicles.Location.Transition(row.id, 'OUTSIDE', {
            reason = 'admin_recovery', actorCharacterId = CMVehicles.Server.GetCharacterId(src),
        })
        return done(ok, result)
    elseif action == 'public' then
        if CMVehicles.Persistence then pcall(CMVehicles.Persistence.FlushVehicle, row.id, 'admin_send_public') end
        if CMVehicles.Spawn then pcall(CMVehicles.Spawn.DeleteVehicle, row.id) end
        local ok, result = CMVehicles.Location.Transition(row.id, 'PUBLIC_GARAGE', {
            ref = tostring(data.ref or 'public:recovery'), slot = data.slot,
            reason = 'admin_recovery', actorCharacterId = CMVehicles.Server.GetCharacterId(src),
        })
        return done(ok, result)
    elseif action == 'impound' then
        if CMVehicles.Persistence then pcall(CMVehicles.Persistence.FlushVehicle, row.id, 'admin_impound') end
        if CMVehicles.Spawn then pcall(CMVehicles.Spawn.DeleteVehicle, row.id) end
        local ok, result = CMVehicles.Location.Transition(row.id, 'IMPOUND', {
            ref = tostring(data.ref or 'impound:admin'), reason = 'admin_recovery',
            actorCharacterId = CMVehicles.Server.GetCharacterId(src),
        })
        return done(ok, result)
    elseif action == 'recall' then
        if GetResourceState('cm-house') ~= 'started' then return done(false, 'cm_house_not_running') end
        local ok, result = exports['cm-house']:AdminRecoverAssignedVehicle(row.id, src)
        return done(ok, result)
    elseif action == 'delete_entity' then
        if CMVehicles.Persistence then pcall(CMVehicles.Persistence.FlushVehicle, row.id, 'admin_delete_entity') end
        local ok, result = CMVehicles.Spawn.DeleteVehicle(row.id)
        return done(ok, result)
    end
    return done(false, 'unknown_action')
end

RegisterCommand('cmvehinspect', function(src, args)
    if src <= 0 or not isAdmin(src) then return end
    local ok, result = R.Action(src, args[1], 'inspect')
    if not ok then return U.Notify(src, tostring(result), 'error') end
    print(('[cm-vehicles] diagnostics requested by %s: %s'):format(src, U.Encode(result)))
    U.Notify(src, ('Vehicle %s: %s | entities %s | duplicates %s'):format(
        result.vehicle.id, result.location and result.location.state or 'UNKNOWN',
        #result.entities, result.duplicateCount), 'info')
end, false)

RegisterCommand('cmvehrecover', function(src, args)
    if src <= 0 or not isAdmin(src) then return end
    local identity, action = args[1], args[2] or 'reconcile'
    local ok, result = R.Action(src, identity, action, { ref = args[3], slot = tonumber(args[4]) })
    U.Notify(src, ok and ('Recovery action completed: ' .. action) or ('Recovery failed: ' .. tostring(result)), ok and 'success' or 'error')
end, false)

exports('GetVehicleDiagnostics', R.Diagnostics)
exports('ListVehicleRecoveryProblems', R.ListProblems)
exports('DeleteDuplicateVehicleEntities', R.DeleteDuplicates)
exports('RunVehicleRecoveryAction', R.Action)
exports('IsVehicleRecoveryAdmin', isAdmin)
