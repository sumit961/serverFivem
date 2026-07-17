-- ============================================================
--  cm-house | sv_garage.lua   |  PHASE 3
--
--  THE ONE RULE: a vehicle exists physically in exactly one place, always.
--
--  cm-vehicles owns physical location (`is_stored`, `garage`, entity registry).
--  cm-house owns the persistent home-space assignment. A vehicle may therefore
--  reserve a house slot while it is outside; Recall returns it to that exact
--  slot, while Remove explicitly frees the assignment.
--
--  Two guards stop the classic duplication bugs:
--    * an in-flight lock, so two rapid clicks cannot both retrieve one car
--    * a UNIQUE key on vehicle_id, so one car cannot hold two slots
-- ============================================================

--- Owned operation-token locks. A stale callback may not unlock a newer
--- operation for the same database vehicle. Each transition can register one
--- idempotent rollback that is run on disconnect, timeout, or explicit failure.
local Operations = {}          -- [vehicleId] = operation
local OperationsBySource = {}  -- [source] = { [vehicleId] = token }
local OPERATION_TTL = 30
local operationSequence = 0
local rollbackOperation

local function lock(vehicleId, action, src)
    vehicleId, src = tonumber(vehicleId), tonumber(src)
    if not vehicleId then return nil end
    local now = os.time()
    local existing = Operations[vehicleId]
    if existing then
        if (now - (existing.startedAt or now)) < OPERATION_TTL then return nil end
        -- Never silently overwrite a stale transition record: run its owned
        -- rollback first so a partially changed DB/slot cannot be hidden by a
        -- newer token for the same vehicle.
        if rollbackOperation then
            rollbackOperation(vehicleId, existing.token, 'stale operation superseded')
        end
        if Operations[vehicleId] then return nil end
    end

    operationSequence = operationSequence + 1
    local token = ('garage-op:%s:%s:%s:%s'):format(vehicleId, tostring(action or 'move'),
        operationSequence, math.random(100000, 999999))
    local op = {
        vehicleId = vehicleId,
        source = src,
        action = tostring(action or 'move'),
        token = token,
        startedAt = now,
        stage = 'started',
        rollback = nil,
        rollingBack = false,
    }
    Operations[vehicleId] = op
    if src then
        OperationsBySource[src] = OperationsBySource[src] or {}
        OperationsBySource[src][vehicleId] = token
    end
    if CMHousePhase2 and CMHousePhase2.BeginOperation then
        local callOk, journalAccepted = pcall(CMHousePhase2.BeginOperation,
            vehicleId, op.action, src, token, { stage = op.stage })
        if not callOk or journalAccepted ~= true then
            -- The durable journal is the cross-resource lock. Do not allow a
            -- local garage transition to proceed while sale/impound/parking or
            -- another garage resource already owns this vehicle.
            Operations[vehicleId] = nil
            if src and OperationsBySource[src] then
                OperationsBySource[src][vehicleId] = nil
                if not next(OperationsBySource[src]) then OperationsBySource[src] = nil end
            end
            return nil
        end
    end
    return token, op
end

local function operationOwned(vehicleId, token)
    local op = Operations[tonumber(vehicleId)]
    return op and op.token == token, op
end

local function setRollback(vehicleId, token, fn, stage)
    local owned, op = operationOwned(vehicleId, token)
    if not owned then return false end
    op.rollback = type(fn) == 'function' and fn or nil
    op.stage = tostring(stage or op.stage)
    op.startedAt = os.time()
    return true
end

local function touchOperation(vehicleId, token, stage, ignoreDisconnect)
    local owned, op = operationOwned(vehicleId, token)
    if not owned then return false end
    op.startedAt = os.time()
    if stage then op.stage = tostring(stage) end
    if ignoreDisconnect ~= nil then op.ignoreDisconnect = ignoreDisconnect == true end
    if CMHousePhase2 and CMHousePhase2.AdvanceOperation then
        pcall(CMHousePhase2.AdvanceOperation, vehicleId, token, op.stage, {
            action = op.action, ignoreDisconnect = op.ignoreDisconnect == true,
        })
    end
    return true
end

local function unlock(vehicleId, token)
    vehicleId = tonumber(vehicleId)
    local owned, op = operationOwned(vehicleId, token)
    if not owned then return false end
    Operations[vehicleId] = nil
    if op.source and OperationsBySource[op.source] then
        OperationsBySource[op.source][vehicleId] = nil
        if not next(OperationsBySource[op.source]) then OperationsBySource[op.source] = nil end
    end
    if op.finalStatus ~= 'failed' and CMHousePhase2 and CMHousePhase2.CompleteOperation then
        pcall(CMHousePhase2.CompleteOperation, vehicleId, token, op.stage or 'completed', {
            action = op.action,
        })
    end
    if GetResourceState('cm-vehicles') == 'started' then
        pcall(function() exports['cm-vehicles']:ReconcileVehicleLocation(vehicleId) end)
    end
    return true
end

rollbackOperation = function(vehicleId, token, reason)
    local owned, op = operationOwned(vehicleId, token)
    if not owned or op.rollingBack then return false end
    op.rollingBack = true
    local ok, result = true, true
    if type(op.rollback) == 'function' then
        ok, result = pcall(op.rollback, tostring(reason or 'operation cancelled'))
    end
    if not ok or result == false then
        print(('[cm-house] ^1garage rollback failed for vehicle %s (%s/%s): %s^7')
            :format(tostring(vehicleId), tostring(op.action), tostring(op.stage), tostring(result)))
    end
    op.finalStatus = 'failed'
    if CMHousePhase2 and CMHousePhase2.FailOperation then
        pcall(CMHousePhase2.FailOperation, vehicleId, token, tostring(reason or 'rollback'), {
            action = op.action, stage = op.stage, rollbackOk = ok and result ~= false,
        })
    end
    unlock(vehicleId, token)
    return ok and result ~= false
end

CreateThread(function()
    while true do
        Wait(5000)
        local now = os.time()
        local stale = {}
        for id, op in pairs(Operations) do
            if (now - (op.startedAt or now)) >= OPERATION_TTL then
                stale[#stale + 1] = { id = id, token = op.token }
            end
        end
        for _, item in ipairs(stale) do rollbackOperation(item.id, item.token, 'operation timeout') end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local owned = OperationsBySource[src]
    if not owned then return end
    local pending = {}
    for id, token in pairs(owned) do
        local isOwned, op = operationOwned(id, token)
        if isOwned and op.ignoreDisconnect == true then
            -- Physical deletion has already started. Rolling the database back
            -- now could leave an outside database row after the entity is gone.
            -- Let the active callback finish and perform its own failure rollback.
            op.source = nil
            op.stage = ('%s_driver_disconnected'):format(tostring(op.stage or 'committing'))
        else
            pending[#pending + 1] = { id = id, token = token }
        end
    end
    OperationsBySource[src] = nil
    CreateThread(function()
        for _, item in ipairs(pending) do rollbackOperation(item.id, item.token, 'player disconnected') end
    end)
end)

-- Real networked vehicles shown inside instantiated garages.
-- [houseId][slotIndex] = { entity, netId, vehicleId, plate }
local GarageEntities = {}

-- Forward declaration: deleteGarageEntity uses this helper before its
-- implementation later in the file. Without this local binding Lua resolves
-- the early call as a global and raises 'attempt to call a nil value'.
local spawnedVehicleInfo

local function decodeTable(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or {}
end


local function sanitizeConditionState(value)
    value = type(value) == 'table' and value or {}
    local out = {
        windowSchema = 2,
        brokenWindows = {},
        doors = {},
        tyres = {},
    }

    -- v1.3.2.6: Legacy snapshots stored every IsVehicleWindowIntact result.
    -- GTA returns false for window indexes/bones a model does not actually have,
    -- so those legacy rows could make all glass smash on every garage recall.
    -- Only schema-2 snapshots are trusted for glass damage. Existing legacy
    -- window maps are intentionally ignored once; the next legitimate storage
    -- captures a fresh model-aware schema-2 snapshot.
    local schema = tonumber(value.windowSchema or value.conditionVersion or value.version) or 0
    if schema >= 2 then
        local broken = type(value.brokenWindows) == 'table' and value.brokenWindows or {}
        for i = 0, 7 do
            local key = tostring(i)
            local isBroken = broken[key]
            if isBroken == nil then isBroken = broken[i] end
            if isBroken == true then out.brokenWindows[key] = true end
        end

        -- Backward-compatible schema-2 reader for early test builds that used
        -- windows[index] = false instead of brokenWindows[index] = true.
        if type(value.windows) == 'table' then
            for i = 0, 7 do
                local key = tostring(i)
                local intact = value.windows[key]
                if intact == nil then intact = value.windows[i] end
                if intact == false then out.brokenWindows[key] = true end
            end
        end
    end

    for i = 0, 7 do
        local key = tostring(i)
        local door = value.doors and (value.doors[key] or value.doors[i])
        if type(door) == 'table' then
            out.doors[key] = {
                damaged = door.damaged == true,
                broken = door.broken == true,
                angle = math.max(0.0, math.min(1.0, tonumber(door.angle) or 0.0)),
            }
        end

        local tyre = value.tyres and (value.tyres[key] or value.tyres[i])
        if type(tyre) == 'table' then
            out.tyres[key] = { burst = tyre.burst == true, onRim = tyre.onRim == true }
        end
    end
    out.engineRunning = value.engineRunning == true
    out.undriveable = value.undriveable == true
    return out
end
local function mergeConditionWear(existing, submitted)
    existing = sanitizeConditionState(existing)
    submitted = sanitizeConditionState(submitted)
    local out = {
        windowSchema = 2,
        brokenWindows = {},
        doors = {},
        tyres = {},
    }
    for i = 0, 7 do
        local key = tostring(i)
        if existing.brokenWindows[key] == true or submitted.brokenWindows[key] == true then
            out.brokenWindows[key] = true
        end

        local oldDoor, newDoor = existing.doors[key], submitted.doors[key]
        if oldDoor or newDoor then
            oldDoor, newDoor = oldDoor or {}, newDoor or {}
            out.doors[key] = {
                damaged = oldDoor.damaged == true or newDoor.damaged == true,
                broken = oldDoor.broken == true or newDoor.broken == true,
                angle = math.max(0.0, math.min(1.0,
                    tonumber(newDoor.angle) or tonumber(oldDoor.angle) or 0.0)),
            }
        end

        local oldTyre, newTyre = existing.tyres[key], submitted.tyres[key]
        if oldTyre or newTyre then
            oldTyre, newTyre = oldTyre or {}, newTyre or {}
            out.tyres[key] = {
                burst = oldTyre.burst == true or newTyre.burst == true,
                onRim = oldTyre.onRim == true or newTyre.onRim == true,
            }
        end
    end
    out.engineRunning = submitted.engineRunning == true
    out.undriveable = submitted.undriveable == true
    return out
end
local function normalizeVehicleHealth(value, defaultValue)
    local fallback = tonumber(defaultValue) or 1000.0
    local n = tonumber(value)

    -- Numeric zero is a valid destroyed condition. Only absent/corrupt/NaN
    -- data falls back. Safe spawn bootstrap health is handled separately by
    -- cm-vehicles and must never replace the saved condition.
    if n == nil or n ~= n then n = fallback end
    if n > 0.0 and n <= 1.0 then n = n * 1000.0 end
    return math.max(0.0, math.min(1000.0, n)) + 0.0
end

local function normalizeVehicleFuel(value, defaultValue)
    local n = tonumber(value)
    if n == nil then n = tonumber(defaultValue) or 100.0 end
    return math.max(0.0, math.min(100.0, n)) + 0.0
end

local function normalizedGarageVehicleRow(row)
    local out = {}
    for key, value in pairs(row or {}) do out[key] = value end

    out.fuel = normalizeVehicleFuel(out.fuel, 100.0)
    out.engine_health = normalizeVehicleHealth(out.engine_health or out.engineHealth, 1000.0)
    out.body_health = normalizeVehicleHealth(out.body_health or out.bodyHealth, 1000.0)
    out.tank_health = normalizeVehicleHealth(out.tank_health or out.tankHealth, 1000.0)
    out.engineHealth = out.engine_health
    out.bodyHealth = out.body_health
    out.tankHealth = out.tank_health
    out.dirt_level = math.max(0.0, math.min(15.0, tonumber(out.dirt_level or out.dirtLevel) or 0.0)) + 0.0
    out.dirtLevel = out.dirt_level
    out.conditionState = decodeTable(out.conditionState or out.condition_state)
    return out
end

local function entityExists(entity)
    if not entity or entity == 0 then return false end
    local ok, exists = pcall(DoesEntityExist, entity)
    return ok and exists == true
end

local function clearSpawnRegistry(vehicleId, plate, timeoutMs)
    if GetResourceState('cm-vehicles') ~= 'started' then
        return false, 'The vehicle system is not running.'
    end

    local callOk, deleted, deleteWhy = pcall(function()
        return exports['cm-vehicles']:DeleteSpawnedVehicle(tonumber(vehicleId) or plate)
    end)
    if not callOk or deleted == false then
        return false, tostring(deleteWhy or deleted or 'cm-vehicles rejected the delete request.')
    end

    -- DeleteSpawnedVehicle is synchronous in the updated cm-vehicles build,
    -- but also verify the registry here so cm-house never requests a new copy
    -- while the previous network identity is still active.
    local deadline = GetGameTimer() + (tonumber(timeoutMs) or 2500)
    repeat
        local okInfo, exists = pcall(function()
            local ok = exports['cm-vehicles']:GetSpawnedVehicleInfo(tonumber(vehicleId) or plate)
            return ok == true
        end)
        if not okInfo then
            return false, 'cm-house could not verify that the old vehicle registry entry was cleared.'
        end
        if exists ~= true then return true end
        Wait(0)
    until GetGameTimer() >= deadline

    return false, 'The old vehicle entity did not leave the cm-vehicles registry in time.'
end

local function deleteGarageEntity(houseId, slotIndex)
    houseId, slotIndex = tonumber(houseId), tonumber(slotIndex)
    local set = houseId and GarageEntities[houseId]
    local entry = set and set[slotIndex]

    -- A slot can remain assigned while its vehicle is outside. Therefore the
    -- slot table alone is NOT proof that the current entity is a garage display.
    local identity = entry and { id = entry.vehicleId, plate = entry.plate } or MySQL.single.await([[
        SELECT v.id, v.plate
        FROM cm_house_vehicle_slots s
        INNER JOIN cm_owned_vehicles v ON v.id = s.vehicle_id
        WHERE s.house_id = ? AND s.slot_index = ?
        LIMIT 1
    ]], { houseId, slotIndex })
    local vehicleId = identity and tonumber(identity.id)
    local plate = identity and identity.plate
    if not vehicleId and (not plate or tostring(plate) == '') then return true end

    local info = spawnedVehicleInfo(vehicleId, plate)
    if info then
        local isThisGarageDisplay = tostring(info.context or '') == 'house_garage'
            and tonumber(info.houseId) == houseId
            and tonumber(info.slotIndex) == slotIndex
        if not isThisGarageDisplay then
            -- Never delete a world entity merely because it owns this slot.
            if set then
                set[slotIndex] = nil
                if not next(set) then GarageEntities[houseId] = nil end
            end
            return true
        end
    elseif not entry then
        return true
    end

    -- cm-vehicles owns the physical OneSync entity and its registry. Delete only
    -- the confirmed garage-display context, synchronously.
    local deleted, why = clearSpawnRegistry(vehicleId, plate)
    if not deleted then return false, why end

    if set then
        set[slotIndex] = nil
        if not next(set) then GarageEntities[houseId] = nil end
    end
    return true
end

local function cleanupGarageEntities(houseId)
    houseId = tonumber(houseId)
    local set = houseId and GarageEntities[houseId]
    if not set then return end
    local indexes = {}
    for slotIndex in pairs(set) do indexes[#indexes + 1] = slotIndex end
    for _, slotIndex in ipairs(indexes) do deleteGarageEntity(houseId, slotIndex) end
end

local function waitForEntity(entity, timeoutMs)
    local deadline = GetGameTimer() + (tonumber(timeoutMs) or 5000)
    while not entityExists(entity) and GetGameTimer() < deadline do Wait(0) end
    return entityExists(entity)
end

local function networkIdFor(entity)
    local netId = 0
    local deadline = GetGameTimer() + 5000
    while netId <= 0 and GetGameTimer() < deadline do
        local ok, value = pcall(NetworkGetNetworkIdFromEntity, entity)
        netId = ok and tonumber(value) or 0
        if netId <= 0 then Wait(0) end
    end
    return netId
end

-- The physical vehicle is owned by cm-vehicles. cm-house keeps only the
-- portable network identity and asks the central registry for lifecycle work.
spawnedVehicleInfo = function(vehicleId, plate)
    if GetResourceState('cm-vehicles') ~= 'started' then return nil end
    local okCall, okResult, info = pcall(function()
        return exports['cm-vehicles']:GetSpawnedVehicleInfo(tonumber(vehicleId) or plate)
    end)
    if not okCall or okResult ~= true or type(info) ~= 'table' then return nil end
    return info
end

local function garageEntryActive(entry)
    if type(entry) ~= 'table' or not entry.plate then return false end
    local info = spawnedVehicleInfo(entry.vehicleId, entry.plate)
    if not info then return false end
    if tostring(info.context or '') ~= 'house_garage' then return false end
    if tonumber(info.houseId) ~= tonumber(entry.houseId)
       or tonumber(info.slotIndex) ~= tonumber(entry.slotIndex) then
        return false
    end
    entry.entity = tonumber(info.entity) or entry.entity or 0
    entry.netId = tonumber(info.netId) or entry.netId or 0
    return tonumber(entry.netId) > 0
end

local function finalizeGarageEntityFor(src, entry, row)
    if GetResourceState('cm-vehicles') ~= 'started' then return false end
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false end

    entry.finalizedFor = entry.finalizedFor or {}
    entry.finalizeAttempts = entry.finalizeAttempts or {}

    -- Server state is authoritative for completion. The previous boolean was
    -- set immediately after sending one client event, so an event delivered
    -- before the network entity streamed permanently suppressed all retries.
    local entity = tonumber(entry.entity) or 0
    if (not entity or entity == 0 or not DoesEntityExist(entity)) and tonumber(entry.netId) and tonumber(entry.netId) > 0 then
        entity = NetworkGetEntityFromNetworkId(tonumber(entry.netId))
        entry.entity = entity or 0
    end
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        local ready = false
        pcall(function() ready = Entity(entity).state.cmConditionReady == true end)
        if ready then
            entry.finalizedFor[src] = true
            entry.finalizeAttempts[src] = nil
            return true
        end
    end

    local now = GetGameTimer()
    local last = tonumber(entry.finalizedFor[src]) or 0
    if last > 0 and now - last < 1500 then return true end
    local attempts = tonumber(entry.finalizeAttempts[src]) or 0
    if attempts >= 8 then
        entry.finalizedFor[src] = nil
        entry.finalizeAttempts[src] = nil
        print(('[cm-house] ^3garage vehicle %s did not acknowledge condition initialization for player %s; it will retry on the next garage sync.^7')
            :format(tostring(entry.vehicleId or entry.plate), tostring(src)))
        return false
    end

    row = normalizedGarageVehicleRow(row)
    local metadata = decodeTable(row.metadata)
    local mods = decodeTable(row.mods)
    TriggerClientEvent('cm-vehicles:client:finalizeSpawn', src, {
        netId = entry.netId,
        id = tonumber(row.id),
        model = row.model,
        label = row.label,
        plate = row.plate,
        fuel = normalizeVehicleFuel(row.fuel, 100.0),
        engineHealth = normalizeVehicleHealth(row.engine_health, 1000.0),
        bodyHealth = normalizeVehicleHealth(row.body_health, 1000.0),
        tankHealth = normalizeVehicleHealth(row.tank_health, 1000.0),
        dirtLevel = tonumber(row.dirt_level) or 0.0,
        locked = false,
        warp = false,
        engineOn = false,
        repairFirst = false,
        garageDisplay = true,
        garageHouseId = tonumber(entry.houseId),
        garageSlot = tonumber(entry.slotIndex),
        metadata = metadata,
        mods = mods,
        conditionState = row.conditionState,
    })
    entry.finalizedFor[src] = now
    entry.finalizeAttempts[src] = attempts + 1

    -- Retry while the same player remains inside the same garage. Client-side
    -- finalization is guarded by netId, so repeated delivery cannot overlap.
    SetTimeout(2000, function()
        if not GetPlayerName(src) or not garageEntryActive(entry) then return end
        local whereHouse, whereKind = WhereIs(src)
        if tonumber(whereHouse) ~= tonumber(entry.houseId) or whereKind ~= 'garage' then return end
        local rowNow = VehicleById(entry.vehicleId)
        if rowNow then finalizeGarageEntityFor(src, entry, rowNow) end
    end)
    return true
end

local GarageCreatePromises = {} -- [database vehicle id] = promise

local function createGarageEntityNow(src, houseId, slot, row)
    if GetResourceState('cm-vehicles') ~= 'started' then
        return nil, 'The vehicle system is not running.'
    end

    local c = slot.coords
    if not c then return nil, 'This garage slot has no vehicle position.' end

    row = normalizedGarageVehicleRow(row)

    -- A new entity request is only allowed after both cm-house's slot registry
    -- and cm-vehicles' central registry have synchronously released any old
    -- copy. The wrapper below serializes this section by database vehicle ID.
    local deleted, deleteWhy = deleteGarageEntity(houseId, slot.index)
    if not deleted then return nil, deleteWhy end

    -- A persistent slot may currently own a world entity. Never delete that
    -- entity from an opportunistic garage refresh while a recall transition is
    -- still moving it into the private bucket.
    local existing = spawnedVehicleInfo(row.id, row.plate)
    if existing then
        return nil, tostring(existing.context or '') == 'world'
            and 'The assigned vehicle is still outside. Use Recall car.'
            or 'The assigned vehicle is already active in another context.'
    end

    local cleared, clearWhy = clearSpawnRegistry(row.id, row.plate)
    if not cleared then return nil, clearWhy end

    -- Do not use server-side CreateVehicle here. Streamed/add-on models can
    -- create a client-visible orphan while the server still reports failure,
    -- which was the source of duplicate recalls and "local display vehicle".
    -- cm-vehicles now performs a tokenised client-assisted NETWORK spawn, then
    -- validates and registers the entity before returning it to cm-house.
    local callOk, created, result = pcall(function()
        return exports['cm-vehicles']:CreateGarageVehicle(src, row, {
            x = c.x + 0.0,
            y = c.y + 0.0,
            z = c.z + 0.0,
            h = (c.h or c.w or 0.0) + 0.0,
        }, {
            bucket = GarageBucket(houseId),
            houseId = tonumber(houseId),
            slotIndex = tonumber(slot.index),
        })
    end)

    if not callOk then
        return nil, ('Vehicle system error: %s'):format(tostring(created))
    end
    if created ~= true or type(result) ~= 'table' then
        return nil, tostring(result or 'The garage vehicle could not be created.')
    end

    local netId = tonumber(result.netId) or 0
    if netId <= 0 then
        clearSpawnRegistry(row.id, row.plate)
        return nil, 'The garage vehicle was created without a valid network id.'
    end

    -- Do not resolve/delete the entity from cm-house. The previous build did
    -- that immediately after cm-vehicles had registered it; propagation timing
    -- made cm-house reject and delete a valid network vehicle, leaving the
    -- client with a temporary local ghost. Configure it through its owner.
    local cfgCall, configured, info = pcall(function()
        return exports['cm-vehicles']:ConfigureHouseGarageVehicle(
            row.id, houseId, slot.index, GarageBucket(houseId))
    end)
    if not cfgCall or configured ~= true or type(info) ~= 'table' then
        clearSpawnRegistry(row.id, row.plate)
        return nil, tostring(info or 'The vehicle system could not configure the garage vehicle.')
    end

    netId = tonumber(info.netId) or netId
    local entry = {
        entity = tonumber(info.entity) or tonumber(result.entity) or 0,
        netId = netId,
        vehicleId = tonumber(row.id),
        plate = tostring(row.plate or ''),
        houseId = tonumber(houseId),
        slotIndex = tonumber(slot.index),
    }
    GarageEntities[houseId] = GarageEntities[houseId] or {}
    GarageEntities[houseId][slot.index] = entry
    finalizeGarageEntityFor(src, entry, row)
    return entry
end

local function createGarageEntity(src, houseId, slot, row)
    local key = row and tonumber(row.id)
    if not key then return nil, 'The vehicle database id is missing.' end

    local pending = GarageCreatePromises[key]
    if pending then
        local shared = Citizen.Await(pending)
        if type(shared) ~= 'table' or not shared.entry then
            return nil, type(shared) == 'table' and shared.error or 'The garage vehicle could not be created.'
        end
        if tonumber(shared.entry.houseId) ~= tonumber(houseId)
           or tonumber(shared.entry.slotIndex) ~= tonumber(slot and slot.index) then
            return nil, 'That vehicle is already being created in another garage space.'
        end
        finalizeGarageEntityFor(src, shared.entry, row)
        return shared.entry
    end

    local deferred = promise.new()
    GarageCreatePromises[key] = deferred

    local callOk, entry, why = pcall(createGarageEntityNow, src, houseId, slot, row)
    local result
    if callOk and entry then
        result = { entry = entry }
    else
        result = { error = callOk and why or tostring(entry) }
    end

    deferred:resolve(result)
    if GarageCreatePromises[key] == deferred then GarageCreatePromises[key] = nil end

    if not result.entry then return nil, result.error end
    return result.entry
end

local function ensureGarageEntity(src, houseId, slot, row)
    houseId = tonumber(houseId)
    local slotIndex = tonumber(slot and slot.index)
    if not houseId or not slotIndex or not row then return nil, 'Garage data is incomplete.' end

    local set = GarageEntities[houseId]
    local entry = set and set[slotIndex]
    if entry and (tonumber(entry.vehicleId) ~= tonumber(row.id) or not garageEntryActive(entry)) then
        local deleted, why = deleteGarageEntity(houseId, slotIndex)
        if not deleted then return nil, why end
        entry = nil
    end

    -- cm-house may have restarted while cm-vehicles kept the persistent garage
    -- entity. Rebuild the local slot registry instead of deleting a valid copy.
    if not entry then
        local info = spawnedVehicleInfo(row.id, row.plate)
        if info and tostring(info.context or '') == 'house_garage'
           and tonumber(info.houseId) == houseId
           and tonumber(info.slotIndex) == slotIndex then
            entry = {
                entity = tonumber(info.entity) or 0,
                netId = tonumber(info.netId) or 0,
                vehicleId = tonumber(row.id),
                plate = tostring(row.plate or ''),
                houseId = houseId,
                slotIndex = slotIndex,
            }
            GarageEntities[houseId] = GarageEntities[houseId] or {}
            GarageEntities[houseId][slotIndex] = entry
        end
    end

    if not entry then
        return createGarageEntity(src, houseId, slot, row)
    end

    finalizeGarageEntityFor(src, entry, row)
    return entry
end

local function refreshGarageEntitiesFor(src, houseId)
    local state = GarageState(houseId)
    if not state then return false, 'This garage is unavailable.' end

    -- Only vehicles physically stored in this garage receive a display entity.
    -- A vehicle may still own/reserve a slot while it is outside in the city.
    local valid = {}
    for _, slot in pairs(state.slots or {}) do
        if slot.vehicle and slot.vehicle.inGarage == true then
            valid[tonumber(slot.index)] = tonumber(slot.vehicle.id)
            local row = VehicleById(slot.vehicle.id)
            if row then
                local _, why = ensureGarageEntity(src, houseId, slot, row)
                if why then return false, why end
            end
        end
    end

    local set = GarageEntities[tonumber(houseId)]
    if set then
        local stale = {}
        for slotIndex, entry in pairs(set) do
            if valid[tonumber(slotIndex)] ~= tonumber(entry.vehicleId) then
                stale[#stale + 1] = slotIndex
            end
        end
        for _, slotIndex in ipairs(stale) do deleteGarageEntity(houseId, slotIndex) end
    end

    return true
end

local function garageKey(houseId) return ('house:%d'):format(houseId) end


local function requireInsideGarage(src, houseId)
    houseId = tonumber(houseId)
    if not houseId then return false, 'That property does not exist.' end
    local whereHouse, whereKind = WhereIs(src)
    if tonumber(whereHouse) ~= houseId or whereKind ~= 'garage' then
        return false, 'You must be inside this garage to use its parking controls.'
    end
    return true
end

local STATUS_LABELS = {
    AVAILABLE = 'Available',
    PARKED_HERE = 'Parked here',
    RESERVED_OUTSIDE = 'Reserved — vehicle outside',
    PARKED_OTHER_SLOT = 'Vehicle parked in another slot',
    OCCUPIED = 'Vehicle occupied',
    IMPOUNDED = 'Impounded',
    POLICE_SEIZED = 'Police seized',
    MISSING_ENTITY = 'Missing entity — recovery available',
    OPERATION_IN_PROGRESS = 'Operation in progress',
    STORED_ELSEWHERE = 'Stored elsewhere',
}

local function vehicleGarageStatus(v, houseId)
    if not v then return 'AVAILABLE', STATUS_LABELS.AVAILABLE, false end
    local vehicleId = tonumber(v.id)
    if vehicleId and Operations[vehicleId] then
        return 'OPERATION_IN_PROGRESS', STATUS_LABELS.OPERATION_IN_PROGRESS, false
    end
    if GetResourceState('cm-vehicles') == 'started' and vehicleId then
        local okBusy, busy = pcall(function()
            return exports['cm-vehicles']:IsVehicleOperationActive(vehicleId)
        end)
        if okBusy and busy == true then
            return 'OPERATION_IN_PROGRESS', STATUS_LABELS.OPERATION_IN_PROGRESS, false
        end
    end

    local location = tostring(v.location_state or ''):upper()
    if location == 'IMPOUND' then return 'IMPOUNDED', STATUS_LABELS.IMPOUNDED, false end
    if location == 'POLICE_SEIZED' then return 'POLICE_SEIZED', STATUS_LABELS.POLICE_SEIZED, false end

    local inGarage = DbBool(v.is_stored) and tostring(v.garage or '') == garageKey(houseId)
    if inGarage then
        local info = spawnedVehicleInfo(vehicleId, v.plate)
        if info then
            local entity = tonumber(info.entity) or 0
            if entity ~= 0 and DoesEntityExist(entity) then
                local maxPassengers = 6
                pcall(function() maxPassengers = math.max(0, GetVehicleMaxNumberOfPassengers(entity)) end)
                for seat = -1, maxPassengers do
                    local ped = 0
                    pcall(function() ped = GetPedInVehicleSeat(entity, seat) end)
                    if ped and ped ~= 0 then return 'OCCUPIED', STATUS_LABELS.OCCUPIED, false end
                end
            end
        end
        return 'PARKED_HERE', STATUS_LABELS.PARKED_HERE, true
    end

    local info = spawnedVehicleInfo(vehicleId, v.plate)
    if location == 'OUTSIDE' and not info then
        return 'MISSING_ENTITY', STATUS_LABELS.MISSING_ENTITY, true
    end
    if DbBool(v.is_stored) then return 'STORED_ELSEWHERE', STATUS_LABELS.STORED_ELSEWHERE, false end
    return 'RESERVED_OUTSIDE', STATUS_LABELS.RESERVED_OUTSIDE, true
end

-- ------------------------------------------------------------
--  Read the garage
-- ------------------------------------------------------------
--- What is actually parked here, laid out against the physical slots.
function GarageState(houseId)
    houseId = tonumber(houseId) or houseId
    local house = Houses[houseId]
    if not house or not house.garage_template_id then return nil end

    local g = GarageTemplates[house.garage_template_id]
    if not g then return nil end

    -- Read every slot reservation. A reserved vehicle may be physically inside
    -- this garage or currently outside; the assignment remains authoritative.
    local assigned = GarageVehicles(houseId)

    local byIndex = {}
    for _, v in ipairs(assigned) do
        local index = tonumber(v.slot_index)
        if index then byIndex[index] = v end
    end

    local capacity = tonumber(g.capacity) or 0
    local slots = {}
    local used = 0
    for i = 1, capacity do
        local s = g.slots[i]
        if s then
            local v = byIndex[i]
            local inGarage = v ~= nil and DbBool(v.is_stored)
                and tostring(v.garage or '') == garageKey(houseId)
            local statusCode, statusLabel, recoverable = vehicleGarageStatus(v, houseId)
            if v then used = used + 1 end
            slots[i] = {
                index  = i,
                coords = s.coords,
                icon   = s.icon,
                empty  = v == nil,
                vehicle = v and {
                    id      = v.id,
                    plate   = v.plate,
                    model   = v.model,
                    label   = v.label,
                    fuel    = normalizeVehicleFuel(v.fuel, 100.0),
                    engine  = normalizeVehicleHealth(v.engine_health, 1000.0),
                    body    = normalizeVehicleHealth(v.body_health, 1000.0),
                    tank    = normalizeVehicleHealth(v.tank_health, 1000.0),
                    ownerCid = tonumber(v.owner_character_id),
                    shared  = v.owner_class == 'family',
                    assigned = true,
                    inGarage = inGarage,
                    outside = not inGarage,
                    locationState = tostring(v.location_state or (inGarage and 'HOUSE_GARAGE' or 'OUTSIDE')),
                    locationRef = v.location_ref,
                    locationSlot = tonumber(v.location_slot),
                    statusCode = statusCode,
                    statusLabel = statusLabel,
                    recoverable = recoverable == true,
                } or nil,
                statusCode = statusCode,
                statusLabel = statusLabel,
            }
        end
    end

    local family = house.family_id and GetFamilyDisplay(house.family_id) or nil
    return {
        houseId  = houseId,
        familyId = house.family_id,
        familyName = family and tostring(family.name or family.label or '') or nil,
        isFamilyGarage = house.family_id ~= nil,
        capacity = capacity,
        slots    = slots,
        used     = used,
        vehicleExit = g.vehicle_exit,
        vehicleExits = g.vehicle_exits,
    }
end

lib.callback.register('cm-house:server:garageState', function(src, houseId)
    houseId = tonumber(houseId)
    local inside, insideWhy = requireInsideGarage(src, houseId)
    if not inside then return nil, insideWhy end
    local cid = GetCid(src)
    local ok, why = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_VIEW)
    if not ok then return nil, why end
    return GarageState(houseId)
end)

lib.callback.register('cm-house:server:ensureGarageVehicles', function(src, houseId)
    houseId = tonumber(houseId)
    local inside, insideWhy = requireInsideGarage(src, houseId)
    if not inside then return false, insideWhy end
    local cid = GetCid(src)
    local ok, why = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_VIEW)
    if not ok then return false, why end
    return refreshGarageEntitiesFor(src, houseId)
end)

--- Every vehicle owned by this character, including cars already parked in
--- another house slot. The slot menu uses this to offer both PARK and CALL
--- actions instead of hiding parked cars from the owner.
lib.callback.register('cm-house:server:parkable', function(src, houseId)
    houseId = tonumber(houseId)
    local inside, insideWhy = requireInsideGarage(src, houseId)
    if not inside then return nil, insideWhy end
    local cid = GetCid(src)
    local ok, why = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_SPAWN_OWN)
    if not ok then return nil, why end

    local rows = MySQL.query.await([[
        SELECT v.id, v.plate, v.model, v.label, v.is_stored, v.garage,
               v.location_state, v.location_ref, v.location_slot,
               s.house_id AS assigned_house_id, s.slot_index AS assigned_slot_index,
               h.label AS assigned_house_label
        FROM cm_owned_vehicles v
        LEFT JOIN cm_house_vehicle_slots s ON s.vehicle_id = v.id
        LEFT JOIN cm_houses h ON h.id = s.house_id
        WHERE v.owner_character_id = ?
        ORDER BY v.id DESC
    ]], { tostring(cid) }) or {}

    local out = {}
    for _, v in ipairs(rows) do
        local assignedHouseId = tonumber(v.assigned_house_id)
        local assignedSlotIndex = tonumber(v.assigned_slot_index)
        local assigned = assignedHouseId ~= nil and assignedSlotIndex ~= nil
        local inAssignedGarage = assigned and DbBool(v.is_stored)
            and tostring(v.garage or '') == garageKey(assignedHouseId)
        local storedElsewhere = DbBool(v.is_stored) and not inAssignedGarage
        local locationState = tostring(v.location_state or (DbBool(v.is_stored) and 'STORED' or 'OUTSIDE')):upper()
        local operationActive = false
        if GetResourceState('cm-vehicles') == 'started' then
            local okBusy, busy = pcall(function() return exports['cm-vehicles']:IsVehicleOperationActive(v.id) end)
            operationActive = okBusy and busy == true
        end
        local blockedState = locationState == 'IMPOUND' or locationState == 'POLICE_SEIZED'
            or locationState == 'PENDING_DELETE' or operationActive
        local statusCode = operationActive and 'OPERATION_IN_PROGRESS'
            or (locationState == 'IMPOUND' and 'IMPOUNDED')
            or (locationState == 'POLICE_SEIZED' and 'POLICE_SEIZED')
            or (inAssignedGarage and 'PARKED_OTHER_SLOT')
            or (assigned and 'RESERVED_OUTSIDE')
            or (not DbBool(v.is_stored) and 'AVAILABLE')
            or 'STORED_ELSEWHERE'

        out[#out + 1] = {
            id = tonumber(v.id),
            plate = tostring(v.plate or ''),
            model = tostring(v.model or ''),
            label = tostring(v.label or v.model or 'Vehicle'),
            isStored = DbBool(v.is_stored),
            assigned = assigned,
            parked = assigned,
            inGarage = inAssignedGarage,
            parkedHouseId = assignedHouseId,
            parkedSlotIndex = assignedSlotIndex,
            parkedHouseLabel = tostring(v.assigned_house_label
                or (assignedHouseId and ('House %d'):format(assignedHouseId)) or ''),
            -- Empty slots can call an already-assigned owned car. The move
            -- callback atomically clears its previous slot before assigning this
            -- one. Vehicles held by a different storage authority stay blocked.
            canPark = not blockedState and not assigned and not DbBool(v.is_stored),
            canCall = not blockedState and assigned and (not DbBool(v.is_stored) or inAssignedGarage),
            locationState = locationState,
            locationRef = v.location_ref,
            locationSlot = tonumber(v.location_slot),
            statusCode = statusCode,
            statusLabel = STATUS_LABELS[statusCode] or statusCode,
            unavailableReason = blockedState
                and (STATUS_LABELS[statusCode] or statusCode)
                or storedElsewhere
                and tostring(v.garage or 'Stored elsewhere')
                or (assigned and ('Assigned to %s · space %d'):format(
                    tostring(v.assigned_house_label or ('House %d'):format(assignedHouseId)),
                    assignedSlotIndex) or nil),
        }
    end
    return out
end)

-- ------------------------------------------------------------
--  RELEASE / DRIVE OUT
--  The parked vehicle already exists as a real network entity inside the
--  garage bucket. Driving it out promotes that SAME entity. Menu-based CALL
--  uses the fresh-world service below so it can recover missing/invisible
--  entities and can call a car from any other house parking space.
-- ------------------------------------------------------------
local function readVehicleCondition(entry, row)
    local okCall, okResult, condition = pcall(function()
        return exports['cm-vehicles']:GetSpawnedVehicleCondition(entry.vehicleId, row)
    end)
    if okCall and okResult == true and type(condition) == 'table' then
        return condition
    end
    return {
        fuel = math.max(0.0, math.min(100.0, tonumber(row.fuel) or 100.0)),
        engine = normalizeVehicleHealth(row.engine_health, 1000.0),
        body = normalizeVehicleHealth(row.body_health, 1000.0),
        tank = normalizeVehicleHealth(row.tank_health, 1000.0),
        dirt = tonumber(row.dirt_level) or 0.0,
        conditionState = decodeTable(row.condition_state),
    }
end

local function checkSeatAccess(src, cid, houseId, seat, vehicle)
    local isOwner = tonumber(vehicle.owner_character_id) == tonumber(cid)
    if not isOwner then
        if seat.owner_class ~= 'family' then return false, 'That is not your vehicle.' end
        local okFam, whyFam = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_SPAWN_FAMILY)
        if not okFam then return false, whyFam end
        -- Per-vehicle family LEVEL gate. cm-family owns the required tier for
        -- each shared vehicle; property-level family access alone is not enough.
        -- Fails closed only when cm-family is running and explicitly denies, so
        -- servers without cm-family are unaffected.
        local famRes = tostring(Config.Family and Config.Family.resource or 'cm-family')
        if Config.Family and Config.Family.enabled and GetResourceState(famRes) == 'started' then
            local vehId = tonumber(vehicle.id) or tonumber(seat.vehicle_id)
            local okLevel, allowed = pcall(function()
                return exports[famRes]:CanUseFamilyVehicle(cid, vehId, 'spawn')
            end)
            if not okLevel or allowed ~= true then
                return false, okLevel
                    and 'This vehicle is private or your family rank cannot use it.'
                    or 'Family vehicle access could not be verified.'
            end
        end
    else
        local okOwn, whyOwn = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_SPAWN_OWN)
        if not okOwn then return false, whyOwn end
    end
    return true
end

local function releaseGarageVehicle(src, houseId, slotIndex, requireDriver, submitted, exitIndex)
    houseId, slotIndex = tonumber(houseId), tonumber(slotIndex)
    local inside, insideWhy = requireInsideGarage(src, houseId)
    if not inside then return false, insideWhy end
    local cid = GetCid(src)
    local house = houseId and Houses[houseId]
    if not house then return false, 'That property does not exist.' end
    local garageTemplate = house.garage_template_id and GarageTemplates[tonumber(house.garage_template_id)]
    if not garageTemplate then return false, 'This property garage template is unavailable.' end

    local okSlot, whySlot = ValidSlot(houseId, slotIndex)
    if not okSlot then return false, whySlot end

    local seat = MySQL.single.await(
        'SELECT vehicle_id, owner_class, assigned_by, assigned_at FROM cm_house_vehicle_slots WHERE house_id = ? AND slot_index = ?',
        { houseId, slotIndex })
    if not seat or not seat.vehicle_id then return false, 'That space is empty.' end

    local vehicle = VehicleById(seat.vehicle_id)
    if not vehicle then
        MySQL.update.await(
            'UPDATE cm_house_vehicle_slots SET vehicle_id = NULL WHERE house_id = ? AND slot_index = ?',
            { houseId, slotIndex })
        deleteGarageEntity(houseId, slotIndex)
        return false, 'That vehicle no longer exists.'
    end

    local allowed, why = checkSeatAccess(src, cid, houseId, seat, vehicle)
    if not allowed then return false, why end
    if not DbBool(vehicle.is_stored) or tostring(vehicle.garage or '') ~= garageKey(houseId) then
        -- The space remains assigned while its vehicle is outside. Never clear
        -- the reservation merely because the physical car has left the garage.
        deleteGarageEntity(houseId, slotIndex)
        return false, 'That vehicle is currently outside. Use Recall car to bring it back to this space.'
    end

    local state = GarageState(houseId)
    local slot = state and state.slots and state.slots[slotIndex]
    if not slot or not slot.coords then return false, 'That garage space is not configured.' end
    local entry, ensureWhy = ensureGarageEntity(src, houseId, slot, vehicle)
    if not entry then return false, ensureWhy or 'The parked vehicle is not ready.' end
    if not garageEntryActive(entry) then return false, 'The parked vehicle is not available.' end

    if requireDriver then
        local driveCall, driving, driveWhy = pcall(function()
            return exports['cm-vehicles']:IsPlayerDrivingSpawnedVehicle(src, vehicle.id, entry.netId)
        end)
        if not driveCall or driving ~= true then
            return false, tostring(driveWhy or 'You must be in the driver seat of this vehicle.')
        end

        -- A template can have several exits. Validate the exact exit used so a
        -- modified client cannot drive out from the middle of the garage.
        local exits = garageTemplate.vehicle_exits or {}
        if #exits == 0 and garageTemplate.vehicle_exit then exits = { garageTemplate.vehicle_exit } end
        local chosen = exits[tonumber(exitIndex) or 0]
        if not chosen then return false, 'That garage exit does not exist.' end
        local ped = GetPlayerPed(src)
        local driven = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
        if not driven or driven == 0 then return false, 'You must be driving the vehicle.' end
        local pos = GetEntityCoords(driven)
        local maxDistance = tonumber(Config.GarageTemplate and Config.GarageTemplate.exitUseDistance) or 1.35
        if #(pos - vector3(chosen.x + 0.0, chosen.y + 0.0, chosen.z + 0.0)) > maxDistance + 0.75 then
            return false, 'Move the vehicle closer to the selected garage exit.'
        end
    end

    local spawn = house.vehicle_exit
    if not spawn then return false, 'This property has no outside vehicle exit.' end
    local opToken = lock(vehicle.id, requireDriver and 'drive_out' or 'call_outside', src)
    if not opToken then return false, 'That vehicle is already being moved.' end

    local condition = readVehicleCondition(entry, vehicle)
    submitted = type(submitted) == 'table' and submitted or nil
    if requireDriver and submitted then
        local function worsen(value, current)
            local n = tonumber(value)
            if n == nil or n ~= n then return current end
            return math.min(current, math.max(0.0, math.min(1000.0, n)))
        end
        condition.fuel = math.min(tonumber(condition.fuel) or 100.0,
            math.max(0.0, math.min(100.0, tonumber(submitted.fuel) or tonumber(condition.fuel) or 100.0)))
        condition.engine = worsen(submitted.engine, normalizeVehicleHealth(condition.engine, 1000.0))
        condition.body = worsen(submitted.body, normalizeVehicleHealth(condition.body, 1000.0))
        condition.tank = worsen(submitted.tank, normalizeVehicleHealth(condition.tank, 1000.0))
        condition.dirt = math.max(tonumber(condition.dirt) or 0.0,
            math.max(0.0, math.min(15.0, tonumber(submitted.dirt) or 0.0)))
        condition.conditionState = mergeConditionWear(
            condition.conditionState or decodeTable(vehicle.condition_state), submitted.conditionState)
    end
    local conditionState = sanitizeConditionState(condition.conditionState or decodeTable(vehicle.condition_state))
    local lastPosition = json.encode({
        x = spawn.x + 0.0, y = spawn.y + 0.0, z = spawn.z + 0.0,
        w = (spawn.h or spawn.w or 0.0) + 0.0,
    })

    if not operationOwned(vehicle.id, opToken) or not GetPlayerName(src) then
        if operationOwned(vehicle.id, opToken) then unlock(vehicle.id, opToken) end
        return false, 'The vehicle move was cancelled before the database transition.'
    end

    local promoted = false
    setRollback(vehicle.id, opToken, function()
        local rollbackOk, rolledBack = pcall(function()
            return MySQL.update.await([[
                UPDATE cm_owned_vehicles v
                INNER JOIN cm_house_vehicle_slots s
                    ON s.vehicle_id = v.id AND s.house_id = ? AND s.slot_index = ?
                SET v.is_stored = 1, v.garage = ?, v.parking_id = ?, v.parked_at = NOW(),
                    v.is_locked = 0
                WHERE v.id = ? AND v.is_stored = 0
            ]], {
                houseId, slotIndex, garageKey(houseId), slotIndex, vehicle.id,
            })
        end)

        if not rollbackOk then return false end
        if not rolledBack or tonumber(rolledBack) <= 0 then
            -- A rollback may run before the guarded release actually commits
            -- (disconnect/query error). Treat the already-original state as a
            -- successful no-op instead of reporting a false critical failure.
            local current = MySQL.single.await([[
                SELECT v.is_stored, v.garage, s.vehicle_id
                FROM cm_owned_vehicles v
                LEFT JOIN cm_house_vehicle_slots s
                    ON s.house_id = ? AND s.slot_index = ?
                WHERE v.id = ? LIMIT 1
            ]], { houseId, slotIndex, vehicle.id })
            if not current or not DbBool(current.is_stored)
               or tostring(current.garage or '') ~= garageKey(houseId)
               or tonumber(current.vehicle_id) ~= tonumber(vehicle.id) then
                return false
            end
        end

        if promoted and GetResourceState('cm-vehicles') == 'started' then
            local okReturn, returned, info = pcall(function()
                return exports['cm-vehicles']:ReturnHouseGarageVehicle(vehicle.id, houseId, slotIndex,
                    GarageBucket(houseId), slot.coords)
            end)
            if not okReturn or returned ~= true then
                pcall(function() exports['cm-vehicles']:DeleteSpawnedVehicle(vehicle.id) end)
                print(('[cm-house] failed to return vehicle %s to garage during rollback: %s')
                    :format(vehicle.id, tostring(info or returned)))
            elseif type(info) == 'table' then
                GarageEntities[houseId] = GarageEntities[houseId] or {}
                GarageEntities[houseId][slotIndex] = {
                    entity = tonumber(info.entity) or 0, netId = tonumber(info.netId) or 0,
                    vehicleId = vehicle.id, plate = vehicle.plate,
                    houseId = houseId, slotIndex = slotIndex,
                }
            end
        end
        if requireDriver and GetPlayerName(src) then SendToGarage(src, houseId) end
        BroadcastGarage(houseId)
        return true
    end, 'release_prepared')

    -- Keep the token owned while the guarded write yields. If the driver
    -- disconnects during this exact window, playerDropped marks the operation
    -- detached but does not unlock it; the installed rollback handles either
    -- an already-committed transition or the unchanged original state.
    touchOperation(vehicle.id, opToken, 'releasing_database', true)
    local updateOk, affected = pcall(function()
        return MySQL.update.await([[
            UPDATE cm_owned_vehicles v
            INNER JOIN cm_house_vehicle_slots s
                ON s.vehicle_id = v.id AND s.house_id = ? AND s.slot_index = ?
            SET v.is_stored = 0, v.garage = NULL, v.parking_id = ?, v.parked_at = NULL,
                v.is_locked = 0, v.fuel = ?, v.engine_health = ?, v.body_health = ?,
                v.tank_health = ?, v.dirt_level = ?, v.condition_state = ?, v.last_position = ?
            WHERE v.id = ? AND v.is_stored = 1 AND v.garage = ?
        ]], {
            houseId, slotIndex, slotIndex,
            math.floor(condition.fuel + 0.5), condition.engine, condition.body,
            condition.tank, condition.dirt, json.encode(conditionState), lastPosition,
            vehicle.id, garageKey(houseId),
        })
    end)

    if not updateOk or not affected or tonumber(affected) <= 0 then
        rollbackOperation(vehicle.id, opToken, updateOk
            and 'release database guard rejected the transition'
            or 'release database query failed')
        return false, updateOk
            and 'That vehicle was already moved or the parking space changed.'
            or 'The vehicle database update failed; its garage state was restored.'
    end

    touchOperation(vehicle.id, opToken, 'database_released', false)

    local owned = operationOwned(vehicle.id, opToken)
    if not owned or not GetPlayerName(src) then
        rollbackOperation(vehicle.id, opToken, 'player unavailable before promotion')
        return false, 'The vehicle move was cancelled.'
    end

    touchOperation(vehicle.id, opToken, 'promoting_entity')
    local promoteCall, promotedOk, promoteInfo = pcall(function()
        return exports['cm-vehicles']:PromoteHouseGarageVehicle(vehicle.id, src, {
            x = spawn.x, y = spawn.y, z = spawn.z, h = spawn.h or spawn.w or 0.0,
        })
    end)
    if not promoteCall or promotedOk ~= true then
        rollbackOperation(vehicle.id, opToken, 'vehicle promotion failed')
        return false, tostring(promoteInfo or 'The vehicle could not be moved outside.')
    end
    promoted = true
    entry.netId = tonumber(type(promoteInfo) == 'table' and promoteInfo.netId) or entry.netId

    -- A disconnect/timeout can run while the export yields. If this token no
    -- longer owns the transition, the DB rollback has already happened; return
    -- the promoted entity immediately instead of leaving a world duplicate.
    if not operationOwned(vehicle.id, opToken) then
        pcall(function()
            exports['cm-vehicles']:ReturnHouseGarageVehicle(vehicle.id, houseId, slotIndex,
                GarageBucket(houseId), slot.coords)
        end)
        return false, 'The vehicle move was cancelled while it was being prepared.'
    end

    -- Remove only the temporary garage display entry. The database slot
    -- reservation intentionally remains assigned to this vehicle while outside.
    local set = GarageEntities[houseId]
    if set then
        set[slotIndex] = nil
        if not next(set) then GarageEntities[houseId] = nil end
    end

    if requireDriver then
        touchOperation(vehicle.id, opToken, 'moving_player_to_world')
        SendToWorld(src)
        Wait(0)
        if not GetPlayerName(src) or GetPlayerRoutingBucket(src) ~= 0 then
            rollbackOperation(vehicle.id, opToken, 'world bucket transfer failed')
            return false, 'The world transition failed; the vehicle was returned to its garage space.'
        end
    end

    unlock(vehicle.id, opToken)

    LogHouse(houseId, house.family_id, cid,
        requireDriver and 'garage_drive_out' or 'garage_recall', {
            vehicle = vehicle.id, plate = vehicle.plate, model = vehicle.model, slot = slotIndex,
        })
    BroadcastGarage(houseId)

    if requireDriver then
        TriggerClientEvent('cm-house:client:garageVehicleExited', src, entry.netId, {
            x = spawn.x, y = spawn.y, z = spawn.z, h = spawn.h or spawn.w or 0.0,
        })
        return true, ('You drove %s outside.'):format(vehicle.label or vehicle.plate)
    end
    return true, ('%s is outside but remains assigned to space %d.'):format(vehicle.label or vehicle.plate, slotIndex)
end

-- Empty parking spaces use callVehicleById below. It moves an already
-- assigned owned vehicle from its previous reserved space into the selected
-- space. The old assignment is cleared in the same database transaction.

lib.callback.register('cm-house:server:takeVehicle', function()
    return false, 'This action is no longer used. Drive the physical garage vehicle out with E, or use Recall car to return it.'
end)

-- Resolve the driver's network vehicle back to its physical parking slot.
-- The client state bag is only a hint: ownership migration can delay it, while
-- the central cm-vehicles registry and GarageEntities remain authoritative.
local function garageSlotFromNetId(houseId, requestedSlot, netId)
    houseId, requestedSlot, netId = tonumber(houseId), tonumber(requestedSlot), tonumber(netId)
    if not houseId or not netId or netId <= 0 then return nil end

    local set = GarageEntities[houseId]
    if set and requestedSlot and requestedSlot > 0 then
        local entry = set[requestedSlot]
        if entry and garageEntryActive(entry) and tonumber(entry.netId) == netId then
            return requestedSlot, entry
        end
    end

    if set then
        for index, entry in pairs(set) do
            if garageEntryActive(entry) and tonumber(entry.netId) == netId then
                return tonumber(index), entry
            end
        end
    end

    -- Resource restarts or a late registry propagation can leave the in-memory
    -- seating map empty. Rebuild only the matching slot from cm-vehicles.
    local state = GarageState(houseId)
    for index, slot in pairs(state and state.slots or {}) do
        if slot.vehicle and slot.vehicle.plate then
            local info = spawnedVehicleInfo(slot.vehicle.id, slot.vehicle.plate)
            if info and tostring(info.context or '') == 'house_garage'
               and tonumber(info.houseId) == houseId
               and tonumber(info.netId) == netId then
                local rebuilt = {
                    entity = tonumber(info.entity) or 0,
                    netId = tonumber(info.netId) or netId,
                    vehicleId = tonumber(slot.vehicle.id),
                    plate = tostring(slot.vehicle.plate or ''),
                    houseId = houseId,
                    slotIndex = tonumber(index),
                }
                GarageEntities[houseId] = GarageEntities[houseId] or {}
                GarageEntities[houseId][tonumber(index)] = rebuilt
                return tonumber(index), rebuilt
            end
        end
    end

    -- Final authority is the database vehicle_id assignment, not a client slot
    -- state bag. This also repairs vehicles whose G-menu registration from an
    -- older build accidentally erased cmHouseSlot/context in memory.
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        local vehicleId, entityPlate
        pcall(function()
            local entityState = Entity(entity).state
            vehicleId = tonumber(entityState.cmVehicleId)
            entityPlate = tostring(entityState.cmPlate or '')
        end)

        if vehicleId and vehicleId > 0 then
            local assigned = MySQL.single.await([[
                SELECT slot_index
                FROM cm_house_vehicle_slots
                WHERE house_id = ? AND vehicle_id = ?
                LIMIT 1
            ]], { houseId, vehicleId })
            local dbSlot = assigned and tonumber(assigned.slot_index) or nil
            local vehicle = dbSlot and VehicleById(vehicleId) or nil
            if dbSlot and vehicle and DbBool(vehicle.is_stored)
               and tostring(vehicle.garage or '') == garageKey(houseId) then
                local slot = state and state.slots and state.slots[dbSlot]
                if slot and slot.coords then
                    pcall(function()
                        exports['cm-vehicles']:ConfigureHouseGarageVehicle(
                            vehicleId, houseId, dbSlot, GarageBucket(houseId))
                    end)
                    local repaired = {
                        entity = entity,
                        netId = netId,
                        vehicleId = vehicleId,
                        plate = tostring(vehicle.plate or entityPlate or ''),
                        houseId = houseId,
                        slotIndex = dbSlot,
                    }
                    GarageEntities[houseId] = GarageEntities[houseId] or {}
                    GarageEntities[houseId][dbSlot] = repaired
                    return dbSlot, repaired
                end
            end
        end
    end

    return nil
end

lib.callback.register('cm-house:server:driveVehicleOut', function(src, houseId, slotIndex, netId, exitIndex, submitted)
    -- Compatibility with v1.5 clients where the fifth argument was condition.
    if type(exitIndex) == 'table' and submitted == nil then submitted, exitIndex = exitIndex, nil end
    houseId, slotIndex, netId, exitIndex = tonumber(houseId), tonumber(slotIndex), tonumber(netId), tonumber(exitIndex)
    local whereHouse, whereKind = WhereIs(src)
    if tonumber(whereHouse) ~= houseId or whereKind ~= 'garage' then
        return false, 'You are not inside this garage.'
    end

    -- Do not trust the slot supplied by a delayed client state bag. Derive the
    -- network id from the actual driver vehicle when needed, then resolve it
    -- against the server's garage registry.
    if not netId or netId <= 0 then
        local ped = GetPlayerPed(src)
        local veh = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
        if veh and veh ~= 0 then
            local okNet, resolved = pcall(NetworkGetNetworkIdFromEntity, veh)
            netId = okNet and tonumber(resolved) or 0
        end
    end

    if not netId or netId <= 0 then
        return false, 'The vehicle is not network-ready yet.'
    end

    local resolvedSlot = garageSlotFromNetId(houseId, slotIndex, netId)
    if not resolvedSlot then
        return false, 'This vehicle is not registered in one of this garage’s parking spaces.'
    end

    return releaseGarageVehicle(src, houseId, resolvedSlot, true, submitted, exitIndex)
end)

-- ------------------------------------------------------------
--  STORE  --  drive into the return zone
--  cm-vehicles has no way to put a car back, so this is where it happens.
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:storeVehicle', function(src, houseId, plate, submitted)
    houseId = tonumber(houseId)
    local cid = GetCid(src)
    local house = Houses[houseId]
    if not house then return false, 'That property does not exist.' end
    if not house.garage_template_id then return false, 'This property has no garage.' end
    local garage = GarageTemplates[house.garage_template_id]
    if not garage then return false, 'This property garage template is unavailable.' end

    local okPerm, whyPerm = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_ENTER)
    if not okPerm then return false, whyPerm end

    plate = tostring(plate or ''):gsub('%s+$', '')
    local v = VehicleByPlate(plate)
    if not v then return false, 'That vehicle is not owned by anyone.' end

    local isOwner = tonumber(v.owner_character_id) == tonumber(cid)
    if not isOwner then
        local shared = MySQL.scalar.await(
            'SELECT house_id FROM cm_house_shared_vehicles WHERE vehicle_id = ?', { v.id })
        if tonumber(shared) ~= houseId then return false, 'That is not your vehicle.' end
        local okFam = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_SPAWN_FAMILY)
        if not okFam then return false, 'You cannot park family vehicles here.' end
    end
    if DbBool(v.is_stored) then return false, 'That vehicle is already parked somewhere.' end

    submitted = type(submitted) == 'table' and submitted or {}
    local driveCall, driving, driveWhy = pcall(function()
        return exports['cm-vehicles']:IsPlayerDrivingSpawnedVehicle(src, v.id, tonumber(submitted.netId) or 0)
    end)
    if not driveCall or driving ~= true then
        return false, tostring(driveWhy or 'You must be driving this vehicle to park it.')
    end

    local opToken = lock(v.id, 'store', src)
    if not opToken then return false, 'That vehicle is already being parked.' end

    local assignment = MySQL.single.await([[
        SELECT house_id, slot_index
        FROM cm_house_vehicle_slots
        WHERE vehicle_id = ? LIMIT 1
    ]], { v.id })
    if assignment and tonumber(assignment.house_id) ~= houseId then
        unlock(v.id, opToken)
        return false, ('This vehicle is assigned to another house garage · space %d. Remove that assignment first.'):format(
            tonumber(assignment.slot_index) or 0)
    end

    local reservedSlot = assignment and tonumber(assignment.slot_index) or nil
    local free = reservedSlot or tonumber(MySQL.scalar.await([[
        SELECT slot_index FROM cm_house_vehicle_slots
        WHERE house_id = ? AND vehicle_id IS NULL
        ORDER BY slot_index LIMIT 1
    ]], { houseId }))
    local newAssignment = reservedSlot == nil
    if not free then
        unlock(v.id, opToken)
        return false, ('The garage is full. All %d spaces are assigned.'):format(GarageCapacity(houseId))
    end
    if not operationOwned(v.id, opToken) or not GetPlayerName(src) then
        if operationOwned(v.id, opToken) then unlock(v.id, opToken) end
        return false, 'Parking was cancelled before the database transition.'
    end

    local dbFuel = math.max(0.0, math.min(100.0, tonumber(v.fuel) or 100.0))
    local dbEngine = normalizeVehicleHealth(v.engine_health, 1000.0)
    local dbBody = normalizeVehicleHealth(v.body_health, 1000.0)
    local dbTank = normalizeVehicleHealth(v.tank_health, 1000.0)
    local dbDirt = math.max(0.0, math.min(15.0, tonumber(v.dirt_level) or 0.0))

    local function submittedWear(value, dbValue)
        local n = tonumber(value)
        if n == nil or n ~= n then return dbValue end
        -- This is a direct native reading, not legacy DB data. Keep a genuine
        -- numeric zero rather than interpreting values <= 1 as a percentage.
        n = math.max(0.0, math.min(1000.0, n))
        return math.min(dbValue, n)
    end

    local condition = {
        fuel = math.min(dbFuel, math.max(0.0, math.min(100.0, tonumber(submitted.fuel) or dbFuel))),
        engine = submittedWear(submitted.engine, dbEngine),
        body = submittedWear(submitted.body, dbBody),
        tank = submittedWear(submitted.tank, dbTank),
        dirt = math.max(dbDirt, math.max(0.0, math.min(15.0, tonumber(submitted.dirt) or dbDirt))),
        conditionState = mergeConditionWear(decodeTable(v.condition_state), submitted.conditionState),
    }

    setRollback(v.id, opToken, function()
        local rollbackOk, rows = pcall(function()
            if newAssignment then
                return MySQL.update.await([[
                    UPDATE cm_owned_vehicles v
                    INNER JOIN cm_house_vehicle_slots s
                        ON s.vehicle_id = v.id AND s.house_id = ? AND s.slot_index = ?
                    SET v.is_stored = 0, v.garage = NULL, v.parking_id = NULL, v.parked_at = NULL,
                        s.vehicle_id = NULL, s.owner_class = 'personal',
                        s.assigned_by = NULL, s.assigned_at = NULL
                    WHERE v.id = ? AND v.is_stored = 1 AND v.garage = ?
                ]], { houseId, free, v.id, garageKey(houseId) })
            end
            return MySQL.update.await([[
                UPDATE cm_owned_vehicles v
                INNER JOIN cm_house_vehicle_slots s
                    ON s.vehicle_id = v.id AND s.house_id = ? AND s.slot_index = ?
                SET v.is_stored = 0, v.garage = NULL, v.parking_id = ?, v.parked_at = NULL
                WHERE v.id = ? AND v.is_stored = 1 AND v.garage = ?
            ]], { houseId, free, free, v.id, garageKey(houseId) })
        end)

        if not rollbackOk then return false end
        if not rows or tonumber(rows) <= 0 then
            local current = MySQL.single.await([[
                SELECT v.is_stored, v.garage, s.vehicle_id
                FROM cm_owned_vehicles v
                LEFT JOIN cm_house_vehicle_slots s
                    ON s.house_id = ? AND s.slot_index = ?
                WHERE v.id = ? LIMIT 1
            ]], { houseId, free, v.id })
            local original = current and not DbBool(current.is_stored)
                and (not newAssignment and tonumber(current.vehicle_id) == tonumber(v.id)
                    or newAssignment and tonumber(current.vehicle_id) ~= tonumber(v.id))
            if not original then return false end
        end

        if GetPlayerName(src) then SendToWorld(src) end
        BroadcastGarage(houseId)
        return true
    end, 'store_prepared')

    touchOperation(v.id, opToken, 'storing_database', true)
    local updateOk, affected = pcall(function()
        if newAssignment then
            return MySQL.update.await([[
                UPDATE cm_owned_vehicles v
                INNER JOIN cm_house_vehicle_slots s ON s.house_id = ? AND s.slot_index = ?
                SET v.is_stored = 1, v.garage = ?, v.parking_id = ?, v.parked_at = NOW(),
                    v.fuel = ?, v.engine_health = ?, v.body_health = ?, v.tank_health = ?,
                    v.dirt_level = ?, v.condition_state = ?,
                    s.vehicle_id = v.id, s.owner_class = ?, s.assigned_by = ?, s.assigned_at = NOW()
                WHERE v.id = ? AND v.is_stored = 0 AND s.vehicle_id IS NULL
            ]], {
                houseId, free, garageKey(houseId), free,
                normalizeVehicleFuel(condition.fuel, 100.0), condition.engine, condition.body, condition.tank,
                condition.dirt, json.encode(condition.conditionState),
                isOwner and 'personal' or 'family', cid, v.id,
            })
        end
        return MySQL.update.await([[
            UPDATE cm_owned_vehicles v
            INNER JOIN cm_house_vehicle_slots s
                ON s.vehicle_id = v.id AND s.house_id = ? AND s.slot_index = ?
            SET v.is_stored = 1, v.garage = ?, v.parking_id = ?, v.parked_at = NOW(),
                v.fuel = ?, v.engine_health = ?, v.body_health = ?, v.tank_health = ?,
                v.dirt_level = ?, v.condition_state = ?,
                s.owner_class = ?, s.assigned_by = ?, s.assigned_at = COALESCE(s.assigned_at, NOW())
            WHERE v.id = ? AND v.is_stored = 0
        ]], {
            houseId, free, garageKey(houseId), free,
            normalizeVehicleFuel(condition.fuel, 100.0), condition.engine, condition.body, condition.tank,
            condition.dirt, json.encode(condition.conditionState),
            isOwner and 'personal' or 'family', cid, v.id,
        })
    end)
    if not updateOk or not affected or tonumber(affected) <= 0 then
        rollbackOperation(v.id, opToken, updateOk
            and 'store database guard rejected the transition'
            or 'store database query failed')
        return false, updateOk
            and 'The assigned parking space changed. Try again.'
            or 'The vehicle database update failed; the exterior state was preserved.'
    end

    touchOperation(v.id, opToken, 'database_stored', false)

    if not operationOwned(v.id, opToken) or not GetPlayerName(src) then
        rollbackOperation(v.id, opToken, 'player disconnected before bucket transfer')
        return false, 'Parking was cancelled because the driver disconnected.'
    end
    touchOperation(v.id, opToken, 'moving_player_to_garage')
    SendToGarage(src, houseId)
    Wait(0)
    if GetPlayerRoutingBucket(src) ~= GarageBucket(houseId) then
        rollbackOperation(v.id, opToken, 'garage bucket transfer failed')
        return false, 'The garage interior could not be entered. The vehicle was left outside.'
    end

    -- From this point physical deletion is irreversible. A disconnect must not
    -- roll the DB back while DeleteEntity is still converging on OneSync.
    touchOperation(v.id, opToken, 'deleting_world_entity', true)
    local despawned, despawnWhy = DespawnVehicle(v.id, v.plate)
    if despawned ~= true then
        local rolledBack = rollbackOperation(v.id, opToken, 'world entity deletion failed')
        if not rolledBack then
            return false, 'The vehicle entity could not be removed and rollback failed. Contact an administrator.'
        end
        return false, tostring(despawnWhy or 'The exterior vehicle could not be removed. Please try again.')
    end

    -- The authoritative DB state and physical deletion are both complete. Clear
    -- the rollback before any client transition can disconnect or time out.
    unlock(v.id, opToken)
    LogHouse(houseId, house.family_id, cid, 'garage_store', {
        vehicle = v.id, plate = v.plate, model = v.model, slot = free,
    })
    BroadcastGarage(houseId)

    return true, ('%s parked in space %d.'):format(v.label or v.plate, free), {
        enterGarage = true, houseId = houseId, label = house.label,
        sourceKind = garage.source_kind, sourceRef = garage.source_ref,
        entry = garage.player_entry, vehicleExit = garage.vehicle_exit,
        vehicleExits = garage.vehicle_exits,
        capacity = tonumber(garage.capacity) or 0,
    }
end)

-- ------------------------------------------------------------
--  ASSIGN / REPLACE from an interior parking symbol.
--  The selected owned vehicle becomes the real networked vehicle shown in that physical slot.
-- ------------------------------------------------------------
local function plateTrim(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function garageViewerFor(houseId, preferred)
    preferred = tonumber(preferred)
    if preferred and GetPlayerName(preferred)
       and GetPlayerRoutingBucket(preferred) == GarageBucket(houseId) then
        return preferred
    end
    for _, candidate in ipairs(InsideProperty(houseId, 'garage')) do
        candidate = tonumber(candidate)
        if candidate and GetPlayerName(candidate)
           and GetPlayerRoutingBucket(candidate) == GarageBucket(houseId) then
            return candidate
        end
    end
    return nil
end

local function vehicleHasOccupant(vehicleId, plate)
    vehicleId = tonumber(vehicleId)
    local wanted = plateTrim(plate)
    if not vehicleId and wanted == '' then return false end
    if type(GetAllVehicles) ~= 'function' then return false end

    local okList, vehicles = pcall(GetAllVehicles)
    if not okList or type(vehicles) ~= 'table' then return false end

    for _, entity in ipairs(vehicles) do
        local okExists, exists = pcall(DoesEntityExist, entity)
        if okExists and exists then
            local matched = false
            pcall(function() matched = vehicleId and tonumber(Entity(entity).state.cmVehicleId) == vehicleId end)
            if not matched and wanted ~= '' then
                local okPlate, actual = pcall(GetVehicleNumberPlateText, entity)
                matched = okPlate and plateTrim(actual) == wanted
            end
            if matched then
                -- Fixed seat scan avoids relying on a client-only passenger-count
                -- native. Eight seats covers normal GTA vehicles and buses used
                -- by this server; failures are ignored rather than crashing the
                -- whole garage callback.
                for seat = -1, 15 do
                    local okPed, ped = pcall(GetPedInVehicleSeat, entity, seat)
                    if okPed and ped and ped ~= 0 then return true end
                end
            end
        end
    end
    return false
end


-- Recall the vehicle assigned to a slot BACK INTO that same slot.
-- This never sends a car outside and never clears the slot reservation.
local function recallAssignedVehicle(src, houseId, slotIndex, vehicleId)
    houseId, slotIndex, vehicleId = tonumber(houseId), tonumber(slotIndex), tonumber(vehicleId)
    local house = houseId and Houses[houseId]
    if not house then return false, 'That property does not exist.' end

    local whereHouse, whereKind = WhereIs(src)
    if tonumber(whereHouse) ~= houseId or whereKind ~= 'garage' then
        return false, 'You must be inside this garage to recall a vehicle.'
    end

    local okSlot, whySlot = ValidSlot(houseId, slotIndex)
    if not okSlot then return false, whySlot end
    local cid = GetCid(src)
    local okAccess, whyAccess = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_SPAWN_OWN)
    if not okAccess then return false, whyAccess end

    local seat = MySQL.single.await([[
        SELECT vehicle_id, owner_class, assigned_by, assigned_at
        FROM cm_house_vehicle_slots
        WHERE house_id = ? AND slot_index = ? LIMIT 1
    ]], { houseId, slotIndex })
    if not seat or not seat.vehicle_id then return false, 'That parking space is empty.' end
    if tonumber(seat.vehicle_id) ~= vehicleId then
        return false, 'The assigned vehicle changed. Reopen the parking menu.'
    end

    local vehicle = VehicleById(vehicleId)
    if not vehicle then return false, 'That vehicle no longer exists.' end
    local allowed, whyAllowed = checkSeatAccess(src, cid, houseId, seat, vehicle)
    if not allowed then return false, whyAllowed end

    local garageTemplate = GarageTemplates[house.garage_template_id]
    local slotDefinition = garageTemplate and garageTemplate.slots and garageTemplate.slots[slotIndex]
    if not slotDefinition or not slotDefinition.coords then
        return false, 'That garage space is not configured.'
    end

    -- The recall menu is opened from the parking marker itself. Move the
    -- requester to the configured pedestrian garage door before placing the
    -- vehicle, otherwise the interaction design forces them to block the slot.
    local requesterPed = GetPlayerPed(src)
    local playerDoor = garageTemplate.player_entry
    if not requesterPed or requesterPed == 0 or not DoesEntityExist(requesterPed) then
        return false, 'Your player entity is not ready.'
    end
    if GetVehiclePedIsIn(requesterPed, false) ~= 0 then
        return false, 'Exit your current vehicle before recalling another car.'
    end
    if not playerDoor or not tonumber(playerDoor.x) or not tonumber(playerDoor.y) or not tonumber(playerDoor.z) then
        return false, 'This garage has no configured pedestrian door position.'
    end
    SetEntityCoords(requesterPed, tonumber(playerDoor.x) + 0.0, tonumber(playerDoor.y) + 0.0,
        tonumber(playerDoor.z) + 0.0, false, false, false, false)
    SetEntityHeading(requesterPed, tonumber(playerDoor.h or playerDoor.w or playerDoor.heading) or 0.0)
    Wait(100)

    -- Never recall a full-sized network vehicle on top of a player. Apart from
    -- the obvious collision risk, client ownership can reject or hide the
    -- placement while a ped occupies the exact slot.
    local slotCoords = slotDefinition.coords
    local slotPoint = vector3(slotCoords.x + 0.0, slotCoords.y + 0.0, slotCoords.z + 0.0)
    local garageBucket = GarageBucket(houseId)
    for _, rawPlayer in ipairs(GetPlayers()) do
        local playerSrc = tonumber(rawPlayer)
        if playerSrc and GetPlayerRoutingBucket(playerSrc) == garageBucket then
            local playerPed = GetPlayerPed(playerSrc)
            if playerPed and playerPed ~= 0 and DoesEntityExist(playerPed)
               and #(GetEntityCoords(playerPed) - slotPoint) < 2.5 then
                return false, 'The parking space is blocked. Everyone must step away before recalling the car.'
            end
        end
    end

    -- If it is already physically stored here, recall is an idempotent
    -- same-entity reset. Move the existing network vehicle back onto the exact
    -- slot coordinates; never delete/recreate it, which avoids the visible flash.
    if DbBool(vehicle.is_stored) and tostring(vehicle.garage or '') == garageKey(houseId) then
        if vehicleHasOccupant(vehicle.id, vehicle.plate) then
            return false, 'That vehicle currently has an occupant and cannot be recalled.'
        end

        local info = spawnedVehicleInfo(vehicle.id, vehicle.plate)
        local entry
        if info and tostring(info.context or '') == 'house_garage'
           and tonumber(info.houseId) == houseId and tonumber(info.slotIndex) == slotIndex then
            local okReturn, returned, returnedInfo = pcall(function()
                return exports['cm-vehicles']:ReturnHouseGarageVehicle(vehicle.id, houseId, slotIndex,
                    GarageBucket(houseId), slotDefinition.coords)
            end)
            if not okReturn or returned ~= true then
                local deleted, deleteWhy = DespawnVehicle(vehicle.id, vehicle.plate)
                if deleted ~= true then
                    return false, tostring(deleteWhy or returnedInfo or 'The old garage vehicle could not be cleared.')
                end
                local whyEntry
                entry, whyEntry = ensureGarageEntity(src, houseId, {
                    index = slotIndex, coords = slotDefinition.coords, icon = slotDefinition.icon,
                }, VehicleById(vehicle.id) or vehicle)
                if not entry then return false, whyEntry or 'The garage vehicle could not be recreated.' end
            else
                entry = {
                    entity = tonumber(type(returnedInfo) == 'table' and returnedInfo.entity) or tonumber(info.entity) or 0,
                    netId = tonumber(type(returnedInfo) == 'table' and returnedInfo.netId) or tonumber(info.netId) or 0,
                    vehicleId = vehicle.id, plate = vehicle.plate,
                    houseId = houseId, slotIndex = slotIndex,
                }
            end
            GarageEntities[houseId] = GarageEntities[houseId] or {}
            GarageEntities[houseId][slotIndex] = entry
            finalizeGarageEntityFor(src, entry, vehicle)
        else
            local whyEntry
            entry, whyEntry = ensureGarageEntity(src, houseId, {
                index = slotIndex, coords = slotDefinition.coords, icon = slotDefinition.icon,
            }, vehicle)
            if not entry then return false, whyEntry or 'The garage vehicle could not be restored.' end
        end

        BroadcastGarage(houseId)
        return true, ('%s was reset in parking space %d.'):format(vehicle.label or vehicle.plate, slotIndex)
    end

    -- Never use a house recall to bypass an impound, public garage or another
    -- authoritative storage system.
    if DbBool(vehicle.is_stored) then
        return false, ('That vehicle is stored in %s and cannot be recalled from this house.'):format(
            tostring(vehicle.garage or 'another garage'))
    end
    if vehicleHasOccupant(vehicle.id, vehicle.plate) then
        return false, 'That vehicle currently has an occupant and cannot be recalled.'
    end

    local token = lock(vehicle.id, 'recall_to_assigned_slot', src)
    if not token then return false, 'That vehicle is already being moved.' end

    local condition = {
        fuel = normalizeVehicleFuel(vehicle.fuel, 100.0),
        engine = normalizeVehicleHealth(vehicle.engine_health, 1000.0),
        body = normalizeVehicleHealth(vehicle.body_health, 1000.0),
        tank = normalizeVehicleHealth(vehicle.tank_health, 1000.0),
        dirt = math.max(0.0, math.min(15.0, tonumber(vehicle.dirt_level) or 0.0)),
        conditionState = decodeTable(vehicle.condition_state),
    }
    local okLive, gotLive, live = pcall(function()
        return exports['cm-vehicles']:GetSpawnedVehicleCondition(vehicle.id, vehicle)
    end)
    if okLive and gotLive == true and type(live) == 'table' then
        condition.fuel = normalizeVehicleFuel(live.fuel, condition.fuel)
        condition.engine = normalizeVehicleHealth(live.engine, condition.engine)
        condition.body = normalizeVehicleHealth(live.body, condition.body)
        condition.tank = normalizeVehicleHealth(live.tank, condition.tank)
        condition.dirt = math.max(0.0, math.min(15.0, tonumber(live.dirt) or condition.dirt))
        condition.conditionState = sanitizeConditionState(live.conditionState or condition.conditionState)
    else
        condition.conditionState = sanitizeConditionState(condition.conditionState)
    end

    local previousLastPosition = vehicle.last_position
    setRollback(vehicle.id, token, function()
        local okRollback, rows = pcall(function()
            return MySQL.update.await([[
                UPDATE cm_owned_vehicles v
                INNER JOIN cm_house_vehicle_slots s
                    ON s.vehicle_id = v.id AND s.house_id = ? AND s.slot_index = ?
                SET v.is_stored = 0, v.garage = NULL, v.parking_id = ?,
                    v.parked_at = NULL, v.last_position = ?
                WHERE v.id = ? AND v.is_stored = 1 AND v.garage = ?
            ]], { houseId, slotIndex, slotIndex, SqlNull(previousLastPosition), vehicle.id, garageKey(houseId) })
        end)
        if not okRollback then return false end
        if rows and tonumber(rows) > 0 then
            BroadcastGarage(houseId)
            return true
        end
        -- If the guarded recall write never committed, the original outside
        -- state is already intact and the slot is still correctly reserved.
        local current = MySQL.single.await([[
            SELECT v.is_stored, v.garage, s.vehicle_id
            FROM cm_owned_vehicles v
            LEFT JOIN cm_house_vehicle_slots s
                ON s.vehicle_id = v.id AND s.house_id = ? AND s.slot_index = ?
            WHERE v.id = ? LIMIT 1
        ]], { houseId, slotIndex, vehicle.id })
        local original = current and not DbBool(current.is_stored)
            and tonumber(current.vehicle_id) == tonumber(vehicle.id)
        BroadcastGarage(houseId)
        return original == true
    end, 'recall_prepared')

    -- The callback may finish safely even if the player disconnects while SQL
    -- or OneSync is yielding; rolling back midway could create a duplicate.
    touchOperation(vehicle.id, token, 'recall_database', true)
    local okUpdate, affected = pcall(function()
        return MySQL.update.await([[
            UPDATE cm_owned_vehicles v
            INNER JOIN cm_house_vehicle_slots s
                ON s.vehicle_id = v.id AND s.house_id = ? AND s.slot_index = ?
            SET v.is_stored = 1, v.garage = ?, v.parking_id = ?, v.parked_at = NOW(),
                v.is_locked = 0, v.fuel = ?, v.engine_health = ?, v.body_health = ?,
                v.tank_health = ?, v.dirt_level = ?, v.condition_state = ?
            WHERE v.id = ? AND v.is_stored = 0
        ]], {
            houseId, slotIndex, garageKey(houseId), slotIndex,
            condition.fuel, condition.engine, condition.body, condition.tank,
            condition.dirt, json.encode(condition.conditionState), vehicle.id,
        })
    end)
    if not okUpdate or not affected or tonumber(affected) <= 0 then
        rollbackOperation(vehicle.id, token, okUpdate and 'recall guard rejected' or 'recall query failed')
        return false, okUpdate and 'The vehicle location changed. Reopen the parking menu.'
            or 'The database recall failed.'
    end

    touchOperation(vehicle.id, token, 'recall_entity', true)
    -- Re-check after the SQL yield so a player who entered the vehicle during
    -- the callback is never teleported into the private garage bucket.
    if vehicleHasOccupant(vehicle.id, vehicle.plate) then
        rollbackOperation(vehicle.id, token, 'vehicle gained an occupant during recall')
        return false, 'Someone entered that vehicle while it was being recalled.'
    end
    local info = spawnedVehicleInfo(vehicle.id, vehicle.plate)
    local entry
    if info then
        if tostring(info.context or '') == 'house_garage'
           and (tonumber(info.houseId) ~= houseId or tonumber(info.slotIndex) ~= slotIndex) then
            rollbackOperation(vehicle.id, token, 'vehicle belongs to another garage entity')
            return false, 'The vehicle is currently registered in another house garage.'
        end

        -- World-to-private-bucket migration is slow and unreliable on some
        -- OneSync ownership paths. Recall directly: synchronously remove the
        -- outside entity, then create one fresh authoritative garage display.
        local deleted, deleteWhy = DespawnVehicle(vehicle.id, vehicle.plate)
        if deleted ~= true then
            rollbackOperation(vehicle.id, token, 'world entity could not despawn for direct recall')
            return false, tostring(deleteWhy or 'The city vehicle could not be removed for recall.')
        end
        local row = VehicleById(vehicle.id)
        local whyEntry
        entry, whyEntry = row and ensureGarageEntity(src, houseId, {
            index = slotIndex, coords = slotDefinition.coords, icon = slotDefinition.icon,
        }, row) or nil
        if not entry then
            rollbackOperation(vehicle.id, token, 'direct garage entity creation failed')
            return false, whyEntry or 'The vehicle was removed from the city but could not be created in its garage space.'
        end
        GarageEntities[houseId] = GarageEntities[houseId] or {}
        GarageEntities[houseId][slotIndex] = entry
        finalizeGarageEntityFor(src, entry, VehicleById(vehicle.id) or vehicle)
    else
        local row = VehicleById(vehicle.id)
        entry = row and ensureGarageEntity(src, houseId, {
            index = slotIndex, coords = slotDefinition.coords, icon = slotDefinition.icon,
        }, row) or nil
        if not entry then
            rollbackOperation(vehicle.id, token, 'garage entity creation failed during recall')
            return false, 'The vehicle could not be respawned in its parking space.'
        end
    end

    unlock(vehicle.id, token)
    BroadcastGarage(houseId)
    LogHouse(houseId, house.family_id, cid, 'garage_recall_to_slot', {
        vehicle = vehicle.id, plate = vehicle.plate, slot = slotIndex,
    })
    return true, ('%s was recalled into parking space %d.'):format(vehicle.label or vehicle.plate, slotIndex)
end

lib.callback.register('cm-house:server:recallAssignedVehicle', recallAssignedVehicle)

-- Trusted server export used by cm-family. It can run remotely; occupied cars
-- are never recalled. Physical garage entities are refreshed immediately when
-- someone is inside, or created normally on the next garage entry.
exports('RecallAllFamilyGarageVehicles', function(familyId, actorCid)
    familyId = tonumber(familyId)
    local src = GetSrcByCid(actorCid)
    if not familyId or not src then return false, 'actor_not_online' end

    local house = MySQL.single.await([[
        SELECT id FROM cm_houses
        WHERE family_id = ? AND garage_template_id IS NOT NULL
        ORDER BY id ASC LIMIT 1
    ]], { familyId })
    local houseId = house and tonumber(house.id) or nil
    if not houseId then return false, 'family_garage_not_found' end

    local rows = MySQL.query.await([[
        SELECT s.slot_index AS assigned_slot, v.*
        FROM cm_house_vehicle_slots s
        INNER JOIN cm_owned_vehicles v ON v.id = s.vehicle_id
        WHERE s.house_id = ? AND v.is_stored = 0
        ORDER BY s.slot_index ASC
    ]], { houseId }) or {}

    local recalled, failed = 0, 0
    local reasons = {}
    for _, vehicle in ipairs(rows) do
        local vehicleId = tonumber(vehicle.id)
        local slotIndex = tonumber(vehicle.assigned_slot)
        if vehicleHasOccupant(vehicleId, vehicle.plate) then
            failed = failed + 1
            if #reasons < 3 then reasons[#reasons + 1] = ('%s is occupied'):format(vehicle.label or vehicle.plate) end
        else
            local token = lock(vehicleId, 'family_recall_all', src)
            if not token then
                failed = failed + 1
                if #reasons < 3 then reasons[#reasons + 1] = ('%s is busy'):format(vehicle.label or vehicle.plate) end
            else
                local condition = {
                    fuel = normalizeVehicleFuel(vehicle.fuel, 100.0),
                    engine = normalizeVehicleHealth(vehicle.engine_health, 1000.0),
                    body = normalizeVehicleHealth(vehicle.body_health, 1000.0),
                    tank = normalizeVehicleHealth(vehicle.tank_health, 1000.0),
                    dirt = tonumber(vehicle.dirt_level) or 0.0,
                    conditionState = sanitizeConditionState(decodeTable(vehicle.condition_state)),
                }
                local liveOk, gotLive, live = pcall(function()
                    return exports['cm-vehicles']:GetSpawnedVehicleCondition(vehicleId, vehicle)
                end)
                if liveOk and gotLive == true and type(live) == 'table' then
                    condition.fuel = normalizeVehicleFuel(live.fuel, condition.fuel)
                    condition.engine = normalizeVehicleHealth(live.engine, condition.engine)
                    condition.body = normalizeVehicleHealth(live.body, condition.body)
                    condition.tank = normalizeVehicleHealth(live.tank, condition.tank)
                    condition.dirt = tonumber(live.dirt) or condition.dirt
                    condition.conditionState = sanitizeConditionState(live.conditionState or condition.conditionState)
                end

                local updated = MySQL.update.await([[
                    UPDATE cm_owned_vehicles
                    SET is_stored = 1, garage = ?, parking_id = ?, parked_at = NOW(),
                        is_locked = 0, fuel = ?, engine_health = ?, body_health = ?,
                        tank_health = ?, dirt_level = ?, condition_state = ?
                    WHERE id = ? AND is_stored = 0
                ]], {
                    garageKey(houseId), slotIndex, condition.fuel, condition.engine,
                    condition.body, condition.tank, condition.dirt,
                    json.encode(condition.conditionState), vehicleId,
                })

                if not updated or tonumber(updated) <= 0 then
                    failed = failed + 1
                    if #reasons < 3 then reasons[#reasons + 1] = ('%s changed location'):format(vehicle.label or vehicle.plate) end
                else
                    local deleted, deleteWhy = DespawnVehicle(vehicleId, vehicle.plate)
                    if deleted == true then
                        recalled = recalled + 1
                    else
                        MySQL.update.await([[
                            UPDATE cm_owned_vehicles
                            SET is_stored = 0, garage = NULL, parking_id = ?, parked_at = NULL
                            WHERE id = ? AND is_stored = 1 AND garage = ?
                        ]], { slotIndex, vehicleId, garageKey(houseId) })
                        failed = failed + 1
                        if #reasons < 3 then reasons[#reasons + 1] = tostring(deleteWhy or 'entity removal failed') end
                    end
                end
                unlock(vehicleId, token)
            end
        end
    end

    BroadcastGarage(houseId)
    local viewer = garageViewerFor(houseId, nil)
    if viewer then refreshGarageEntitiesFor(viewer, houseId) end

    local message = ('Recalled %d family garage car%s.'):format(recalled, recalled == 1 and '' or 's')
    if failed > 0 then
        message = message .. (' %d could not be recalled'):format(failed)
        if #reasons > 0 then message = message .. ': ' .. table.concat(reasons, '; ') end
        message = message .. '.'
    end
    return true, { recalled = recalled, failed = failed, message = message }
end)

-- Move/call a vehicle that is already assigned to another persistent house
-- slot. The vehicle keeps one database id, one physical entity and one slot.
-- The source assignment is cleared before the target assignment is written in
-- the same SQL transaction, so the unique vehicle_id index remains satisfied.
lib.callback.register('cm-house:server:callVehicleById', function(src, houseId, slotIndex, vehicleId)
    local cid = GetCid(src)
    houseId, slotIndex, vehicleId = tonumber(houseId), tonumber(slotIndex), tonumber(vehicleId)
    local house = houseId and Houses[houseId]
    if not house then return false, 'That property does not exist.' end

    local whereHouse, whereKind = WhereIs(src)
    if tonumber(whereHouse) ~= houseId or whereKind ~= 'garage' then
        return false, 'You must be inside this garage to call a vehicle.'
    end

    local okSlot, whySlot = ValidSlot(houseId, slotIndex)
    if not okSlot then return false, whySlot end
    local okOwn, whyOwn = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_SPAWN_OWN)
    if not okOwn then return false, whyOwn end

    local targetSeat = MySQL.single.await([[
        SELECT vehicle_id
        FROM cm_house_vehicle_slots
        WHERE house_id = ? AND slot_index = ? LIMIT 1
    ]], { houseId, slotIndex })
    if not targetSeat then return false, 'That parking space is not configured.' end
    if targetSeat.vehicle_id then return false, 'That parking space is already occupied.' end

    local selected = VehicleById(vehicleId)
    if not selected then return false, 'That vehicle does not exist.' end
    if tonumber(selected.owner_character_id) ~= tonumber(cid) then
        return false, 'You can only call a vehicle you own.'
    end

    local sourceSeat = MySQL.single.await([[
        SELECT s.house_id, s.slot_index, s.owner_class, s.assigned_by, s.assigned_at,
               h.label AS house_label
        FROM cm_house_vehicle_slots s
        LEFT JOIN cm_houses h ON h.id = s.house_id
        WHERE s.vehicle_id = ? LIMIT 1
    ]], { vehicleId })
    if not sourceSeat then
        return false, 'That vehicle is not assigned yet. Reopen the space and use Call here again.'
    end

    local sourceHouseId = tonumber(sourceSeat.house_id)
    local sourceSlotIndex = tonumber(sourceSeat.slot_index)
    if sourceHouseId == houseId and sourceSlotIndex == slotIndex then
        return false, 'That vehicle is already assigned to this parking space.'
    end

    local sourceHouse = sourceHouseId and Houses[sourceHouseId]
    local sourceTemplate = sourceHouse and GarageTemplates[sourceHouse.garage_template_id]
    local sourceDefinition = sourceTemplate and sourceTemplate.slots and sourceTemplate.slots[sourceSlotIndex]
    local targetTemplate = GarageTemplates[house.garage_template_id]
    local targetDefinition = targetTemplate and targetTemplate.slots and targetTemplate.slots[slotIndex]
    if not targetDefinition or not targetDefinition.coords then
        return false, 'The selected parking space has no vehicle coordinates.'
    end

    local wasStored = DbBool(selected.is_stored)
    local sourceGarage = garageKey(sourceHouseId)
    local sourceInHouseGarage = wasStored and tostring(selected.garage or '') == sourceGarage
    if wasStored and not sourceInHouseGarage then
        return false, ('That vehicle is stored in %s and cannot be called from the house garage.'):format(
            tostring(selected.garage or 'another storage system'))
    end
    if vehicleHasOccupant(selected.id, selected.plate) then
        return false, 'That vehicle currently has an occupant and cannot be moved.'
    end

    local token = lock(vehicleId, 'move_assigned_vehicle_to_slot', src)
    if not token then return false, 'That vehicle is already being moved.' end

    local condition = {
        fuel = normalizeVehicleFuel(selected.fuel, 100.0),
        engine = normalizeVehicleHealth(selected.engine_health, 1000.0),
        body = normalizeVehicleHealth(selected.body_health, 1000.0),
        tank = normalizeVehicleHealth(selected.tank_health, 1000.0),
        dirt = math.max(0.0, math.min(15.0, tonumber(selected.dirt_level) or 0.0)),
        conditionState = sanitizeConditionState(decodeTable(selected.condition_state)),
    }
    local okLive, gotLive, live = pcall(function()
        return exports['cm-vehicles']:GetSpawnedVehicleCondition(selected.id, selected)
    end)
    if okLive and gotLive == true and type(live) == 'table' then
        condition.fuel = normalizeVehicleFuel(live.fuel, condition.fuel)
        condition.engine = normalizeVehicleHealth(live.engine, condition.engine)
        condition.body = normalizeVehicleHealth(live.body, condition.body)
        condition.tank = normalizeVehicleHealth(live.tank, condition.tank)
        condition.dirt = math.max(0.0, math.min(15.0, tonumber(live.dirt) or condition.dirt))
        condition.conditionState = sanitizeConditionState(live.conditionState or condition.conditionState)
    end

    local original = {
        isStored = wasStored and 1 or 0,
        garage = selected.garage,
        parkingId = selected.parking_id,
        parkedAt = selected.parked_at,
        lastPosition = selected.last_position,
        locked = DbBool(selected.is_locked) and 1 or 0,
        fuel = normalizeVehicleFuel(selected.fuel, condition.fuel),
        engine = normalizeVehicleHealth(selected.engine_health, condition.engine),
        body = normalizeVehicleHealth(selected.body_health, condition.body),
        tank = normalizeVehicleHealth(selected.tank_health, condition.tank),
        dirt = math.max(0.0, math.min(15.0, tonumber(selected.dirt_level) or condition.dirt)),
        conditionState = sanitizeConditionState(decodeTable(selected.condition_state)),
    }
    local infoBefore = spawnedVehicleInfo(selected.id, selected.plate)
    local physicalMoved = false

    local function restoreDatabase()
        local okRestore, restored = pcall(function()
            return MySQL.transaction.await({
                {
                    query = [[
                        UPDATE cm_house_vehicle_slots
                        SET vehicle_id = NULL, owner_class = 'personal', assigned_by = NULL, assigned_at = NULL
                        WHERE house_id = ? AND slot_index = ? AND vehicle_id = ?
                    ]],
                    values = { houseId, slotIndex, vehicleId },
                },
                {
                    query = [[
                        UPDATE cm_house_vehicle_slots
                        SET vehicle_id = ?, owner_class = ?, assigned_by = ?, assigned_at = ?
                        WHERE house_id = ? AND slot_index = ? AND vehicle_id IS NULL
                    ]],
                    values = {
                        vehicleId, sourceSeat.owner_class or 'personal',
                        SqlNull(sourceSeat.assigned_by), SqlNull(sourceSeat.assigned_at),
                        sourceHouseId, sourceSlotIndex,
                    },
                },
                {
                    query = [[
                        UPDATE cm_owned_vehicles
                        SET is_stored = ?, garage = ?, parking_id = ?, parked_at = ?, last_position = ?,
                            is_locked = ?, fuel = ?, engine_health = ?, body_health = ?, tank_health = ?,
                            dirt_level = ?, condition_state = ?
                        WHERE id = ?
                    ]],
                    values = {
                        original.isStored, SqlNull(original.garage), SqlNull(original.parkingId),
                        SqlNull(original.parkedAt), SqlNull(original.lastPosition), original.locked,
                        original.fuel, original.engine, original.body, original.tank, original.dirt,
                        json.encode(original.conditionState), vehicleId,
                    },
                },
            })
        end)
        return okRestore and restored == true
    end

    setRollback(vehicleId, token, function()
        local restored = restoreDatabase()
        if restored and physicalMoved then
            -- Restore the physical authority as well as the database if a
            -- disconnect/timeout lands after the same entity has moved.
            if sourceInHouseGarage and sourceDefinition and sourceDefinition.coords then
                pcall(function()
                    exports['cm-vehicles']:ReturnHouseGarageVehicle(vehicleId, sourceHouseId,
                        sourceSlotIndex, GarageBucket(sourceHouseId), sourceDefinition.coords)
                end)
            elseif infoBefore then
                local world = decodeTable(original.lastPosition)
                local x, y, z = tonumber(world.x), tonumber(world.y), tonumber(world.z)
                if x and y and z then
                    pcall(function()
                        exports['cm-vehicles']:PromoteHouseGarageVehicle(vehicleId, src, {
                            x = x, y = y, z = z,
                            h = tonumber(world.h or world.w or world.heading) or 0.0,
                        })
                    end)
                end
            else
                pcall(function() DespawnVehicle(vehicleId, selected.plate) end)
            end

            local targetSet = GarageEntities[houseId]
            if targetSet then
                targetSet[slotIndex] = nil
                if not next(targetSet) then GarageEntities[houseId] = nil end
            end
        end
        if restored then
            BroadcastGarage(sourceHouseId)
            if sourceHouseId ~= houseId then BroadcastGarage(houseId) end
        end
        return restored
    end, 'move_assignment_prepared')

    touchOperation(vehicleId, token, 'moving_assignment_database', true)
    local txOk, committed = pcall(function()
        return MySQL.transaction.await({
            {
                query = [[
                    UPDATE cm_house_vehicle_slots
                    SET vehicle_id = NULL, owner_class = 'personal', assigned_by = NULL, assigned_at = NULL
                    WHERE house_id = ? AND slot_index = ? AND vehicle_id = ?
                ]],
                values = { sourceHouseId, sourceSlotIndex, vehicleId },
            },
            {
                query = [[
                    UPDATE cm_house_vehicle_slots
                    SET vehicle_id = ?, owner_class = ?, assigned_by = ?, assigned_at = NOW()
                    WHERE house_id = ? AND slot_index = ? AND vehicle_id IS NULL
                ]],
                values = {
                    vehicleId, sourceSeat.owner_class or 'personal', cid,
                    houseId, slotIndex,
                },
            },
            {
                query = [[
                    UPDATE cm_owned_vehicles
                    SET is_stored = 1, garage = ?, parking_id = ?, parked_at = NOW(),
                        is_locked = 0, fuel = ?, engine_health = ?, body_health = ?, tank_health = ?,
                        dirt_level = ?, condition_state = ?
                    WHERE id = ? AND owner_character_id = ?
                ]],
                values = {
                    garageKey(houseId), slotIndex, condition.fuel, condition.engine,
                    condition.body, condition.tank, condition.dirt,
                    json.encode(condition.conditionState), vehicleId, tostring(cid),
                },
            },
        })
    end)
    if not txOk or committed ~= true then
        rollbackOperation(vehicleId, token, txOk and 'move assignment transaction rejected' or 'move assignment query failed')
        return false, 'The parking assignment could not be moved.'
    end

    local verified = MySQL.single.await([[
        SELECT v.is_stored, v.garage, target.vehicle_id AS target_vehicle,
               source.vehicle_id AS source_vehicle
        FROM cm_owned_vehicles v
        LEFT JOIN cm_house_vehicle_slots target
            ON target.house_id = ? AND target.slot_index = ?
        LEFT JOIN cm_house_vehicle_slots source
            ON source.house_id = ? AND source.slot_index = ?
        WHERE v.id = ? LIMIT 1
    ]], { houseId, slotIndex, sourceHouseId, sourceSlotIndex, vehicleId })
    if not verified or tonumber(verified.target_vehicle) ~= vehicleId
       or tonumber(verified.source_vehicle) ~= nil
       or not DbBool(verified.is_stored)
       or tostring(verified.garage or '') ~= garageKey(houseId) then
        rollbackOperation(vehicleId, token, 'move assignment verification failed')
        return false, 'The parking space changed while the car was being called.'
    end

    touchOperation(vehicleId, token, 'moving_physical_vehicle', true)
    if vehicleHasOccupant(selected.id, selected.plate) then
        rollbackOperation(vehicleId, token, 'vehicle gained occupant during slot move')
        return false, 'Someone entered that vehicle while it was being moved.'
    end

    local entry
    if infoBefore then
        local okReturn, returned, returnedInfo = pcall(function()
            return exports['cm-vehicles']:ReturnHouseGarageVehicle(selected.id, houseId, slotIndex,
                GarageBucket(houseId), targetDefinition.coords)
        end)
        if not okReturn or returned ~= true then
            rollbackOperation(vehicleId, token, 'physical vehicle could not move to target slot')
            return false, tostring(returnedInfo or returned or 'The vehicle could not be moved into the selected space.')
        end
        physicalMoved = true
        entry = {
            entity = tonumber(type(returnedInfo) == 'table' and returnedInfo.entity) or tonumber(infoBefore.entity) or 0,
            netId = tonumber(type(returnedInfo) == 'table' and returnedInfo.netId) or tonumber(infoBefore.netId) or 0,
            vehicleId = vehicleId, plate = selected.plate,
            houseId = houseId, slotIndex = slotIndex,
        }
    else
        -- No active entity exists. Clear any stale source slot registry and create
        -- exactly one display entity in the new target space.
        local sourceDeleted, sourceDeleteWhy = deleteGarageEntity(sourceHouseId, sourceSlotIndex)
        if not sourceDeleted then
            rollbackOperation(vehicleId, token, 'stale source entity could not be cleared')
            return false, tostring(sourceDeleteWhy or 'The old parking-space entity could not be cleared.')
        end
        local row = VehicleById(vehicleId)
        local whyEntry
        entry, whyEntry = row and ensureGarageEntity(src, houseId, {
            index = slotIndex, coords = targetDefinition.coords, icon = targetDefinition.icon,
        }, row) or nil
        if not entry then
            rollbackOperation(vehicleId, token, 'target garage entity creation failed')
            return false, whyEntry or 'The vehicle could not be created in the selected parking space.'
        end
        physicalMoved = true
    end

    local sourceSet = GarageEntities[sourceHouseId]
    if sourceSet then
        sourceSet[sourceSlotIndex] = nil
        if not next(sourceSet) then GarageEntities[sourceHouseId] = nil end
    end
    GarageEntities[houseId] = GarageEntities[houseId] or {}
    GarageEntities[houseId][slotIndex] = entry
    finalizeGarageEntityFor(src, entry, VehicleById(vehicleId) or selected)

    unlock(vehicleId, token)
    BroadcastGarage(sourceHouseId)
    if sourceHouseId ~= houseId then BroadcastGarage(houseId) end
    LogHouse(houseId, house.family_id, cid, 'garage_move_assignment', {
        vehicle = vehicleId, plate = selected.plate,
        fromHouse = sourceHouseId, fromSlot = sourceSlotIndex, toSlot = slotIndex,
    })
    return true, ('%s moved from space %d to space %d.'):format(
        selected.label or selected.plate, sourceSlotIndex, slotIndex)
end)

lib.callback.register('cm-house:server:assignVehicleToSlot', function(src, houseId, slotIndex, vehicleId, replace)
    houseId, slotIndex, vehicleId = tonumber(houseId), tonumber(slotIndex), tonumber(vehicleId)
    local inside, insideWhy = requireInsideGarage(src, houseId)
    if not inside then return false, insideWhy end
    local cid = GetCid(src)
    local house = houseId and Houses[houseId]
    if not house then return false, 'That property does not exist.' end

    local okSlot, whySlot = ValidSlot(houseId, slotIndex)
    if not okSlot then return false, whySlot end
    local okOwn, whyOwn = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_SPAWN_OWN)
    if not okOwn then return false, whyOwn end

    local selected = VehicleById(vehicleId)
    if not selected then return false, 'That vehicle does not exist.' end
    if tonumber(selected.owner_character_id) ~= tonumber(cid) then
        return false, 'You can only assign a vehicle you own.'
    end
    local existingAssignment = MySQL.single.await([[
        SELECT s.house_id, s.slot_index, h.label AS house_label
        FROM cm_house_vehicle_slots s
        LEFT JOIN cm_houses h ON h.id = s.house_id
        WHERE s.vehicle_id = ? LIMIT 1
    ]], { vehicleId })
    if existingAssignment then
        return false, ('That vehicle is already assigned to %s · space %d. Remove that assignment first.'):format(
            tostring(existingAssignment.house_label or ('House %d'):format(tonumber(existingAssignment.house_id) or 0)),
            tonumber(existingAssignment.slot_index) or 0)
    end
    if DbBool(selected.is_stored) then
        return false, 'That vehicle is stored in another garage system.'
    end
    if vehicleHasOccupant(selected.id, selected.plate) then
        return false, 'That vehicle is currently being used.'
    end

    local seat = MySQL.single.await(
        'SELECT vehicle_id, owner_class, assigned_by, assigned_at FROM cm_house_vehicle_slots WHERE house_id = ? AND slot_index = ?',
        { houseId, slotIndex })
    local oldId = seat and tonumber(seat.vehicle_id) or nil
    if oldId then
        return false, 'That parking space is occupied. Remove its assigned vehicle first.'
    end

    local selectedToken = lock(vehicleId, oldId and 'replace_into_slot' or 'assign_to_slot', src)
    if not selectedToken then return false, 'That vehicle is already being moved.' end
    local oldToken
    if oldId then
        oldToken = lock(oldId, 'replace_from_slot', nil)
        if not oldToken then
            unlock(vehicleId, selectedToken)
            return false, 'The parked vehicle is already being moved.'
        end
    end

    local oldVehicle = oldId and VehicleById(oldId) or nil
    local garageTemplate = GarageTemplates[house.garage_template_id]
    local slotDefinition = garageTemplate and garageTemplate.slots and garageTemplate.slots[slotIndex] or nil

    setRollback(vehicleId, selectedToken, function()
        local rollbackOk, reversed = pcall(function()
            if oldId then
                return MySQL.update.await([[
                    UPDATE cm_owned_vehicles selected
                    INNER JOIN cm_house_vehicle_slots s
                        ON s.house_id = ? AND s.slot_index = ?
                    INNER JOIN cm_owned_vehicles previous ON previous.id = ?
                    SET selected.is_stored = 0, selected.garage = NULL,
                        selected.parking_id = NULL, selected.parked_at = NULL,
                        previous.is_stored = 1, previous.garage = ?,
                        previous.parking_id = NULL, previous.parked_at = NOW(),
                        s.vehicle_id = previous.id, s.owner_class = ?,
                        s.assigned_by = ?, s.assigned_at = ?
                    WHERE selected.id = ? AND selected.is_stored = 1
                      AND selected.garage = ? AND s.vehicle_id = selected.id
                      AND previous.is_stored = 0
                ]], {
                    houseId, slotIndex, oldId, garageKey(houseId),
                    seat.owner_class or 'personal', seat.assigned_by, seat.assigned_at,
                    vehicleId, garageKey(houseId),
                })
            end
            return MySQL.update.await([[
                UPDATE cm_owned_vehicles selected
                INNER JOIN cm_house_vehicle_slots s
                    ON s.house_id = ? AND s.slot_index = ?
                SET selected.is_stored = 0, selected.garage = NULL,
                    selected.parking_id = NULL, selected.parked_at = NULL,
                    s.vehicle_id = NULL, s.owner_class = ?,
                    s.assigned_by = ?, s.assigned_at = ?
                WHERE selected.id = ? AND selected.is_stored = 1
                  AND selected.garage = ? AND s.vehicle_id = selected.id
            ]], {
                houseId, slotIndex, seat.owner_class or 'personal',
                seat.assigned_by, seat.assigned_at, vehicleId, garageKey(houseId),
            })
        end)

        if not rollbackOk then
            if oldId then unlock(oldId, oldToken) end
            return false
        end
        if not reversed or tonumber(reversed) <= 0 then
            local current = MySQL.single.await([[
                SELECT selected.is_stored AS selected_stored, selected.garage AS selected_garage,
                       s.vehicle_id, previous.is_stored AS previous_stored,
                       previous.garage AS previous_garage
                FROM cm_owned_vehicles selected
                LEFT JOIN cm_house_vehicle_slots s
                    ON s.house_id = ? AND s.slot_index = ?
                LEFT JOIN cm_owned_vehicles previous ON previous.id = ?
                WHERE selected.id = ? LIMIT 1
            ]], { houseId, slotIndex, oldId or 0, vehicleId })
            local original = current and not DbBool(current.selected_stored)
                and (oldId and tonumber(current.vehicle_id) == oldId
                    and DbBool(current.previous_stored)
                    and tostring(current.previous_garage or '') == garageKey(houseId)
                    or not oldId and tonumber(current.vehicle_id) ~= vehicleId)
            if not original then
                if oldId then unlock(oldId, oldToken) end
                return false
            end
        end

        if oldVehicle and slotDefinition then
            local viewer = garageViewerFor(houseId, src)
            if viewer then
                local restored, restoreWhy = ensureGarageEntity(viewer, houseId, {
                    index = slotIndex, coords = slotDefinition.coords, icon = slotDefinition.icon,
                }, oldVehicle)
                if not restored then
                    print(('[cm-house] ^3failed to restore slot %s:%s during assignment rollback: %s^7')
                        :format(houseId, slotIndex, tostring(restoreWhy)))
                end
            end
        end
        if oldId then unlock(oldId, oldToken) end
        BroadcastGarage(houseId)
        return true
    end, 'assignment_prepared')

    -- Remove every physical copy before changing either database authority.
    -- If the guarded SQL later loses a race, the database remains loose and
    -- cm-vehicles can recreate the selected vehicle normally; no duplicate can
    -- survive in the world and garage bucket at the same time.
    local looseDeleted, looseDeleteWhy = DespawnVehicle(selected.id, selected.plate)
    if looseDeleted == false then
        rollbackOperation(vehicleId, selectedToken, 'selected world entity deletion failed')
        return false, tostring(looseDeleteWhy or 'The selected vehicle could not be removed from the world.')
    end
    if not operationOwned(vehicleId, selectedToken)
       or (oldId and not operationOwned(oldId, oldToken)) then
        return false, 'The parking change was cancelled while the selected vehicle was being removed.'
    end

    local bayDeleted, bayDeleteWhy = deleteGarageEntity(houseId, slotIndex)
    if not bayDeleted then
        rollbackOperation(vehicleId, selectedToken, 'existing garage entity deletion failed')
        return false, tostring(bayDeleteWhy or 'The existing garage entity could not be removed.')
    end
    if not operationOwned(vehicleId, selectedToken)
       or (oldId and not operationOwned(oldId, oldToken)) then
        return false, 'The parking change was cancelled before the database transition.'
    end

    touchOperation(vehicleId, selectedToken, 'assigning_database', true)
    if oldId then touchOperation(oldId, oldToken, 'assigning_database', true) end
    local updateOk, affected
    if oldId then
        updateOk, affected = pcall(function()
            return MySQL.update.await([[
                UPDATE cm_owned_vehicles selected
                INNER JOIN cm_house_vehicle_slots s
                    ON s.house_id = ?
                   AND s.slot_index = ?
                INNER JOIN cm_owned_vehicles previous
                    ON previous.id = s.vehicle_id
                SET selected.is_stored = 1,
                    selected.garage = ?,
                    selected.parking_id = NULL,
                    selected.parked_at = NOW(),
                    s.vehicle_id = selected.id,
                    s.owner_class = 'personal',
                    s.assigned_by = ?,
                    s.assigned_at = NOW(),
                    previous.is_stored = 0,
                    previous.garage = NULL,
                    previous.parking_id = NULL,
                    previous.parked_at = NULL
                WHERE selected.id = ?
                  AND selected.owner_character_id = ?
                  AND selected.is_stored = 0
                  AND previous.id = ?
                  AND previous.is_stored = 1
                  AND previous.garage = ?
            ]], {
                houseId, slotIndex,
                garageKey(houseId), cid,
                vehicleId, tostring(cid),
                oldId, garageKey(houseId),
            })
        end)
    else
        updateOk, affected = pcall(function()
            return MySQL.update.await([[
                UPDATE cm_owned_vehicles selected
                INNER JOIN cm_house_vehicle_slots s
                    ON s.house_id = ?
                   AND s.slot_index = ?
                SET selected.is_stored = 1,
                    selected.garage = ?,
                    selected.parking_id = NULL,
                    selected.parked_at = NOW(),
                    s.vehicle_id = selected.id,
                    s.owner_class = 'personal',
                    s.assigned_by = ?,
                    s.assigned_at = NOW()
                WHERE selected.id = ?
                  AND selected.owner_character_id = ?
                  AND selected.is_stored = 0
                  AND s.vehicle_id IS NULL
            ]], {
                houseId, slotIndex,
                garageKey(houseId), cid,
                vehicleId, tostring(cid),
            })
        end)
    end

    if not updateOk or not affected or tonumber(affected) <= 0 then
        rollbackOperation(vehicleId, selectedToken, updateOk
            and 'assignment database guard rejected the transition'
            or 'assignment database query failed')
        return false, updateOk
            and 'The parking space changed. Try again.'
            or 'The vehicle database update failed; the original parking state was restored.'
    end

    touchOperation(vehicleId, selectedToken, 'assignment_committed', false)
    if oldId then touchOperation(oldId, oldToken, 'assignment_committed', false) end
    if not GetPlayerName(src) then
        rollbackOperation(vehicleId, selectedToken, 'player disconnected during slot assignment')
        return false, 'The parking change was cancelled because the player disconnected.'
    end

    -- Both the loose selected copy and the previous bay copy were already
    -- synchronously deleted before the guarded database transition. The next
    -- garage update is therefore the only path allowed to create the new bay
    -- entity.
    unlock(vehicleId, selectedToken)
    if oldId then unlock(oldId, oldToken) end

    pcall(function()
        MySQL.query.await('DELETE FROM cm_house_shared_vehicles WHERE vehicle_id = ?', { vehicleId })
        if oldId then
            MySQL.query.await('DELETE FROM cm_house_shared_vehicles WHERE vehicle_id = ?', { oldId })
        end
    end)

    LogHouse(houseId, house.family_id, cid, oldId and 'garage_replace' or 'garage_assign', {
        vehicle = vehicleId, plate = selected.plate, slot = slotIndex, replaced = oldId,
    })
    BroadcastGarage(houseId)
    return true, oldId
        and ('%s replaced the vehicle in space %d.'):format(selected.label or selected.plate, slotIndex)
        or ('%s parked in space %d.'):format(selected.label or selected.plate, slotIndex)
end)

-- Remove the slot assignment without spawning the car. It returns to the
-- player's available-vehicle list and can be placed in another bay later.
lib.callback.register('cm-house:server:removeVehicleFromSlot', function(src, houseId, slotIndex)
    houseId, slotIndex = tonumber(houseId), tonumber(slotIndex)
    local inside, insideWhy = requireInsideGarage(src, houseId)
    if not inside then return false, insideWhy end
    local cid = GetCid(src)
    local house = houseId and Houses[houseId]
    if not house then return false, 'That property does not exist.' end

    local okSlot, whySlot = ValidSlot(houseId, slotIndex)
    if not okSlot then return false, whySlot end
    local seat = MySQL.single.await([[
        SELECT vehicle_id, owner_class, assigned_by, assigned_at
        FROM cm_house_vehicle_slots
        WHERE house_id = ? AND slot_index = ? LIMIT 1
    ]], { houseId, slotIndex })
    local vehicleId = seat and tonumber(seat.vehicle_id) or nil
    if not vehicleId then return false, 'That parking space is empty.' end

    local vehicle = VehicleById(vehicleId)
    if not vehicle then
        local okManage, whyManage = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_MANAGE_SLOTS)
        if not okManage then return false, whyManage end
        MySQL.update.await([[
            UPDATE cm_house_vehicle_slots
            SET vehicle_id = NULL, owner_class = 'personal', assigned_by = NULL, assigned_at = NULL
            WHERE house_id = ? AND slot_index = ? AND vehicle_id = ?
        ]], { houseId, slotIndex, vehicleId })
        deleteGarageEntity(houseId, slotIndex)
        BroadcastGarage(houseId)
        return true, 'The missing vehicle assignment was removed.'
    end

    local ownsVehicle = tonumber(vehicle.owner_character_id) == tonumber(cid)
    if not ownsVehicle then
        local okManage, whyManage = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_MANAGE_SLOTS)
        if not okManage then return false, whyManage end
    end

    local token = lock(vehicleId, 'remove_slot_assignment', src)
    if not token then return false, 'That vehicle is already being moved.' end

    local inGarage = DbBool(vehicle.is_stored)
        and tostring(vehicle.garage or '') == garageKey(houseId)
    local garageTemplate = GarageTemplates[house.garage_template_id]
    local slotDefinition = garageTemplate and garageTemplate.slots and garageTemplate.slots[slotIndex]

    setRollback(vehicleId, token, function()
        local okRollback, rows = pcall(function()
            if inGarage then
                return MySQL.update.await([[
                    UPDATE cm_owned_vehicles v
                    INNER JOIN cm_house_vehicle_slots s
                        ON s.house_id = ? AND s.slot_index = ?
                    SET s.vehicle_id = v.id, s.owner_class = ?,
                        s.assigned_by = ?, s.assigned_at = ?,
                        v.is_stored = 1, v.garage = ?, v.parking_id = ?, v.parked_at = NOW()
                    WHERE v.id = ? AND s.vehicle_id IS NULL
                ]], {
                    houseId, slotIndex, seat.owner_class or 'personal',
                    SqlNull(seat.assigned_by), SqlNull(seat.assigned_at),
                    garageKey(houseId), slotIndex, vehicleId,
                })
            end
            return MySQL.update.await([[
                UPDATE cm_house_vehicle_slots
                SET vehicle_id = ?, owner_class = ?, assigned_by = ?, assigned_at = ?
                WHERE house_id = ? AND slot_index = ? AND vehicle_id IS NULL
            ]], {
                vehicleId, seat.owner_class or 'personal', SqlNull(seat.assigned_by), SqlNull(seat.assigned_at),
                houseId, slotIndex,
            })
        end)
        if not okRollback then return false end
        if not rows or tonumber(rows) <= 0 then
            local current = MySQL.single.await([[
                SELECT v.is_stored, v.garage, s.vehicle_id
                FROM cm_owned_vehicles v
                LEFT JOIN cm_house_vehicle_slots s
                    ON s.house_id = ? AND s.slot_index = ?
                WHERE v.id = ? LIMIT 1
            ]], { houseId, slotIndex, vehicleId })
            local original = current and tonumber(current.vehicle_id) == vehicleId
                and (not inGarage or (DbBool(current.is_stored)
                    and tostring(current.garage or '') == garageKey(houseId)))
            if not original then return false end
        end

        if inGarage and slotDefinition then
            local viewer = garageViewerFor(houseId, src)
            if viewer then
                local row = VehicleById(vehicleId)
                if row then
                    ensureGarageEntity(viewer, houseId, {
                        index = slotIndex, coords = slotDefinition.coords, icon = slotDefinition.icon,
                    }, row)
                end
            end
        end
        BroadcastGarage(houseId)
        return true
    end, 'remove_assignment_prepared')

    if inGarage then
        touchOperation(vehicleId, token, 'deleting_garage_entity', true)
        local deleted, deleteWhy = deleteGarageEntity(houseId, slotIndex)
        if not deleted then
            rollbackOperation(vehicleId, token, 'garage entity deletion failed during remove')
            return false, tostring(deleteWhy or 'The garage vehicle could not be removed safely.')
        end
    end

    touchOperation(vehicleId, token, 'clearing_slot_assignment', true)
    local okUpdate, affected = pcall(function()
        if inGarage then
            return MySQL.update.await([[
                UPDATE cm_owned_vehicles v
                INNER JOIN cm_house_vehicle_slots s
                    ON s.vehicle_id = v.id AND s.house_id = ? AND s.slot_index = ?
                SET s.vehicle_id = NULL, s.owner_class = 'personal',
                    s.assigned_by = NULL, s.assigned_at = NULL,
                    v.is_stored = 0, v.garage = NULL, v.parking_id = NULL, v.parked_at = NULL
                WHERE v.id = ? AND v.is_stored = 1 AND v.garage = ?
            ]], { houseId, slotIndex, vehicleId, garageKey(houseId) })
        end
        -- The vehicle is already outside. Free only the reserved slot and leave
        -- the live city entity and its location untouched.
        return MySQL.update.await([[
            UPDATE cm_house_vehicle_slots
            SET vehicle_id = NULL, owner_class = 'personal',
                assigned_by = NULL, assigned_at = NULL
            WHERE house_id = ? AND slot_index = ? AND vehicle_id = ?
        ]], { houseId, slotIndex, vehicleId })
    end)

    if not okUpdate or not affected or tonumber(affected) <= 0 then
        rollbackOperation(vehicleId, token, okUpdate and 'remove assignment guard rejected' or 'remove assignment query failed')
        return false, okUpdate and 'The parking assignment changed. Reopen the menu.'
            or 'The parking assignment could not be removed.'
    end

    unlock(vehicleId, token)
    pcall(function()
        MySQL.query.await('DELETE FROM cm_house_shared_vehicles WHERE vehicle_id = ?', { vehicleId })
    end)
    LogHouse(houseId, house.family_id, cid, 'garage_remove_assignment', {
        vehicle = vehicleId, plate = vehicle.plate, slot = slotIndex, wasInside = inGarage,
    })
    BroadcastGarage(houseId)
    return true, ('%s was removed from parking space %d. The space is now available.'):format(
        vehicle.label or vehicle.plate, slotIndex)
end)

-- ------------------------------------------------------------
--  Family sharing: the owner flags which cars the family may drive.
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:shareVehicle', function(src, houseId, vehicleId, share)
    houseId, vehicleId = tonumber(houseId), tonumber(vehicleId)
    local inside, insideWhy = requireInsideGarage(src, houseId)
    if not inside then return false, insideWhy end
    local cid = GetCid(src)

    local ok, why = CanAccessProperty(cid, houseId, ACTIONS.GARAGE_MANAGE_SLOTS)
    if not ok then return false, why end

    local v = VehicleById(vehicleId)
    if not v then return false, 'That vehicle does not exist.' end

    -- Only the car's OWNER decides who may drive it. Not the house owner, not
    -- the family head -- it is not their car.
    if tonumber(v.owner_character_id) ~= tonumber(cid) then
        return false, 'Only the vehicle owner can share it.'
    end

    if share then
        MySQL.insert.await([[
            INSERT INTO cm_house_shared_vehicles (vehicle_id, house_id, shared_by)
            VALUES (?,?,?)
            ON DUPLICATE KEY UPDATE house_id = VALUES(house_id), shared_by = VALUES(shared_by)
        ]], { vehicleId, houseId, cid })

        MySQL.update.await(
            'UPDATE cm_house_vehicle_slots SET owner_class = ? WHERE vehicle_id = ?',
            { 'family', vehicleId })
    else
        MySQL.query.await('DELETE FROM cm_house_shared_vehicles WHERE vehicle_id = ?',
            { vehicleId })
        MySQL.update.await(
            'UPDATE cm_house_vehicle_slots SET owner_class = ? WHERE vehicle_id = ?',
            { 'personal', vehicleId })
    end

    LogHouse(houseId, Houses[houseId].family_id, cid,
        share and 'garage_share' or 'garage_unshare',
        { vehicle = vehicleId, plate = v.plate })

    BroadcastGarage(houseId)

    return true, share
        and ('%s can now be used by the family.'):format(v.label or v.plate)
        or  ('%s is private again.'):format(v.label or v.plate)
end)

-- ------------------------------------------------------------
--  Push a fresh garage view to everyone standing in it.
-- ------------------------------------------------------------
function BroadcastGarage(houseId)
    local state = GarageState(houseId)
    if not state then return end

    for _, src in ipairs(InsideProperty(houseId, 'garage')) do
        TriggerClientEvent('cm-house:client:garageUpdate', src, state)
    end
end

-- ------------------------------------------------------------
--  Reconciliation.
--  Slot reservations intentionally survive while a vehicle is outside.
--  Reconciliation removes only missing vehicles or conflicting house-storage
--  claims; is_stored=0 is a valid assigned-and-outside state.
-- ------------------------------------------------------------
function ReconcileGarages()
    -- Repair legacy duplicate physical slot rows and assignments before relying
    -- on the unique indexes. Keep the oldest row for a given house/index.
    local duplicateSlotRows = MySQL.update.await([[
        DELETE newer
        FROM cm_house_vehicle_slots newer
        INNER JOIN cm_house_vehicle_slots older
            ON older.house_id = newer.house_id
           AND older.slot_index = newer.slot_index
           AND older.id < newer.id
    ]]) or 0

    local duplicateRows = MySQL.update.await([[
        UPDATE cm_house_vehicle_slots duplicate_slot
        INNER JOIN (
            SELECT vehicle_id, MIN(id) AS keep_id
            FROM cm_house_vehicle_slots
            WHERE vehicle_id IS NOT NULL
            GROUP BY vehicle_id
            HAVING COUNT(*) > 1
        ) duplicate_vehicle ON duplicate_vehicle.vehicle_id = duplicate_slot.vehicle_id
        SET duplicate_slot.vehicle_id = NULL,
            duplicate_slot.owner_class = 'personal',
            duplicate_slot.assigned_by = NULL,
            duplicate_slot.assigned_at = NULL
        WHERE duplicate_slot.id <> duplicate_vehicle.keep_id
    ]]) or 0

    local staleRows = MySQL.update.await([[
        UPDATE cm_house_vehicle_slots s
        LEFT JOIN cm_owned_vehicles v ON v.id = s.vehicle_id
        SET s.vehicle_id = NULL, s.owner_class = 'personal',
            s.assigned_by = NULL, s.assigned_at = NULL
        WHERE s.vehicle_id IS NOT NULL
          AND (v.id IS NULL
               OR (v.is_stored = 1 AND (v.garage IS NULL
                   OR (v.garage REGEXP '^house:[0-9]+$'
                       AND v.garage <> CONCAT('house:', s.house_id)))))
    ]]) or 0

    -- Ensure every stored house vehicle has exactly one usable physical slot.
    local houseRows = MySQL.query.await([[
        SELECT DISTINCT CAST(SUBSTRING_INDEX(garage, ':', -1) AS UNSIGNED) AS house_id
        FROM cm_owned_vehicles
        WHERE is_stored = 1 AND garage REGEXP '^house:[0-9]+$'
    ]]) or {}
    local reseated = 0
    for _, row in ipairs(houseRows) do
        reseated = reseated + (ReseatHomelessVehicles(tonumber(row.house_id)) or 0)
    end

    -- Existing databases may predate the unique keys even though fresh schema
    -- files contain them. Add them only after cleanup; migration 009 does the
    -- same explicitly for operators who prefer SQL-controlled deployments.
    local function ensureUnique(indexName, columns)
        local exists = tonumber(MySQL.scalar.await([[
            SELECT COUNT(*) FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_house_vehicle_slots'
              AND INDEX_NAME = ?
        ]], { indexName })) or 0
        if exists > 0 then return true end
        local ok, err = pcall(function()
            MySQL.query.await(('ALTER TABLE cm_house_vehicle_slots ADD UNIQUE KEY `%s` (%s)')
                :format(indexName, columns))
        end)
        if not ok then
            print(('[cm-house] ^1could not add garage unique key %s: %s^7'):format(indexName, tostring(err)))
            return false
        end
        return true
    end
    ensureUnique('uq_house_slot', '`house_id`, `slot_index`')
    ensureUnique('uq_vehicle_once', '`vehicle_id`')

    if GetResourceState('cm-vehicles') == 'started' then
        local ok, result, details = pcall(function()
            return exports['cm-vehicles']:ReconcileSpawnRegistry()
        end)
        if not ok or result ~= true then
            print(('[cm-house] ^3cm-vehicles registry reconciliation was unavailable: %s^7')
                :format(tostring(details or result)))
        elseif Config.Debug then
            print(('[cm-house] vehicle registry reconciled: %s'):format(json.encode(details or {})))
        end
    end

    print(('[cm-house] garages reconciled | stale=%d duplicateSlots=%d duplicateVehicles=%d reseated=%d')
        :format(tonumber(staleRows) or 0, tonumber(duplicateSlotRows) or 0,
            tonumber(duplicateRows) or 0, reseated))
end

-- The bucket layer calls this when the final person leaves a garage. Real
-- parked entities are temporary representations; delete them until someone
-- enters again, while the database/slot assignment remains authoritative.
function OnGarageEmpty(houseId)
    cleanupGarageEntities(houseId)
    if Config.Debug then
        print(('[cm-house] unloaded networked garage vehicles for property %s'):format(tostring(houseId)))
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if GetResourceState('cm-vehicles') == 'started' then
        pcall(function() exports['cm-vehicles']:CleanupHouseGarageVehicles() end)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local pending = {}
    for vehicleId, op in pairs(Operations) do
        pending[#pending + 1] = { vehicleId = vehicleId, token = op.token }
    end
    for _, item in ipairs(pending) do
        rollbackOperation(item.vehicleId, item.token, 'cm-house resource stopping')
    end
    local houses = {}
    for houseId in pairs(GarageEntities) do houses[#houses + 1] = houseId end
    for _, houseId in ipairs(houses) do cleanupGarageEntities(houseId) end
end)

exports('GetGarageState', GarageState)
exports('IsGarageVehicleOperationActive', function(vehicleId)
    return Operations[tonumber(vehicleId)] ~= nil
end)

-- Local server-only event: cm-vehicles calls this after a permanent vehicle is
-- deleted transactionally. The database assignment is already clear; this
-- only refreshes current garage viewers. This is intentionally AddEventHandler
-- rather than RegisterNetEvent, so clients cannot invoke it.
AddEventHandler('cm-house:server:vehicleDeleted', function(vehicleId, houseIds)
    for _, houseId in ipairs(type(houseIds) == 'table' and houseIds or {}) do
        houseId = tonumber(houseId)
        if houseId then BroadcastGarage(houseId) end
    end
end)
