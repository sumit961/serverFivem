-- cm-inventory/external.lua
-- Generic secondary-inventory support.
-- This lets vehicles, warehouses, houses, businesses, etc. reuse the same inventory UI
-- without adding new UI/server logic for every storage type.

local ActiveExternalInventories = ActiveExternalInventories or {}
local EXTERNAL_UI_PREFIX = 'external-'
local validateExternalMovementAccess

-- UI slots are intentionally kept separate from DB slots.
-- UI sends external-1..external-30; DB stores trunk-1, warehouse-1, etc.
-- This helper is tolerant so older UI builds or future storage modules cannot fall
-- back into normal player-slot validation and show the confusing "Invalid slot" error.
local function parsePositiveSlotIndex(slot, prefixes)
    if type(slot) ~= 'string' and type(slot) ~= 'number' then return nil end
    slot = tostring(slot or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if slot == '' then return nil end
    local lowerSlot = slot:lower()
    for _, prefix in ipairs(prefixes or {}) do
        prefix = tostring(prefix or '')
        if prefix ~= '' then
            local lowerPrefix = prefix:lower()
            if lowerSlot:find(lowerPrefix, 1, true) == 1 then
                local idx = tonumber(slot:sub(#prefix + 1))
                if idx and idx >= 1 then return math.floor(idx) end
            end
        end
    end
    return nil
end

local function isExternalUiSlot(slot)
    local idx = parsePositiveSlotIndex(slot, {
        EXTERNAL_UI_PREFIX, 'external_', 'externalSlot-', 'externalSlot_',
        'storage-', 'storage_', 'storageSlot-', 'storageSlot_'
    })
    if not idx then return false, nil end
    return true, idx
end

local function externalUiSlotFromIndex(idx)
    idx = tonumber(idx)
    if not idx or idx < 1 then return nil end
    return EXTERNAL_UI_PREFIX .. tostring(math.floor(idx))
end

local function externalIndexForContext(ctx, slot)
    local ok, idx = isExternalUiSlot(slot)
    if ok then return idx end
    if not ctx then return nil end
    idx = parsePositiveSlotIndex(slot, { tostring(ctx.slotPrefix or 'slot-'), 'trunk-', 'trunk_', 'warehouse-', 'warehouse_', 'house-', 'house_', 'storage-', 'storage_' })
    if idx then return idx end
    -- Accept a raw numeric string only while an external inventory is open.
    -- This makes future storage UIs safer without changing DB slot naming.
    local raw = tonumber(slot)
    if raw and raw >= 1 then return math.floor(raw) end
    return nil
end

local function getPlayerOwner(src)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return nil, nil, 'No character owner found.' end
    return ownerType, tostring(ownerId)
end

local function sanitizeExternalContext(src, context)
    context = type(context) == 'table' and context or {}

    local ownerType = tostring(context.ownerType or context.owner_type or ''):gsub('%s+', '')
    local ownerId = tostring(context.ownerId or context.owner_id or '')
    local slots = math.floor(tonumber(context.slots or context.slotCount or context.slot_count) or 0)
    local displaySlots = math.floor(tonumber(context.displaySlots or context.display_slots or context.visualSlots or context.visual_slots) or 30)
    local slotPrefix = tostring(context.slotPrefix or context.slot_prefix or 'slot-')

    if ownerType == '' then return nil, 'External inventory ownerType missing.' end
    if ownerId == '' then return nil, 'External inventory ownerId missing.' end
    if slots < 1 then return nil, 'External inventory has no slots.' end
    if slots > 200 then slots = 200 end
    -- Storage UI is standardised to a 6x5 board. The real usable slot count is still
    -- controlled by `slots`, but the UI can show a stable 30-slot board for trunks,
    -- warehouses, houses, businesses, etc.
    if displaySlots < slots then displaySlots = slots end
    if displaySlots < 1 then displaySlots = 30 end
    if displaySlots > 30 then displaySlots = 30 end
    if #slotPrefix > 35 then return nil, 'External slot prefix is too long.' end
    if slotPrefix:find(EXTERNAL_UI_PREFIX, 1, true) == 1 then return nil, 'External slot prefix is reserved.' end

    local invokingResource = tostring(GetInvokingResource() or '')
    local accessExport = tostring(context.accessExport or context.access_export or '')
    if #accessExport > 64 or not accessExport:match('^[%w_]+$') then accessExport = '' end
    local activityExport = tostring(context.activityExport or context.activity_export or '')
    if #activityExport > 64 or not activityExport:match('^[%w_]+$') then activityExport = '' end
    return {
        ownerType = ownerType,
        ownerId = ownerId,
        slots = slots,
        displaySlots = displaySlots,
        slotPrefix = slotPrefix,
        label = tostring(context.label or context.title or 'Storage'),
        subtitle = tostring(context.subtitle or context.description or ''),
        kind = tostring(context.kind or ownerType),
        icon = tostring(context.icon or ''),
        replace = tostring(context.replace or 'equipment'),
        noWeightLimit = context.noWeightLimit ~= false,
        canDeposit = context.canDeposit ~= false,
        canWithdraw = context.canWithdraw ~= false,
        resource = invokingResource,
        accessExport = accessExport ~= '' and accessExport or nil,
        activityExport = activityExport ~= '' and activityExport or nil,
        data = type(context.data) == 'table' and context.data or {}
    }
end

local function storageSlotForExternal(ctx, uiSlot)
    local idx = externalIndexForContext(ctx, uiSlot)
    if not idx then
        dprint(('storageSlotForExternal FAILED uiSlot=%s ownerType=%s ownerId=%s prefix=%s slots=%s display=%s'):format(
            tostring(uiSlot), tostring(ctx and ctx.ownerType), tostring(ctx and ctx.ownerId),
            tostring(ctx and ctx.slotPrefix), tostring(ctx and ctx.slots), tostring(ctx and ctx.displaySlots)
        ))
        return nil, 'Invalid storage slot.'
    end
    if idx > tonumber(ctx.slots or 0) then
        dprint(('storageSlotForExternal LOCKED uiSlot=%s idx=%s slots=%s'):format(tostring(uiSlot), tostring(idx), tostring(ctx.slots)))
        return nil, ('This storage only has %s usable slots.'):format(tostring(ctx.slots or 0))
    end
    local storageSlot = tostring(ctx.slotPrefix or 'slot-') .. tostring(idx)
    dprint(('storageSlotForExternal OK uiSlot=%s idx=%s storageSlot=%s'):format(tostring(uiSlot), tostring(idx), tostring(storageSlot)))
    return storageSlot
end

local function externalUiSlotFromStorage(ctx, storageSlot)
    storageSlot = tostring(storageSlot or '')
    local prefix = tostring(ctx.slotPrefix or 'slot-')
    if storageSlot:find(prefix, 1, true) ~= 1 then return nil end
    local idx = tonumber(storageSlot:sub(#prefix + 1))
    if not idx or idx < 1 or idx > tonumber(ctx.slots or 0) then return nil end
    return EXTERNAL_UI_PREFIX .. tostring(math.floor(idx))
end

local function itemWeight(row)
    if not row then return 0 end
    local def = getItemDef(row.item_name)
    return (tonumber(def and def.weight) or 0) * (tonumber(row.quantity) or 1)
end

local function sameStackableItem(a, b)
    return rowsCanStack(a, b)
end

local function canPlayerReceiveRow(src, ownerType, ownerId, destSlot, incomingRow, outgoingRow)
    if not isValidSlot(destSlot) then return false, 'Invalid player slot.' end
    if not isSlotUnlocked(ownerType, ownerId, destSlot) then return false, 'That backpack slot is locked by your bag level.' end

    local canSlot, slotErr = canPlaceInSlot(incomingRow.item_name, destSlot)
    if not canSlot then return false, slotErr end

    local genderOk, genderErr = validateEquipmentGender(src, destSlot, incomingRow)
    if not genderOk then return false, genderErr end

    local maxWeight = getMaxWeight(ownerType, ownerId)
    local afterWeight = getUsedWeight(ownerType, ownerId) + itemWeight(incomingRow) - itemWeight(outgoingRow)
    if afterWeight > maxWeight then
        return false, 'Inventory is too heavy. Upgrade/equip a better bag.'
    end

    return true
end

local function buildExternalInventoryPayload(src)
    local payload, err = buildInventoryPayload(src)
    if not payload then return nil, err end

    local ctx = ActiveExternalInventories[tonumber(src)]
    if not ctx then return payload end

    local rows = getRows(ctx.ownerType, ctx.ownerId)
    local items = {}
    local usedWeight = 0

    for _, row in ipairs(rows) do
        local uiSlot = externalUiSlotFromStorage(ctx, row.slot)
        if uiSlot then
            local item = rowToItem(row)
            item.sourceSlot = row.slot
            item.external = true
            item.slot = uiSlot
            items[#items + 1] = item
            usedWeight = usedWeight + itemWeight(row)
        end
    end

    payload.mode = 'external'
    payload.external = {
        active = true,
        ownerType = ctx.ownerType,
        ownerId = ctx.ownerId,
        kind = ctx.kind,
        label = ctx.label,
        subtitle = ctx.subtitle,
        icon = ctx.icon,
        replace = ctx.replace,
        slotPrefix = ctx.slotPrefix,
        slotCount = ctx.slots,
        slots = ctx.slots,
        displaySlots = ctx.displaySlots,
        items = items,
        weight = { current = usedWeight, max = 0 },
        noWeightLimit = ctx.noWeightLimit,
        canDeposit = ctx.canDeposit,
        canWithdraw = ctx.canWithdraw,
        data = ctx.data
    }

    return payload
end

local function sendInventorySmart(src, forceOpen)
    src = tonumber(src)
    if not src or src <= 0 then return false end
    if forceOpen == true and isPlayerDeadState(src) then return false end

    if ActiveExternalInventories[src] then
        local payload, err = buildExternalInventoryPayload(src)
        if not payload then
            TriggerClientEvent('cm-inventory:client:notify', src, err or 'Could not load inventory.', 'error')
            return false
        end
        TriggerClientEvent(forceOpen == true and 'cm-inventory:client:open' or 'cm-inventory:client:update', src, payload)
        return true
    end

    return sendInventory(src, forceOpen)
end

local function OpenExternalInventoryInternal(src, context)
    src = tonumber(src)
    if not src or src <= 0 then return false, 'Invalid player.' end
    if isPlayerDeadState(src) then return false, 'Player is unconscious.' end

    -- If another resource checks owner/permission and explicitly denies the
    -- storage, do not leave the player with nothing. Open their normal inventory.
    if type(context) == 'table' and (context.allowed == false or context.canOpen == false or context.can_open == false or context.isAllowed == false) then
        ActiveExternalInventories[src] = nil
        sendInventory(src, true)
        return false, 'External inventory access denied.'
    end

    local ctx, err = sanitizeExternalContext(src, context)
    if not ctx then return false, err end

    local accessOk, accessErr = validateExternalMovementAccess(src, ctx, 'storage.open')
    if not accessOk then return false, accessErr end

    ActiveExternalInventories[src] = ctx
    dprint(('OPEN EXTERNAL src=%s ownerType=%s ownerId=%s prefix=%s slots=%s display=%s label=%s'):format(
        tostring(src), tostring(ctx.ownerType), tostring(ctx.ownerId), tostring(ctx.slotPrefix), tostring(ctx.slots), tostring(ctx.displaySlots), tostring(ctx.label)
    ))
    local sent = sendInventorySmart(src, true)
    if not sent then
        ActiveExternalInventories[src] = nil
        return false, 'Could not open external inventory.'
    end

    return true
end

local function CloseExternalInventoryInternal(src)
    dprint(('CLOSE EXTERNAL src=%s'):format(tostring(src)))
    ActiveExternalInventories[tonumber(src)] = nil
    return true
end

-- Vehicle trunks are opened by cm-vehicles after its distance, lock and access
-- checks. Revalidate authorization for every item movement as well: an external
-- inventory can remain open while a player goes off duty, is suspended, or has
-- their organization rank changed. The persistent vehicle ID is the storage
-- owner ID, so no client-provided plate or network ID is trusted here.
validateExternalMovementAccess = function(src, ctx, action)
    if ctx and ctx.accessExport then
        if ctx.resource == '' or GetResourceState(ctx.resource) ~= 'started' then
            return false, 'Storage access authority is unavailable.'
        end
        local ok, allowed, reason = pcall(function()
            return exports[ctx.resource][ctx.accessExport](src, ctx.ownerType, ctx.ownerId, action)
        end)
        if not ok or allowed ~= true then
            return false, reason or 'You no longer have access to this storage.'
        end
    end
    if not ctx or tostring(ctx.ownerType or '') ~= 'vehicle_trunk' then return true end
    if GetResourceState('cm-vehicles') ~= 'started' then
        return false, 'Vehicle access is unavailable.'
    end

    local vehicleId = tonumber(ctx.ownerId)
    if not vehicleId then return false, 'Invalid vehicle trunk.' end
    local ok, allowed = pcall(function()
        return exports['cm-vehicles']:CanUseVehicle(src, vehicleId, action)
    end)
    if not ok or allowed ~= true then
        return false, 'You no longer have access to this vehicle trunk.'
    end
    return true
end

local function moveFromPlayerToExternal(src, ctx, fromSlot, toSlot)
    dprint(('moveFromPlayerToExternal START src=%s from=%s to=%s ctx=%s/%s'):format(tostring(src), tostring(fromSlot), tostring(toSlot), tostring(ctx and ctx.ownerType), tostring(ctx and ctx.ownerId)))
    if ctx.canDeposit == false then return false, 'You cannot put items in this storage.' end
    local accessOk, accessErr = validateExternalMovementAccess(src, ctx, 'vehicle.trunk.deposit')
    if not accessOk then return false, accessErr end

    local ownerType, ownerId, ownerErr = getPlayerOwner(src)
    if not ownerId then return false, ownerErr end

    local storageSlot, slotErr = storageSlotForExternal(ctx, toSlot)
    if not storageSlot then return false, slotErr end
    if not isValidSlot(fromSlot) then
        dprint(('moveFromPlayerToExternal INVALID PLAYER SLOT from=%s owner=%s/%s'):format(tostring(fromSlot), tostring(ownerType), tostring(ownerId)))
        return false, 'Invalid player slot.'
    end

    local source = getItemAt(ownerType, ownerId, fromSlot)
    dprint(('moveFromPlayerToExternal SOURCE from=%s item=%s id=%s qty=%s storageSlot=%s'):format(tostring(fromSlot), tostring(source and source.item_name), tostring(source and source.id), tostring(source and source.quantity), tostring(storageSlot)))
    if not source then return false, 'Source slot is empty.' end

    local bagOk, bagErr = validateBagRemovalFromSlot(ownerType, ownerId, fromSlot, source)
    if not bagOk then return false, bagErr end

    local dest = getItemAt(ctx.ownerType, ctx.ownerId, storageSlot)

    if not dest then
        MySQL.update.await('UPDATE inventory_items SET owner_type = ?, owner_id = ?, slot = ? WHERE id = ?', {
            ctx.ownerType, tostring(ctx.ownerId), storageSlot, source.id
        })
        audit(ownerId, 'move_to_external', source.item_name, source.quantity, fromSlot, storageSlot, ctx.kind, decode(source.metadata))
        syncEquipmentSlot(src, fromSlot)
        dprint(('moveFromPlayerToExternal DB MOVE OK itemId=%s -> %s/%s:%s'):format(tostring(source.id), tostring(ctx.ownerType), tostring(ctx.ownerId), tostring(storageSlot)))
        return true
    end

    if sameStackableItem(source, dest) then
        MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ? WHERE id = ?', { source.quantity, dest.id })
        MySQL.update.await('DELETE FROM inventory_items WHERE id = ?', { source.id })
        audit(ownerId, 'merge_to_external', source.item_name, source.quantity, fromSlot, storageSlot, ctx.kind, decode(source.metadata))
        syncEquipmentSlot(src, fromSlot)
        return true
    end

    local canReceive, receiveErr = canPlayerReceiveRow(src, ownerType, ownerId, fromSlot, dest, source)
    if not canReceive then return false, receiveErr end

    local tempSlot = ('__tmp_ext_%s_%s'):format(source.id, math.random(1000, 9999))
    MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { tempSlot, source.id })
    MySQL.update.await('UPDATE inventory_items SET owner_type = ?, owner_id = ?, slot = ? WHERE id = ?', { ownerType, tostring(ownerId), fromSlot, dest.id })
    MySQL.update.await('UPDATE inventory_items SET owner_type = ?, owner_id = ?, slot = ? WHERE id = ?', { ctx.ownerType, tostring(ctx.ownerId), storageSlot, source.id })
    audit(ownerId, 'swap_to_external', source.item_name, source.quantity, fromSlot, storageSlot, ctx.kind, decode(source.metadata))
    syncEquipmentSlot(src, fromSlot)
    return true
end

local function moveFromExternalToPlayer(src, ctx, fromSlot, toSlot)
    if ctx.canWithdraw == false then return false, 'You cannot take items from this storage.' end
    local accessOk, accessErr = validateExternalMovementAccess(src, ctx, 'vehicle.trunk.withdraw')
    if not accessOk then return false, accessErr end

    local ownerType, ownerId, ownerErr = getPlayerOwner(src)
    if not ownerId then return false, ownerErr end

    local storageSlot, slotErr = storageSlotForExternal(ctx, fromSlot)
    if not storageSlot then return false, slotErr end
    if not isValidSlot(toSlot) then return false, 'Invalid player slot.' end
    if not isSlotUnlocked(ownerType, ownerId, toSlot) then return false, 'That backpack slot is locked by your bag level.' end

    local source = getItemAt(ctx.ownerType, ctx.ownerId, storageSlot)
    if not source then return false, 'Storage slot is empty.' end

    local dest = getItemAt(ownerType, ownerId, toSlot)
    local canReceive, receiveErr = canPlayerReceiveRow(src, ownerType, ownerId, toSlot, source, dest)
    if not canReceive then return false, receiveErr end

    if not dest then
        MySQL.update.await('UPDATE inventory_items SET owner_type = ?, owner_id = ?, slot = ? WHERE id = ?', {
            ownerType, tostring(ownerId), toSlot, source.id
        })
        audit(ownerId, 'take_from_external', source.item_name, source.quantity, storageSlot, toSlot, ctx.kind, decode(source.metadata))
        syncEquipmentSlot(src, toSlot)
        return true
    end

    if sameStackableItem(source, dest) then
        MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ? WHERE id = ?', { source.quantity, dest.id })
        MySQL.update.await('DELETE FROM inventory_items WHERE id = ?', { source.id })
        audit(ownerId, 'merge_from_external', source.item_name, source.quantity, storageSlot, toSlot, ctx.kind, decode(source.metadata))
        syncEquipmentSlot(src, toSlot)
        return true
    end

    local bagOk, bagErr = validateBagRemovalFromSlot(ownerType, ownerId, toSlot, dest)
    if not bagOk then return false, bagErr end

    local tempSlot = ('__tmp_ext_%s_%s'):format(source.id, math.random(1000, 9999))
    MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { tempSlot, source.id })
    MySQL.update.await('UPDATE inventory_items SET owner_type = ?, owner_id = ?, slot = ? WHERE id = ?', { ctx.ownerType, tostring(ctx.ownerId), storageSlot, dest.id })
    MySQL.update.await('UPDATE inventory_items SET owner_type = ?, owner_id = ?, slot = ? WHERE id = ?', { ownerType, tostring(ownerId), toSlot, source.id })
    audit(ownerId, 'swap_from_external', source.item_name, source.quantity, storageSlot, toSlot, ctx.kind, decode(source.metadata))
    syncEquipmentSlot(src, toSlot)
    return true
end

local function moveInsideExternal(src, ctx, fromSlot, toSlot)
    local fromStorageSlot, fromErr = storageSlotForExternal(ctx, fromSlot)
    local toStorageSlot, toErr = storageSlotForExternal(ctx, toSlot)
    if not fromStorageSlot then return false, fromErr end
    if not toStorageSlot then return false, toErr end
    if fromStorageSlot == toStorageSlot then return true end

    local source = getItemAt(ctx.ownerType, ctx.ownerId, fromStorageSlot)
    if not source then return false, 'Storage slot is empty.' end

    local dest = getItemAt(ctx.ownerType, ctx.ownerId, toStorageSlot)
    if not dest then
        MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { toStorageSlot, source.id })
        return true
    end

    if sameStackableItem(source, dest) then
        MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ? WHERE id = ?', { source.quantity, dest.id })
        MySQL.update.await('DELETE FROM inventory_items WHERE id = ?', { source.id })
        return true
    end

    local tempSlot = ('__tmp_ext_%s_%s'):format(source.id, math.random(1000, 9999))
    MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { tempSlot, source.id })
    MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { fromStorageSlot, dest.id })
    MySQL.update.await('UPDATE inventory_items SET slot = ? WHERE id = ?', { toStorageSlot, source.id })
    return true
end

local function MoveItemSmart(src, fromSlot, toSlot)
    src = tonumber(src)
    fromSlot = tostring(fromSlot or '')
    toSlot = tostring(toSlot or '')

    local ctx = ActiveExternalInventories[src]
    local fromExternal = false
    local toExternal = false

    if ctx then
        fromExternal = externalIndexForContext(ctx, fromSlot) ~= nil
        toExternal = externalIndexForContext(ctx, toSlot) ~= nil
    else
        fromExternal = isExternalUiSlot(fromSlot)
        toExternal = isExternalUiSlot(toSlot)
    end

    if not ctx and (fromExternal or toExternal) then
        dprint(('MoveItemSmart NO CTX src=%s from=%s fromExternal=%s to=%s toExternal=%s'):format(tostring(src), tostring(fromSlot), tostring(fromExternal), tostring(toSlot), tostring(toExternal)))
        return false, 'No external storage is open. Close inventory, open the trunk, then press I again.'
    end

    if not ctx then
        dprint(('MoveItemSmart NORMAL src=%s from=%s to=%s'):format(tostring(src), tostring(fromSlot), tostring(toSlot)))
    end

    if ctx then
        dprint(('external move ctx=%s/%s slots=%s display=%s from=%s fromExternal=%s to=%s toExternal=%s'):format(
            tostring(ctx.ownerType), tostring(ctx.ownerId), tostring(ctx.slots), tostring(ctx.displaySlots),
            tostring(fromSlot), tostring(fromExternal), tostring(toSlot), tostring(toExternal)
        ))
    end

    local movedRow, movement
    if ctx and not fromExternal and toExternal then
        local ownerType, ownerId = getPlayerOwner(src)
        if ownerId then movedRow, movement = getItemAt(ownerType, ownerId, fromSlot), 'deposit' end
    elseif ctx and fromExternal and not toExternal then
        local storageSlot = storageSlotForExternal(ctx, fromSlot)
        if storageSlot then movedRow, movement = getItemAt(ctx.ownerType, ctx.ownerId, storageSlot), 'withdraw' end
    end
    local ok, reason
    if not fromExternal and not toExternal then ok, reason = MoveItemInternal(src, fromSlot, toSlot)
    elseif not fromExternal and toExternal then ok, reason = moveFromPlayerToExternal(src, ctx, fromSlot, toSlot)
    elseif fromExternal and not toExternal then ok, reason = moveFromExternalToPlayer(src, ctx, fromSlot, toSlot)
    else ok, reason = moveInsideExternal(src, ctx, fromSlot, toSlot) end
    if ok and movedRow and movement and ctx.activityExport and ctx.resource ~= '' then
        pcall(function()
            exports[ctx.resource][ctx.activityExport](src, ctx.ownerType, ctx.ownerId, movement,
                tostring(movedRow.item_name), tonumber(movedRow.quantity) or 1)
        end)
    end
    return ok, reason
end

AddEventHandler('playerDropped', function()
    ActiveExternalInventories[tonumber(source)] = nil
end)
