local Config = CMVehicles.Config
local Spawned = {}

local function dprint(...)
    if Config.Debug then print('[CM-VEHICLES]', ...) end
end

local function normalizePlate(plate)
    return tostring(plate or ''):upper():gsub('%s+', '')
end

local function truthy(value)
    if value == true then return true end
    if value == false or value == nil then return false end
    if tonumber(value) == 1 then return true end
    local s = tostring(value):lower()
    return s == 'true' or s == 'yes' or s == 'on'
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

local function notify(src, msg, typeName)
    TriggerClientEvent('cm-vehicles:client:notify', src, msg or '', typeName or 'info')
end

local function callExport(resource, method, ...)
    if GetResourceState(resource) ~= 'started' then return false, nil end
    local args = { ... }
    local ok, result, extra = pcall(function()
        return exports[resource][method](table.unpack(args))
    end)
    if ok then return true, result, extra end
    print(('[CM-VEHICLES] Export failed: %s.%s | %s'):format(resource, method, tostring(result)))
    return false, result
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

local function audit(charId, plate, action, data)
    pcall(function()
        MySQL.insert.await('INSERT INTO cm_vehicle_audit (character_id, plate, action, data) VALUES (?, ?, ?, ?)', {
            tostring(charId or ''), normalizePlate(plate), action, encode(data or {})
        })
    end)
end

local function getCharacterId(src)
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

    local accountId
    pcall(function()
        local st = Player(src).state
        accountId = st.accountId or st.account_id or st.cmAccountId
    end)

    if accountId then
        local okDb, dbCharId = pcall(function()
            return MySQL.scalar.await([[
                SELECT id FROM characters
                WHERE account_id = ?
                ORDER BY last_played DESC, updated_at DESC, created_at DESC
                LIMIT 1
            ]], { tostring(accountId) })
        end)
        if okDb and dbCharId then return tostring(dbCharId) end
    end

    return nil
end

local function getVehicleByPlate(plate)
    plate = normalizePlate(plate)
    if plate == '' then return nil end
    local row = MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { plate })
    if row then
        row.plate = normalizePlate(row.plate)
        row.trunk_level = tonumber(row.trunk_level) or 0
        row.is_locked = truthy(row.is_locked)
        row.metadata = decode(row.metadata)
    end
    return row
end


local function resolvePlate(plate, netId)
    plate = normalizePlate(plate)
    if plate ~= '' and getVehicleByPlate(plate) then return plate end

    netId = tonumber(netId)
    if netId then
        for p, data in pairs(Spawned) do
            if data and tonumber(data.netId) == netId then
                return normalizePlate(p)
            end
        end

        local ok, statePlate = pcall(function()
            local ent = NetworkGetEntityFromNetworkId(netId)
            if ent and ent ~= 0 then
                return Entity(ent).state.cmPlate
            end
        end)
        statePlate = ok and normalizePlate(statePlate) or ''
        if statePlate ~= '' and getVehicleByPlate(statePlate) then return statePlate end
    end

    return plate
end

local function getSpawnedNetId(plate)
    plate = normalizePlate(plate)
    local data = Spawned[plate]
    if data and data.netId then return data.netId end
    return nil
end

local function isOwner(src, plate)
    local charId = getCharacterId(src)
    if not charId then return false end
    local row = getVehicleByPlate(plate)
    return row and tostring(row.owner_character_id) == tostring(charId) or false
end

local function hasTempKey(src, plate)
    local ok, result = callExport('cm-vehiclekeys', 'HasTempKey', src, normalizePlate(plate))
    return ok and result == true
end

local function hasAccess(src, plate)
    return isOwner(src, plate) or hasTempKey(src, plate)
end

local function trunkSlotCount(level)
    level = tonumber(level) or 0
    return Config.TrunkSlotsByLevel[level] or 0
end

local function getItemDef(itemName)
    itemName = tostring(itemName or ''):lower()
    local ok, def = callExport('cm-items', 'GetItem', itemName)
    if ok and type(def) == 'table' then
        def.name = def.name or itemName
        def.label = def.label or itemName
        def.weight = tonumber(def.weight) or 0
        def.stack = def.stack ~= false and def.unique ~= true
        def.image = def.image or def.icon or (itemName .. '.png')
        def.description = def.description or ''
        return def
    end
    return { name = itemName, label = itemName, weight = 0, stack = true, image = itemName .. '.png', description = '' }
end

local function rowToItem(row)
    local def = getItemDef(row.item_name)
    local meta = decode(row.metadata)
    return {
        id = row.id,
        slot = row.slot,
        item_name = row.item_name,
        name = row.item_name,
        label = meta.label or def.label or row.item_name,
        image = def.image or 'placeholder.png',
        quantity = tonumber(row.quantity) or 1,
        weight = tonumber(def.weight) or 0,
        stack = def.stack ~= false,
        description = meta.description or def.description or '',
        metadata = meta,
        rarity = meta.rarity or meta.itemType or def.rarity or def.itemType or 'normal',
        durability = meta.durability or def.durability
    }
end

local function getInventoryRows(ownerType, ownerId)
    return MySQL.query.await('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? ORDER BY slot ASC', {
        ownerType, tostring(ownerId)
    }) or {}
end

local function getRowAt(ownerType, ownerId, slot)
    return MySQL.single.await('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? AND slot = ? LIMIT 1', {
        ownerType, tostring(ownerId), slot
    })
end

local function findEmptyTrunkSlot(vehicleId, maxSlots)
    for i = 1, maxSlots do
        local slot = 'trunk-' .. i
        if not getRowAt('vehicle_trunk', vehicleId, slot) then return slot end
    end
    return nil
end

local function addToTrunk(vehicleId, maxSlots, itemName, amount, metadata, preferredSlot)
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then return false, 'Invalid amount.' end
    itemName = tostring(itemName or ''):lower()
    metadata = type(metadata) == 'table' and metadata or {}
    local def = getItemDef(itemName)
    local metaEncoded = encode(metadata)
    local isEmptyMeta = next(metadata) == nil

    preferredSlot = tostring(preferredSlot or '')
    if preferredSlot ~= '' then
        local n = tonumber(preferredSlot:match('^trunk%-(%d+)$'))
        if not n or n < 1 or n > maxSlots then return false, 'Invalid trunk slot.' end
        local existingAtSlot = getRowAt('vehicle_trunk', tostring(vehicleId), preferredSlot)
        if existingAtSlot then
            if def.stack ~= false and isEmptyMeta and existingAtSlot.item_name == itemName and (not existingAtSlot.metadata or existingAtSlot.metadata == '' or existingAtSlot.metadata == '{}') then
                MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ? WHERE id = ?', { amount, existingAtSlot.id })
                return true, preferredSlot
            end
            return false, 'Target trunk slot is occupied.'
        end
        MySQL.insert.await([[INSERT INTO inventory_items (owner_type, owner_id, slot, item_name, quantity, metadata)
            VALUES ('vehicle_trunk', ?, ?, ?, ?, ?)]], { tostring(vehicleId), preferredSlot, itemName, amount, metaEncoded })
        return true, preferredSlot
    end

    if def.stack ~= false and isEmptyMeta then
        local existing = MySQL.single.await([[SELECT * FROM inventory_items
            WHERE owner_type = 'vehicle_trunk' AND owner_id = ? AND item_name = ? AND (metadata IS NULL OR metadata = '' OR metadata = '{}')
            ORDER BY slot ASC LIMIT 1]], { tostring(vehicleId), itemName })
        if existing then
            MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ? WHERE id = ?', { amount, existing.id })
            return true, existing.slot
        end
    end

    local slot = findEmptyTrunkSlot(tostring(vehicleId), maxSlots)
    if not slot then return false, 'Vehicle trunk is full.' end

    MySQL.insert.await([[INSERT INTO inventory_items (owner_type, owner_id, slot, item_name, quantity, metadata)
        VALUES ('vehicle_trunk', ?, ?, ?, ?, ?)]], { tostring(vehicleId), slot, itemName, amount, metaEncoded })
    return true, slot
end

local function removeFromRow(row, amount)
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then return false, 'Invalid amount.' end
    local current = tonumber(row.quantity) or 0
    if current < amount then return false, 'Not enough quantity.' end
    if current == amount then
        MySQL.update.await('DELETE FROM inventory_items WHERE id = ?', { row.id })
    else
        MySQL.update.await('UPDATE inventory_items SET quantity = quantity - ? WHERE id = ?', { amount, row.id })
    end
    return true
end

local function buildTrunkPayload(src, plate)
    local charId = getCharacterId(src)
    if not charId then return nil, 'Character is not loaded.' end
    local vehicle = getVehicleByPlate(plate)
    if not vehicle then return nil, 'Vehicle not found.' end

    local slotCount = trunkSlotCount(vehicle.trunk_level)
    if slotCount <= 0 then return nil, 'This vehicle has no trunk.' end

    local pRows = getInventoryRows('character', charId)
    local tRows = getInventoryRows('vehicle_trunk', vehicle.id)
    local playerItems, trunkItems = {}, {}
    for _, r in ipairs(pRows) do playerItems[#playerItems + 1] = rowToItem(r) end
    for _, r in ipairs(tRows) do trunkItems[#trunkItems + 1] = rowToItem(r) end

    local playerPayload = { ownerId = charId, items = playerItems }
    local okInv, invPayload = callExport('cm-inventory', 'GetInventory', src)
    if okInv and type(invPayload) == 'table' then
        playerPayload = invPayload
        playerPayload.ownerId = charId
    end

    return {
        plate = vehicle.plate,
        vehicleId = vehicle.id,
        vehicleLabel = vehicle.label,
        trunkLevel = vehicle.trunk_level,
        trunkSlots = slotCount,
        player = playerPayload,
        trunk = { ownerId = tostring(vehicle.id), items = trunkItems }
    }
end

local function refreshTrunk(src, plate)
    local payload, err = buildTrunkPayload(src, plate)
    if payload then
        TriggerClientEvent('cm-vehicles:client:updateTrunk', src, payload)
        return true
    end
    notify(src, err or 'Could not refresh trunk.', 'error')
    return false
end

local function generatePlate()
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

local function createOwnedVehicle(src, model, label, trunkLevel, metadata)
    local charId = getCharacterId(src)
    if not charId then return false, 'Character is not loaded.' end
    model = tostring(model or ''):lower()
    if model == '' then return false, 'Invalid model.' end
    label = tostring(label or model)
    trunkLevel = tonumber(trunkLevel) or Config.DefaultTrunkLevel or 1
    if trunkLevel < 0 then trunkLevel = 0 end
    local plate = generatePlate()

    local id = MySQL.insert.await([[INSERT INTO cm_owned_vehicles
        (owner_character_id, model, label, plate, trunk_level, metadata)
        VALUES (?, ?, ?, ?, ?, ?)]], {
            tostring(charId), model, label, plate, trunkLevel, encode(metadata or {})
        })

    audit(charId, plate, 'vehicle_created', { model = model, label = label, trunkLevel = trunkLevel })

    return true, {
        id = id,
        owner_character_id = tostring(charId),
        model = model,
        label = label,
        plate = plate,
        trunk_level = trunkLevel,
        is_locked = true,
        fuel = 100
    }
end

local function validateNearVehicle(src, netId, maxDistance)
    netId = tonumber(netId)
    if not netId then return true end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return true end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end
    local dist = #(GetEntityCoords(ped) - GetEntityCoords(veh))
    return dist <= (tonumber(maxDistance) or 5.0), dist
end

local function vehicleInfoFor(src, plate)
    local row = getVehicleByPlate(plate)
    if not row then return nil end
    local charId = getCharacterId(src)
    local owner = charId and tostring(row.owner_character_id) == tostring(charId) or false
    local key = hasTempKey(src, row.plate)
    local access = owner or key
    local netId = getSpawnedNetId(row.plate)
    return {
        id = row.id,
        model = row.model,
        label = row.label,
        plate = row.plate,
        ownerCharacterId = tostring(row.owner_character_id),
        trunkLevel = row.trunk_level,
        trunkSlots = trunkSlotCount(row.trunk_level),
        locked = row.is_locked,
        access = access,
        owner = owner,
        tempKey = key,
        netId = netId,
        fuel = tonumber(row.fuel) or 100,
        engineHealth = tonumber(row.engine_health) or 1000,
        bodyHealth = tonumber(row.body_health) or 1000
    }
end

CreateThread(function()
    ensureTables()
    print('[CM-VEHICLES] Started v1.7-normaldrive')
end)

RegisterNetEvent('cm-vehicles:server:registerNetVehicle', function(plate, netId)
    local src = source
    plate = resolvePlate(plate, netId)
    local row = getVehicleByPlate(plate)
    if not row then return end
    if not hasAccess(src, plate) then return end
    netId = tonumber(netId)
    if not netId then return end

    local existing = Spawned[plate] or {}
    existing.netId = netId or existing.netId
    existing.source = src
    existing.updatedAt = os.time()
    Spawned[plate] = existing

    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh and veh ~= 0 then
        Entity(veh).state:set('cmPlate', plate, true)
        pcall(function() SetVehicleNumberPlateText(veh, '        ') end)
        Entity(veh).state:set('cmVehicleId', row.id, true)
        Entity(veh).state:set('cmLocked', row.is_locked, true)
        Entity(veh).state:set('cmEngine', existing.engine == true, true)
    end
end)

RegisterNetEvent('cm-vehicles:server:requestInfo', function(plate, netId)
    local src = source
    plate = resolvePlate(plate, netId)
    local info = vehicleInfoFor(src, plate)
    if not info then notify(src, 'Vehicle not found.', 'error') return end
    if netId then info.netId = tonumber(netId) end
    TriggerClientEvent('cm-vehicles:client:openMenu', src, info)
end)

RegisterNetEvent('cm-vehicles:server:toggleLock', function(plate, netId)
    local src = source
    plate = resolvePlate(plate, netId)
    if plate == '' then notify(src, 'Vehicle id not found yet. Try again.', 'error') return end
    if not hasAccess(src, plate) then notify(src, 'You do not have keys for this vehicle.', 'error') return end
    local near = validateNearVehicle(src, netId, Config.Interaction.distance + 2.0)
    if not near then notify(src, 'You are too far from the vehicle.', 'error') return end

    local row = getVehicleByPlate(plate)
    if not row then return end
    local newLocked = row.is_locked ~= true
    MySQL.update.await('UPDATE cm_owned_vehicles SET is_locked = ? WHERE plate = ?', { newLocked and 1 or 0, plate })
    Spawned[plate] = Spawned[plate] or {}
    Spawned[plate].netId = tonumber(netId) or Spawned[plate].netId
    audit(getCharacterId(src), plate, newLocked and 'lock' or 'unlock', {})
    local finalNetId = tonumber(netId) or getSpawnedNetId(plate)
    if finalNetId then
        local ent = NetworkGetEntityFromNetworkId(finalNetId)
        if ent and ent ~= 0 then
            pcall(function() Entity(ent).state:set('cmLocked', newLocked, true) end)
        end
    end
    TriggerClientEvent('cm-vehicles:client:setVehicleState', -1, plate, finalNetId, { locked = newLocked })
    notify(src, newLocked and 'Vehicle locked.' or 'Vehicle unlocked.', 'success')
end)

RegisterNetEvent('cm-vehicles:server:toggleEngine', function(plate, netId)
    local src = source
    plate = resolvePlate(plate, netId)
    if plate == '' then notify(src, 'Vehicle id not found yet. Try again.', 'error') return end
    if not hasAccess(src, plate) then notify(src, 'You do not have keys for this vehicle.', 'error') return end
    local row = getVehicleByPlate(plate)
    if not row then return end
    local current = Spawned[plate] and Spawned[plate].engine == true or false
    local newEngine = not current
    Spawned[plate] = Spawned[plate] or {}
    Spawned[plate].netId = tonumber(netId) or Spawned[plate].netId
    Spawned[plate].engine = newEngine
    audit(getCharacterId(src), plate, newEngine and 'engine_on' or 'engine_off', {})
    TriggerClientEvent('cm-vehicles:client:setVehicleState', -1, plate, tonumber(netId) or getSpawnedNetId(plate), { engine = newEngine })
    notify(src, newEngine and 'Engine started.' or 'Engine stopped.', 'success')
end)


RegisterNetEvent('cm-vehicles:server:setEngine', function(plate, netId, desired)
    local src = source
    plate = resolvePlate(plate, netId)
    if plate == '' then notify(src, 'Vehicle id not found yet. Try again.', 'error') return end
    if not hasAccess(src, plate) then notify(src, 'You do not have keys for this vehicle.', 'error') return end
    local row = getVehicleByPlate(plate)
    if not row then return end
    local newEngine = desired == true or desired == 1 or desired == 'true'
    Spawned[plate] = Spawned[plate] or {}
    Spawned[plate].netId = tonumber(netId) or Spawned[plate].netId
    Spawned[plate].engine = newEngine
    audit(getCharacterId(src), plate, newEngine and 'engine_on' or 'engine_off', { command = true })
    TriggerClientEvent('cm-vehicles:client:setVehicleState', -1, plate, tonumber(netId) or getSpawnedNetId(plate), { engine = newEngine })
    notify(src, newEngine and 'Engine started.' or 'Engine stopped.', 'success')
end)

RegisterNetEvent('cm-vehicles:server:giveTempKey', function(plate, targetSrc)
    local src = source
    plate = resolvePlate(plate)
    targetSrc = tonumber(targetSrc)
    if not isOwner(src, plate) then notify(src, 'Only the vehicle owner can give temporary keys.', 'error') return end
    if not targetSrc or not GetPlayerName(targetSrc) then notify(src, 'Target player is not online.', 'error') return end

    local ped = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetSrc)
    if ped and targetPed and ped ~= 0 and targetPed ~= 0 then
        local dist = #(GetEntityCoords(ped) - GetEntityCoords(targetPed))
        if dist > (Config.Interaction.keyGiveDistance or 6.0) then
            notify(src, 'Target player is too far away.', 'error')
            return
        end
    end

    local ok, result = callExport('cm-vehiclekeys', 'GiveTempKey', src, targetSrc, plate)
    if not ok or result ~= true then
        notify(src, tostring(result or 'Could not give temporary key.'), 'error')
    end
end)

RegisterNetEvent('cm-vehicles:server:toggleTrunkDoor', function(plate, netId)
    local src = source
    plate = resolvePlate(plate, netId)
    local vehicle = getVehicleByPlate(plate)
    if not vehicle then notify(src, 'Vehicle not found.', 'error') return end
    if vehicle.is_locked then notify(src, 'Vehicle is locked.', 'error') return end
    if not hasAccess(src, plate) then notify(src, 'You do not have keys for this trunk.', 'error') return end
    if trunkSlotCount(vehicle.trunk_level) <= 0 then notify(src, 'This vehicle has no trunk.', 'error') return end
    local near = validateNearVehicle(src, netId, Config.Interaction.trunkDistance + 2.0)
    if not near then notify(src, 'You are too far from the trunk.', 'error') return end

    Spawned[plate] = Spawned[plate] or {}
    Spawned[plate].netId = tonumber(netId) or Spawned[plate].netId
    local newOpen = not (Spawned[plate].trunkOpen == true)
    Spawned[plate].trunkOpen = newOpen
    audit(getCharacterId(src), plate, newOpen and 'trunk_open' or 'trunk_close', {})
    TriggerClientEvent('cm-vehicles:client:setVehicleState', -1, plate, tonumber(netId) or getSpawnedNetId(plate), { trunkOpen = newOpen })
    notify(src, newOpen and 'Trunk opened. Press I near the trunk to open inventory.' or 'Trunk closed.', 'success')
end)

RegisterNetEvent('cm-vehicles:server:openTrunk', function(plate, netId)
    local src = source
    plate = resolvePlate(plate, netId)
    local vehicle = getVehicleByPlate(plate)
    if not vehicle then notify(src, 'Vehicle not found.', 'error') return end
    if vehicle.is_locked then notify(src, 'Vehicle is locked.', 'error') return end
    if not hasAccess(src, plate) then notify(src, 'You do not have keys for this trunk.', 'error') return end
    if trunkSlotCount(vehicle.trunk_level) <= 0 then notify(src, 'This vehicle has no trunk.', 'error') return end
    local near = validateNearVehicle(src, netId, Config.Interaction.trunkDistance + 2.0)
    if not near then notify(src, 'You are too far from the trunk.', 'error') return end

    local payload, err = buildTrunkPayload(src, plate)
    if not payload then notify(src, err or 'Could not open trunk.', 'error') return end
    Spawned[plate] = Spawned[plate] or {}
    Spawned[plate].netId = tonumber(netId) or Spawned[plate].netId
    Spawned[plate].trunkOpen = true
    TriggerClientEvent('cm-vehicles:client:openTrunk', src, payload)
    TriggerClientEvent('cm-vehicles:client:setVehicleState', -1, plate, tonumber(netId) or getSpawnedNetId(plate), { trunkOpen = true })
end)

RegisterNetEvent('cm-vehicles:server:closeTrunkDoor', function(plate, netId)
    plate = resolvePlate(plate, netId)
    Spawned[plate] = Spawned[plate] or {}
    Spawned[plate].trunkOpen = false
    TriggerClientEvent('cm-vehicles:client:setVehicleState', -1, plate, tonumber(netId) or getSpawnedNetId(plate), { trunkOpen = false })
end)

RegisterNetEvent('cm-vehicles:server:moveToTrunk', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local plate = normalizePlate(data.plate)
    local slot = tostring(data.slot or '')
    local amount = math.floor(tonumber(data.amount) or 1)
    if amount < 1 then return end

    local charId = getCharacterId(src)
    local vehicle = getVehicleByPlate(plate)
    if not charId or not vehicle then return end
    if vehicle.is_locked then notify(src, 'Vehicle is locked.', 'error') return end
    if not hasAccess(src, plate) then notify(src, 'You do not have keys for this trunk.', 'error') return end

    local maxSlots = trunkSlotCount(vehicle.trunk_level)
    if maxSlots <= 0 then notify(src, 'This vehicle has no trunk.', 'error') return end

    local row = getRowAt('character', charId, slot)
    if not row then notify(src, 'Item not found.', 'error') return end
    local metadata = decode(row.metadata)
    local okAdd, addErr = addToTrunk(tostring(vehicle.id), maxSlots, row.item_name, amount, metadata, data.toSlot)
    if not okAdd then notify(src, addErr or 'Could not move item.', 'error') return end

    local okRemove, remErr = removeFromRow(row, amount)
    if not okRemove then notify(src, remErr or 'Could not remove item.', 'error') return end

    audit(charId, plate, 'move_to_trunk', { item = row.item_name, amount = amount, fromSlot = slot })
    refreshTrunk(src, plate)
    local okInv, payload = callExport('cm-inventory', 'GetInventory', src)
    if okInv and type(payload) == 'table' then
        TriggerClientEvent('cm-inventory:client:update', src, payload)
    end
end)

RegisterNetEvent('cm-vehicles:server:takeFromTrunk', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local plate = normalizePlate(data.plate)
    local slot = tostring(data.slot or '')
    local amount = math.floor(tonumber(data.amount) or 1)
    if amount < 1 then return end

    local charId = getCharacterId(src)
    local vehicle = getVehicleByPlate(plate)
    if not charId or not vehicle then return end
    if vehicle.is_locked then notify(src, 'Vehicle is locked.', 'error') return end
    if not hasAccess(src, plate) then notify(src, 'You do not have keys for this trunk.', 'error') return end

    local row = getRowAt('vehicle_trunk', tostring(vehicle.id), slot)
    if not row then notify(src, 'Item not found.', 'error') return end
    local metadata = decode(row.metadata)

    local ok, result, reason = callExport('cm-inventory', 'AddItem', src, row.item_name, amount, metadata, 'vehicle_trunk_take', data.toSlot)
    if not ok or result ~= true then
        notify(src, tostring(reason or result or 'No space in player inventory.'), 'error')
        return
    end

    local okRemove, remErr = removeFromRow(row, amount)
    if not okRemove then
        -- Best-effort rollback if something very unexpected happens.
        callExport('cm-inventory', 'RemoveItem', src, row.item_name, amount, metadata, 'vehicle_trunk_rollback')
        notify(src, remErr or 'Could not remove trunk item.', 'error')
        return
    end

    audit(charId, plate, 'take_from_trunk', { item = row.item_name, amount = amount, fromSlot = slot })
    refreshTrunk(src, plate)
end)

RegisterNetEvent('cm-vehicles:server:savePosition', function(plate, pos)
    local src = source
    plate = normalizePlate(plate)
    if not hasAccess(src, plate) then return end
    if type(pos) ~= 'table' then return end
    MySQL.update.await('UPDATE cm_owned_vehicles SET last_position = ? WHERE plate = ?', { encode(pos), plate })
end)

RegisterNetEvent('cm-vehicles:server:requestMyVehicles', function()
    local src = source
    local charId = getCharacterId(src)
    if not charId then return end
    local rows = MySQL.query.await('SELECT id, model, label, plate, trunk_level, is_locked, is_stored FROM cm_owned_vehicles WHERE owner_character_id = ? ORDER BY id DESC', { charId }) or {}
    TriggerClientEvent('cm-vehicles:client:showMyVehicles', src, rows)
end)

RegisterCommand('myvehicles', function(src)
    if src <= 0 then return end
    local charId = getCharacterId(src)
    if not charId then notify(src, 'Character is not loaded.', 'error') return end
    local rows = MySQL.query.await('SELECT id, model, label, plate, trunk_level, is_locked, is_stored FROM cm_owned_vehicles WHERE owner_character_id = ? ORDER BY id DESC', { charId }) or {}
    TriggerClientEvent('cm-vehicles:client:showMyVehicles', src, rows)
end, false)

RegisterCommand('vehgive', function(src, args)
    if src <= 0 then return end
    if not (Config.Commands and Config.Commands.adminSpawnOwned) then return end
    local model = tostring(args[1] or 'sultan'):lower()
    local trunkLevel = tonumber(args[2]) or 3
    local label = args[3] or model
    local ok, result = createOwnedVehicle(src, model, label, trunkLevel, { source = 'vehgive' })
    if not ok then notify(src, tostring(result), 'error') return end
    TriggerClientEvent('cm-vehicles:client:spawnPurchasedVehicle', src, result)
    notify(src, ('Created %s.'):format(result.label), 'success')
end, false)

exports('CreateOwnedVehicle', function(src, model, label, trunkLevel, metadata)
    return createOwnedVehicle(src, model, label, trunkLevel, metadata)
end)

exports('GetVehicleByPlate', function(plate)
    return getVehicleByPlate(plate)
end)

exports('HasVehicleAccess', function(src, plate)
    return hasAccess(src, plate)
end)

exports('PlayerOwnsVehicle', function(src, plate)
    return isOwner(src, plate)
end)

exports('GetCharacterId', function(src)
    return getCharacterId(src)
end)
