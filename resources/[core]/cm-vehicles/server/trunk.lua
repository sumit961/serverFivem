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

RegisterNetEvent('cm-vehicles:server:openTrunk', function()
    U.Notify(source, 'Open the trunk, then press I to use cm-inventory.')
end)


RegisterNetEvent('cm-vehicles:server:openSharedTrunkInventory', function(plate, netId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    local vehicle = CMVehicles.Server.GetVehicleByPlate(plate)
    if not vehicle then return U.Notify(src, 'Vehicle not found.', 'error') end
    if vehicle.is_locked then return U.Notify(src, 'Vehicle is locked.', 'error') end
    if not CMVehicles.Server.IsOwner(src, plate) then return U.Notify(src, 'Only the vehicle owner can open this trunk inventory.', 'error') end

    local slotCount = CMVehicles.Trunk.SlotCount(vehicle.trunk_level)
    if slotCount <= 0 then return U.Notify(src, 'This vehicle has no trunk storage.', 'error') end

    local spawned = CMVehicles.Server.Spawned[plate] or {}
    if spawned.trunkOpen ~= true then
        return U.Notify(src, 'Open the trunk first, then press I near the trunk.', 'error')
    end

    local near = CMVehicles.Server.ValidateNearVehicle(src, netId, (Config.Interaction.trunkDistance or 4.5) + 2.0)
    if not near then return U.Notify(src, 'Move closer to the open trunk.', 'error') end

    if GetResourceState('cm-inventory') ~= 'started' then
        return U.Notify(src, 'Inventory resource is not started.', 'error')
    end

    CMVehicles.Server.Spawned[plate] = CMVehicles.Server.Spawned[plate] or {}
    CMVehicles.Server.Spawned[plate].netId = tonumber(netId) or CMVehicles.Server.Spawned[plate].netId

    local externalContext = {
        ownerType = 'vehicle_trunk',
        ownerId = tostring(vehicle.id),
        slotPrefix = 'trunk-',
        slots = math.min(slotCount, 30),
        displaySlots = 30,
        kind = 'vehicle_trunk',
        label = tostring(vehicle.label or vehicle.model or 'Vehicle') .. ' Trunk',
        subtitle = tostring(vehicle.plate or plate),
        icon = 'vehicle',
        replace = 'equipment',
        noWeightLimit = true,
        canDeposit = true,
        canWithdraw = true,
        data = {
            plate = tostring(vehicle.plate or plate),
            vehicleId = tostring(vehicle.id),
            trunkLevel = tonumber(vehicle.trunk_level) or 0,
            displaySlots = 30
        }
    }

    U.Debug(('Opening cm-inventory external trunk src=%s plate=%s vehicleId=%s level=%s slots=%s netId=%s'):format(
        tostring(src), tostring(plate), tostring(vehicle.id), tostring(vehicle.trunk_level), tostring(slotCount), tostring(netId)
    ))
    U.Debug(('External context ownerType=%s ownerId=%s prefix=%s slots=%s display=%s'):format(
        tostring(externalContext.ownerType), tostring(externalContext.ownerId), tostring(externalContext.slotPrefix), tostring(externalContext.slots), tostring(externalContext.displaySlots)
    ))

    local ok, resultOrErr, externalErr = pcall(function()
        return exports['cm-inventory']:OpenExternalInventory(src, externalContext)
    end)

    if not ok or resultOrErr ~= true then
        U.Debug(('OpenExternalInventory failed src=%s result=%s err=%s'):format(tostring(src), tostring(resultOrErr), tostring(externalErr)))
        return U.Notify(src, tostring(externalErr or resultOrErr or 'Could not open trunk inventory.'), 'error')
    end

    U.Debug(('OpenExternalInventory success src=%s plate=%s vehicleId=%s'):format(tostring(src), tostring(plate), tostring(vehicle.id)))
end)

-- Legacy cm-vehicles item inventory movement removed. All item movement now goes through cm-inventory external storage.
RegisterNetEvent('cm-vehicles:server:moveToTrunk', function()
    U.Notify(source, 'Vehicle inventory is handled by cm-inventory. Open the trunk and press I.', 'error')
end)

RegisterNetEvent('cm-vehicles:server:takeFromTrunk', function()
    U.Notify(source, 'Vehicle inventory is handled by cm-inventory. Open the trunk and press I.', 'error')
end)

-- Player-in-trunk state. This is separate from the item inventory trunk.
-- It prevents more than one player from hiding in the same vehicle trunk.
CMVehicles.Server.TrunkOccupants = CMVehicles.Server.TrunkOccupants or {}

local function occupantStillOnline(src)
    src = tonumber(src)
    return src and src > 0 and GetPlayerName(src) ~= nil
end

RegisterNetEvent('cm-vehicles:server:requestEnterTrunk', function(plate, netId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    local vehicle = CMVehicles.Server.GetVehicleByPlate(plate)
    if not vehicle then return U.Notify(src, 'Vehicle not found.', 'error') end
    if vehicle.is_locked then return U.Notify(src, 'Unlock the vehicle first.', 'error') end
    if CMVehicles.Trunk.SlotCount(vehicle.trunk_level) <= 0 then return U.Notify(src, 'This vehicle has no trunk.', 'error') end

    local near = CMVehicles.Server.ValidateNearVehicle(src, netId, (Config.Interaction.trunkDistance or 4.5) + 2.5)
    if not near then return U.Notify(src, 'You are too far from the trunk.', 'error') end

    local current = CMVehicles.Server.TrunkOccupants[plate]
    if current and current ~= src and occupantStillOnline(current) then
        return U.Notify(src, 'Someone is already in this trunk.', 'error')
    end

    CMVehicles.Server.TrunkOccupants[plate] = src
    CMVehicles.Server.Spawned[plate] = CMVehicles.Server.Spawned[plate] or {}
    CMVehicles.Server.Spawned[plate].netId = tonumber(netId) or CMVehicles.Server.Spawned[plate].netId
    CMVehicles.Server.Spawned[plate].trunkOpen = true

    local finalNetId = tonumber(netId) or CMVehicles.Server.GetSpawnedNetId(plate)
    TriggerClientEvent('cm-vehicles:client:setVehicleState', -1, plate, finalNetId, { trunkOpen = true })
    TriggerClientEvent('cm-vehicles:client:enterTrunk', src, finalNetId, plate)
end)

RegisterNetEvent('cm-vehicles:server:leaveTrunk', function(plate)
    local src = source
    plate = U.NormalizePlate(plate)
    if plate ~= '' and tonumber(CMVehicles.Server.TrunkOccupants[plate]) == tonumber(src) then
        CMVehicles.Server.TrunkOccupants[plate] = nil
    else
        for p, occupant in pairs(CMVehicles.Server.TrunkOccupants) do
            if tonumber(occupant) == tonumber(src) then CMVehicles.Server.TrunkOccupants[p] = nil end
        end
    end
end)

RegisterNetEvent('cm-vehicles:server:forceOutTrunk', function(plate, netId)
    local src = source
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    local vehicle = CMVehicles.Server.GetVehicleByPlate(plate)
    if not vehicle then return U.Notify(src, 'Vehicle not found.', 'error') end
    if not CMVehicles.Server.HasAccess(src, plate) then return U.Notify(src, 'You do not have keys for this vehicle.', 'error') end

    local near = CMVehicles.Server.ValidateNearVehicle(src, netId, 8.0)
    if not near then return U.Notify(src, 'Move closer to the vehicle.', 'error') end

    local target = CMVehicles.Server.TrunkOccupants[plate]
    if not target or not occupantStillOnline(target) then
        CMVehicles.Server.TrunkOccupants[plate] = nil
        return U.Notify(src, 'No player is in this trunk.', 'error')
    end

    CMVehicles.Server.TrunkOccupants[plate] = nil
    TriggerClientEvent('cm-vehicles:client:exitTrunk', target, true)
    U.Notify(src, 'Player removed from the trunk.', 'success')
    if tonumber(target) ~= tonumber(src) then U.Notify(target, 'You were removed from the trunk.', 'info') end
end)

RegisterNetEvent('cm-vehicles:server:ejectPassenger', function(plate, netId, targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    plate = CMVehicles.Server.ResolvePlate(plate, netId)
    if not targetSrc or not GetPlayerName(targetSrc) then return U.Notify(src, 'Passenger is not online.', 'error') end
    if tonumber(targetSrc) == tonumber(src) then return U.Notify(src, 'You cannot eject yourself from this menu.', 'error') end
    if not CMVehicles.Server.HasAccess(src, plate) then return U.Notify(src, 'You do not have keys for this vehicle.', 'error') end
    if not CMVehicles.Server.IsDriverOfVehicle(src, netId) then return U.Notify(src, 'Only the driver can remove passengers.', 'error') end

    TriggerClientEvent('cm-vehicles:client:forceLeaveVehicle', targetSrc)
    U.Notify(src, 'Passenger removed from vehicle.', 'success')
    U.Notify(targetSrc, 'The driver removed you from the vehicle.', 'info')
end)

AddEventHandler('playerDropped', function()
    local src = source
    for plate, occupant in pairs(CMVehicles.Server.TrunkOccupants) do
        if tonumber(occupant) == tonumber(src) then CMVehicles.Server.TrunkOccupants[plate] = nil end
    end
end)
