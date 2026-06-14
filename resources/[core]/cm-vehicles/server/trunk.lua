local U = CMVehicles.Utils
local Config = CMVehicles.Config
CMVehicles.Trunk = CMVehicles.Trunk or {}

function CMVehicles.Trunk.SlotCount(level)
    level = tonumber(level) or 0
    return Config.TrunkSlotsByLevel[level] or 0
end

local function getItemDef(itemName)
    itemName = tostring(itemName or ''):lower()
    local ok, def = U.CallExport('cm-items', 'GetItem', itemName)
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
    local meta = U.Decode(row.metadata)
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
    return MySQL.query.await('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? ORDER BY slot ASC', { ownerType, tostring(ownerId) }) or {}
end

local function getRowAt(ownerType, ownerId, slot)
    return MySQL.single.await('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? AND slot = ? LIMIT 1', { ownerType, tostring(ownerId), tostring(slot) })
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
    local metaEncoded = U.Encode(metadata)

    local slot = tostring(preferredSlot or '')
    if slot ~= '' then
        local n = tonumber(slot:match('trunk%-(%d+)'))
        if not n or n < 1 or n > maxSlots then return false, 'Invalid trunk slot.' end
        local existing = getRowAt('vehicle_trunk', vehicleId, slot)
        if existing then return false, 'Slot is occupied.' end
    else
        slot = findEmptyTrunkSlot(vehicleId, maxSlots)
        if not slot then return false, 'Trunk is full.' end
    end

    if def.stack ~= false and next(metadata) == nil then
        local rows = getInventoryRows('vehicle_trunk', vehicleId)
        for _, r in ipairs(rows) do
            if tostring(r.item_name):lower() == itemName and (not r.metadata or r.metadata == '' or r.metadata == '{}') then
                MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ? WHERE id = ?', { amount, r.id })
                return true, r.slot
            end
        end
    end

    MySQL.insert.await('INSERT INTO inventory_items (owner_type, owner_id, slot, item_name, quantity, metadata) VALUES (?, ?, ?, ?, ?, ?)', { 'vehicle_trunk', tostring(vehicleId), slot, itemName, amount, metaEncoded })
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

function CMVehicles.Trunk.BuildPayload(src, plate)
    local charId = CMVehicles.Server.GetCharacterId(src)
    if not charId then return nil, 'Character is not loaded.' end
    local vehicle = CMVehicles.Server.GetVehicleByPlate(plate)
    if not vehicle then return nil, 'Vehicle not found.' end
    local slotCount = CMVehicles.Trunk.SlotCount(vehicle.trunk_level)
    if slotCount <= 0 then return nil, 'This vehicle has no trunk.' end
    local pRows = getInventoryRows('character', charId)
    local tRows = getInventoryRows('vehicle_trunk', vehicle.id)
    local playerItems, trunkItems = {}, {}
    for _, r in ipairs(pRows) do playerItems[#playerItems + 1] = rowToItem(r) end
    for _, r in ipairs(tRows) do trunkItems[#trunkItems + 1] = rowToItem(r) end
    local playerPayload = { ownerId = charId, items = playerItems }
    local okInv, invPayload = U.CallExport('cm-inventory', 'GetInventory', src)
    if okInv and type(invPayload) == 'table' then playerPayload = invPayload; playerPayload.ownerId = charId end
    return { plate = vehicle.plate, vehicleId = vehicle.id, vehicleLabel = vehicle.label, trunkLevel = vehicle.trunk_level, trunkSlots = slotCount, player = playerPayload, trunk = { ownerId = tostring(vehicle.id), items = trunkItems } }
end

function CMVehicles.Trunk.Refresh(src, plate)
    local payload, err = CMVehicles.Trunk.BuildPayload(src, plate)
    if payload then TriggerClientEvent('cm-vehicles:client:updateTrunk', src, payload); return true end
    U.Notify(src, err or 'Could not refresh trunk.', 'error')
    return false
end

RegisterNetEvent('cm-vehicles:server:toggleTrunkDoor', function(plate, netId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    local vehicle = CMVehicles.Server.GetVehicleByPlate(plate)
    if not vehicle then return U.Notify(src, 'Vehicle not found.', 'error') end
    if vehicle.is_locked then return U.Notify(src, 'Vehicle is locked.', 'error') end
    if not CMVehicles.Server.HasAccess(src, plate) then return U.Notify(src, 'You do not have keys for this trunk.', 'error') end
    if CMVehicles.Trunk.SlotCount(vehicle.trunk_level) <= 0 then return U.Notify(src, 'This vehicle has no trunk.', 'error') end
    local near = CMVehicles.Server.ValidateNearVehicle(src, netId, (Config.Interaction.trunkDistance or 4.0) + 2.0)
    if not near then return U.Notify(src, 'You are too far from the trunk.', 'error') end
    CMVehicles.Server.Spawned[plate] = CMVehicles.Server.Spawned[plate] or {}
    CMVehicles.Server.Spawned[plate].netId = tonumber(netId) or CMVehicles.Server.Spawned[plate].netId
    local newOpen = not (CMVehicles.Server.Spawned[plate].trunkOpen == true)
    CMVehicles.Server.Spawned[plate].trunkOpen = newOpen
    TriggerClientEvent('cm-vehicles:client:setVehicleState', -1, plate, tonumber(netId) or CMVehicles.Server.GetSpawnedNetId(plate), { trunkOpen = newOpen })
    U.Notify(src, newOpen and 'Trunk opened. Press I near the trunk to open inventory.' or 'Trunk closed.', 'success')
end)

RegisterNetEvent('cm-vehicles:server:openTrunk', function(plate, netId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    local vehicle = CMVehicles.Server.GetVehicleByPlate(plate)
    if not vehicle then return U.Notify(src, 'Vehicle not found.', 'error') end
    if vehicle.is_locked then return U.Notify(src, 'Vehicle is locked.', 'error') end
    if not CMVehicles.Server.HasAccess(src, plate) then return U.Notify(src, 'You do not have keys for this trunk.', 'error') end
    local payload, err = CMVehicles.Trunk.BuildPayload(src, plate)
    if not payload then return U.Notify(src, err or 'Could not open trunk.', 'error') end
    CMVehicles.Server.Spawned[plate] = CMVehicles.Server.Spawned[plate] or {}
    CMVehicles.Server.Spawned[plate].netId = tonumber(netId) or CMVehicles.Server.Spawned[plate].netId
    CMVehicles.Server.Spawned[plate].trunkOpen = true
    TriggerClientEvent('cm-vehicles:client:openTrunk', src, payload)
    TriggerClientEvent('cm-vehicles:client:setVehicleState', -1, plate, tonumber(netId) or CMVehicles.Server.GetSpawnedNetId(plate), { trunkOpen = true })
end)

RegisterNetEvent('cm-vehicles:server:moveToTrunk', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local plate = U.NormalizePlate(data.plate)
    local vehicle = CMVehicles.Server.GetVehicleByPlate(plate)
    local charId = CMVehicles.Server.GetCharacterId(src)
    if not charId or not vehicle or vehicle.is_locked or not CMVehicles.Server.HasAccess(src, plate) then return end
    local maxSlots = CMVehicles.Trunk.SlotCount(vehicle.trunk_level)
    local row = getRowAt('character', charId, data.slot)
    if not row then return U.Notify(src, 'Item not found.', 'error') end
    local okAdd, addErr = addToTrunk(tostring(vehicle.id), maxSlots, row.item_name, data.amount, U.Decode(row.metadata), data.toSlot)
    if not okAdd then return U.Notify(src, addErr or 'Could not move item.', 'error') end
    local okRemove, remErr = removeFromRow(row, data.amount)
    if not okRemove then return U.Notify(src, remErr or 'Could not remove item.', 'error') end
    CMVehicles.Trunk.Refresh(src, plate)
end)

RegisterNetEvent('cm-vehicles:server:takeFromTrunk', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local plate = U.NormalizePlate(data.plate)
    local vehicle = CMVehicles.Server.GetVehicleByPlate(plate)
    if not vehicle or vehicle.is_locked or not CMVehicles.Server.HasAccess(src, plate) then return end
    local row = getRowAt('vehicle_trunk', tostring(vehicle.id), data.slot)
    if not row then return U.Notify(src, 'Item not found.', 'error') end
    local ok, result, reason = U.CallExport('cm-inventory', 'AddItem', src, row.item_name, data.amount, U.Decode(row.metadata), 'vehicle_trunk_take', data.toSlot)
    if not ok or result ~= true then return U.Notify(src, tostring(reason or result or 'No space in player inventory.'), 'error') end
    local okRemove, remErr = removeFromRow(row, data.amount)
    if not okRemove then return U.Notify(src, remErr or 'Could not remove trunk item.', 'error') end
    CMVehicles.Trunk.Refresh(src, plate)
end)
