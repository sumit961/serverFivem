local Config = CMVehicles.Config
local U = CMVehicles.Utils
CMVehicles.Server = CMVehicles.Server or {}
CMVehicles.Server.Spawned = CMVehicles.Server.Spawned or {}

local function ensureColumn(tableName, columnName, definition)
    local ok, exists = pcall(function()
        return MySQL.scalar.await(('SHOW COLUMNS FROM `%s` LIKE ?'):format(tableName), { columnName })
    end)
    if ok and not exists then
        pcall(function() MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition)) end)
    end
end

function CMVehicles.Server.EnsureTables()
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
        CREATE TABLE IF NOT EXISTS inventory_items (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            owner_type VARCHAR(50) NOT NULL DEFAULT 'character',
            owner_id VARCHAR(100) NOT NULL,
            slot VARCHAR(50) NOT NULL,
            item_name VARCHAR(100) NOT NULL,
            quantity INT NOT NULL DEFAULT 1,
            metadata LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY unique_owner_slot (owner_type, owner_id, slot),
            INDEX idx_owner (owner_type, owner_id),
            INDEX idx_item_name (item_name)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_vehicle_audit (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            character_id VARCHAR(100) NULL,
            plate VARCHAR(16) NULL,
            action VARCHAR(64) NOT NULL,
            data LONGTEXT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_character_id (character_id),
            INDEX idx_plate (plate),
            INDEX idx_action (action)
        )
    ]])
end

function CMVehicles.Server.Audit(charId, plate, action, data)
    pcall(function()
        MySQL.insert.await('INSERT INTO cm_vehicle_audit (character_id, plate, action, data) VALUES (?, ?, ?, ?)', {
            tostring(charId or ''), U.NormalizePlate(plate), action, U.Encode(data or {})
        })
    end)
end

function CMVehicles.Server.GetCharacterId(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local ok, stateId = pcall(function()
        local st = Player(src).state
        return st.charId or st.characterId or st.character_id or st.citizenid
    end)
    if ok and stateId then return tostring(stateId) end

    ok, stateId = pcall(function()
        if GetResourceState('cm-core') == 'started' and exports['cm-core'].GetPlayer then
            local p = exports['cm-core'].GetPlayer(src)
            if type(p) == 'table' then
                return p.CharacterId or p.charId or (p.Character and p.Character.id) or (p.character and p.character.id)
            end
        end
    end)
    if ok and stateId then return tostring(stateId) end
    return nil
end

function CMVehicles.Server.GetVehicleByPlate(plate)
    plate = U.NormalizePlate(plate)
    if plate == '' then return nil end
    local row = MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { plate })
    if row then
        row.plate = U.NormalizePlate(row.plate)
        row.trunk_level = tonumber(row.trunk_level) or 0
        row.is_locked = U.Truthy(row.is_locked)
        row.is_stored = U.Truthy(row.is_stored)
        row.metadata = U.Decode(row.metadata)
    end
    return row
end

function CMVehicles.Server.GetVehicleById(id)
    local row = MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE id = ? LIMIT 1', { tonumber(id) })
    if row then
        row.plate = U.NormalizePlate(row.plate)
        row.trunk_level = tonumber(row.trunk_level) or 0
        row.is_locked = U.Truthy(row.is_locked)
        row.is_stored = U.Truthy(row.is_stored)
        row.metadata = U.Decode(row.metadata)
    end
    return row
end

function CMVehicles.Server.ResolvePlate(plate, netId)
    plate = U.NormalizePlate(plate)
    if plate ~= '' and CMVehicles.Server.GetVehicleByPlate(plate) then return plate end
    netId = tonumber(netId)
    if netId then
        for p, data in pairs(CMVehicles.Server.Spawned) do
            if data and tonumber(data.netId) == netId then return U.NormalizePlate(p) end
        end
        local ok, statePlate = pcall(function()
            local ent = NetworkGetEntityFromNetworkId(netId)
            if ent and ent ~= 0 then return Entity(ent).state.cmPlate end
        end)
        statePlate = ok and U.NormalizePlate(statePlate) or ''
        if statePlate ~= '' and CMVehicles.Server.GetVehicleByPlate(statePlate) then return statePlate end
    end
    return plate
end

function CMVehicles.Server.IsOwner(src, plate)
    local charId = CMVehicles.Server.GetCharacterId(src)
    if not charId then return false end
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    return row and tostring(row.owner_character_id) == tostring(charId) or false
end

function CMVehicles.Server.HasTempKey(src, plate)
    local ok, result = U.CallExport('cm-vehiclekeys', 'HasTempKey', src, U.NormalizePlate(plate))
    return ok and result == true
end

function CMVehicles.Server.HasAccess(src, plate)
    return CMVehicles.Server.IsOwner(src, plate) or CMVehicles.Server.HasTempKey(src, plate)
end

function CMVehicles.Server.ValidateNearVehicle(src, netId, maxDistance)
    netId = tonumber(netId)
    if not netId then return true end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return true end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end
    local dist = #(GetEntityCoords(ped) - GetEntityCoords(veh))
    return dist <= (tonumber(maxDistance) or 5.0), dist
end

function CMVehicles.Server.GetSpawnedNetId(plate)
    plate = U.NormalizePlate(plate)
    local data = CMVehicles.Server.Spawned[plate]
    return data and data.netId or nil
end

function CMVehicles.Server.VehicleInfoFor(src, plate)
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row then return nil end
    local charId = CMVehicles.Server.GetCharacterId(src)
    local owner = charId and tostring(row.owner_character_id) == tostring(charId) or false
    local key = CMVehicles.Server.HasTempKey(src, row.plate)
    return {
        id = row.id,
        model = row.model,
        label = row.label,
        plate = row.plate,
        ownerCharacterId = tostring(row.owner_character_id),
        trunkLevel = row.trunk_level,
        trunkSlots = CMVehicles.Trunk and CMVehicles.Trunk.SlotCount(row.trunk_level) or 0,
        locked = row.is_locked,
        access = owner or key,
        owner = owner,
        tempKey = key,
        netId = CMVehicles.Server.GetSpawnedNetId(row.plate),
        fuel = tonumber(row.fuel) or 100,
        engineHealth = tonumber(row.engine_health) or 1000,
        bodyHealth = tonumber(row.body_health) or 1000,
        tankHealth = tonumber(row.tank_health) or 1000,
        dirtLevel = tonumber(row.dirt_level) or 0,
        metadata = row.metadata or {}
    }
end

function CMVehicles.Server.GeneratePlate()
    local prefix = (Config.Plate and Config.Plate.prefix) or 'CM'
    local digits = tonumber(Config.Plate and Config.Plate.length) or 6
    for _ = 1, 50 do
        local n = math.random(0, (10 ^ digits) - 1)
        local plate = (prefix .. string.format('%0' .. digits .. 'd', n)):upper()
        local exists = MySQL.scalar.await('SELECT plate FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { plate })
        if not exists then return plate end
    end
    return (prefix .. tostring(os.time() % 1000000)):upper()
end

function CMVehicles.Server.CreateOwnedVehicle(src, model, label, trunkLevel, metadata)
    local charId = CMVehicles.Server.GetCharacterId(src)
    if not charId then return false, 'Character is not loaded.' end
    model = tostring(model or ''):lower()
    if model == '' then return false, 'Invalid model.' end
    label = tostring(label or model)
    trunkLevel = tonumber(trunkLevel) or Config.DefaultTrunkLevel or 1
    if trunkLevel < 0 then trunkLevel = 0 end
    local plate = CMVehicles.Server.GeneratePlate()

    local id = MySQL.insert.await([[INSERT INTO cm_owned_vehicles
        (owner_character_id, model, label, plate, trunk_level, metadata)
        VALUES (?, ?, ?, ?, ?, ?)]], { tostring(charId), model, label, plate, trunkLevel, U.Encode(metadata or {}) })

    CMVehicles.Server.Audit(charId, plate, 'vehicle_created', { model = model, label = label, trunkLevel = trunkLevel })
    return true, { id = id, owner_character_id = tostring(charId), model = model, label = label, plate = plate, trunk_level = trunkLevel, is_locked = true, fuel = 100, metadata = metadata or {} }
end

RegisterNetEvent('cm-vehicles:server:registerNetVehicle', function(plate, netId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row or not CMVehicles.Server.HasAccess(src, plate) then return end
    CMVehicles.Spawn.RegisterEntity(src, row, netId)
end)

RegisterNetEvent('cm-vehicles:server:requestInfo', function(plate, netId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    local info = CMVehicles.Server.VehicleInfoFor(src, plate)
    if not info then return U.Notify(src, 'Vehicle not found.', 'error') end
    if netId then info.netId = tonumber(netId) end
    TriggerClientEvent('cm-vehicles:client:openMenu', src, info)
end)

RegisterNetEvent('cm-vehicles:server:saveState', function(vehicleId, state)
    local src = source
    state = type(state) == 'table' and state or {}
    local row = CMVehicles.Server.GetVehicleById(vehicleId)
    if not row or not CMVehicles.Server.HasAccess(src, row.plate) then return end
    local metadata = type(row.metadata) == 'table' and row.metadata or {}
    if type(state.metadata) == 'table' then for k,v in pairs(state.metadata) do metadata[k] = v end end
    if state.mileage then metadata.mileage = (tonumber(metadata.mileage) or 0.0) + (tonumber(state.mileage) or 0.0) end
    if state.neons then metadata.neons = state.neons end
    MySQL.update.await([[UPDATE cm_owned_vehicles SET
        fuel = ?, engine_health = ?, body_health = ?, tank_health = ?, dirt_level = ?, last_position = ?, metadata = ?
        WHERE id = ?]], {
        math.floor(tonumber(state.fuel) or row.fuel or 100),
        U.ClampHealth(state.engineHealth or row.engine_health),
        U.ClampHealth(state.bodyHealth or row.body_health),
        U.ClampHealth(state.tankHealth or row.tank_health or 1000),
        tonumber(state.dirtLevel or row.dirt_level) or 0,
        U.Encode(state.position or U.Decode(row.last_position)),
        U.Encode(metadata),
        row.id
    })
end)

RegisterNetEvent('cm-vehicles:server:pingTracker', function(plate)
    local src = source
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row or not CMVehicles.Server.IsOwner(src, row.plate) then return end
    local metadata = row.metadata or {}
    if metadata.has_tracker ~= true then return U.Notify(src, 'This vehicle has no GPS tracker.', 'error') end
    local active = CMVehicles.Server.Spawned[row.plate]
    if active and active.netId then
        TriggerClientEvent('cm-vehicles:client:trackerPing', src, active.netId, row.label)
    else
        U.Notify(src, 'Tracker signal is offline.', 'error')
    end
end)

RegisterNetEvent('cm-vehicles:server:requestMyVehicles', function()
    local src = source
    local charId = CMVehicles.Server.GetCharacterId(src)
    if not charId then return end
    local rows = MySQL.query.await('SELECT id, model, label, plate, trunk_level, is_locked, is_stored FROM cm_owned_vehicles WHERE owner_character_id = ? ORDER BY id DESC', { charId }) or {}
    TriggerClientEvent('cm-vehicles:client:showMyVehicles', src, rows)
end)

RegisterCommand('myvehicles', function(src)
    if src <= 0 then return end
    local charId = CMVehicles.Server.GetCharacterId(src)
    if not charId then return U.Notify(src, 'Character is not loaded.', 'error') end
    local rows = MySQL.query.await('SELECT id, model, label, plate, trunk_level, is_locked, is_stored FROM cm_owned_vehicles WHERE owner_character_id = ? ORDER BY id DESC', { charId }) or {}
    TriggerClientEvent('cm-vehicles:client:showMyVehicles', src, rows)
end, false)

RegisterCommand('vehgive', function(src, args)
    if src <= 0 or not (Config.Commands and Config.Commands.adminSpawnOwned) then return end
    local model = tostring(args[1] or 'sultan'):lower()
    local trunkLevel = tonumber(args[2]) or 3
    local label = args[3] or model
    local ok, result = CMVehicles.Server.CreateOwnedVehicle(src, model, label, trunkLevel, { source = 'vehgive' })
    if not ok then return U.Notify(src, tostring(result), 'error') end
    CMVehicles.Spawn.CreateForPlayer(src, result, { warp = true, engineOn = false })
    U.Notify(src, ('Created %s.'):format(result.label), 'success')
end, false)

AddEventHandler('playerDropped', function()
    local src = source
    if Config.Rules.DeletePlayerVehiclesOnLogout and CMVehicles.Spawn then CMVehicles.Spawn.DeletePlayerVehicles(src) end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CMVehicles.Server.EnsureTables()
    print('[CM-VEHICLES] Started v2.0 OneSync modular. Engine key: Left Ctrl.')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not Config.Rules.DeleteSpawnedVehiclesOnRestart then return end
    for _, data in pairs(CMVehicles.Server.Spawned) do
        if data.entity and DoesEntityExist(data.entity) then DeleteEntity(data.entity) end
    end
end)

exports('CreateOwnedVehicle', CMVehicles.Server.CreateOwnedVehicle)
exports('GetVehicleByPlate', CMVehicles.Server.GetVehicleByPlate)
exports('HasVehicleAccess', CMVehicles.Server.HasAccess)
exports('PlayerOwnsVehicle', CMVehicles.Server.IsOwner)
exports('GetCharacterId', CMVehicles.Server.GetCharacterId)
