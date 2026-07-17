local U = CMVehicles.Utils
local Config = CMVehicles.Config

CMVehicles.Location = CMVehicles.Location or {}
local L = CMVehicles.Location

L.States = {
    OUTSIDE = 'OUTSIDE',
    HOUSE_GARAGE = 'HOUSE_GARAGE',
    PUBLIC_GARAGE = 'PUBLIC_GARAGE',
    JOB_GARAGE = 'JOB_GARAGE',
    IMPOUND = 'IMPOUND',
    POLICE_SEIZED = 'POLICE_SEIZED',
    DESTROYED = 'DESTROYED',
    PENDING_STORE = 'PENDING_STORE',
    PENDING_SPAWN = 'PENDING_SPAWN',
    PENDING_MOVE = 'PENDING_MOVE',
    PENDING_DELETE = 'PENDING_DELETE',
    STORED = 'STORED',
}

local valid = {}
for _, state in pairs(L.States) do valid[state] = true end

local function ensureColumn(tableName, columnName, definition)
    local ok, exists = pcall(function()
        return MySQL.scalar.await(('SHOW COLUMNS FROM `%s` LIKE ?'):format(tableName), { columnName })
    end)
    if ok and not exists then
        pcall(function()
            MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition))
        end)
    end
end

local function bool(v) return v == true or tonumber(v) == 1 end

function L.Infer(row)
    if type(row) ~= 'table' then return nil end
    local garage = tostring(row.garage or '')
    local stored = bool(row.is_stored)
    local engine = tonumber(row.engine_health)
    if engine and engine <= 0.0 and tostring(row.location_state or '') == L.States.DESTROYED then
        return L.States.DESTROYED, nil, nil
    end
    if stored then
        local houseId = garage:match('^house:(%d+)$')
        if houseId then return L.States.HOUSE_GARAGE, tostring(houseId), tonumber(row.parking_id) end
        if garage:match('^impound') then return L.States.IMPOUND, garage, tonumber(row.parking_id) end
        if garage:match('^police') or garage:match('^seized') then return L.States.POLICE_SEIZED, garage, tonumber(row.parking_id) end
        if garage:match('^job:') then return L.States.JOB_GARAGE, garage, tonumber(row.parking_id) end
        if garage ~= '' or row.parking_id ~= nil then return L.States.PUBLIC_GARAGE, garage ~= '' and garage or tostring(row.parking_id), tonumber(row.parking_id) end
        return L.States.STORED, nil, tonumber(row.parking_id)
    end
    return L.States.OUTSIDE, nil, nil
end

function L.NormalizeState(state)
    state = tostring(state or ''):upper()
    return valid[state] and state or nil
end

local function legacyFor(state, ref, slot)
    state = L.NormalizeState(state)
    ref = ref ~= nil and tostring(ref) or nil
    slot = tonumber(slot)
    if state == L.States.HOUSE_GARAGE then
        local houseId = tonumber(ref and ref:match('(%d+)'))
        return 1, houseId and ('house:%d'):format(houseId) or ref, slot
    elseif state == L.States.PUBLIC_GARAGE or state == L.States.JOB_GARAGE
        or state == L.States.IMPOUND or state == L.States.POLICE_SEIZED or state == L.States.STORED then
        return 1, ref, slot
    elseif state == L.States.PENDING_STORE then
        return 0, nil, slot
    elseif state == L.States.PENDING_SPAWN or state == L.States.PENDING_MOVE or state == L.States.PENDING_DELETE then
        return nil, nil, slot
    end
    return 0, nil, nil
end

local function invokingAllowed()
    local invoker = GetInvokingResource()
    if not invoker or invoker == GetCurrentResourceName() then return true end
    local allowed = Config.Location and Config.Location.authorizedResources or {}
    return allowed[invoker] == true
end

function L.Get(vehicleIdOrPlate)
    local row
    local id = tonumber(vehicleIdOrPlate)
    if id then
        row = MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE id = ? LIMIT 1', { id })
    else
        row = MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { U.NormalizePlate(vehicleIdOrPlate) })
    end
    if not row then return nil end
    local state = L.NormalizeState(row.location_state)
    local ref = row.location_ref
    local slot = tonumber(row.location_slot)
    if not state then state, ref, slot = L.Infer(row) end
    return {
        vehicleId = tonumber(row.id), plate = U.NormalizePlate(row.plate), state = state,
        ref = ref, slot = slot, isStored = bool(row.is_stored), garage = row.garage,
        parkingId = row.parking_id, updatedAt = row.location_updated_at,
    }
end

function L.ReconcileVehicle(vehicleId)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'invalid_vehicle_id' end
    local row = MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE id = ? LIMIT 1', { vehicleId })
    if not row then return false, 'vehicle_not_found' end
    local state, ref, slot = L.Infer(row)
    local changed = MySQL.update.await([[
        UPDATE cm_owned_vehicles
        SET location_state = ?, location_ref = ?, location_slot = ?, location_updated_at = NOW()
        WHERE id = ? AND (
            COALESCE(location_state, '') <> COALESCE(?, '') OR
            COALESCE(location_ref, '') <> COALESCE(?, '') OR
            COALESCE(location_slot, -1) <> COALESCE(?, -1)
        )
    ]], { state, ref, slot, vehicleId, state, ref, slot })
    return true, { state = state, ref = ref, slot = slot, changed = tonumber(changed) or 0 }
end

function L.Transition(vehicleId, state, data)
    if not invokingAllowed() then return false, 'resource_not_authorized' end
    vehicleId = tonumber(vehicleId)
    state = L.NormalizeState(state)
    data = type(data) == 'table' and data or {}
    if not vehicleId or not state then return false, 'invalid_transition' end

    local ref = data.ref ~= nil and tostring(data.ref) or nil
    local slot = tonumber(data.slot)
    local stored, garage, parkingId = legacyFor(state, ref, slot)
    local sets = { 'location_state = ?', 'location_ref = ?', 'location_slot = ?', 'location_updated_at = NOW()' }
    local values = { state, ref, slot }
    if stored ~= nil then
        sets[#sets + 1] = 'is_stored = ?'; values[#values + 1] = stored
        sets[#sets + 1] = 'garage = ?'; values[#values + 1] = garage
        sets[#sets + 1] = 'parking_id = ?'; values[#values + 1] = parkingId
        if stored == 1 then
            sets[#sets + 1] = 'parked_at = NOW()'
        else
            sets[#sets + 1] = 'parked_at = NULL'
        end
    end
    values[#values + 1] = vehicleId
    local affected = MySQL.update.await(('UPDATE cm_owned_vehicles SET %s WHERE id = ?'):format(table.concat(sets, ', ')), values)
    if not affected or tonumber(affected) <= 0 then return false, 'vehicle_not_found' end

    pcall(function()
        MySQL.insert.await([[
            INSERT INTO cm_vehicle_location_history
                (vehicle_id, state, location_ref, location_slot, reason, actor_character_id, data)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], {
            vehicleId, state, ref, slot, tostring(data.reason or 'transition'),
            data.actorCharacterId and tostring(data.actorCharacterId) or nil,
            U.Encode(data),
        })
    end)
    return true, L.Get(vehicleId)
end

function L.ReconcileAll()
    local rows = MySQL.query.await('SELECT id FROM cm_owned_vehicles') or {}
    local changed, failed = 0, 0
    for _, row in ipairs(rows) do
        local ok, result = pcall(L.ReconcileVehicle, tonumber(row.id))
        if ok and result == true then changed = changed + 1 else failed = failed + 1 end
        if changed % 100 == 0 then Wait(0) end
    end
    return true, { scanned = #rows, reconciled = changed, failed = failed }
end

local function decodedPosition(value)
    if type(value) == 'table' then return value end
    local decoded = U.Decode(value)
    return type(decoded) == 'table' and decoded or {}
end

local function xyz(value)
    value = type(value) == 'table' and value or {}
    local x, y, z = tonumber(value.x or value[1]), tonumber(value.y or value[2]), tonumber(value.z or value[3])
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z }
end

local function houseLocation(houseId)
    houseId = tonumber(houseId)
    if not houseId then return nil end
    local ok, row = pcall(function()
        return MySQL.single.await('SELECT label, door_coords, garage_coords FROM cm_houses WHERE id = ? LIMIT 1', { houseId })
    end)
    if not ok or not row then return nil end
    return xyz(U.Decode(row.garage_coords)) or xyz(U.Decode(row.door_coords)), row.label
end

function L.GetTrackableLocation(vehicleId)
    if not invokingAllowed() then return false, 'resource_not_authorized' end
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'invalid_vehicle_id' end

    local row = MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE id = ? LIMIT 1', { vehicleId })
    if not row then return false, 'Vehicle not found.' end
    local location = L.Get(vehicleId) or {}

    if CMVehicles.Spawn and CMVehicles.Spawn.GetSpawnedVehicleInfo then
        local okInfo, info = CMVehicles.Spawn.GetSpawnedVehicleInfo(vehicleId)
        if okInfo == true and type(info) == 'table' and tonumber(info.entity) and DoesEntityExist(tonumber(info.entity)) then
            local context = tostring(info.context or 'world')
            if context ~= 'house_garage' then
                local coords = GetEntityCoords(tonumber(info.entity))
                return true, {
                    vehicleId = vehicleId,
                    plate = U.NormalizePlate(row.plate),
                    state = location.state or L.States.OUTSIDE,
                    x = coords.x, y = coords.y, z = coords.z,
                    live = true,
                    label = tostring(row.model or row.plate or 'Family vehicle'),
                    message = 'Live vehicle location marked. The marker expires in five minutes.',
                }
            end
        end
    end

    if tostring(location.state or '') == L.States.HOUSE_GARAGE then
        local coords, houseLabel = houseLocation(tonumber(location.ref) or tonumber(tostring(location.garage or ''):match('house:(%d+)')))
        if coords then
            return true, {
                vehicleId = vehicleId,
                plate = U.NormalizePlate(row.plate),
                state = L.States.HOUSE_GARAGE,
                x = coords.x, y = coords.y, z = coords.z,
                live = false,
                label = tostring(row.model or row.plate or 'Family vehicle'),
                message = ('Vehicle is stored at %s.'):format(tostring(houseLabel or 'the family house garage')),
            }
        end
    end

    local last = xyz(decodedPosition(row.last_position))
    if last then
        return true, {
            vehicleId = vehicleId,
            plate = U.NormalizePlate(row.plate),
            state = location.state or L.States.OUTSIDE,
            x = last.x, y = last.y, z = last.z,
            live = false,
            label = tostring(row.model or row.plate or 'Family vehicle'),
            message = 'Last known vehicle location marked. It may have moved since the last saved position.',
            updatedAt = location.updatedAt,
        }
    end

    return false, 'This vehicle has no saved or live location.'
end

local function ensureTables()
    ensureColumn('cm_owned_vehicles', 'location_state', "VARCHAR(32) NULL")
    ensureColumn('cm_owned_vehicles', 'location_ref', "VARCHAR(96) NULL")
    ensureColumn('cm_owned_vehicles', 'location_slot', "INT NULL")
    ensureColumn('cm_owned_vehicles', 'location_updated_at', "TIMESTAMP NULL")
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_vehicle_location_history (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            vehicle_id BIGINT NOT NULL,
            state VARCHAR(32) NOT NULL,
            location_ref VARCHAR(96) NULL,
            location_slot INT NULL,
            reason VARCHAR(64) NOT NULL,
            actor_character_id VARCHAR(100) NULL,
            data LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_cm_vehicle_location_vehicle (vehicle_id, created_at),
            INDEX idx_cm_vehicle_location_state (state)
        )
    ]])
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(250)
        ensureTables()
        L.ReconcileAll()
    end)
end)

exports('GetVehicleLocation', L.Get)
exports('GetTrackableVehicleLocation', L.GetTrackableLocation)
exports('TransitionVehicleLocation', L.Transition)
exports('ReconcileVehicleLocation', L.ReconcileVehicle)
exports('ReconcileAllVehicleLocations', L.ReconcileAll)
exports('GetVehicleLocationStates', function() return L.States end)
