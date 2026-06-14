local Config = CMParking.Config
local requestLocks = {}

local function dprint(...)
    if Config.Debug then print('[CM-PARKING]', ...) end
end

local function normalizePlate(plate)
    return tostring(plate or ''):upper():gsub('%s+', '')
end

local function encode(v)
    local ok, out = pcall(json.encode, v or {})
    return ok and out or '{}'
end

local function decode(v)
    if type(v) == 'table' then return v end
    if not v or v == '' then return {} end
    local ok, out = pcall(json.decode, v)
    return ok and type(out) == 'table' and out or {}
end

local function truthy(value)
    if value == true then return true end
    if value == false or value == nil then return false end
    if tonumber(value) == 1 then return true end
    local s = tostring(value):lower()
    return s == 'true' or s == 'yes' or s == 'on'
end

local function notify(src, msg, typeName)
    TriggerClientEvent('cm-parking:client:notify', src, msg or '', typeName or 'info')
end

local function callExport(resource, method, ...)
    if GetResourceState(resource) ~= 'started' then return false, nil end
    local args = { ... }
    local ok, result, extra = pcall(function()
        return exports[resource][method](table.unpack(args))
    end)
    if ok then return true, result, extra end
    print(('[CM-PARKING] Export failed: %s.%s | %s'):format(resource, method, tostring(result)))
    return false, result
end

local function getLot(id)
    id = tostring(id or '')
    for _, lot in ipairs(Config.ParkingLots or {}) do
        if lot.id == id then return lot end
    end
    return nil
end

local function getCharacterId(src)
    local ok, charId = callExport('cm-vehicles', 'GetCharacterId', src)
    if ok and charId then return tostring(charId) end
    local st = Player(src).state
    return st and tostring(st.charId or st.characterId or st.character_id or st.citizenid or '') or nil
end

local function ensureColumn(tableName, columnName, definition)
    local exists = MySQL.scalar.await(('SHOW COLUMNS FROM `%s` LIKE ?'):format(tableName), { columnName })
    if not exists then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition))
    end
end

local function ensureTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_owned_vehicles (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            owner_character_id VARCHAR(100) NOT NULL,
            model VARCHAR(64) NOT NULL,
            label VARCHAR(100) NOT NULL,
            plate VARCHAR(16) NOT NULL UNIQUE,
            trunk_level INT NOT NULL DEFAULT 1,
            fuel INT NOT NULL DEFAULT 100,
            engine_health FLOAT NOT NULL DEFAULT 1000,
            body_health FLOAT NOT NULL DEFAULT 1000,
            is_locked TINYINT(1) NOT NULL DEFAULT 1,
            is_stored TINYINT(1) NOT NULL DEFAULT 0,
            garage VARCHAR(64) NULL,
            last_position LONGTEXT NULL,
            metadata LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_owner_character_id (owner_character_id),
            INDEX idx_plate (plate),
            INDEX idx_model (model)
        )
    ]])
    ensureColumn('cm_owned_vehicles', 'parking_id', 'VARCHAR(64) NULL')
    ensureColumn('cm_owned_vehicles', 'parked_at', 'TIMESTAMP NULL')
    ensureColumn('cm_owned_vehicles', 'tank_health', 'FLOAT NOT NULL DEFAULT 1000')
    ensureColumn('cm_owned_vehicles', 'dirt_level', 'FLOAT NOT NULL DEFAULT 0')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_parking_audit (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            character_id VARCHAR(100) NULL,
            vehicle_id BIGINT NULL,
            plate VARCHAR(16) NULL,
            parking_id VARCHAR(64) NULL,
            action VARCHAR(64) NOT NULL,
            data LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_character_id (character_id),
            INDEX idx_vehicle_id (vehicle_id),
            INDEX idx_plate (plate),
            INDEX idx_parking_id (parking_id)
        )
    ]])
end

local function audit(charId, vehicleId, plate, parkingId, action, data)
    pcall(function()
        MySQL.insert.await([[INSERT INTO cm_parking_audit
            (character_id, vehicle_id, plate, parking_id, action, data)
            VALUES (?, ?, ?, ?, ?, ?)]], {
            tostring(charId or ''), tonumber(vehicleId), normalizePlate(plate), tostring(parkingId or ''), action, encode(data or {})
        })
    end)
end

local function rowByPlate(plate)
    plate = normalizePlate(plate)
    if plate == '' then return nil end
    local row = MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { plate })
    if row then
        row.plate = normalizePlate(row.plate)
        row.is_locked = truthy(row.is_locked)
        row.is_stored = truthy(row.is_stored)
        row.metadata = decode(row.metadata)
    end
    return row
end

local function rowById(id)
    id = tonumber(id)
    if not id then return nil end
    local row = MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE id = ? LIMIT 1', { id })
    if row then
        row.plate = normalizePlate(row.plate)
        row.is_locked = truthy(row.is_locked)
        row.is_stored = truthy(row.is_stored)
        row.metadata = decode(row.metadata)
    end
    return row
end

local function lotLabel(id)
    local lot = getLot(id)
    return lot and lot.label or tostring(id or '')
end

local function getOwnedVehicles(src)
    local charId = getCharacterId(src)
    if not charId or charId == '' then return nil, 'Character is not loaded.' end
    local rows = MySQL.query.await([[SELECT id, owner_character_id, model, label, plate, trunk_level,
        fuel, engine_health, body_health, is_locked, is_stored, parking_id, parked_at, last_position
        FROM cm_owned_vehicles WHERE owner_character_id = ? ORDER BY id DESC]], { tostring(charId) }) or {}
    for _, row in ipairs(rows) do
        row.plate = normalizePlate(row.plate)
        row.is_locked = truthy(row.is_locked)
        row.is_stored = truthy(row.is_stored)
        row.parking_label = row.parking_id and lotLabel(row.parking_id) or nil
    end
    return rows, nil, charId
end

local function nearLot(src, lot)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true, 0 end
    local dist = #(GetEntityCoords(ped) - vector3(lot.coords.x, lot.coords.y, lot.coords.z))
    return dist <= (tonumber(lot.radius) or 25.0), dist
end

local function nearVehicle(src, netId, maxDistance)
    netId = tonumber(netId)
    if not netId then return false, nil, nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return false, nil, nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true, veh, 0 end
    local dist = #(GetEntityCoords(ped) - GetEntityCoords(veh))
    return dist <= (tonumber(maxDistance) or 20.0), veh, dist
end

local function buildUiPayload(src, lotId)
    local rows, err = getOwnedVehicles(src)
    if not rows then return nil, err end
    local lot = getLot(lotId)
    return {
        lotId = lotId,
        lotLabel = lot and lot.label or 'Parking',
        allowRetrieveFromAnyParking = Config.Rules.AllowRetrieveFromAnyParking == true,
        vehicles = rows
    }
end

RegisterNetEvent('cm-parking:server:open', function(lotId)
    local src = source
    local lot = getLot(lotId)
    if not lot then notify(src, 'Parking not found.', 'error') return end
    local okNear = nearLot(src, lot)
    if not okNear then notify(src, 'You are too far from parking.', 'error') return end
    local payload, err = buildUiPayload(src, lotId)
    if not payload then notify(src, err or 'Could not open parking.', 'error') return end
    TriggerClientEvent('cm-parking:client:open', src, payload)
end)

RegisterNetEvent('cm-parking:server:refresh', function(lotId)
    local src = source
    local payload, err = buildUiPayload(src, lotId)
    if not payload then notify(src, err or 'Could not refresh parking.', 'error') return end
    TriggerClientEvent('cm-parking:client:update', src, payload)
end)

RegisterNetEvent('cm-parking:server:parkVehicle', function(data)
    local src = source
    if requestLocks[src] then return end
    requestLocks[src] = true
    data = type(data) == 'table' and data or {}

    local function finish() requestLocks[src] = nil end

    local lot = getLot(data.lotId)
    if not lot then notify(src, 'Parking not found.', 'error') finish() return end
    local okNearLot = nearLot(src, lot)
    if not okNearLot then notify(src, 'You are too far from parking.', 'error') finish() return end

    local netId = tonumber(data.netId)
    local okVeh, veh = nearVehicle(src, netId, Config.Interaction.parkVehicleDistance or 18.0)
    if not okVeh then notify(src, 'Your vehicle is too far from parking.', 'error') finish() return end

    local plate = normalizePlate(data.plate)
    if plate == '' and veh and veh ~= 0 then
        pcall(function() plate = normalizePlate(Entity(veh).state.cmPlate) end)
    end
    local row = rowByPlate(plate)
    if not row then notify(src, 'This vehicle is not registered.', 'error') finish() return end

    local charId = getCharacterId(src)
    if not charId or tostring(row.owner_character_id) ~= tostring(charId) then
        notify(src, 'Only the owner can park this vehicle.', 'error') finish() return
    end
    if row.is_stored then notify(src, 'This vehicle is already parked.', 'error') finish() return end

    local pos = type(data.position) == 'table' and data.position or {}
    if veh and veh ~= 0 then
        local coords = GetEntityCoords(veh)
        pos = { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(veh) }
    end

    local fuel = math.floor(tonumber(data.fuel) or row.fuel or 100)
    local engineHealth = tonumber(data.engineHealth) or row.engine_health or 1000.0
    local bodyHealth = tonumber(data.bodyHealth) or row.body_health or 1000.0
    local tankHealth = tonumber(data.tankHealth) or row.tank_health or 1000.0
    local dirtLevel = tonumber(data.dirtLevel) or row.dirt_level or 0.0
    local locked = Config.Rules.LockVehicleWhenParked == true and 1 or (row.is_locked and 1 or 0)

    MySQL.update.await([[UPDATE cm_owned_vehicles SET
        is_stored = 1,
        parking_id = ?,
        garage = NULL,
        last_position = ?,
        fuel = ?,
        engine_health = ?,
        body_health = ?,
        tank_health = ?,
        dirt_level = ?,
        is_locked = ?,
        parked_at = CURRENT_TIMESTAMP
        WHERE id = ? AND owner_character_id = ?]], {
        lot.id, encode(pos), fuel, engineHealth, bodyHealth, tankHealth, dirtLevel, locked, row.id, tostring(charId)
    })

    audit(charId, row.id, row.plate, lot.id, 'park_vehicle', { fuel = fuel, engineHealth = engineHealth, bodyHealth = bodyHealth, tankHealth = tankHealth, dirtLevel = dirtLevel })
    TriggerClientEvent('cm-parking:client:deleteVehicle', src, netId)
    notify(src, ('Parked %s at %s.'):format(row.label or row.model, lot.label), 'success')

    local payload = buildUiPayload(src, lot.id)
    if payload then TriggerClientEvent('cm-parking:client:update', src, payload) end
    finish()
end)

RegisterNetEvent('cm-parking:server:retrieveVehicle', function(data)
    local src = source
    if requestLocks[src] then return end
    requestLocks[src] = true
    data = type(data) == 'table' and data or {}

    local function finish() requestLocks[src] = nil end

    local lot = getLot(data.lotId)
    if not lot then notify(src, 'Parking not found.', 'error') finish() return end
    local okNearLot = nearLot(src, lot)
    if not okNearLot then notify(src, 'You are too far from parking.', 'error') finish() return end

    local charId = getCharacterId(src)
    if not charId then notify(src, 'Character is not loaded.', 'error') finish() return end

    local row = rowById(data.vehicleId) or rowByPlate(data.plate)
    if not row then notify(src, 'Vehicle not found.', 'error') finish() return end
    if tostring(row.owner_character_id) ~= tostring(charId) then notify(src, 'You do not own this vehicle.', 'error') finish() return end

    -- v1.2: Parking can call a vehicle even if DB says it is already out.
    -- This is useful during testing and also works like a simple recall system.
    -- If it is parked, keep the normal lot check. If it is out, skip parked-location check.
    local wasStored = row.is_stored == true

    if wasStored and Config.Rules.AllowRetrieveFromAnyParking ~= true and tostring(row.parking_id or '') ~= tostring(lot.id) then
        notify(src, ('This vehicle is parked at %s.'):format(lotLabel(row.parking_id)), 'error')
        finish()
        return
    end

    local spawn = lot.spawn or lot.coords
    local unlockOnRetrieve = Config.Rules and Config.Rules.UnlockOnRetrieve == true

    local okSpawn, spawnErr, meta = false, 'cm-vehicles is not started.', nil
    if GetResourceState('cm-vehicles') == 'started' then
        okSpawn, spawnErr, meta = exports['cm-vehicles']:SpawnVehicleFromParking(src, row.id, lot.id, { x = spawn.x, y = spawn.y, z = spawn.z, w = spawn.w or 0.0 }, {
            unlockOnRetrieve = unlockOnRetrieve,
            engineOn = true,
            warp = false
        })
    end

    if not okSpawn then
        notify(src, tostring(spawnErr or 'Could not retrieve vehicle.'), 'error')
        finish()
        return
    end

    audit(charId, row.id, row.plate, lot.id, wasStored and 'retrieve_vehicle' or 'call_out_vehicle', meta or {})
    notify(src, (wasStored and ('Retrieved %s.') or ('Called %s.')):format(row.label or row.model), 'success')

    local payload = buildUiPayload(src, lot.id)
    if payload then TriggerClientEvent('cm-parking:client:update', src, payload) end
    finish()
end)

RegisterCommand('parklist', function(src)
    if src <= 0 then return end
    local rows, err = getOwnedVehicles(src)
    if not rows then notify(src, err or 'Could not load vehicles.', 'error') return end
    if #rows == 0 then notify(src, 'You do not own any vehicles.', 'error') return end
    for _, v in ipairs(rows) do
        local status = v.is_stored and ('parked at ' .. (v.parking_label or v.parking_id or 'parking')) or 'out'
        notify(src, ('#%s %s | %s'):format(v.id, v.label or v.model, status), 'info')
        Wait(350)
    end
end, false)

CreateThread(function()
    ensureTables()
    print('[CM-PARKING] Started v1.5-normaldrive')
end)
