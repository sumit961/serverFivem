local U = CMVehicles.Utils
local Config = CMVehicles.Config
CMVehicles.Spawn = CMVehicles.Spawn or {}
CMVehicles.Server.Spawned = CMVehicles.Server.Spawned or {} -- compatibility plate index
CMVehicles.Server.SpawnedById = CMVehicles.Server.SpawnedById or {} -- authoritative registry
CMVehicles.Server.PlateToVehicleId = CMVehicles.Server.PlateToVehicleId or {}

-- Client-assisted garage creation is used for instantiated house garages.
-- Server-side CreateVehicle can fail for streamed/add-on models while still
-- leaving an orphan visible on a client. That caused invisible registry state,
-- duplicate recalls, and "local display vehicle" errors. The server now asks a
-- trusted nearby client to load/create the model as a NETWORK vehicle, then
-- validates and registers the returned entity before cm-house can use it.
local PendingGarageCreates = {}
local GarageCreateById = {}
local PersistentWorldCreateById = {}
local PersistentWorldRecoveryById = {}
local PersistentWorldRecoveryStates = {}
local PersistentWorldFailureLogAt = {}
local garageCreateSequence = 0
local garageReleaseSequence = 0
local finishGarageCreate

-- A model replacement normally completes after a vehicle is stored. If the
-- original stream files are already missing, there may be no live entity left
-- to store. Immediately before creating a replacement entity, let the catalog
-- owner finalize an existing server-authorized pending migration and reload
-- the same persistent vehicle row.
local function resolvePendingModelReplacementForSpawn(row)
    if type(row) ~= 'table' or not tonumber(row.id)
        or GetResourceState('rn-vehicleshop') ~= 'started' then
        return row
    end

    local called, applied, targetModel = pcall(function()
        return exports['rn-vehicleshop']:ResolvePendingModelReplacement(tonumber(row.id))
    end)
    if not called or applied ~= true then return row end

    local refreshed = CMVehicles.Server.GetVehicleById(tonumber(row.id))
    if refreshed then return refreshed end
    if type(targetModel) == 'string' and targetModel ~= '' then row.model = targetModel end
    return row
end

local function applyMissingModelFallbackForSpawn(row, reasonCode)
    if type(row) ~= 'table' or not tonumber(row.id)
        or GetResourceState('rn-vehicleshop') ~= 'started' then
        return nil, nil
    end

    local called, applied, targetModel, notice = pcall(function()
        return exports['rn-vehicleshop']:ApplyMissingModelFallback(tonumber(row.id), reasonCode)
    end)
    if not called or applied ~= true or tostring(targetModel or '') ~= 'komoda' then
        return nil, nil
    end

    local refreshed = CMVehicles.Server.GetVehicleById(tonumber(row.id))
    if not refreshed or tostring(refreshed.model or ''):lower() ~= 'komoda' then return nil, nil end
    return refreshed, tostring(notice or '')
end

local function waitForEntity(entity, timeoutMs)
    local timeout = GetGameTimer() + (tonumber(timeoutMs) or 5000)
    while entity and entity ~= 0 and not DoesEntityExist(entity) and GetGameTimer() < timeout do Wait(0) end
    return entity and entity ~= 0 and DoesEntityExist(entity)
end

local function waitForNetEntity(netId, timeoutMs)
    netId = tonumber(netId) or 0
    local entity = 0
    local timeout = GetGameTimer() + (tonumber(timeoutMs) or 7000)
    while GetGameTimer() < timeout do
        local ok, value = pcall(NetworkGetEntityFromNetworkId, netId)
        entity = ok and tonumber(value) or 0
        if entity and entity ~= 0 and DoesEntityExist(entity) then return entity end
        Wait(0)
    end
    return 0
end

-- OneSync deletion is asynchronous. Reconciliation must never report a stale
-- or duplicate entity as removed until the server confirms that it no longer
-- exists. This helper deliberately retries DeleteEntity for a short bounded
-- window and returns an acknowledgement to the caller.
local function deleteEntityConfirmed(entity, timeoutMs)
    entity = tonumber(entity) or 0
    if entity == 0 or not DoesEntityExist(entity) then return true end

    local deadline = GetGameTimer() + (tonumber(timeoutMs) or 3000)
    repeat
        pcall(DeleteEntity, entity)
        if not DoesEntityExist(entity) then return true end
        Wait(0)
    until GetGameTimer() >= deadline

    return not DoesEntityExist(entity)
end

local function activeEntity(active)
    if type(active) ~= 'table' then return 0 end
    local entity = tonumber(active.entity) or 0
    if entity ~= 0 and DoesEntityExist(entity) then return entity end
    local netId = tonumber(active.netId) or 0
    if netId > 0 then
        local ok, resolved = pcall(NetworkGetEntityFromNetworkId, netId)
        resolved = ok and tonumber(resolved) or 0
        if resolved ~= 0 and DoesEntityExist(resolved) then return resolved end
    end
    return 0
end

local function registryIdentity(identity)
    local vehicleId = tonumber(identity)
    if vehicleId and vehicleId > 0 then
        local active = CMVehicles.Server.SpawnedById[vehicleId]
        return vehicleId, active and active.plate or nil, active
    end

    local plate = U.NormalizePlate(identity)
    if plate == '' then return nil, nil, nil end
    vehicleId = tonumber(CMVehicles.Server.PlateToVehicleId[plate])
    local active = vehicleId and CMVehicles.Server.SpawnedById[vehicleId] or nil

    -- Compatibility recovery for records created before v3.3.0.
    if not active and type(CMVehicles.Server.Spawned[plate]) == 'table' then
        active = CMVehicles.Server.Spawned[plate]
        vehicleId = tonumber(active.vehicleId)
        if vehicleId then
            CMVehicles.Server.SpawnedById[vehicleId] = active
            CMVehicles.Server.PlateToVehicleId[plate] = vehicleId
        end
    end
    return vehicleId, plate, active
end

local function registrySet(rowOrId, active)
    active = type(active) == 'table' and active or {}
    local vehicleId = tonumber(type(rowOrId) == 'table' and rowOrId.id or rowOrId or active.vehicleId)
    local plate = U.NormalizePlate(type(rowOrId) == 'table' and rowOrId.plate or active.plate)
    if not vehicleId or vehicleId <= 0 or plate == '' then return false end

    -- If the plate changed, remove the stale secondary index first.
    local previous = CMVehicles.Server.SpawnedById[vehicleId]
    if previous and previous.plate and previous.plate ~= plate then
        CMVehicles.Server.Spawned[previous.plate] = nil
        CMVehicles.Server.PlateToVehicleId[previous.plate] = nil
    end

    active.vehicleId = vehicleId
    active.plate = plate
    CMVehicles.Server.SpawnedById[vehicleId] = active
    CMVehicles.Server.PlateToVehicleId[plate] = vehicleId
    CMVehicles.Server.Spawned[plate] = active
    return true
end

local function registryRemove(identity)
    local vehicleId, plate, active = registryIdentity(identity)
    if active then
        plate = U.NormalizePlate(active.plate or plate)
        vehicleId = tonumber(active.vehicleId) or vehicleId
    end
    if vehicleId then CMVehicles.Server.SpawnedById[vehicleId] = nil end
    if plate and plate ~= '' then
        CMVehicles.Server.PlateToVehicleId[plate] = nil
        CMVehicles.Server.Spawned[plate] = nil
    end
end

function CMVehicles.Spawn.RemoveDuplicateEntities(vehicleId, keepEntity)
    vehicleId = tonumber(vehicleId)
    keepEntity = tonumber(keepEntity) or 0
    if not vehicleId then return false, { deleted = 0, failed = 0 } end
    local ok, vehicles = pcall(GetAllVehicles)
    if not ok or type(vehicles) ~= 'table' then return false, 'vehicle_enumeration_unavailable' end
    local deleted, failed = 0, 0
    for _, entity in ipairs(vehicles) do
        if entity and entity ~= 0 and entity ~= keepEntity and DoesEntityExist(entity) then
            local id
            pcall(function() id = tonumber(Entity(entity).state.cmVehicleId) end)
            if id == vehicleId then
                if deleteEntityConfirmed(entity, 3000) then deleted = deleted + 1 else failed = failed + 1 end
            end
        end
    end
    return failed == 0, { deleted = deleted, failed = failed }
end

function CMVehicles.Spawn.RegisterEntity(src, row, netId, opts)
    opts = type(opts) == 'table' and opts or {}
    netId = tonumber(netId)
    if not row or not tonumber(row.id) or not netId or netId <= 0 then return false end
    local ent = waitForNetEntity(netId, 3500)
    if ent == 0 then return false end

    local plate = U.NormalizePlate(row.plate)
    if plate == '' then return false end
    local locked = opts.locked
    if locked == nil then locked = row.is_locked == true or row.is_locked == 1 end

    local previous = CMVehicles.Server.SpawnedById[tonumber(row.id)]
    local sameEntity = previous and (tonumber(previous.netId) == netId or activeEntity(previous) == ent)

    -- Database vehicle ID is the only authoritative identity. Before accepting
    -- a new registration, synchronously remove any other OneSync entity carrying
    -- the same cmVehicleId. This closes duplicate spawns caused by stale net IDs,
    -- client retries, or interrupted garage handoffs.
    local duplicateOk, duplicateInfo = CMVehicles.Spawn.RemoveDuplicateEntities(tonumber(row.id), ent)
    if duplicateOk ~= true then
        return false, ('Duplicate entity cleanup failed (%s).'):format(tostring(type(duplicateInfo) == 'table' and duplicateInfo.failed or duplicateInfo))
    end
    local context = opts.context
    local houseId = tonumber(opts.houseId)
    local slotIndex = tonumber(opts.slotIndex)
    local persistent = opts.persistent == true

    -- A passive registration refresh (for example opening the G menu) must not
    -- downgrade a parked house vehicle to world context. Explicit lifecycle
    -- calls still pass opts.context and therefore remain authoritative.
    if context == nil and sameEntity then
        context = previous.context
        houseId = tonumber(previous.houseId)
        slotIndex = tonumber(previous.slotIndex)
        persistent = tonumber(previous.source) == 0
    end
    context = tostring(context or 'world')

    local active = {
        netId = netId,
        entity = ent,
        -- Persistent garage entities are not tied to the client who happened to
        -- create them, so that player's logout cannot delete everyone else's car.
        source = persistent and 0 or tonumber(src) or 0,
        vehicleId = tonumber(row.id),
        plate = plate,
        context = context,
        houseId = houseId,
        slotIndex = slotIndex,
        updatedAt = os.time(),
    }
    if not registrySet(row, active) then return false end
    if CMVehicles.Location and CMVehicles.Location.ReconcileVehicle then
        pcall(CMVehicles.Location.ReconcileVehicle, tonumber(row.id))
    end

    local state = Entity(ent).state
    state:set('cmPlate', plate, true)
    state:set('cmVehicleId', tonumber(row.id), true)
    state:set('cmGarageCreateToken', false, true)
    state:set('cmLocked', locked == true, true)
    state:set('cmFuel', tonumber(state.cmFuel) or tonumber(row.fuel)
        or tonumber(Config.Fuel and Config.Fuel.defaultFuel) or 100.0, true)
    local healthNormalizer = U.NormalizeSavedHealth or U.NormalizeHealth
    state:set('cmEngineHealth', healthNormalizer(
        state.cmEngineHealth ~= nil and state.cmEngineHealth or row.engineHealth or row.engine_health, 1000.0), true)
    state:set('cmBodyHealth', healthNormalizer(
        state.cmBodyHealth ~= nil and state.cmBodyHealth or row.bodyHealth or row.body_health, 1000.0), true)
    state:set('cmTankHealth', healthNormalizer(
        state.cmTankHealth ~= nil and state.cmTankHealth or row.tankHealth or row.tank_health, 1000.0), true)
    state:set('cmDirtLevel', tonumber(state.cmDirtLevel) or tonumber(row.dirtLevel or row.dirt_level) or 0.0, true)
    local conditionState = type(state.cmConditionState) == 'table' and state.cmConditionState
        or (type(row.conditionState) == 'table' and row.conditionState or U.Decode(row.condition_state))
    state:set('cmConditionState', conditionState, true)
    local destroyedThreshold = tonumber(Config.Damage and Config.Damage.destroyedEngineHealth) or 150.0
    local destroyedState
    if sameEntity and state.cmEngineDestroyed ~= nil then
        destroyedState = state.cmEngineDestroyed == true
    else
        destroyedState = healthNormalizer(state.cmEngineHealth, 1000.0) <= destroyedThreshold
    end
    state:set('cmEngineDestroyed', destroyedState, true)
    -- Newly created entities need a finalize phase. Re-registering an existing,
    -- ready entity must never put it back into the loading quarantine.
    local currentlyReady = state.cmConditionReady == true
    local requiresFinalize
    if opts.requiresFinalize ~= nil then
        requiresFinalize = opts.requiresFinalize == true
    else
        requiresFinalize = context == 'house_garage' and not currentlyReady
    end
    state:set('cmConditionReady', currentlyReady or not requiresFinalize, true)
    local metadata = type(row.metadata) == 'table' and row.metadata or U.Decode(row.metadata)
    state:set('cmMileage', tonumber(metadata.mileage) or 0.0, true)
    state:set('cmRacingHarness', metadata.racingHarness == true or metadata.racing_harness == true, true)

    local isHouseGarage = context == 'house_garage'
    state:set('cmHouseGarageDisplay', isHouseGarage, true)
    state:set('cmHouseId', isHouseGarage and (houseId or 0) or 0, true)
    state:set('cmHouseSlot', isHouseGarage and (slotIndex or 0) or 0, true)
    if isHouseGarage then
        state:set('cmGarageReleased', false, true)
        state:set('cmGarageReleaseVersion', false, true)
        state:set('cmGarageReleasePending', false, true)
        if not sameEntity then state:set('cmGarageDriving', false, true) end
    end

    -- Plate text stays blank unless police have issued this vehicle a
    -- registration (cm-police MDT) -- vehicle identity is never read from
    -- this text (see docs/API.md), so showing the license number here is
    -- purely cosmetic/roleplay, safe to change without touching lookups.
    pcall(function() SetVehicleNumberPlateText(ent, row.license_number or '        ') end)
    return true
end

-- Vehicle ID is authoritative. Plate remains accepted for backward-compatible
-- callers and is resolved through the secondary index.
function CMVehicles.Spawn.DeleteVehicle(identity)
    local vehicleId, plate, active = registryIdentity(identity)
    if not vehicleId and type(identity) == 'number' then return true end
    plate = U.NormalizePlate((active and active.plate) or plate or identity)

    -- Cancel a client-assisted create before deleting. Late client responses are
    -- rejected and their entity is removed by the token handler.
    for token, pending in pairs(PendingGarageCreates) do
        local pendingId = tonumber(pending.row and pending.row.id)
        local pendingPlate = U.NormalizePlate(pending.row and pending.row.plate)
        if ((vehicleId and pendingId == vehicleId) or (plate ~= '' and pendingPlate == plate)) and finishGarageCreate then
            finishGarageCreate(token, { ok = false, error = 'Vehicle creation was superseded by a newer request.' })
        end
    end

    local occupant = plate ~= '' and CMVehicles.Server.TrunkOccupants and CMVehicles.Server.TrunkOccupants[plate]
    if occupant then
        TriggerClientEvent('cm-vehicles:client:exitTrunk', occupant, true)
        CMVehicles.Server.TrunkOccupants[plate] = nil
    end

    local targets = {}
    local entity = activeEntity(active)
    if entity ~= 0 then targets[entity] = true end

    -- Recover orphaned entities using the immutable database vehicle ID first.
    local okVehicles, vehicles = pcall(GetAllVehicles)
    if okVehicles and type(vehicles) == 'table' then
        for _, candidate in ipairs(vehicles) do
            if candidate and candidate ~= 0 and DoesEntityExist(candidate) then
                local stateId, statePlate
                pcall(function()
                    local state = Entity(candidate).state
                    stateId = tonumber(state.cmVehicleId)
                    statePlate = U.NormalizePlate(state.cmPlate)
                end)
                if (vehicleId and stateId == vehicleId) or (not vehicleId and plate ~= '' and statePlate == plate) then
                    targets[candidate] = true
                    vehicleId = vehicleId or stateId
                    if plate == '' then plate = statePlate end
                end
            end
        end
    end

    for target in pairs(targets) do pcall(DeleteEntity, target) end

    local deadline = GetGameTimer() + 3000
    while GetGameTimer() < deadline do
        local remaining = false
        for target in pairs(targets) do
            if DoesEntityExist(target) then
                remaining = true
                pcall(DeleteEntity, target)
            else
                targets[target] = nil
            end
        end
        if not remaining then
            registryRemove(vehicleId or plate)
            return true
        end
        Wait(0)
    end

    local survivor
    for target in pairs(targets) do
        if DoesEntityExist(target) then survivor = target break end
    end

    if survivor then
        local restored = type(active) == 'table' and active or {}
        local state = Entity(survivor).state
        local okNet, netId = pcall(NetworkGetNetworkIdFromEntity, survivor)
        restored.entity = survivor
        restored.netId = okNet and tonumber(netId) or tonumber(restored.netId) or 0
        restored.vehicleId = tonumber(restored.vehicleId) or vehicleId or tonumber(state.cmVehicleId)
        restored.plate = U.NormalizePlate(restored.plate or plate or state.cmPlate)
        restored.context = tostring(restored.context or (state.cmHouseGarageDisplay == true and 'house_garage' or 'world'))
        restored.houseId = tonumber(restored.houseId) or tonumber(state.cmHouseId)
        restored.slotIndex = tonumber(restored.slotIndex) or tonumber(state.cmHouseSlot)
        restored.updatedAt = os.time()
        registrySet(restored.vehicleId, restored)
        return false, ('Network entity %s could not be deleted.'):format(tostring(survivor))
    end

    registryRemove(vehicleId or plate)
    return true
end

-- Legacy function name retained for resources that still call it directly.
function CMVehicles.Spawn.DeleteByPlate(plate)
    return CMVehicles.Spawn.DeleteVehicle(plate)
end

function CMVehicles.Spawn.DeletePlayerVehicles(src)
    local ids = {}
    for vehicleId, data in pairs(CMVehicles.Server.SpawnedById) do
        if tonumber(data.source) == tonumber(src) then ids[#ids + 1] = vehicleId end
    end
    for _, vehicleId in ipairs(ids) do CMVehicles.Spawn.DeleteVehicle(vehicleId) end
end

finishGarageCreate = function(token, value)
    local pending = PendingGarageCreates[token]
    if not pending or pending.done then return end
    pending.done = true
    PendingGarageCreates[token] = nil
    pending.promise:resolve(value)
end

RegisterNetEvent('cm-vehicles:server:garageVehicleCreated', function(token, netId, clientError, errorCode)
    local src = source
    token = tostring(token or '')
    local pending = PendingGarageCreates[token]
    if not pending or pending.done or tonumber(pending.source) ~= tonumber(src) then
        if tonumber(netId) and tonumber(netId) > 0 then
            TriggerClientEvent('cm-vehicles:client:garageVehicleCreateRejected', src, token, tonumber(netId))
        end
        return
    end

    if clientError and tostring(clientError) ~= '' then
        local safeCode = tostring(errorCode or '') == 'model_unavailable' and 'model_unavailable' or nil
        finishGarageCreate(token, { ok = false, error = tostring(clientError), errorCode = safeCode })
        return
    end

    netId = tonumber(netId) or 0
    if netId <= 0 then
        finishGarageCreate(token, { ok = false, error = 'The client did not create a network vehicle.' })
        return
    end

    local entity = waitForNetEntity(netId, 7000)
    if entity == 0 then
        TriggerClientEvent('cm-vehicles:client:garageVehicleCreateRejected', src, token, netId)
        finishGarageCreate(token, { ok = false, error = 'The created vehicle never reached OneSync.' })
        return
    end

    local okType, entityType = pcall(GetEntityType, entity)
    if okType and entityType ~= 2 then
        pcall(DeleteEntity, entity)
        TriggerClientEvent('cm-vehicles:client:garageVehicleCreateRejected', src, token, netId)
        finishGarageCreate(token, { ok = false, error = 'The returned network entity is not a vehicle.' })
        return
    end

    local okModel, entityModel = pcall(GetEntityModel, entity)
    if not okModel or tonumber(entityModel) ~= tonumber(pending.modelHash) then
        pcall(DeleteEntity, entity)
        TriggerClientEvent('cm-vehicles:client:garageVehicleCreateRejected', src, token, netId)
        finishGarageCreate(token, { ok = false, error = 'The returned vehicle model did not match the owned vehicle.' })
        return
    end

    local coordsOk, distance = pcall(function()
        local actual = GetEntityCoords(entity)
        local expected = pending.spawn
        return #(actual - vector3(expected.x, expected.y, expected.z))
    end)
    if not coordsOk or tonumber(distance) > 12.0 then
        pcall(DeleteEntity, entity)
        TriggerClientEvent('cm-vehicles:client:garageVehicleCreateRejected', src, token, netId)
        finishGarageCreate(token, { ok = false, error = 'The returned vehicle was created outside its assigned garage space.' })
        return
    end

    SetEntityRoutingBucket(entity, tonumber(pending.bucket) or GetPlayerRoutingBucket(src))
    if SetEntityOrphanMode then pcall(SetEntityOrphanMode, entity, 2) end

    local registered = CMVehicles.Spawn.RegisterEntity(src, pending.row, netId, {
        persistent = true,
        context = 'house_garage',
        houseId = pending.houseId,
        slotIndex = pending.slotIndex,
        locked = false,
    })
    if not registered then
        pcall(DeleteEntity, entity)
        TriggerClientEvent('cm-vehicles:client:garageVehicleCreateRejected', src, token, netId)
        finishGarageCreate(token, { ok = false, error = 'The network vehicle could not be registered.' })
        return
    end

    TriggerClientEvent('cm-vehicles:client:garageVehicleCreateAccepted', src, token, netId)
    finishGarageCreate(token, { ok = true, entity = entity, netId = netId })
end)

local function resolveServerSetterType(row, suppliedType)
    local candidate = tostring(suppliedType or row.vehicle_type or ''):lower()
    local direct = {
        automobile = 'automobile', car = 'automobile', bike = 'bike', motorcycle = 'bike',
        bicycle = 'bike', boat = 'boat', heli = 'heli', helicopter = 'heli',
        plane = 'plane', submarine = 'submarine', trailer = 'trailer', train = 'train',
    }
    if direct[candidate] then return direct[candidate] end

    -- The shop catalog stores broad land/boat/air families. Resolve land and
    -- air subtypes from the actual model class so aircraft do not fall through
    -- to CreateVehicleServerSetter's automobile path.
    local model = tostring(row.model or ''):lower()
    if GetResourceState('rn-vehicleshop') == 'started' and model ~= '' then
        local ok, catalog = pcall(function()
            return MySQL.single.await('SELECT vehicle_type FROM cm_vehicle_catalog WHERE model = ? LIMIT 1', { model })
        end)
        if ok and type(catalog) == 'table' then candidate = tostring(catalog.vehicle_type or candidate):lower() end
    end

    local okClass, classId = pcall(GetVehicleClassFromName, type(row.model) == 'number' and row.model or joaat(model))
    classId = okClass and tonumber(classId) or nil
    if candidate == 'boat' or classId == 14 then return 'boat' end
    if classId == 15 then return 'heli' end
    if classId == 16 then return 'plane' end
    if classId == 21 then return 'train' end
    if classId == 8 or classId == 13 then return 'bike' end
    if candidate == 'air' then return 'plane' end
    return 'automobile'
end

-- Shared low-level CreateVehicleServerSetter path. It deliberately performs no
-- database writes or registry changes; callers decide the authoritative
-- context and must register the returned entity before exposing it.
local function tryServerGarageSetter(row, modelHash, spawn, vehicleType, bucket)
    if type(CreateVehicleServerSetter) ~= 'function' then return nil, 'server_setter_unavailable' end
    local okCreate, entity = pcall(CreateVehicleServerSetter,
        modelHash, vehicleType, spawn.x + 0.0, spawn.y + 0.0, spawn.z + 0.0, spawn.h + 0.0)
    entity = okCreate and tonumber(entity) or 0
    if entity == 0 or not waitForEntity(entity, 7000) then
        if entity ~= 0 then pcall(function() if DoesEntityExist(entity) then DeleteEntity(entity) end end) end
        return nil, 'server_setter_failed'
    end

    local okBucket = pcall(SetEntityRoutingBucket, entity, tonumber(bucket) or 0)
    if not okBucket then
        pcall(function() if DoesEntityExist(entity) then DeleteEntity(entity) end end)
        return nil, 'routing_bucket_failed'
    end
    if type(SetEntityOrphanMode) == 'function' then pcall(SetEntityOrphanMode, entity, 2) end

    local netId = 0
    local deadline = GetGameTimer() + 7000
    while netId <= 0 and GetGameTimer() < deadline do
        local okNet, value = pcall(NetworkGetNetworkIdFromEntity, entity)
        netId = okNet and tonumber(value) or 0
        if netId <= 0 then Wait(0) end
    end
    if netId <= 0 then
        pcall(function() if DoesEntityExist(entity) then DeleteEntity(entity) end end)
        return nil, 'network_id_unavailable'
    end
    return { entity = entity, netId = netId }
end

local function validWorldSpawn(spawn)
    if type(spawn) ~= 'table' then return nil end
    local x, y, z = tonumber(spawn.x), tonumber(spawn.y), tonumber(spawn.z)
    local h = tonumber(spawn.h or spawn.heading or spawn.w) or 0.0
    if not x or not y or not z or x ~= x or y ~= y or z ~= z or h ~= h
        or math.abs(x) > 20000 or math.abs(y) > 20000 or z < -500 or z > 5000
        or math.abs(h) > 100000 then return nil end
    h = h % 360.0
    return { x = x, y = y, z = z, h = h }
end

local function findWorldEntityByVehicleId(vehicleId)
    local active = CMVehicles.Server.SpawnedById[vehicleId]
    local entity = activeEntity(active)
    if entity ~= 0 then
        local houseDisplay = tostring(active.context or '') == 'house_garage'
        local okState, stateDisplay = pcall(function()
            return Entity(entity).state.cmHouseGarageDisplay == true
        end)
        if houseDisplay or (okState and stateDisplay) then
            return 0, nil, 'house_garage_display_present'
        end
        return entity, active, 'registry'
    end

    local ok, vehicles = pcall(GetAllVehicles)
    if not ok or type(vehicles) ~= 'table' then return 0, nil, 'enumeration_unavailable' end
    for _, candidate in ipairs(vehicles) do
        if candidate and candidate ~= 0 then
            local foundId, garage
            local okState = pcall(function()
                if not DoesEntityExist(candidate) then return end
                local state = Entity(candidate).state
                foundId = tonumber(state.cmVehicleId)
                garage = state.cmHouseGarageDisplay == true
            end)
            if okState and foundId == vehicleId and garage ~= true then
                return candidate, nil, 'orphan'
            elseif okState and foundId == vehicleId and garage == true then
                return 0, nil, 'house_garage_display_present'
            end
        end
    end
    return 0, nil, 'missing'
end

local function isVehicleSpawnBlocked(spawn)
    local ok, vehicles = pcall(GetAllVehicles)
    if not ok or type(vehicles) ~= 'table' then return false end
    for _, entity in ipairs(vehicles) do
        if entity and entity ~= 0 then
            local exists, coords = pcall(function()
                if not DoesEntityExist(entity) then return nil end
                return GetEntityCoords(entity)
            end)
            if exists and coords then
                local dx, dy, dz = coords.x - spawn.x, coords.y - spawn.y, coords.z - spawn.z
                if (dx * dx + dy * dy + dz * dz) < (2.75 * 2.75) then return true end
            end
        end
    end
    return false
end

local function persistentFinalizePayload(row, netId)
    local metadata = type(row.metadata) == 'table' and row.metadata or U.Decode(row.metadata)
    local health = U.NormalizeSavedHealth or U.NormalizeHealth
    return {
        netId = netId, id = tonumber(row.id), model = row.model, label = row.label,
        plate = U.NormalizePlate(row.plate), licenseNumber = row.license_number,
        fuel = tonumber(row.fuel) or 100.0,
        engineHealth = health(row.engine_health, 1000.0),
        bodyHealth = health(row.body_health, 1000.0),
        tankHealth = health(row.tank_health, 1000.0),
        dirtLevel = tonumber(row.dirt_level) or 0.0,
        locked = row.is_locked == true or row.is_locked == 1,
        warp = false, engineOn = false, repairFirst = false,
        metadata = metadata,
        mods = type(row.mods) == 'table' and row.mods or U.Decode(row.mods),
        conditionState = type(row.conditionState) == 'table' and row.conditionState or U.Decode(row.condition_state),
    }
end

local function createPersistentWorldVehicleLocked(vehicleId, spawn, organizationId)
    local row = CMVehicles.Server.GetVehicleById(vehicleId)
    if not row then return false, 'vehicle_not_found' end
    if tostring(row.owner_type or ''):lower() ~= 'organization'
        or tostring(row.owner_id or ''):lower() ~= organizationId then
        return false, 'organization_ownership_mismatch'
    end

    local existing, active, source = findWorldEntityByVehicleId(vehicleId)
    if source == 'enumeration_unavailable' then return false, 'entity_enumeration_unavailable' end
    if source == 'house_garage_display_present' then return false, 'vehicle_in_house_garage' end
    if existing ~= 0 then
        local currentlyReady = false
        local okReady = pcall(function() currentlyReady = Entity(existing).state.cmConditionReady == true end)
        local netOk, netId = pcall(NetworkGetNetworkIdFromEntity, existing)
        netId = netOk and tonumber(netId) or 0
        local registerCall, registered = false, false
        if netId > 0 then
            registerCall, registered = pcall(CMVehicles.Spawn.RegisterEntity, 0, row, netId, {
                persistent = true, context = 'world', locked = row.is_locked,
                requiresFinalize = not (okReady and currentlyReady),
            })
        end
        if not registerCall or registered ~= true then
            return false, 'existing_entity_register_failed'
        end
        if not (okReady and currentlyReady) then
            local stateOk = pcall(function()
                local state = Entity(existing).state
                state:set('cmConditionReady', false, true)
                state:set('cmPendingFinalize', persistentFinalizePayload(row, netId), true)
            end)
            if not stateOk then return false, 'existing_entity_finalize_state_failed' end
        end
        return true, {
            entity = existing, netId = netId, vehicleId = vehicleId, reused = true,
            pendingFinalize = not (okReady and currentlyReady),
        }
    end

    if isVehicleSpawnBlocked(spawn) then return false, 'spawn_point_blocked' end

    row = resolvePendingModelReplacementForSpawn(row)
    local modelName = tostring(row.model or ''):lower()
    local modelHash = type(row.model) == 'number' and row.model or (modelName ~= '' and joaat(modelName) or 0)
    if not modelHash or modelHash == 0 then return false, 'model_unavailable' end
    local vehicleType = resolveServerSetterType(row, nil)
    local created, createReason = tryServerGarageSetter(row, modelHash, spawn, vehicleType, 0)

    if not created and createReason == 'server_setter_failed' then
        local fallbackRow = applyMissingModelFallbackForSpawn(row, 'server_create_failed')
        if fallbackRow then
            row = fallbackRow
            modelName = tostring(row.model or ''):lower()
            modelHash = type(row.model) == 'number' and row.model or (modelName ~= '' and joaat(modelName) or 0)
            if modelHash and modelHash ~= 0 then
                vehicleType = resolveServerSetterType(row, nil)
                created, createReason = tryServerGarageSetter(row, modelHash, spawn, vehicleType, 0)
            end
        end
    end
    if not created then return false, createReason or 'server_setter_failed' end

    local entity = tonumber(created.entity) or 0
    if entity == 0 then return false, 'server_setter_failed' end
    local normalize = U.NormalizeSavedHealth or U.NormalizeHealth
    local engine = normalize(row.engine_health, 1000.0)
    local body = normalize(row.body_health, 1000.0)
    local tank = normalize(row.tank_health, 1000.0)
    pcall(SetVehicleNumberPlateText, entity, row.license_number or '        ')
    pcall(SetVehicleEngineHealth, entity, engine)
    pcall(SetVehicleBodyHealth, entity, body)
    pcall(SetVehiclePetrolTankHealth, entity, tank)
    pcall(SetVehicleFuelLevel, entity, tonumber(row.fuel) or 100.0)
    pcall(SetVehicleDirtLevel, entity, tonumber(row.dirt_level) or 0.0)
    pcall(SetVehicleDoorsLocked, entity, row.is_locked and 2 or 1)

    local registerCall, registered = pcall(CMVehicles.Spawn.RegisterEntity, 0, row, created.netId, {
        persistent = true, context = 'world', locked = row.is_locked, requiresFinalize = true,
    })
    if not registerCall or registered ~= true then
        pcall(function() if DoesEntityExist(entity) then DeleteEntity(entity) end end)
        return false, 'duplicate_cleanup_or_registration_failed'
    end

    local stateOk = pcall(function()
        local state = Entity(entity).state
        state:set('cmConditionReady', false, true)
        local payload = persistentFinalizePayload(row, created.netId)
        state:set('cmPendingFinalize', payload, true)
    end)
    if not stateOk then
        CMVehicles.Spawn.DeleteVehicle(vehicleId)
        return false, 'persistent_state_initialization_failed'
    end
    return true, { entity = entity, netId = created.netId, vehicleId = vehicleId, reused = false, pendingFinalize = true }
end

function CMVehicles.Spawn.CreatePersistentWorldVehicle(vehicleId, spawn, context)
    if GetInvokingResource() ~= 'cm-law' then return false, 'untrusted_caller' end
    vehicleId = tonumber(vehicleId)
    context = type(context) == 'table' and context or {}
    local organizationId = tostring(context.organizationId or ''):lower()
    local validOrg = { police = true, sahp = true, sheriff = true, fib = true, army = true }
    if not vehicleId or vehicleId <= 0 or not validOrg[organizationId] then return false, 'invalid_request' end
    spawn = validWorldSpawn(spawn)
    if not spawn then return false, 'invalid_spawn' end
    if PersistentWorldCreateById[vehicleId] then return false, 'recovery_in_progress' end
    PersistentWorldCreateById[vehicleId] = true
    local ok, result, detail = pcall(createPersistentWorldVehicleLocked, vehicleId, spawn, organizationId)
    PersistentWorldCreateById[vehicleId] = nil
    if not ok then return false, 'server_spawn_failed' end
    return result == true, detail
end

local function logPersistentWorldFailure(vehicleId, reason)
    local key = ('%s:%s'):format(tostring(vehicleId or 0), tostring(reason or 'unknown'))
    local now = os.time()
    if PersistentWorldFailureLogAt[key] and now - PersistentWorldFailureLogAt[key] < 300 then return end
    PersistentWorldFailureLogAt[key] = now
    print(('[cm-vehicles] persistent recovery vehicle_id %s: %s')
        :format(tostring(vehicleId or 'unknown'), tostring(reason or 'unknown')))
end

local function recoverPersistentWorldVehicleLocked(src, vehicleId, spawn, organizationId)
    PersistentWorldRecoveryStates[vehicleId] = { state = 'recovering_server', updatedAt = os.time() }
    local callOk, spawned, result = pcall(createPersistentWorldVehicleLocked, vehicleId, spawn, organizationId)
    if callOk and spawned == true and type(result) == 'table' then
        PersistentWorldRecoveryStates[vehicleId] = {
            state = result.pendingFinalize == true and 'active_pending_finalize' or 'active',
            updatedAt = os.time(),
        }
        return true, result, result.reused == true and 'existing' or 'server'
    end

    local reason = callOk and tostring(result or 'server_spawn_failed') or 'server_spawn_failed'
    if reason == 'organization_ownership_mismatch' or reason == 'vehicle_not_found'
        or reason == 'invalid_spawn' or reason == 'untrusted_caller'
        or reason == 'vehicle_in_house_garage' then
        PersistentWorldRecoveryStates[vehicleId] = { state = 'disabled', reason = reason, updatedAt = os.time() }
        logPersistentWorldFailure(vehicleId, reason)
        return false, reason
    end
    if reason == 'spawn_point_blocked' then
        PersistentWorldRecoveryStates[vehicleId] = { state = 'recovering_server', reason = reason, updatedAt = os.time() }
        logPersistentWorldFailure(vehicleId, reason)
        return false, reason
    end

    local clientFallbackAllowed = reason == 'server_setter_unavailable'
        or reason == 'server_setter_failed' or reason == 'model_unavailable'
    if not clientFallbackAllowed then
        PersistentWorldRecoveryStates[vehicleId] = { state = 'recovering_server', reason = reason, updatedAt = os.time() }
        logPersistentWorldFailure(vehicleId, reason)
        return false, reason
    end

    local suitableClient = src and src > 0 and GetPlayerName(src) ~= nil
    if suitableClient then
        local okBucket, bucket = pcall(GetPlayerRoutingBucket, src)
        suitableClient = okBucket and tonumber(bucket) == 0
    end
    if not suitableClient then
        PersistentWorldRecoveryStates[vehicleId] = {
            state = 'waiting_for_client', reason = reason, updatedAt = os.time(),
        }
        return false, 'waiting_for_client'
    end

    local row = CMVehicles.Server.GetVehicleById(vehicleId)
    if not row then
        PersistentWorldRecoveryStates[vehicleId] = { state = 'disabled', reason = 'vehicle_not_found', updatedAt = os.time() }
        return false, 'vehicle_not_found'
    end
    if tostring(row.owner_type or ''):lower() ~= 'organization'
        or tostring(row.owner_id or ''):lower() ~= organizationId then
        PersistentWorldRecoveryStates[vehicleId] = {
            state = 'disabled', reason = 'organization_ownership_mismatch', updatedAt = os.time(),
        }
        logPersistentWorldFailure(vehicleId, 'organization_ownership_mismatch')
        return false, 'organization_ownership_mismatch'
    end

    local createCall, created, createResult = pcall(function()
        return CMVehicles.Spawn.CreateGarageVehicle(src, row, spawn, { bucket = 0 })
    end)
    if not createCall or created ~= true or type(createResult) ~= 'table' then
        local fallbackReason = tostring(not createCall and 'client_spawn_call_failed'
            or (type(createResult) == 'table' and createResult.error or createResult or 'client_spawn_failed'))
        PersistentWorldRecoveryStates[vehicleId] = {
            state = 'waiting_for_client', reason = fallbackReason, updatedAt = os.time(),
        }
        logPersistentWorldFailure(vehicleId, fallbackReason)
        return false, fallbackReason
    end

    local promoteCall, promoted, promoteResult = pcall(function()
        return CMVehicles.Spawn.PromoteHouseGarageVehicle(vehicleId, src, spawn)
    end)
    if not promoteCall or promoted ~= true then
        pcall(CMVehicles.Spawn.DeleteVehicle, vehicleId)
        local fallbackReason = tostring(not promoteCall and 'client_spawn_promote_call_failed'
            or promoteResult or 'client_spawn_promote_failed')
        PersistentWorldRecoveryStates[vehicleId] = {
            state = 'waiting_for_client', reason = fallbackReason, updatedAt = os.time(),
        }
        logPersistentWorldFailure(vehicleId, fallbackReason)
        return false, fallbackReason
    end

    local active, info = CMVehicles.Spawn.GetSpawnedVehicleInfo(vehicleId)
    if active ~= true or type(info) ~= 'table' then
        PersistentWorldRecoveryStates[vehicleId] = {
            state = 'waiting_for_client', reason = 'client_entity_not_registered', updatedAt = os.time(),
        }
        logPersistentWorldFailure(vehicleId, 'client_entity_not_registered')
        return false, 'client_entity_not_registered'
    end
    PersistentWorldRecoveryStates[vehicleId] = { state = 'active_pending_finalize', updatedAt = os.time() }
    return true, {
        entity = tonumber(info.entity), netId = tonumber(info.netId), vehicleId = vehicleId,
        reused = false, pendingFinalize = true,
    }, 'client'
end

function CMVehicles.Spawn.RecoverPersistentWorldVehicle(src, vehicleId, spawn, context)
    if GetInvokingResource() ~= 'cm-law' then return { ok = false, error = 'untrusted_caller' } end
    vehicleId, src = tonumber(vehicleId), tonumber(src)
    context = type(context) == 'table' and context or {}
    local organizationId = tostring(context.organizationId or ''):lower()
    local validOrg = { police = true, sahp = true, sheriff = true, fib = true, army = true }
    if not vehicleId or vehicleId <= 0 or not validOrg[organizationId] then
        return { ok = false, error = 'invalid_request' }
    end
    spawn = validWorldSpawn(spawn)
    if not spawn then return { ok = false, error = 'invalid_spawn' } end
    if PersistentWorldRecoveryById[vehicleId] or PersistentWorldCreateById[vehicleId] then
        return { ok = false, error = 'recovery_in_progress' }
    end

    PersistentWorldRecoveryById[vehicleId] = true
    PersistentWorldCreateById[vehicleId] = true
    local results = table.pack(pcall(recoverPersistentWorldVehicleLocked, src, vehicleId, spawn, organizationId))
    PersistentWorldCreateById[vehicleId] = nil
    PersistentWorldRecoveryById[vehicleId] = nil
    if not results[1] then
        PersistentWorldRecoveryStates[vehicleId] = {
            state = 'recovering_server', reason = 'recovery_exception', updatedAt = os.time(),
        }
        logPersistentWorldFailure(vehicleId, 'recovery_exception')
        return { ok = false, error = 'recovery_exception' }
    end
    local recovered, result, mode = table.unpack(results, 2, results.n)
    if recovered ~= true or type(result) ~= 'table' then
        return { ok = false, error = tostring(result or 'recovery_failed') }
    end
    return { ok = true, vehicle = result, mode = mode, reused = result.reused == true }
end

--- Creates one registered network vehicle for a house garage slot.
--- This is a trusted server export; no public client event can request a model.
--- NOT CALLED. cm-house already fires finalizeSpawn from its own
--- finalizeGarageEntityFor, and doing it here too would just apply the same
--- condition twice.
---
--- Kept because it documents exactly what a garage car needs, and because a
--- caller that does NOT go through cm-house would need it.
local function finalizeGarageCondition(src, row, netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return end

    local metadata = U.Decode(row.metadata)
    local mods = U.Decode(row.mods)

    TriggerClientEvent('cm-vehicles:client:finalizeSpawn', src, {
        netId        = netId,
        id           = tonumber(row.id),
        model        = row.model,
        label        = row.label,
        plate        = U.NormalizePlate(row.plate),
        licenseNumber = row.licenseNumber or row.license_number,

        -- Straight from cm_owned_vehicles. This is the whole point.
        fuel         = tonumber(row.fuel) or 100.0,
        engineHealth = (U.NormalizeSavedHealth or U.NormalizeHealth)(row.engineHealth or row.engine_health, 1000.0),
        bodyHealth   = (U.NormalizeSavedHealth or U.NormalizeHealth)(row.bodyHealth or row.body_health, 1000.0),
        tankHealth   = (U.NormalizeSavedHealth or U.NormalizeHealth)(row.tankHealth or row.tank_health, 1000.0),
        dirtLevel    = tonumber(row.dirt_level) or 0.0,

        locked       = false,   -- a parked car in your own garage is not locked
        warp         = false,   -- do not throw the player into it
        engineOn     = false,
        mods         = mods,
        metadata     = metadata,
        conditionState = type(row.conditionState) == 'table' and row.conditionState or U.Decode(row.condition_state),
    })
end

function CMVehicles.Spawn.CreateGarageVehicle(src, row, spawn, context)
    src = tonumber(src)
    context = type(context) == 'table' and context or {}
    spawn = type(spawn) == 'table' and spawn or {}
    if not src or src <= 0 or not GetPlayerName(src) then return false, 'The garage viewer is not online.' end
    local vehicleId = row and tonumber(row.id)
    if not vehicleId then return false, 'Vehicle data is missing.' end

    local plate = U.NormalizePlate(row.plate)
    if plate == '' then return false, 'Vehicle plate is missing.' end

    local x, y, z = tonumber(spawn.x), tonumber(spawn.y), tonumber(spawn.z)
    if not x or not y or not z then return false, 'The garage slot position is invalid.' end
    local heading = tonumber(spawn.h or spawn.w or spawn.heading) or 0.0
    local bucket = tonumber(context.bucket) or GetPlayerRoutingBucket(src)
    if bucket ~= GetPlayerRoutingBucket(src) then return false, 'The garage routing bucket is not ready.' end

    -- Database vehicle ID is the authoritative identity. Plates remain display
    -- data and may change, so they must never serialize physical entity creation.
    local _, _, active = registryIdentity(vehicleId)
    local existingEntity = activeEntity(active)
    if existingEntity ~= 0
       and tostring(active.context or '') == 'house_garage'
       and tonumber(active.houseId) == tonumber(context.houseId)
       and tonumber(active.slotIndex) == tonumber(context.slotIndex) then
        SetEntityRoutingBucket(existingEntity, bucket)
        return true, { entity = existingEntity, netId = tonumber(active.netId), vehicleId = vehicleId }
    end

    local existingCreate = GarageCreateById[vehicleId]
    if existingCreate then
        local sharedResult = Citizen.Await(existingCreate)
        if type(sharedResult) ~= 'table' or sharedResult.ok ~= true then
            return false, type(sharedResult) == 'table' and sharedResult.error or 'The garage vehicle could not be created.'
        end
        return true, { entity = sharedResult.entity, netId = sharedResult.netId, vehicleId = vehicleId }
    end

    local deferred = promise.new()
    GarageCreateById[vehicleId] = deferred

    local deleted, deleteWhy = CMVehicles.Spawn.DeleteVehicle(vehicleId)
    if deleted == false then
        local failed = { ok = false, error = tostring(deleteWhy or 'The previous vehicle entity could not be deleted.') }
        deferred:resolve(failed)
        if GarageCreateById[vehicleId] == deferred then GarageCreateById[vehicleId] = nil end
        return false, failed.error
    end

    row = resolvePendingModelReplacementForSpawn(row)
    local modelHash = type(row.model) == 'number' and row.model or joaat(tostring(row.model or ''))
    if not modelHash or modelHash == 0 then
        local failed = { ok = false, error = 'The vehicle model is invalid.' }
        deferred:resolve(failed)
        if GarageCreateById[vehicleId] == deferred then GarageCreateById[vehicleId] = nil end
        return false, failed.error
    end

    garageCreateSequence = garageCreateSequence + 1
    local token = ('garage:%s:%s:%s:%s'):format(src, vehicleId, garageCreateSequence, math.random(100000, 999999))
    PendingGarageCreates[token] = {
        source = src,
        row = row,
        vehicleId = vehicleId,
        modelHash = modelHash,
        spawn = { x = x, y = y, z = z, h = heading },
        bucket = bucket,
        houseId = tonumber(context.houseId),
        slotIndex = tonumber(context.slotIndex),
        promise = deferred,
        done = false,
    }

    local saved = U.NormalizeSavedHealth or U.NormalizeHealth
    local bootstrap = U.NormalizeBootstrapHealth or function() return 1000.0 end
    TriggerClientEvent('cm-vehicles:client:createGarageNetworkVehicle', src, token, {
        id = vehicleId,
        plate = plate,
        model = tostring(row.model or ''),
        modelHash = modelHash,
        spawn = { x = x, y = y, z = z, h = heading },
        fuel = tonumber(row.fuel) or 100.0,
        engineHealth = saved(row.engineHealth or row.engine_health, 1000.0),
        bodyHealth = saved(row.bodyHealth or row.body_health, 1000.0),
        tankHealth = saved(row.tankHealth or row.tank_health, 1000.0),
        bootstrapEngineHealth = bootstrap(Config.Garage and Config.Garage.bootstrapHealth, 1000.0),
        bootstrapBodyHealth = bootstrap(Config.Garage and Config.Garage.bootstrapHealth, 1000.0),
        bootstrapTankHealth = bootstrap(Config.Garage and Config.Garage.bootstrapHealth, 1000.0),
        dirtLevel = tonumber(row.dirtLevel or row.dirt_level) or 0.0,
        mods = type(row.mods) == 'table' and row.mods or U.Decode(row.mods),
        metadata = type(row.metadata) == 'table' and row.metadata or U.Decode(row.metadata),
        conditionState = type(row.conditionState) == 'table' and row.conditionState or U.Decode(row.condition_state),
    })

    -- Client creation may spend 10s loading a streamed model, 7s obtaining a
    -- net ID and several seconds converging saved condition. Twelve seconds
    -- abandoned valid cars mid-flight and caused missing cars plus late ghosts.
    SetTimeout(30000, function()
        if PendingGarageCreates[token] then
            TriggerClientEvent('cm-vehicles:client:garageVehicleCreateRejected', src, token, 0)
            finishGarageCreate(token, { ok = false, error = 'Timed out while creating the garage vehicle.' })
        end
    end)

    local result = Citizen.Await(deferred)
    if GarageCreateById[vehicleId] == deferred then GarageCreateById[vehicleId] = nil end
    if type(result) ~= 'table' or result.ok ~= true then
        if type(result) == 'table' and result.errorCode == 'model_unavailable'
            and context._missingModelFallbackAttempted ~= true then
            local fallbackRow, notice = applyMissingModelFallbackForSpawn(row, 'model_unavailable')
            if fallbackRow then
                context._missingModelFallbackAttempted = true
                if notice ~= '' then U.Notify(src, notice, 'inform') end
                return CMVehicles.Spawn.CreateGarageVehicle(src, fallbackRow, spawn, context)
            end
        end
        return false, type(result) == 'table' and result.error or 'The garage vehicle could not be created.'
    end
    return true, { entity = result.entity, netId = result.netId, vehicleId = vehicleId }
end

function CMVehicles.Spawn.CleanupHouseGarageVehicles()
    local ids = {}
    for vehicleId, active in pairs(CMVehicles.Server.SpawnedById) do
        if tostring(active.context or '') == 'house_garage' then ids[#ids + 1] = vehicleId end
    end
    for _, vehicleId in ipairs(ids) do CMVehicles.Spawn.DeleteVehicle(vehicleId) end

    local ok, vehicles = pcall(GetAllVehicles)
    if ok and type(vehicles) == 'table' then
        for _, entity in ipairs(vehicles) do
            if entity and entity ~= 0 and DoesEntityExist(entity) then
                local isGarage = false
                pcall(function() isGarage = Entity(entity).state.cmHouseGarageDisplay == true end)
                if isGarage then pcall(DeleteEntity, entity) end
            end
        end
    end
    return true
end

function CMVehicles.Spawn.SetSpawnContext(identity, src, context)
    local vehicleId, _, active = registryIdentity(identity)
    if not vehicleId or not active then return false end
    active.source = tonumber(src) or active.source or 0
    active.context = tostring(context or 'world')
    active.houseId = nil
    active.slotIndex = nil
    active.updatedAt = os.time()
    registrySet(vehicleId, active)
    return true
end

local function spawnedSnapshot(identity)
    local vehicleId, _, active = registryIdentity(identity)
    if not vehicleId or type(active) ~= 'table' then return nil end

    local entity = activeEntity(active)
    if entity == 0 then
        registryRemove(vehicleId)
        return nil
    end

    local netId = tonumber(active.netId) or 0
    if netId <= 0 then
        local okNet, value = pcall(NetworkGetNetworkIdFromEntity, entity)
        netId = okNet and tonumber(value) or 0
    end
    if netId <= 0 then return nil end

    active.entity = entity
    active.netId = netId
    active.updatedAt = os.time()
    registrySet(vehicleId, active)
    return active, entity, netId
end

function CMVehicles.Spawn.GetSpawnedVehicleInfo(identity)
    local active, entity, netId = spawnedSnapshot(identity)
    if not active then return false, 'The spawned vehicle is not available.' end
    return true, {
        entity = entity,
        netId = netId,
        plate = active.plate,
        vehicleId = tonumber(active.vehicleId),
        context = tostring(active.context or 'world'),
        houseId = tonumber(active.houseId),
        slotIndex = tonumber(active.slotIndex),
    }
end

function CMVehicles.Spawn.ConfigureHouseGarageVehicle(identity, houseId, slotIndex, bucket)
    local active, entity, netId = spawnedSnapshot(identity)
    if not active then return false, 'The garage vehicle is no longer registered.' end

    houseId = tonumber(houseId)
    slotIndex = tonumber(slotIndex)
    bucket = tonumber(bucket)
    if not houseId or not slotIndex or not bucket then
        return false, 'Garage vehicle placement data is incomplete.'
    end

    SetEntityRoutingBucket(entity, bucket)
    if SetEntityOrphanMode then pcall(SetEntityOrphanMode, entity, 2) end

    active.source = 0
    active.context = 'house_garage'
    active.houseId = houseId
    active.slotIndex = slotIndex
    active.updatedAt = os.time()
    registrySet(active.vehicleId, active)

    local state = Entity(entity).state
    state:set('cmHouseGarageDisplay', true, true)
    state:set('cmHouseId', houseId, true)
    state:set('cmHouseSlot', slotIndex, true)
    state:set('cmGarageDriving', false, true)
    state:set('cmGarageReleased', false, true)
    state:set('cmGarageReleaseVersion', false, true)
    state:set('cmGarageReleasePending', false, true)
    state:set('cmLocked', false, true)

    return true, {
        entity = entity,
        netId = netId,
        plate = active.plate,
        vehicleId = tonumber(active.vehicleId),
        context = active.context,
        houseId = houseId,
        slotIndex = slotIndex,
    }
end

function CMVehicles.Spawn.GetSpawnedVehicleCondition(identity, fallback)
    local active, entity = spawnedSnapshot(identity)
    if not active then return false, 'The garage vehicle is no longer registered.' end
    fallback = type(fallback) == 'table' and fallback or {}

    local state = Entity(entity).state
    local saved = U.NormalizeSavedHealth or U.NormalizeHealth
    local stateEngine = saved(state.cmEngineHealth ~= nil and state.cmEngineHealth or fallback.engine_health or fallback.engine, 1000.0)
    local stateBody = saved(state.cmBodyHealth ~= nil and state.cmBodyHealth or fallback.body_health or fallback.body, 1000.0)
    local stateTank = saved(state.cmTankHealth ~= nil and state.cmTankHealth or fallback.tank_health or fallback.tank, 1000.0)
    local parked = state.cmHouseGarageDisplay == true or tostring(active.context or '') == 'house_garage'
    local ready = state.cmConditionReady == true

    local function nativeHealth(savedValue, native)
        local ok, value = pcall(native)
        value = ok and tonumber(value) or nil
        if value == nil or value ~= value then return savedValue end
        -- Before initialization is ready a native zero can be a streaming read.
        -- Afterwards zero is genuine damage and must be preserved.
        if not ready and value <= 0.0 then return savedValue end
        return saved(value, savedValue)
    end
    local function nativeNumber(defaultValue, native)
        local ok, value = pcall(native)
        value = ok and tonumber(value) or nil
        return value ~= nil and value or tonumber(defaultValue) or 0.0
    end

    local snapshot = type(state.cmConditionState) == 'table' and state.cmConditionState
        or (type(fallback.conditionState) == 'table' and fallback.conditionState or U.Decode(fallback.condition_state))
    return true, {
        fuel = math.max(0.0, math.min(100.0, tonumber(state.cmFuel) or tonumber(fallback.fuel) or 100.0)),
        engine = parked and stateEngine or nativeHealth(stateEngine, function() return GetVehicleEngineHealth(entity) end),
        body = parked and stateBody or nativeHealth(stateBody, function() return GetVehicleBodyHealth(entity) end),
        tank = parked and stateTank or nativeHealth(stateTank, function() return GetVehiclePetrolTankHealth(entity) end),
        dirt = nativeNumber(state.cmDirtLevel or fallback.dirt_level or fallback.dirt or 0.0,
            function() return GetVehicleDirtLevel(entity) end),
        conditionState = snapshot,
        conditionReady = ready,
    }
end

function CMVehicles.Spawn.IsPlayerDrivingSpawnedVehicle(src, identity, expectedNetId)
    src = tonumber(src)
    local active, entity, netId = spawnedSnapshot(identity)
    if not src or not active then return false, 'The garage vehicle is not available.' end
    if tonumber(expectedNetId) and tonumber(expectedNetId) > 0 and tonumber(expectedNetId) ~= netId then
        return false, 'The vehicle network identity changed.'
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Your player entity is not ready.' end
    local current = GetVehiclePedIsIn(ped, false)
    if not current or current == 0 or current ~= entity then
        return false, 'You must be in the driver seat of this vehicle.'
    end
    if GetPedInVehicleSeat(entity, -1) ~= ped then
        return false, 'You must be in the driver seat of this vehicle.'
    end
    return true
end

function CMVehicles.Spawn.PromoteHouseGarageVehicle(identity, src, spawn)
    local active, entity, netId = spawnedSnapshot(identity)
    if not active then return false, 'The garage vehicle is not available.' end
    spawn = type(spawn) == 'table' and spawn or {}

    local x, y, z = tonumber(spawn.x), tonumber(spawn.y), tonumber(spawn.z)
    local h = tonumber(spawn.h or spawn.w or spawn.heading) or 0.0
    if not x or not y or not z then return false, 'The outside vehicle exit is invalid.' end

    -- A non-owner may take the car only after the authoritative integration
    -- owner (family, EMS, police, admin) confirms access. CanUseVehicle also
    -- grants/revalidates the family session key where that integration needs
    -- one, while EMS fleet access remains tied to duty and rank permissions.
    if tonumber(src) and tonumber(src) > 0 and CMVehicles.API and CMVehicles.API.CanUseVehicle then
        local row = CMVehicles.Server.GetVehicleById(tonumber(active.vehicleId))
        if row and not CMVehicles.Server.IsOwner(src, row.plate) then
            local allowed, why = CMVehicles.API.CanUseVehicle(src, row.id, 'vehicle.drive')
            if allowed ~= true then
                return false, ('Vehicle access denied: %s'):format(tostring(why or 'not_allowed'))
            end
        end
    end

    local state = Entity(entity).state
    local destroyed = state.cmEngineDestroyed == true

    -- Move the entity first, then publish the world/reveal state. Publishing the
    -- state while the car is still in the private bucket can be missed by clients
    -- that only stream it after they return to bucket 0.
    SetEntityRoutingBucket(entity, 0)
    SetEntityCoords(entity, x + 0.0, y + 0.0, z + 0.0, false, false, false, false)
    SetEntityHeading(entity, h + 0.0)
    pcall(function() SetEntityVisible(entity, true, false) end)
    pcall(function() ResetEntityAlpha(entity) end)
    pcall(function() SetEntityCollision(entity, true, true) end)
    pcall(function() SetEntityInvincible(entity, false) end)
    pcall(function() SetVehicleCanBeVisiblyDamaged(entity, true) end)
    pcall(function() SetEntityProofs(entity, false, false, false, false, false, false, false, false) end)
    pcall(function() SetEntityHasGravity(entity, true) end)
    FreezeEntityPosition(entity, false)
    pcall(function() SetVehicleHandbrake(entity, false) end)

    garageReleaseSequence = garageReleaseSequence + 1
    local releaseToken = ('%s:%s:%s'):format(
        tostring(active.vehicleId), tostring(os.time()), tostring(garageReleaseSequence))
    state:set('cmHouseGarageDisplay', false, true)
    state:set('cmHouseId', 0, true)
    state:set('cmHouseSlot', 0, true)
    state:set('cmGarageDriving', false, true)
    -- Persistent replicated marker. Visibility, alpha, collision and freeze are
    -- client-local in practice, so every client that streams this vehicle must
    -- be able to recover the world state even after another client acknowledged
    -- the one-shot release token.
    state:set('cmGarageReleased', true, true)
    state:set('cmGarageReleaseVersion', releaseToken, true)
    state:set('cmLocked', false, true)
    state:set('cmGarageReleasePending', releaseToken, true)

    -- State-bag events are the durable cross-client mechanism, but visibility
    -- and alpha are client-local. Notify the requesting player immediately so
    -- their client begins a per-frame reveal watcher before the entity streams.
    if tonumber(src) and tonumber(src) > 0 then
        TriggerClientEvent('cm-vehicles:client:forceGarageWorldReveal', tonumber(src), netId, releaseToken)
    end

    active.source = tonumber(src) or 0
    active.context = 'world'
    active.houseId = nil
    active.slotIndex = nil
    active.updatedAt = os.time()
    registrySet(active.vehicleId, active)

    local conditionReady = state.cmConditionReady == true
    if not conditionReady then
        -- A persistent world vehicle can have been registered before its first
        -- streaming client verified the saved condition. Recalling it moves the
        -- same entity into range, so explicitly replay the trusted pending
        -- payload to the requester instead of waiting for another state-bag
        -- change that may never occur.
        local pendingFinalize = state.cmPendingFinalize
        if tonumber(src) and tonumber(src) > 0 and type(pendingFinalize) == 'table' then
            local payload = {}
            for key, value in pairs(pendingFinalize) do payload[key] = value end
            payload.netId = netId
            TriggerClientEvent('cm-vehicles:client:finalizeSpawn', tonumber(src), payload)
        end
    end

    if destroyed or not conditionReady then
        pcall(function() SetVehicleEngineOn(entity, false, true, true) end)
        pcall(function() SetVehicleUndriveable(entity, true) end)
    else
        pcall(function() SetVehicleUndriveable(entity, false) end)
    end
    return true, {
        entity = entity,
        netId = netId,
        vehicleId = tonumber(active.vehicleId),
        engineDestroyed = destroyed,
        releaseToken = releaseToken,
    }
end

-- Reposition an already-spawned world vehicle without deleting/recreating it.
-- This is the correct behaviour for a second "call vehicle" request: preserve
-- the same entity, its damage, occupants/state and network identity.
function CMVehicles.Spawn.RecallWorldVehicle(identity, src, spawn)
    local active, entity = spawnedSnapshot(identity)
    if not active then return false, 'The vehicle is not currently spawned.' end
    if tostring(active.context or '') == 'house_garage' then
        return false, 'The vehicle is still parked in a house garage.'
    end

    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then
        return false, 'The player requesting the vehicle is not available.'
    end
    local playerPed = GetPlayerPed(src)
    local driver = GetPedInVehicleSeat(entity, -1)
    if driver and driver ~= 0 and driver ~= playerPed then
        return false, 'That vehicle is currently being driven by another player.'
    end

    return CMVehicles.Spawn.PromoteHouseGarageVehicle(identity, src, spawn)
end

function CMVehicles.Spawn.ReturnHouseGarageVehicle(identity, houseId, slotIndex, bucket, spawn)
    local active, entity, netId = spawnedSnapshot(identity)
    if not active then return false, 'The vehicle entity is no longer available for rollback.' end
    spawn = type(spawn) == 'table' and spawn or {}
    houseId, slotIndex, bucket = tonumber(houseId), tonumber(slotIndex), tonumber(bucket)
    local x, y, z = tonumber(spawn.x), tonumber(spawn.y), tonumber(spawn.z)
    local h = tonumber(spawn.h or spawn.w or spawn.heading) or 0.0
    if not houseId or not slotIndex or not bucket or not x or not y or not z then
        return false, 'Garage rollback placement is incomplete.'
    end

    local oldBucket = GetEntityRoutingBucket(entity)
    local oldCoords = GetEntityCoords(entity)
    local oldHeading = GetEntityHeading(entity)
    local zOffset = tonumber(Config.Garage and Config.Garage.spawnZOffset) or 0.45
    local target = vector3(x + 0.0, y + 0.0, z + zOffset)

    -- Bucket migration and entity ownership can converge on different ticks.
    -- Repeat placement until OneSync confirms both the private garage bucket
    -- and slot coordinates instead of reporting a successful invisible recall.
    local placed = false
    local deadline = GetGameTimer() + 4000
    repeat
        SetEntityRoutingBucket(entity, bucket)
        SetEntityCoords(entity, target.x, target.y, target.z, false, false, false, false)
        SetEntityHeading(entity, h)
        pcall(function() SetEntityVelocity(entity, 0.0, 0.0, 0.0) end)
        FreezeEntityPosition(entity, true)
        Wait(0)
        placed = GetEntityRoutingBucket(entity) == bucket
            and #(GetEntityCoords(entity) - target) <= 2.0
        if not placed then Wait(50) end
    until placed or GetGameTimer() >= deadline

    if not placed then
        SetEntityRoutingBucket(entity, oldBucket)
        SetEntityCoords(entity, oldCoords.x, oldCoords.y, oldCoords.z, false, false, false, false)
        SetEntityHeading(entity, oldHeading)
        FreezeEntityPosition(entity, false)
        return false, 'The vehicle could not converge into the garage parking space.'
    end
    pcall(function() SetVehicleHandbrake(entity, true) end)

    active.source = 0
    active.context = 'house_garage'
    active.houseId = houseId
    active.slotIndex = slotIndex
    active.updatedAt = os.time()
    registrySet(active.vehicleId, active)

    local state = Entity(entity).state
    state:set('cmHouseGarageDisplay', true, true)
    state:set('cmHouseId', houseId, true)
    state:set('cmHouseSlot', slotIndex, true)
    state:set('cmGarageDriving', false, true)
    state:set('cmGarageReleased', false, true)
    state:set('cmGarageReleaseVersion', false, true)
    state:set('cmGarageReleasePending', false, true)
    state:set('cmLocked', false, true)

    -- Returning to the family garage ends every temporary family driving
    -- session for this car. Manual owner-lent keys are not touched.
    if CMVehicles.API and CMVehicles.API.RevokeFamilyVehicleKeys then
        CMVehicles.API.RevokeFamilyVehicleKeys(active.vehicleId, nil, 'family-vehicle-returned')
    end

    return true, { entity = entity, netId = netId, vehicleId = tonumber(active.vehicleId) }
end

RegisterNetEvent('cm-vehicles:server:garageReleaseApplied', function(netId, token)
    local src = source
    netId = tonumber(netId) or 0
    token = tostring(token or '')
    if netId <= 0 or token == '' then return end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    if GetPlayerRoutingBucket(src) ~= GetEntityRoutingBucket(entity) then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local okNear, near = pcall(function()
        return #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= 150.0
    end)
    if not okNear or near ~= true then return end

    local state = Entity(entity).state
    if tostring(state.cmGarageReleasePending or '') ~= token then return end
    state:set('cmGarageReleasePending', false, true)
end)

-- Two rapid triggers of the same server-authoritative spawn for one
-- vehicleId (a doubled client event, or two access holders racing to call
-- the same car) could otherwise both observe the vehicle as "not yet
-- spawned" and each create their own live entity, since the body below
-- yields several times (native creation, net-id polling) before
-- RegisterEntity marks it spawned. Mirrors the GarageCreateById dedupe used
-- for client-assisted garage creates above.
local SpawnCreateById = {}

local function createForPlayerLocked(src, row, opts)
    opts = type(opts) == 'table' and opts or {}
    if not row then return false, 'Vehicle missing.' end
    local plate = U.NormalizePlate(row.plate)
    local deleted, deleteWhy = CMVehicles.Spawn.DeleteVehicle(tonumber(row.id) or plate)
    if deleted ~= true then
        return false, tostring(deleteWhy or 'The previous vehicle entity could not be removed.')
    end
    row = resolvePendingModelReplacementForSpawn(row)

    local spawn = opts.spawn or U.Decode(row.last_position)
    local ped = GetPlayerPed(src)
    local pcoords = ped and ped ~= 0 and GetEntityCoords(ped) or vector3(0.0, 0.0, 72.0)
    local x = spawn.x or spawn[1] or (pcoords.x + 3.0)
    local y = spawn.y or spawn[2] or pcoords.y
    local z = spawn.z or spawn[3] or pcoords.z
    local h = spawn.w or spawn.heading or spawn[4] or (ped and GetEntityHeading(ped) or 0.0)

    local modelHash = type(row.model) == 'number' and row.model or joaat(row.model or 'sultan')
    local veh = 0
    if type(CreateVehicleServerSetter) == 'function' then
        local vehicleType = tostring(row.vehicle_type or opts.vehicleType or 'automobile'):lower()
        local allowedTypes = {
            automobile = true, bike = true, boat = true, heli = true,
            plane = true, submarine = true, trailer = true, train = true,
        }
        if not allowedTypes[vehicleType] then vehicleType = 'automobile' end
        local okSetter, created = pcall(CreateVehicleServerSetter,
            modelHash, vehicleType, x + 0.0, y + 0.0, z + 0.0, h + 0.0)
        if okSetter then veh = tonumber(created) or 0 end
    end
    if veh == 0 or not waitForEntity(veh, 3500) then
        if veh ~= 0 and DoesEntityExist(veh) then pcall(DeleteEntity, veh) end
        local okCreate, created = pcall(CreateVehicle,
            modelHash, x + 0.0, y + 0.0, z + 0.0, h + 0.0, true, true)
        veh = okCreate and tonumber(created) or 0
    end
    if veh == 0 or not waitForEntity(veh) then
        if veh ~= 0 and DoesEntityExist(veh) then pcall(DeleteEntity, veh) end
        if opts._missingModelFallbackAttempted ~= true then
            local fallbackRow, notice = applyMissingModelFallbackForSpawn(row, 'server_create_failed')
            if fallbackRow then
                opts._missingModelFallbackAttempted = true
                if notice ~= '' then U.Notify(src, notice, 'inform') end
                return createForPlayerLocked(src, fallbackRow, opts)
            end
        end
        return false, 'Server-side vehicle creation failed.'
    end

    local targetBucket = tonumber(opts.bucket)
    if targetBucket == nil then targetBucket = GetPlayerRoutingBucket(src) end
    SetEntityRoutingBucket(veh, targetBucket)
    if SetEntityOrphanMode then pcall(SetEntityOrphanMode, veh, 2) end
    if SetVehicleNumberPlateText then SetVehicleNumberPlateText(veh, row.license_number or '        ') end

    local locked = opts.locked
    if locked == nil then locked = row.is_locked == true or row.is_locked == 1 end
    local netId = 0
    local netDeadline = GetGameTimer() + 5000
    while netId <= 0 and GetGameTimer() < netDeadline do
        local okNet, value = pcall(NetworkGetNetworkIdFromEntity, veh)
        netId = okNet and tonumber(value) or 0
        if netId <= 0 then Wait(0) end
    end
    if netId <= 0 then
        if DoesEntityExist(veh) then DeleteEntity(veh) end
        return false, 'Vehicle entity was created but never received a network id.'
    end

    if not CMVehicles.Spawn.RegisterEntity(src, row, netId, {
        locked = locked, context = 'world', requiresFinalize = true
    }) then
        if DoesEntityExist(veh) then DeleteEntity(veh) end
        return false, 'Vehicle entity could not be registered.'
    end

    local metadata = type(row.metadata) == 'table' and row.metadata or U.Decode(row.metadata)
    local finalizePayload = {
        netId = netId,
        id = tonumber(row.id),
        model = row.model,
        label = row.label,
        plate = plate,
        licenseNumber = row.licenseNumber or row.license_number,
        fuel = tonumber(row.fuel) or 100,
        engineHealth = (U.NormalizeSavedHealth or U.NormalizeHealth)(opts.engineHealth or row.engineHealth or row.engine_health, 1000.0),
        bodyHealth = (U.NormalizeSavedHealth or U.NormalizeHealth)(opts.bodyHealth or row.bodyHealth or row.body_health, 1000.0),
        tankHealth = (U.NormalizeSavedHealth or U.NormalizeHealth)(opts.tankHealth or row.tankHealth or row.tank_health, 1000.0),
        dirtLevel = tonumber(opts.dirtLevel or row.dirtLevel or row.dirt_level) or 0,
        locked = locked == true,
        warp = opts.warp == true,
        engineOn = opts.engineOn == true,
        repairFirst = opts.repairFirst == true,
        metadata = metadata,
        mods = type(row.mods) == 'table' and row.mods or U.Decode(row.mods),
        conditionState = type(row.conditionState) == 'table' and row.conditionState or U.Decode(row.condition_state)
    }

    -- If the caller is inside a private garage bucket while requesting a car
    -- outside, their client cannot stream/finalize the new world entity yet.
    -- Replicate the trusted payload so the first world client that streams it
    -- can complete condition/mod initialization. The normal direct event is
    -- still used whenever the caller already shares the target bucket.
    Entity(veh).state:set('cmPendingFinalize', finalizePayload, true)
    if targetBucket == GetPlayerRoutingBucket(src) then
        TriggerClientEvent('cm-vehicles:client:finalizeSpawn', src, finalizePayload)
    end

    return true, netId
end

-- Deduplicates concurrent spawn requests for the same DB vehicle instead of
-- letting each one race through createForPlayerLocked independently.
function CMVehicles.Spawn.CreateForPlayer(src, row, opts)
    local vehicleId = type(row) == 'table' and tonumber(row.id)
    if not vehicleId then return createForPlayerLocked(src, row, opts) end

    local existing = SpawnCreateById[vehicleId]
    if existing then
        local shared = Citizen.Await(existing)
        if type(shared) == 'table' and shared.ok == true then return true, shared.netId end
        return false, type(shared) == 'table' and shared.error or 'The vehicle could not be created.'
    end

    local deferred = promise.new()
    SpawnCreateById[vehicleId] = deferred
    local ok, result = createForPlayerLocked(src, row, opts)
    if SpawnCreateById[vehicleId] == deferred then SpawnCreateById[vehicleId] = nil end
    deferred:resolve(ok == true and { ok = true, netId = result } or { ok = false, error = result })
    return ok, result
end

RegisterNetEvent('cm-vehicles:server:spawnOwnedVehicle', function(vehicleId)
    local src = source
    vehicleId = tonumber(vehicleId)
    local row = CMVehicles.Server.GetVehicleById(vehicleId)
    if not row then return U.Notify(src, 'Vehicle not found.', 'error') end
    if not CMVehicles.Server.IsOwner(src, row.plate) then return U.Notify(src, 'You do not own this vehicle.', 'error') end

    local infoOk, info = CMVehicles.Spawn.GetSpawnedVehicleInfo(vehicleId)
    if infoOk and type(info) == 'table' then
        if tostring(info.context or '') == 'house_garage' then
            return U.Notify(src, 'This vehicle is parked in a house garage. Call it from that garage.', 'error')
        end
        local ped = GetPlayerPed(src)
        local coords = ped and ped ~= 0 and GetEntityCoords(ped) or vector3(0.0, 0.0, 72.0)
        local heading = ped and ped ~= 0 and GetEntityHeading(ped) or 0.0
        local ok, result = CMVehicles.Spawn.RecallWorldVehicle(vehicleId, src, {
            x = coords.x + 3.0, y = coords.y, z = coords.z, h = heading,
        })
        if ok then
            return U.Notify(src, 'Your existing vehicle was recalled nearby.', 'success')
        end
        return U.Notify(src, tostring(result or 'The existing vehicle could not be recalled.'), 'error')
    end

    local ok, err = CMVehicles.Spawn.CreateForPlayer(src, row, {
        warp = false, engineOn = false, repairFirst = false
    })
    if not ok then U.Notify(src, tostring(err or 'Could not spawn vehicle.'), 'error') end
end)

RegisterNetEvent('cm-vehicles:server:spawnPurchasedVehicle', function(payload)
    local src = source
    local vehicleId = type(payload) == 'table' and tonumber(payload.id or payload.vehicleId) or tonumber(payload)
    if not vehicleId then return U.Notify(src, 'Purchased vehicle id is missing.', 'error') end

    local row = CMVehicles.Server.GetVehicleById(vehicleId)
    if not row then return U.Notify(src, 'Purchased vehicle was not found in the database.', 'error') end
    if not CMVehicles.Server.IsOwner(src, row.plate) then
        return U.Notify(src, 'You do not own this purchased vehicle.', 'error')
    end

    local ok, err = CMVehicles.Spawn.CreateForPlayer(src, row, { warp = true, engineOn = false, repairFirst = true })
    if not ok then U.Notify(src, tostring(err or 'Could not spawn purchased vehicle.'), 'error') end
end)

function CMVehicles.Spawn.SpawnFromParking(src, vehicleId, lotId, spawn, options)
    options = type(options) == 'table' and options or {}
    local row = CMVehicles.Server.GetVehicleById(vehicleId)
    if not row then return false, 'Vehicle not found.' end
    local isCharacterOwner = tostring(row.owner_type or 'character') == 'character'
        and tostring(row.owner_character_id) == tostring(CMVehicles.Server.GetCharacterId(src))
    if not isCharacterOwner then
        local accessAllowed = false
        if options.allowAuthorizedAccess == true and CMVehicles.API and CMVehicles.API.CanUseVehicle then
            local okAccess, allowed = pcall(CMVehicles.API.CanUseVehicle, src, row, 'vehicle.drive')
            accessAllowed = okAccess and allowed == true
        end
        if not accessAllowed then return false, 'You do not own this vehicle.' end
    end

    local wasStored = row.is_stored == true or row.is_stored == 1
    local destroyed = (U.NormalizeSavedHealth or U.NormalizeHealth)(row.engine_health, 1000.0)
        <= (tonumber(Config.Damage and Config.Damage.destroyedEngineHealth) or 150.0)
    local repair = wasStored and destroyed and Config.Rules.ParkingRepairOnRetrieve == true
    local finalLocked = options.unlockOnRetrieve == true and false or (row.is_locked == true or row.is_locked == 1)

    local previous = {
        isStored = wasStored,
        parkingId = row.parking_id,
        garage = row.garage,
        parkedAt = row.parked_at,
        locked = row.is_locked == true or row.is_locked == 1,
        engine = (U.NormalizeSavedHealth or U.NormalizeHealth)(row.engine_health, 1000.0),
        body = (U.NormalizeSavedHealth or U.NormalizeHealth)(row.body_health, 1000.0),
        tank = (U.NormalizeSavedHealth or U.NormalizeHealth)(row.tank_health, 1000.0),
        dirt = tonumber(row.dirt_level) or 0.0,
        conditionState = type(row.conditionState) == 'table' and row.conditionState or U.Decode(row.condition_state),
    }

    local targetEngine = repair and 1000.0 or previous.engine
    local targetBody = repair and 1000.0 or previous.body
    local targetTank = repair and 1000.0 or previous.tank
    local targetDirt = repair and 0.0 or previous.dirt
    local targetCondition = repair and {} or previous.conditionState

    local insuranceFee = repair and math.max(0, math.floor(tonumber(Config.Rules.ParkingInsuranceFee) or 0)) or 0
    local insuranceAccount = tostring(Config.Rules.ParkingInsuranceAccount or 'cash')
    local insuranceCharged = false

    local function refundInsurance(reason)
        if not insuranceCharged or insuranceFee <= 0 then return true end
        local refunded = CMVehicles.Server.AddMoney(src, insuranceFee,
            reason or 'parking-insurance-refund', insuranceAccount)
        if refunded then
            insuranceCharged = false
            CMVehicles.Server.Audit(CMVehicles.Server.GetCharacterId(src), row.plate,
                'parking_insurance_refunded', { amount = insuranceFee, account = insuranceAccount })
        else
            local charId = CMVehicles.Server.GetCharacterId(src)
            local refundToken = ('insurance-refund:%s:%s:%s'):format(
                tostring(row.id), tostring(os.time()), tostring(math.random(100000, 999999)))
            pcall(function()
                MySQL.insert.await([[
                    INSERT IGNORE INTO cm_vehicle_pending_payouts
                        (sale_token, vehicle_id, character_id, plate, amount, account, reason, status, last_error)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 'immediate_refund_failed')
                ]], {
                    refundToken, tonumber(row.id), tostring(charId or ''), row.plate,
                    insuranceFee, insuranceAccount, reason or 'parking-insurance-refund',
                })
            end)
            print(('[cm-vehicles] ^3Parking insurance refund $%s queued for src %s, vehicle %s.^7')
                :format(tostring(insuranceFee), tostring(src), tostring(row.id)))
        end
        return refunded
    end

    if insuranceFee > 0 then
        if not CMVehicles.Server.RemoveMoney(src, insuranceFee,
            'parking-insurance-recovery', insuranceAccount) then
            local held = CMVehicles.Server.GetMoney(src, insuranceAccount)
            return false, ('Insurance recovery costs $%s. You have $%s in %s.')
                :format(tostring(insuranceFee), tostring(math.floor(held or 0)), insuranceAccount)
        end
        insuranceCharged = true
    end

    if wasStored then
        local affected = MySQL.update.await([[UPDATE cm_owned_vehicles SET
            is_stored = 0,
            parking_id = NULL,
            garage = NULL,
            parked_at = NULL,
            is_locked = ?,
            engine_health = ?,
            body_health = ?,
            tank_health = ?,
            dirt_level = ?,
            condition_state = ?
            WHERE id = ? AND is_stored = 1]], {
            finalLocked and 1 or 0,
            targetEngine, targetBody, targetTank, targetDirt, U.Encode(targetCondition), row.id
        })
        if not affected or tonumber(affected) <= 0 then
            refundInsurance('parking-insurance-state-refund')
            return false, 'The parking state changed before retrieval. Try again.'
        end
    elseif finalLocked ~= previous.locked then
        MySQL.update.await('UPDATE cm_owned_vehicles SET is_locked = ? WHERE id = ?', {
            finalLocked and 1 or 0, row.id
        })
    end

    row.is_stored = false
    row.parking_id = nil
    row.garage = nil
    row.parked_at = nil
    row.is_locked = finalLocked
    row.engine_health = targetEngine
    row.body_health = targetBody
    row.tank_health = targetTank
    row.dirt_level = targetDirt
    row.condition_state = U.Encode(targetCondition)
    row.conditionState = targetCondition

    local ok, result = CMVehicles.Spawn.CreateForPlayer(src, row, {
        spawn = spawn,
        warp = options.warp == true,
        engineOn = options.engineOn == true,
        repairFirst = repair,
        engineHealth = targetEngine,
        bodyHealth = targetBody,
        tankHealth = targetTank,
        dirtLevel = targetDirt,
        locked = finalLocked,
        vehicleType = options.vehicleType,
    })
    if not ok then
        if wasStored then
            local restored = MySQL.update.await([[UPDATE cm_owned_vehicles SET
                is_stored = 1, parking_id = ?, garage = ?, parked_at = ?, is_locked = ?,
                engine_health = ?, body_health = ?, tank_health = ?, dirt_level = ?, condition_state = ?
                WHERE id = ? AND is_stored = 0]], {
                previous.parkingId, previous.garage, previous.parkedAt, previous.locked and 1 or 0,
                previous.engine, previous.body, previous.tank, previous.dirt,
                U.Encode(previous.conditionState), row.id
            })
            if not restored or tonumber(restored) <= 0 then
                print(('[cm-vehicles] ^1parking spawn rollback failed for vehicle %s after: %s^7')
                    :format(tostring(row.id), tostring(result)))
                refundInsurance('parking-insurance-critical-refund')
                return false, 'Vehicle spawn failed and its parking rollback also failed. Contact an administrator.'
            end
        end
        refundInsurance('parking-insurance-spawn-refund')
        return false, result
    end

    if CMVehicles.Location then
        pcall(CMVehicles.Location.Transition, row.id, 'OUTSIDE', {
            reason = 'parking_retrieval', actorCharacterId = CMVehicles.Server.GetCharacterId(src)
        })
    end

    if insuranceCharged then
        CMVehicles.Server.Audit(CMVehicles.Server.GetCharacterId(src), row.plate,
            'parking_insurance_paid', { amount = insuranceFee, account = insuranceAccount })
    end

    local msg
    if repair then
        msg = ('Insurance vehicle recovered. Paid: $%s from %s'):format(tostring(insuranceFee), insuranceAccount)
    elseif wasStored then
        msg = destroyed and 'Damaged vehicle retrieved. Repair the engine before driving.' or 'Vehicle retrieved from parking.'
    else
        msg = 'Vehicle called to parking.'
    end
    U.Notify(src, msg, 'success')
    return true, result, {
        wasStored = wasStored,
        destroyed = destroyed,
        repaired = repair,
        fee = insuranceFee,
        account = insuranceAccount
    }
end

RegisterNetEvent('cm-vehicles:server:spawnFromParking', function(vehicleId, lotId, spawn, options)
    local src = source
    local ok, err = CMVehicles.Spawn.SpawnFromParking(src, vehicleId, lotId, spawn, options)
    if not ok then U.Notify(src, tostring(err or 'Could not spawn vehicle.'), 'error') end
end)

function CMVehicles.Spawn.ReconcileSpawnRegistry()
    local byId = {}
    local okVehicles, vehicles = pcall(GetAllVehicles)
    if not okVehicles or type(vehicles) ~= 'table' then return false, 'OneSync vehicle enumeration is unavailable.' end

    for _, entity in ipairs(vehicles) do
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            local vehicleId, plate, isGarage, houseId, slotIndex
            pcall(function()
                local state = Entity(entity).state
                vehicleId = tonumber(state.cmVehicleId)
                plate = U.NormalizePlate(state.cmPlate)
                isGarage = state.cmHouseGarageDisplay == true
                houseId = tonumber(state.cmHouseId)
                slotIndex = tonumber(state.cmHouseSlot)
            end)
            if vehicleId then
                byId[vehicleId] = byId[vehicleId] or {}
                byId[vehicleId][#byId[vehicleId] + 1] = {
                    entity = entity, plate = plate, isGarage = isGarage,
                    houseId = houseId, slotIndex = slotIndex,
                }
            end
        end
    end

    local rebuilt, deleted, deleteFailures = 0, 0, 0
    for vehicleId, list in pairs(byId) do
        local row = MySQL.single.await('SELECT id, plate, is_stored, garage FROM cm_owned_vehicles WHERE id = ? LIMIT 1', { vehicleId })
        local expectedHouse = row and tostring(row.garage or ''):match('^house:(%d+)$')
        expectedHouse = tonumber(expectedHouse)
        local keep
        for _, candidate in ipairs(list) do
            local valid = row ~= nil
            if valid and expectedHouse then
                valid = (row.is_stored == true or row.is_stored == 1)
                    and candidate.isGarage == true and candidate.houseId == expectedHouse
            elseif valid and (row.is_stored == true or row.is_stored == 1) then
                -- Public/impound stored vehicles must not have a live world
                -- entity. Delete it rather than rebuilding a duplicate registry.
                valid = false
            elseif valid then
                valid = candidate.isGarage ~= true
            end
            if valid and not keep then
                keep = candidate
            else
                if deleteEntityConfirmed(candidate.entity, 3000) then
                    deleted = deleted + 1
                else
                    deleteFailures = deleteFailures + 1
                    print(('[cm-vehicles] ^1startup reconciliation could not delete duplicate entity %s for vehicle %s^7')
                        :format(tostring(candidate.entity), tostring(vehicleId)))
                end
            end
        end

        if keep and DoesEntityExist(keep.entity) then
            local okNet, netId = pcall(NetworkGetNetworkIdFromEntity, keep.entity)
            local active = {
                entity = keep.entity,
                netId = okNet and tonumber(netId) or 0,
                source = 0,
                vehicleId = vehicleId,
                plate = U.NormalizePlate(row.plate or keep.plate),
                context = keep.isGarage and 'house_garage' or 'world',
                houseId = keep.isGarage and keep.houseId or nil,
                slotIndex = keep.isGarage and keep.slotIndex or nil,
                updatedAt = os.time(),
            }
            registrySet(row, active)
            rebuilt = rebuilt + 1
        else
            registryRemove(vehicleId)
        end
    end

    -- Drop stale in-memory records whose entity disappeared.
    local stale = {}
    for vehicleId, active in pairs(CMVehicles.Server.SpawnedById) do
        if activeEntity(active) == 0 then stale[#stale + 1] = vehicleId end
    end
    for _, vehicleId in ipairs(stale) do registryRemove(vehicleId) end
    if deleteFailures > 0 then
        return false, ('%s duplicate vehicle entities could not be deleted.'):format(deleteFailures), {
            rebuilt = rebuilt, deleted = deleted, deleteFailures = deleteFailures,
        }
    end
    return true, { rebuilt = rebuilt, deleted = deleted, deleteFailures = 0 }
end

AddEventHandler('playerDropped', function()
    local src = source
    for token, pending in pairs(PendingGarageCreates) do
        if tonumber(pending.source) == tonumber(src) then
            finishGarageCreate(token, { ok = false, error = 'The garage viewer disconnected.' })
        end
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1500)
        local ok, result, details = pcall(CMVehicles.Spawn.ReconcileSpawnRegistry)
        if not ok or result ~= true then
            print(('[cm-vehicles] ^3startup registry reconciliation unavailable: %s^7')
                :format(tostring(details or result)))
        elseif Config.Debug then
            print(('[cm-vehicles] registry reconciled: %s'):format(U.Encode(details or {})))
        end
    end)
end)

exports('SpawnVehicleFromParking', CMVehicles.Spawn.SpawnFromParking)
exports('CreateGarageVehicle', CMVehicles.Spawn.CreateGarageVehicle)
exports('CreatePersistentWorldVehicle', CMVehicles.Spawn.CreatePersistentWorldVehicle)
exports('RecoverPersistentWorldVehicle', CMVehicles.Spawn.RecoverPersistentWorldVehicle)
exports('GetSpawnedVehicleInfo', CMVehicles.Spawn.GetSpawnedVehicleInfo)
exports('ConfigureHouseGarageVehicle', CMVehicles.Spawn.ConfigureHouseGarageVehicle)
exports('GetSpawnedVehicleCondition', CMVehicles.Spawn.GetSpawnedVehicleCondition)
exports('IsPlayerDrivingSpawnedVehicle', CMVehicles.Spawn.IsPlayerDrivingSpawnedVehicle)
exports('PromoteHouseGarageVehicle', CMVehicles.Spawn.PromoteHouseGarageVehicle)
exports('RecallWorldVehicle', CMVehicles.Spawn.RecallWorldVehicle)
exports('CreateVehicleForPlayer', CMVehicles.Spawn.CreateForPlayer)
exports('ReturnHouseGarageVehicle', CMVehicles.Spawn.ReturnHouseGarageVehicle)
exports('ReconcileSpawnRegistry', CMVehicles.Spawn.ReconcileSpawnRegistry)
exports('SetSpawnContext', CMVehicles.Spawn.SetSpawnContext)
exports('CleanupHouseGarageVehicles', CMVehicles.Spawn.CleanupHouseGarageVehicles)
exports('DeleteSpawnedVehicle', CMVehicles.Spawn.DeleteVehicle)
exports('RemoveDuplicateVehicleEntities', CMVehicles.Spawn.RemoveDuplicateEntities)
