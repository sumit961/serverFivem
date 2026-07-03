local Config = CMVehicles.Config
local U = CMVehicles.Utils
CMVehicles.Server = CMVehicles.Server or {}
CMVehicles.Server.Spawned = CMVehicles.Server.Spawned or {}
CMVehicles.Server.TrunkOccupants = CMVehicles.Server.TrunkOccupants or {}

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
    ensureColumn('cm_owned_vehicles', 'owner_name', 'VARCHAR(120) NULL')
    ensureColumn('cm_owned_vehicles', 'insurance_days', 'INT NOT NULL DEFAULT 0')
    ensureColumn('cm_owned_vehicles', 'state_value', 'INT NOT NULL DEFAULT 0')

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


local function numFrom(...)
    for _, v in ipairs({ ... }) do
        local n = tonumber(v)
        if n and n > 0 then return math.floor(n) end
    end
    return 0
end

local function mileagePenaltyInfo(mileage)
    mileage = tonumber(mileage) or 0.0
    if mileage < 5000.0 then return 1.00, 'No mileage penalty yet', 5000 end
    if mileage < 10000.0 then return 0.98, 'Small mileage wear: 2% power loss', 10000 end
    if mileage < 20000.0 then return 0.95, 'Moderate mileage wear: 5% power loss', 20000 end
    if mileage < 50000.0 then return 0.90, 'Heavy mileage wear: 10% power loss', 50000 end
    return 0.85, 'Very high mileage wear: 15% power loss', nil
end

function CMVehicles.Server.GetCharacterName(src, charId)
    local ok, name = pcall(function()
        if GetResourceState('cm-core') == 'started' and exports['cm-core'].GetPlayer then
            local p = exports['cm-core'].GetPlayer(src)
            if type(p) == 'table' then
                if p.name or p.Name then return p.name or p.Name end
                local c = p.Character or p.character or p.PlayerData or {}
                local first = c.firstName or c.firstname or c.first_name or c.FirstName
                local last = c.lastName or c.lastname or c.last_name or c.LastName
                if first or last then return (tostring(first or '') .. ' ' .. tostring(last or '')):gsub('^%s+', ''):gsub('%s+$', '') end
                if c.name or c.Name then return c.name or c.Name end
            end
        end
    end)
    if ok and name and tostring(name) ~= '' then return tostring(name) end
    return tostring(charId or 'Unknown')
end

function CMVehicles.Server.AddMoney(src, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local ok = pcall(function()
        if GetResourceState('cm-core') == 'started' and exports['cm-core'].GetPlayer then
            local p = exports['cm-core'].GetPlayer(src)
            if type(p) == 'table' then
                if p.Functions and p.Functions.AddMoney then
                    p.Functions.AddMoney('cash', amount, reason or 'vehicle-state-sale')
                    return true
                end
                if p.AddMoney then p.AddMoney('cash', amount, reason or 'vehicle-state-sale'); return true end
                if p.addMoney then p.addMoney('cash', amount, reason or 'vehicle-state-sale'); return true end
            end
        end
        error('no player money function')
    end)
    if ok then return true end

    local attempts = {
        { 'cm-core', 'AddMoney', src, 'cash', amount, reason or 'vehicle-state-sale' },
        { 'cm-core', 'AddMoney', src, amount, 'cash', reason or 'vehicle-state-sale' },
        { 'cm-core', 'AddCash', src, amount, reason or 'vehicle-state-sale' },
        { 'cm-core', 'GiveMoney', src, amount, reason or 'vehicle-state-sale' },
        { 'cm-core', 'AddPlayerMoney', src, 'cash', amount, reason or 'vehicle-state-sale' }
    }

    for _, a in ipairs(attempts) do
        local resource, method = a[1], a[2]
        if GetResourceState(resource) == 'started' and exports[resource] and exports[resource][method] then
            local args = {}
            for i = 3, #a do args[#args + 1] = a[i] end
            local success = pcall(function() return exports[resource][method](table.unpack(args)) end)
            if success then return true end
        end
    end

    return false
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

function CMVehicles.Server.IsDriverOfVehicle(src, netId)
    netId = tonumber(netId)
    if not netId then return false end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return GetVehiclePedIsIn(ped, false) == veh and GetPedInVehicleSeat(veh, -1) == ped
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
    local metadata = type(row.metadata) == 'table' and row.metadata or {}
    local stateValue = numFrom(row.state_value, metadata.stateValue, metadata.state_value, metadata.storePrice, metadata.store_price, metadata.purchasePrice, metadata.purchase_price, metadata.price, metadata.vehiclePrice, metadata.vehicle_price)
    local insuranceDays = numFrom(row.insurance_days, row.insurance, metadata.insuranceDays, metadata.insurance_days, metadata.insurance)
    local ownerName = row.owner_name or metadata.ownerName or metadata.owner_name or metadata.owner or CMVehicles.Server.GetCharacterName(src, row.owner_character_id)

    return {
        id = row.id,
        model = row.model,
        label = row.label,
        plate = row.plate,
        ownerCharacterId = tostring(row.owner_character_id),
        ownerName = tostring(ownerName or 'Unknown'),
        insuranceDays = insuranceDays,
        stateValue = stateValue,
        sellValue = math.floor(stateValue * 0.30),
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
        mileage = tonumber(metadata.mileage) or 0.0,
        mileageMultiplier = select(1, mileagePenaltyInfo(metadata.mileage)),
        mileagePenaltyText = select(2, mileagePenaltyInfo(metadata.mileage)),
        nextMileageService = select(3, mileagePenaltyInfo(metadata.mileage)),
        racingHarness = metadata.racingHarness == true or metadata.racing_harness == true,
        metadata = metadata
    }
end


function CMVehicles.Server.HasRacingHarness(plate)
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row then return false end
    local metadata = type(row.metadata) == 'table' and row.metadata or {}
    return metadata.racingHarness == true or metadata.racing_harness == true
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

    metadata = type(metadata) == 'table' and metadata or {}
    local stateValue = numFrom(metadata.stateValue, metadata.state_value, metadata.storePrice, metadata.store_price, metadata.purchasePrice, metadata.purchase_price, metadata.price, metadata.vehiclePrice, metadata.vehicle_price)
    local insuranceDays = numFrom(metadata.insuranceDays, metadata.insurance_days, metadata.insurance)
    local ownerName = metadata.ownerName or metadata.owner_name or CMVehicles.Server.GetCharacterName(src, charId)
    metadata.stateValue = metadata.stateValue or stateValue
    metadata.ownerName = metadata.ownerName or ownerName
    metadata.insuranceDays = metadata.insuranceDays or insuranceDays

    local id = MySQL.insert.await([[INSERT INTO cm_owned_vehicles
        (owner_character_id, owner_name, model, label, plate, trunk_level, insurance_days, state_value, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]], { tostring(charId), tostring(ownerName or ''), model, label, plate, trunkLevel, insuranceDays, stateValue, U.Encode(metadata or {}) })

    CMVehicles.Server.Audit(charId, plate, 'vehicle_created', { model = model, label = label, trunkLevel = trunkLevel, stateValue = stateValue })
    return true, { id = id, owner_character_id = tostring(charId), owner_name = tostring(ownerName or ''), model = model, label = label, plate = plate, trunk_level = trunkLevel, insurance_days = insuranceDays, state_value = stateValue, is_locked = true, fuel = 100, metadata = metadata or {} }
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


RegisterNetEvent('cm-vehicles:server:sellToState', function(plate, netId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row then return U.Notify(src, 'Vehicle not found.', 'error') end
    if not CMVehicles.Server.IsOwner(src, row.plate) then return U.Notify(src, 'Only the owner can sell this vehicle to the state.', 'error') end

    local okNear = CMVehicles.Server.ValidateNearVehicle(src, netId, 10.0)
    if not okNear then return U.Notify(src, 'Move closer to the vehicle.', 'error') end

    local metadata = type(row.metadata) == 'table' and row.metadata or {}
    local stateValue = numFrom(row.state_value, metadata.stateValue, metadata.state_value, metadata.storePrice, metadata.store_price, metadata.purchasePrice, metadata.purchase_price, metadata.price, metadata.vehiclePrice, metadata.vehicle_price)
    if stateValue <= 0 then return U.Notify(src, 'State value is missing for this vehicle.', 'error') end

    local payout = math.floor(stateValue * 0.30)
    if payout <= 0 then return U.Notify(src, 'Sell value is too low.', 'error') end

    if not CMVehicles.Server.AddMoney(src, payout, 'vehicle-state-sale') then
        return U.Notify(src, 'Money export not found. Connect cm-vehicles AddMoney to your cm-core economy.', 'error')
    end

    netId = tonumber(netId) or CMVehicles.Server.GetSpawnedNetId(row.plate)

    local occupant = CMVehicles.Server.TrunkOccupants and CMVehicles.Server.TrunkOccupants[row.plate]
    if occupant then
        TriggerClientEvent('cm-vehicles:client:exitTrunk', occupant, true)
        CMVehicles.Server.TrunkOccupants[row.plate] = nil
    end

    MySQL.query.await('DELETE FROM inventory_items WHERE owner_type = ? AND owner_id = ?', { 'vehicle_trunk', tostring(row.id) })
    MySQL.query.await('DELETE FROM cm_owned_vehicles WHERE id = ?', { row.id })
    CMVehicles.Server.Spawned[row.plate] = nil

    if netId then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then
            DeleteEntity(ent)
        end
    end

    CMVehicles.Server.Audit(CMVehicles.Server.GetCharacterId(src), row.plate, 'vehicle_sold_to_state', { stateValue = stateValue, payout = payout })
    U.Notify(src, ('Vehicle sold to state for $%s.'):format(payout), 'success')
    TriggerClientEvent('cm-vehicles:client:soldToState', src, netId, payout)
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
        math.floor(math.max(0, math.min(100, tonumber(state.fuel) or row.fuel or tonumber(Config.Fuel and Config.Fuel.defaultFuel) or 100))),
        U.ClampHealth(state.engineHealth or row.engine_health),
        U.ClampHealth(state.bodyHealth or row.body_health),
        U.ClampHealth(state.tankHealth or row.tank_health or 1000),
        tonumber(state.dirtLevel or row.dirt_level) or 0,
        U.Encode(state.position or U.Decode(row.last_position)),
        U.Encode(metadata),
        row.id
    })

    local active = CMVehicles.Server.Spawned[row.plate]
    if active and active.entity and DoesEntityExist(active.entity) then
        Entity(active.entity).state:set('cmMileage', tonumber(metadata.mileage) or 0.0, true)
        Entity(active.entity).state:set('cmRacingHarness', metadata.racingHarness == true or metadata.racing_harness == true, true)
    end
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



RegisterNetEvent('cm-vehicles:server:installRacingHarness', function(plate, netId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    local row = CMVehicles.Server.GetVehicleByPlate(plate)
    if not row then return U.Notify(src, 'Vehicle not found.', 'error') end
    if not CMVehicles.Server.HasAccess(src, row.plate) then return U.Notify(src, 'You do not have keys for this vehicle.', 'error') end

    local near = CMVehicles.Server.ValidateNearVehicle(src, netId, 8.0)
    if not near then return U.Notify(src, 'Move closer to the vehicle to install the racing harness.', 'error') end

    local metadata = type(row.metadata) == 'table' and row.metadata or {}
    if metadata.racingHarness == true or metadata.racing_harness == true then
        return U.Notify(src, 'This vehicle already has a racing harness installed.', 'info')
    end

    metadata.racingHarness = true
    metadata.racing_harness = true
    MySQL.update.await('UPDATE cm_owned_vehicles SET metadata = ? WHERE id = ?', { U.Encode(metadata), row.id })

    local finalNetId = tonumber(netId) or CMVehicles.Server.GetSpawnedNetId(row.plate)
    if finalNetId then
        local ent = NetworkGetEntityFromNetworkId(finalNetId)
        if ent and ent ~= 0 then Entity(ent).state:set('cmRacingHarness', true, true) end
    end

    CMVehicles.Server.Audit(CMVehicles.Server.GetCharacterId(src), row.plate, 'racing_harness_installed', {})
    U.Notify(src, 'Racing harness installed. Seatbelt crash ejection is disabled for this vehicle.', 'success')
end)



RegisterNetEvent('cm-vehicles:server:useRacingHarness', function()
    TriggerClientEvent('cm-vehicles:client:useRacingHarness', source)
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
exports('HasRacingHarness', CMVehicles.Server.HasRacingHarness)
