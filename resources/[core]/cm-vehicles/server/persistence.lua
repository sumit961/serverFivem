local U = CMVehicles.Utils
local Config = CMVehicles.Config
CMVehicles.Persistence = CMVehicles.Persistence or {}
local P = CMVehicles.Persistence

P.Cache = P.Cache or {}
P.Pending = P.Pending or {}

local function decode(value)
    if type(value) == 'table' then return value end
    return U.Decode(value)
end

local function encode(value) return U.Encode(type(value) == 'table' and value or {}) end
local function close(a, b, tolerance) return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= (tonumber(tolerance) or 0) end

local function posChanged(oldValue, newValue)
    oldValue, newValue = decode(oldValue), type(newValue) == 'table' and newValue or {}
    local ox, oy, oz, ow = tonumber(oldValue.x), tonumber(oldValue.y), tonumber(oldValue.z), tonumber(oldValue.w or oldValue.h)
    local nx, ny, nz, nw = tonumber(newValue.x), tonumber(newValue.y), tonumber(newValue.z), tonumber(newValue.w or newValue.h)
    if not nx or not ny or not nz then return false end
    if not ox or not oy or not oz then return true end
    local dist = math.sqrt((nx-ox)^2 + (ny-oy)^2 + (nz-oz)^2)
    local heading = math.abs((nw or 0) - (ow or 0))
    return dist >= (tonumber(Config.Persistence and Config.Persistence.positionThresholdMeters) or 1.5)
        or heading >= (tonumber(Config.Persistence and Config.Persistence.headingThresholdDegrees) or 4.0)
end

local function normalizePayload(row, data)
    data = type(data) == 'table' and data or {}
    return {
        fuel = math.max(0, math.min(100, tonumber(data.fuel) or tonumber(row.fuel) or 100)),
        engine = U.NormalizeHealth(data.engine or data.engineHealth or row.engine_health, 1000.0),
        body = U.NormalizeHealth(data.body or data.bodyHealth or row.body_health, 1000.0),
        tank = U.NormalizeHealth(data.tank or data.tankHealth or row.tank_health, 1000.0),
        dirt = math.max(0, math.min(15, tonumber(data.dirt or data.dirtLevel) or tonumber(row.dirt_level) or 0)),
        condition = U.SanitizeConditionState(data.conditionState or decode(row.condition_state)),
        position = data.position,
        metadata = type(data.metadata) == 'table' and data.metadata or decode(row.metadata),
        lock = data.locked,
        reason = tostring(data.reason or 'dirty_state'),
    }
end

function P.WriteState(rowOrId, data, opts)
    opts = type(opts) == 'table' and opts or {}
    local row = type(rowOrId) == 'table' and rowOrId or CMVehicles.Server.GetVehicleById(rowOrId)
    if not row then return false, 'vehicle_not_found' end
    local vehicleId = tonumber(row.id)
    local payload = normalizePayload(row, data)
    local sets, values, fields = {}, {}, {}

    local function set(field, column, value)
        sets[#sets + 1] = column .. ' = ?'; values[#values + 1] = value; fields[#fields + 1] = field
    end

    local fuelTolerance = tonumber(Config.Persistence and Config.Persistence.fuelThreshold) or 0.5
    local healthTolerance = tonumber(Config.Persistence and Config.Persistence.healthThreshold) or 1.0
    local dirtTolerance = tonumber(Config.Persistence and Config.Persistence.dirtThreshold) or 0.1

    if opts.force or not close(row.fuel, payload.fuel, fuelTolerance) then set('fuel', 'fuel', math.floor(payload.fuel + 0.5)) end
    if opts.force or not close(row.engine_health, payload.engine, healthTolerance) then set('engine', 'engine_health', payload.engine) end
    if opts.force or not close(row.body_health, payload.body, healthTolerance) then set('body', 'body_health', payload.body) end
    if opts.force or not close(row.tank_health, payload.tank, healthTolerance) then set('tank', 'tank_health', payload.tank) end
    if opts.force or not close(row.dirt_level, payload.dirt, dirtTolerance) then set('dirt', 'dirt_level', payload.dirt) end

    local oldCondition = encode(decode(row.condition_state))
    local newCondition = encode(payload.condition)
    if opts.force or oldCondition ~= newCondition then set('condition', 'condition_state', newCondition) end

    if payload.position and (opts.force or posChanged(row.last_position, payload.position)) then
        set('position', 'last_position', encode(payload.position))
    end

    local oldMetadata = encode(decode(row.metadata))
    local newMetadata = encode(payload.metadata)
    if opts.force or oldMetadata ~= newMetadata then set('metadata', 'metadata', newMetadata) end

    if payload.lock ~= nil and (opts.force or (row.is_locked == 1 or row.is_locked == true) ~= (payload.lock == true)) then
        set('locked', 'is_locked', payload.lock == true and 1 or 0)
    end

    if #sets == 0 then
        P.Cache[vehicleId] = { at = os.time(), reason = payload.reason, fields = {} }
        return true, { changed = false, fields = {} }
    end

    values[#values + 1] = vehicleId
    local affected = MySQL.update.await(('UPDATE cm_owned_vehicles SET %s WHERE id = ?'):format(table.concat(sets, ', ')), values)
    if not affected then return false, 'database_update_failed' end
    P.Cache[vehicleId] = { at = os.time(), reason = payload.reason, fields = fields }
    if Config.Debug then
        print(('[cm-vehicles] persisted vehicle %s (%s): %s'):format(vehicleId, payload.reason, table.concat(fields, ',')))
    end
    return true, { changed = true, fields = fields }
end

local function activeEntity(vehicleId)
    local active = CMVehicles.Server.SpawnedById and CMVehicles.Server.SpawnedById[tonumber(vehicleId)]
    if not active then return nil, nil end
    local entity = tonumber(active.entity) or 0
    if entity == 0 or not DoesEntityExist(entity) then
        local netId = tonumber(active.netId) or 0
        if netId > 0 then
            local ok, resolved = pcall(NetworkGetEntityFromNetworkId, netId)
            entity = ok and tonumber(resolved) or 0
        end
    end
    if entity == 0 or not DoesEntityExist(entity) then return active, nil end
    return active, entity
end

function P.CaptureVehicle(vehicleId, reason, opts)
    vehicleId = tonumber(vehicleId)
    local row = vehicleId and CMVehicles.Server.GetVehicleById(vehicleId)
    if not row then return false, 'vehicle_not_found' end
    local active, entity = activeEntity(vehicleId)
    if not entity then return true, { changed = false, noEntity = true } end
    local state = Entity(entity).state
    if state.cmHouseGarageDisplay == true and not (opts and opts.allowGarageDisplay) then
        return true, { changed = false, garageDisplay = true }
    end
    local coords = GetEntityCoords(entity)
    local heading = GetEntityHeading(entity)
    local metadata = decode(row.metadata)
    metadata.mileage = tonumber(state.cmMileage) or tonumber(metadata.mileage) or 0
    local data = {
        fuel = tonumber(state.cmFuel) or row.fuel,
        engine = tonumber(state.cmEngineHealth) or row.engine_health,
        body = tonumber(state.cmBodyHealth) or row.body_health,
        tank = tonumber(state.cmTankHealth) or row.tank_health,
        dirt = tonumber(state.cmDirtLevel) or row.dirt_level,
        conditionState = type(state.cmConditionState) == 'table' and state.cmConditionState or decode(row.condition_state),
        position = { x = coords.x, y = coords.y, z = coords.z, w = heading },
        metadata = metadata,
        locked = state.cmLocked,
        reason = reason or 'entity_capture',
    }
    return P.WriteState(row, data, opts)
end

function P.FlushVehicle(vehicleId, reason)
    return P.CaptureVehicle(vehicleId, reason or 'explicit_flush', { force = true })
end

function P.FlushAll(reason)
    local ids = {}
    for vehicleId in pairs(CMVehicles.Server.SpawnedById or {}) do ids[#ids + 1] = tonumber(vehicleId) end
    local okCount, failCount = 0, 0
    for _, vehicleId in ipairs(ids) do
        local ok = P.CaptureVehicle(vehicleId, reason or 'flush_all', { force = true, allowGarageDisplay = true })
        if ok then okCount = okCount + 1 else failCount = failCount + 1 end
        Wait(0)
    end
    return true, { saved = okCount, failed = failCount }
end

local function occupantSource(entity, droppedSrc)
    local max = 6
    pcall(function() max = math.max(0, GetVehicleMaxNumberOfPassengers(entity)) end)
    for seat = -1, max do
        local ped = 0
        pcall(function() ped = GetPedInVehicleSeat(entity, seat) end)
        if ped and ped ~= 0 then
            local owner = 0
            pcall(function() owner = NetworkGetEntityOwner(ped) end)
            if tonumber(owner) and tonumber(owner) > 0 and tonumber(owner) ~= tonumber(droppedSrc) and GetPlayerName(owner) then
                return tonumber(owner)
            end
        end
    end
    return nil
end

function P.HandlePlayerDropped(src)
    src = tonumber(src)
    local changed = 0
    for vehicleId, active in pairs(CMVehicles.Server.SpawnedById or {}) do
        if tonumber(active.source) == src then
            pcall(P.CaptureVehicle, vehicleId, 'responsible_player_disconnect', { force = true })
            local _, entity = activeEntity(vehicleId)
            local replacement = entity and occupantSource(entity, src) or nil
            active.source = replacement or 0
            active.responsibleCharacterId = replacement and CMVehicles.Server.GetCharacterId(replacement) or nil
            active.abandonedAt = replacement and nil or os.time()
            active.updatedAt = os.time()
            changed = changed + 1
        end
    end
    return true, { transferred = changed }
end

CreateThread(function()
    while true do
        Wait(60000)
        local ttl = tonumber(Config.Persistence and Config.Persistence.abandonedDespawnSeconds) or 1800
        if ttl > 0 and CMVehicles.Spawn then
            local now = os.time()
            local remove = {}
            for vehicleId, active in pairs(CMVehicles.Server.SpawnedById or {}) do
                if active.context == 'world' and tonumber(active.source) == 0 and active.abandonedAt
                    and now - tonumber(active.abandonedAt) >= ttl then
                    local _, entity = activeEntity(vehicleId)
                    if entity then
                        local occupied = occupantSource(entity, -1) ~= nil
                        if not occupied then remove[#remove + 1] = vehicleId end
                    else
                        remove[#remove + 1] = vehicleId
                    end
                end
            end
            for _, vehicleId in ipairs(remove) do
                pcall(P.CaptureVehicle, vehicleId, 'abandoned_despawn', { force = true })
                pcall(CMVehicles.Spawn.DeleteVehicle, vehicleId)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    pcall(P.FlushAll, 'resource_stop')
end)

exports('PersistVehicleState', P.WriteState)
exports('CaptureVehicleState', P.CaptureVehicle)
exports('FlushVehicleState', P.FlushVehicle)
exports('FlushAllVehicleStates', P.FlushAll)
exports('GetVehiclePersistenceStatus', function(vehicleId) return P.Cache[tonumber(vehicleId)] end)
