-- cm-inventory/drops.lua
-- Split from legacy server/main.lua. Loaded by server/main.lua bootloader in this exact order.

local function UseItemInternal(src, slot)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(slot) then return false, 'Invalid slot.' end

    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false, 'Slot is empty.' end

    local item = rowToItem(row)
    local itemName = tostring(item.item_name or ''):lower()
    local ammoSlot = (Config.Ammo and Config.Ammo.slot) or 'ammo'

    -- USE bag first. `clothing_bags` is both clothing and a real backpack, so bag capacity
    -- must be resolved before the generic clothing branch catches it.
    if isBagItemName(itemName) then
        if slot ~= 'bag' then
            local moved, moveErr = MoveItemInternal(src, slot, 'bag')
            if not moved then return false, moveErr or 'Could not equip bag.' end
        else
            syncEquipmentSlot(src, 'bag')
            saveAppearance(src)
        end
        local bag = getBagInfo(ownerType, ownerId)
        notify(src, ('%s equipped. Backpack slots: %s / %s'):format(bag.label, bag.backpackSlots, Config.Slots.backpack.count), 'success')
        audit(ownerId, 'use_bag', itemName, 1, slot, 'bag', 'equip_bag', item.metadata)
        return true
    end

    -- USE clothing = move it to the matching clothing/equipment slot. Dragging to that slot uses the same visual equip logic.
    if isClothingItemName(itemName) then
        local targetSlot = getClothingEquipSlot(itemName, item.metadata)
        if not targetSlot then return false, 'This clothing category has no inventory slot.' end

        if slot ~= targetSlot then
            local moved, moveErr = MoveItemInternal(src, slot, targetSlot)
            if not moved then return false, moveErr or 'Could not equip clothing.' end
        else
            TriggerClientEvent('cm-inventory:client:equipClothingFromItem', src, targetSlot, item)
            saveAppearance(src)
        end

        notify(src, ('Equipped %s.'):format(item.label or itemName), 'success')
        audit(ownerId, 'use_clothing', itemName, 1, slot, targetSlot, 'equip_clothing_slot', item.metadata)
        return true
    end

    -- USE weapon = equip weapon slot, then move the first matching ammo stack into ammo slot.
    -- Ammo is NOT consumed on use/reload. It is consumed only from inventory when the player shoots.
    if isWeaponItemName(itemName) then
        local moved, moveErr = MoveItemInternal(src, slot, 'weapon')
        if not moved then return false, moveErr or 'Could not equip weapon.' end
        syncEquipmentSlot(src, 'weapon')

        local ammoReady, ammoMsg = EnsureAmmoSlotForWeaponInternal(src)
        if ammoReady then
            notify(src, ('Weapon equipped. %s'):format(ammoMsg or ''), 'success')
        else
            notify(src, ('Weapon equipped. %s'):format(ammoMsg or 'No ammo moved.'), 'info')
        end

        audit(ownerId, 'use_weapon', itemName, 1, slot, 'weapon', 'use_weapon_inventory_ammo', item.metadata)
        return true
    end

    -- USE armor = equip into the body armor slot and apply armor on the character.
    -- Armor item is not deleted; it becomes equipped in the bodyarmor slot.
    if isArmorItemName(itemName) then
        if slot ~= 'bodyarmor' then
            local moved, moveErr = MoveItemInternal(src, slot, 'bodyarmor')
            if not moved then return false, moveErr or 'Could not equip armor.' end
        end

        syncEquipmentSlot(src, 'bodyarmor')
        notify(src, 'Body armor equipped.', 'success')
        audit(ownerId, 'use_armor', itemName, 1, slot, 'bodyarmor', 'use_armor_equip', item.metadata)
        return true
    end

    -- USE ammo = move ammo to ammo slot only. It does not reload or consume ammo.
    if isAmmoItemName(itemName) then
        if slot ~= ammoSlot then
            local moved, moveErr = MoveItemInternal(src, slot, ammoSlot)
            if not moved then return false, moveErr or 'Could not move ammo to ammo slot.' end
            notify(src, ('Moved %s to ammo slot.'):format(item.label or itemName), 'success')
            audit(ownerId, 'use_ammo_move_to_slot', itemName, tonumber(row.quantity) or 1, slot, ammoSlot, 'use_ammo', item.metadata)
            return true
        end

        notify(src, 'Ammo is ready in ammo slot. It will be used from inventory when you shoot.', 'info')
        return true
    end

    local handler = UseableItems[itemName]

    if item.usable ~= true and not handler then
        return false, 'Item is not usable.'
    end

    if not handler then
        notify(src, (item.label or itemName) .. ' has no use effect registered yet.', 'info')
        return true
    end

    local success, consumeAmount, message = runUsableHandler(src, itemName, item, handler)

    if not success then
        return false, message or 'Item use failed.'
    end

    consumeAmount = tonumber(consumeAmount) or 0
    if consumeAmount > 0 then
        local consumed, consumeErr = ConsumeSlotItemInternal(src, slot, consumeAmount, 'use_consume')
        if not consumed then return false, consumeErr or 'Could not consume item.' end
    end

    audit(ownerId, 'use', itemName, consumeAmount > 0 and consumeAmount or 1, slot, nil, 'use_item', item.metadata)
    TriggerEvent('cm-inventory:server:itemUsed', src, item, consumeAmount)

    if message and message ~= '' then
        notify(src, message, 'success')
    end

    return true
end

ReloadWeaponInternal = function(src)
    -- Reload key is intentionally disabled for this RP inventory system.
    -- Ammo is kept in inventory and consumed one-by-one when the player shoots.
    return false, 'Manual reload is disabled. Ammo is used from inventory while shooting.'
end

local function ConsumeEquippedWeaponAmmoInternal(src)
    if Config.Ammo and Config.Ammo.enabled == false then
        return false, 'Ammo system is disabled.'
    end

    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end

    local ammoSlot = (Config.Ammo and Config.Ammo.slot) or 'ammo'
    local weaponCfg, weaponName, cfgErr = getEquippedWeaponAmmoConfig(ownerType, ownerId)
    if not weaponCfg then return false, cfgErr or 'No weapon ammo config.' end

    local requiredAmmo = tostring(weaponCfg.ammo or ''):lower()
    if requiredAmmo == '' then return false, 'Weapon ammo type is missing.' end

    local ammoRow = getItemAt(ownerType, ownerId, ammoSlot)
    if not ammoRow or tostring(ammoRow.item_name or ''):lower() ~= requiredAmmo then
        return false, ('%s is not in ammo slot.'):format(requiredAmmo)
    end

    local available = tonumber(ammoRow.quantity) or 0
    if available <= 0 then return false, 'No ammo available.' end

    local weaponRow = getItemAt(ownerType, ownerId, 'weapon')
    if weaponRow then
        local wmeta = decode(weaponRow.metadata)
        local durability = tonumber(wmeta.durability) or tonumber((getItemDef(weaponRow.item_name) or {}).durability) or 100
        if durability <= 0 then return false, 'Weapon durability is 0%.' end
    end

    local consumed, consumeErr = ConsumeSlotItemInternal(src, ammoSlot, 1, 'weapon_shot')
    if not consumed then return false, consumeErr or 'Could not consume ammo.' end

    reduceSlotDurability(ownerType, ownerId, 'weapon', 1)
    audit(ownerId, 'weapon_shot', requiredAmmo, 1, ammoSlot, 'weapon', weaponName, {})
    return true, 'Ammo consumed from inventory.'
end

local function getClosestPlayer(src, maxDistance)
    maxDistance = tonumber(maxDistance) or 3.0
    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return nil, nil end

    local srcCoords = GetEntityCoords(srcPed)
    local closest, closestDist = nil, maxDistance + 0.01

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and target ~= tonumber(src) then
            local targetPed = GetPlayerPed(target)
            if targetPed and targetPed ~= 0 then
                local targetCoords = GetEntityCoords(targetPed)
                local dx = srcCoords.x - targetCoords.x
                local dy = srcCoords.y - targetCoords.y
                local dz = srcCoords.z - targetCoords.z
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist < closestDist then
                    closest = target
                    closestDist = dist
                end
            end
        end
    end

    return closest, closestDist
end

local function GiveItemInternal(src, slot, amount)
    if Config.Give and Config.Give.enabled == false then return false, 'Giving items is disabled.' end

    amount = tonumber(amount) or 1
    if amount < 1 then return false, 'Invalid amount.' end

    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(slot) then return false, 'Invalid slot.' end

    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false, 'Slot is empty.' end

    local available = tonumber(row.quantity) or 1
    if amount > available then return false, 'Not enough items.' end

    local target, distance = getClosestPlayer(src, (Config.Give and Config.Give.distance) or 3.0)
    if not target then return false, 'No nearby player found.' end

    local metadata = decode(row.metadata)
    local targetOwnerType, targetOwnerId = getOwner(target)
    if not targetOwnerId then return false, 'Nearby player has no active character.' end

    local carryOk, carryReason = canCarry(targetOwnerType, targetOwnerId, row.item_name, amount)
    if not carryOk then return false, 'Receiver cannot carry item: ' .. tostring(carryReason) end

    local consumed, consumeErr = ConsumeSlotItemInternal(src, slot, amount, 'give_item')
    if not consumed then return false, consumeErr or 'Could not remove item.' end

    local added, addReason = AddItemInternal(target, row.item_name, amount, metadata, 'received_from_player')
    if not added then
        -- rollback to sender where possible
        AddItemInternal(src, row.item_name, amount, metadata, 'give_rollback')
        return false, addReason or 'Could not give item.'
    end

    audit(ownerId, 'give_item', row.item_name, amount, slot, nil, ('to_player_%s'):format(target), metadata)
    audit(targetOwnerId, 'receive_item', row.item_name, amount, nil, nil, ('from_player_%s'):format(src), metadata)

    notify(src, ('Gave %sx %s.'):format(amount, row.item_name), 'success')
    notify(target, ('Received %sx %s.'):format(amount, row.item_name), 'success')
    sendInventorySmart(src)
    sendInventorySmart(target)
    return true
end



-- =========================================================
-- Dev give-transfer self-test helpers
-- Lets one developer test the same remove/add transfer logic
-- without needing a second player online.
-- =========================================================
local function AddItemToOwnerContainer(ownerType, ownerId, itemName, amount, metadata, reason, preferredSlot)
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then return false, 'Invalid amount.' end

    ownerType = tostring(ownerType or '')
    ownerId = tostring(ownerId or '')
    itemName = tostring(itemName or ''):lower()
    metadata = type(metadata) == 'table' and metadata or {}

    if ownerType == '' or ownerId == '' then return false, 'Invalid target container.' end

    local allowed, err = isInventoryItem(itemName)
    if not allowed then return false, err end

    local def = getItemDef(itemName)
    if not def then return false, 'Unknown item.' end

    local okCarry, carryErr = canCarry(ownerType, ownerId, itemName, amount)
    if not okCarry then return false, carryErr end

    local slot = preferredSlot
    if slot and not canPlaceInSlot(itemName, slot) then slot = nil end

    if def.stack ~= false and next(metadata) == nil and not slot then
        local existing = MySQL.single.await([[SELECT * FROM inventory_items
            WHERE owner_type = ? AND owner_id = ? AND item_name = ? AND (metadata IS NULL OR metadata = '' OR metadata = '{}')
            ORDER BY FIELD(SUBSTRING_INDEX(slot, '-', 1), 'pocket', 'backpack', 'quickaccess') LIMIT 1]], {
            ownerType, ownerId, itemName
        })
        if existing then
            MySQL.update.await('UPDATE inventory_items SET quantity = quantity + ? WHERE id = ?', { amount, existing.id })
            audit(ownerId, 'dev_add_stack', itemName, amount, nil, existing.slot, reason or 'dev_test_add', metadata)
            return true, existing.slot
        end
    end

    if not slot then slot = findEmptySlot(ownerType, ownerId) end
    if not slot then return false, 'No empty slot in test receiver.' end

    local canSlot, slotErr = canPlaceInSlot(itemName, slot)
    if not canSlot then return false, slotErr end

    local existingAtSlot = getItemAt(ownerType, ownerId, slot)
    if existingAtSlot then return false, 'Slot is already occupied.' end

    MySQL.insert.await([[INSERT INTO inventory_items
        (owner_type, owner_id, slot, item_name, quantity, metadata)
        VALUES (?, ?, ?, ?, ?, ?)]], {
        ownerType, ownerId, slot, itemName, amount, encode(metadata)
    })
    audit(ownerId, 'dev_add', itemName, amount, nil, slot, reason or 'dev_test_add', metadata)
    return true, slot
end

local function GetFirstPlayerItemByName(src, itemName)
    itemName = tostring(itemName or ''):lower()
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return nil, 'No character owner found.' end

    local row = MySQL.single.await([[SELECT * FROM inventory_items
        WHERE owner_type = ? AND owner_id = ? AND item_name = ?
        ORDER BY quantity DESC, id ASC LIMIT 1]], {
        ownerType, tostring(ownerId), itemName
    })

    if not row then return nil, 'You do not have ' .. itemName end
    return row, ownerId
end

local function DevGiveTestInternal(src, itemName, amount)
    if not src or src <= 0 then return false, 'Use this in-game from F8.' end
    itemName = tostring(itemName or 'water'):lower()
    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then return false, 'Invalid amount.' end

    local row, ownerIdOrReason = GetFirstPlayerItemByName(src, itemName)
    if not row then return false, ownerIdOrReason end

    local available = tonumber(row.quantity) or 0
    if available < amount then return false, ('You only have %sx %s.'):format(available, itemName) end

    local metadata = decode(row.metadata)
    local removed, removeReason = RemoveItemInternal(src, itemName, amount, metadata, 'dev_givetest_remove')
    if not removed then return false, removeReason or 'Could not remove item from player.' end

    local testOwnerType = 'test_receiver'
    local testOwnerId = 'dev_receiver_1'
    local added, addReason = AddItemToOwnerContainer(testOwnerType, testOwnerId, itemName, amount, metadata, 'dev_givetest_add')
    if not added then
        AddItemInternal(src, itemName, amount, metadata, 'dev_givetest_refund')
        return false, 'Test receiver add failed, item refunded: ' .. tostring(addReason)
    end

    audit(ownerIdOrReason, 'dev_give_test_out', itemName, amount, nil, nil, testOwnerType .. '/' .. testOwnerId, metadata)
    audit(testOwnerId, 'dev_give_test_in', itemName, amount, nil, nil, 'from_player_' .. tostring(src), metadata)
    return true, ('Give test success: moved %sx %s to test_receiver/dev_receiver_1.'):format(amount, itemName)
end

local function ShowTestReceiverInternal(src)
    local rows = MySQL.query.await([[SELECT slot, item_name, quantity, metadata FROM inventory_items
        WHERE owner_type = ? AND owner_id = ? ORDER BY slot ASC]], { 'test_receiver', 'dev_receiver_1' }) or {}

    if #rows == 0 then
        local msg = 'Test receiver is empty.'
        if src and src > 0 then notify(src, msg, 'info') end
        print('[CM-INVENTORY] ' .. msg)
        return rows
    end

    print('[CM-INVENTORY] Test receiver contents:')
    local brief = {}
    for _, row in ipairs(rows) do
        local line = ('%s: %sx %s'):format(row.slot, tonumber(row.quantity) or 0, row.item_name)
        print('[CM-INVENTORY]   ' .. line)
        brief[#brief + 1] = line
    end

    if src and src > 0 then
        notify(src, ('Test receiver: %s'):format(table.concat(brief, ' | ')), 'info')
    end
    return rows
end

local function ClearTestReceiverInternal(src)
    local affected = MySQL.update.await('DELETE FROM inventory_items WHERE owner_type = ? AND owner_id = ?', {
        'test_receiver', 'dev_receiver_1'
    }) or 0
    local msg = ('Cleared test receiver. Removed %s rows.'):format(tostring(affected))
    print('[CM-INVENTORY] ' .. msg)
    if src and src > 0 then notify(src, msg, 'success') end
    return true
end

local function dropToPayload(row)
    local def = getItemDef(row.item_name) or { label = row.item_name, image = 'placeholder.png', weight = 0, category = 'misc' }
    local metadata = decode(row.metadata)
    return {
        id = tonumber(row.id),
        item_name = row.item_name,
        name = row.item_name,
        label = def.label or row.item_name,
        image = metadata.image or metadata.icon or def.image or def.icon or 'placeholder.png',
        icon = metadata.icon or metadata.image or def.image or def.icon or 'placeholder.png',
        quantity = tonumber(row.quantity) or 1,
        weight = tonumber(def.weight) or 0,
        category = def.category or def.type or 'misc',
        metadata = metadata,
        coords = { x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z) }
    }
end

cleanupDrops = function()
    MySQL.update.await('DELETE FROM inventory_drops WHERE expires_at IS NOT NULL AND expires_at <= NOW()', {})
end

local function getActiveDrops()
    cleanupDrops()
    local rows = MySQL.query.await('SELECT * FROM inventory_drops WHERE expires_at IS NULL OR expires_at > NOW() ORDER BY id DESC LIMIT 250', {}) or {}
    local drops = {}
    for _, row in ipairs(rows) do drops[#drops + 1] = dropToPayload(row) end
    return drops
end

sendDrops = function(target)
    TriggerClientEvent('cm-inventory:client:updateDrops', target or -1, getActiveDrops())
end

createWorldDrop = function(src, row, amount)
    if not Config.Drops or Config.Drops.enabled == false then return nil end
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local ownerType, ownerId = getOwner(src)
    local expireMinutes = tonumber(Config.Drops.expireMinutes) or 10
    local id = MySQL.insert.await([[INSERT INTO inventory_drops
        (item_name, quantity, metadata, x, y, z, created_by, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? MINUTE))]], {
        row.item_name,
        amount,
        row.metadata or '{}',
        coords.x,
        coords.y,
        coords.z - 0.9,
        tostring(ownerId or ownerType or src),
        expireMinutes
    })
    return id
end

local function PickupDropInternal(src, dropId)
    dropId = tonumber(dropId)
    if not dropId then return false, 'Invalid drop.' end

    cleanupDrops()
    local row = MySQL.single.await('SELECT * FROM inventory_drops WHERE id = ? AND (expires_at IS NULL OR expires_at > NOW()) LIMIT 1', { dropId })
    if not row then return false, 'Drop no longer exists.' end

    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local dx, dy, dz = coords.x - tonumber(row.x), coords.y - tonumber(row.y), coords.z - tonumber(row.z)
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist > (tonumber(Config.Drops.pickupDistance) or 2.0) + 1.0 then
        return false, 'You are too far from the drop.'
    end

    local metadata = decode(row.metadata)
    local ok, reason = AddItemInternal(src, row.item_name, tonumber(row.quantity) or 1, metadata, 'pickup_drop')
    if not ok then return false, reason end

    MySQL.update.await('DELETE FROM inventory_drops WHERE id = ?', { dropId })
    local _, ownerId = getOwner(src)
    audit(ownerId, 'pickup_drop', row.item_name, tonumber(row.quantity) or 1, nil, nil, 'pickup_drop', metadata)
    sendDrops(-1)
    return true
end

notify = function(src, message, typeName)
    TriggerClientEvent('cm-inventory:client:notify', src, tostring(message or ''), typeName or 'info')
end

RegisterNetEvent('cm-inventory:server:openInventory', function()
    local src = source
    CloseExternalInventoryInternal(src)
    sendInventorySmart(src, true)
end)

RegisterNetEvent('cm-inventory:server:closeInventory', function()
    CloseExternalInventoryInternal(source)
end)

RegisterNetEvent('cm-inventory:server:debugPing', function()
    dprint(('debugPing received from player %s'):format(source))
end)

RegisterNetEvent('cm-inventory:server:requestDrops', function()
    sendDrops(source)
end)

RegisterNetEvent('cm-inventory:server:requestEquipment', function()
    syncAllEquipment(source)
end)

RegisterNetEvent('cm-inventory:server:pickupDrop', function(dropId)
    local src = source
    local ok, reason = PickupDropInternal(src, dropId)
    if ok then
        notify(src, 'Picked up item.', 'success')
        sendInventorySmart(src)
    else
        notify(src, reason or 'Could not pick up drop.', 'error')
        sendDrops(src)
    end
end)


RegisterNetEvent('cm-inventory:server:armorChanged', function(armorValue)
    local src = source
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return end
    local ok, newDur = setSlotDurability(ownerType, ownerId, 'bodyarmor', tonumber(armorValue) or 0)
    if ok then
        audit(ownerId, 'armor_durability_update', 'armor', 1, 'bodyarmor', 'bodyarmor', tostring(newDur), { durability = newDur })
        sendInventorySmart(src)
    end
end)

RegisterNetEvent('cm-inventory:server:debugGiveItem', function(itemName, amount)
    local src = source
    amount = tonumber(amount) or 1
    itemName = tostring(itemName or 'water'):lower()
    dprint(('debugGiveItem called by player %s: %sx %s'):format(src, amount, itemName))
    local ok, reason = AddItemInternal(src, itemName, amount, {}, 'debug_testgive')
    if ok then
        dprint(('debugGiveItem added %sx %s to player %s'):format(amount, itemName, src))
        notify(src, ('Added %sx %s'):format(amount, itemName), 'success')
        sendInventorySmart(src)
    else
        dprint(('debugGiveItem failed for player %s item=%s reason=%s'):format(src, itemName, tostring(reason)))
        notify(src, 'Failed: ' .. tostring(reason), 'error')
    end
end)


RegisterNetEvent('cm-inventory:server:setDebug', function(enabled)
    Config.Debug = enabled == true or enabled == 1 or enabled == '1' or tostring(enabled):lower() == 'true'
    print(('[CM-INVENTORY] Debug toggled by player %s: %s'):format(tostring(source), Config.Debug and 'ON' or 'OFF'))
end)

RegisterNetEvent('cm-inventory:server:uiDebug', function(data)
    if not Config.Debug then return end
    local ok, encoded = pcall(json.encode, data or {})
    print(('[CM-INVENTORY][UI-DEBUG][src=%s] %s'):format(tostring(source), ok and encoded or tostring(data)))
end)

RegisterNetEvent('cm-inventory:server:moveItem', function(data)
    local src = source
    data = type(data) == 'table' and data or {}

    local function truthy(v)
        return v == true or v == 1 or v == '1' or tostring(v):lower() == 'true'
    end

    local function slotFromExternalFlag(slot, flag, idx)
        slot = tostring(slot or ''):gsub('^%s+', ''):gsub('%s+$', '')
        if truthy(flag) then
            local n = tonumber(idx)
            if n and n >= 1 then return 'external-' .. tostring(math.floor(n)) end
        end
        return slot
    end

    local rawFromSlot = tostring(data.fromSlot or '')
    local rawToSlot = tostring(data.toSlot or '')
    local rawFromExternal = data.fromExternal
    local rawToExternal = data.toExternal
    local rawFromIndex = data.fromIndex
    local rawToIndex = data.toIndex

    local fromSlot = slotFromExternalFlag(data.fromSlot, data.fromExternal, data.fromIndex)
    local toSlot = slotFromExternalFlag(data.toSlot, data.toExternal, data.toIndex)

    -- Defensive compatibility: if an external storage is open and a future/old UI sends
    -- trunk-1, storage_1, etc., normalize it back to external-1 before validation.
    local ctx = ActiveExternalInventories and ActiveExternalInventories[tonumber(src)] or nil
    local ctxFromIdx, ctxToIdx = nil, nil
    if ctx then
        ctxFromIdx = externalIndexForContext(ctx, fromSlot)
        ctxToIdx = externalIndexForContext(ctx, toSlot)
        if ctxFromIdx then fromSlot = 'external-' .. tostring(ctxFromIdx) end
        if ctxToIdx then toSlot = 'external-' .. tostring(ctxToIdx) end
    end

    if Config.Debug then
        local okJson, encoded = pcall(json.encode, data or {})
        dprint(('MOVE RAW src=%s payload=%s'):format(tostring(src), okJson and encoded or tostring(data)))
        dprint(('MOVE NORMALIZED src=%s raw=%s -> %s flags=%s/%s idx=%s/%s ctx=%s ctxInfo=%s/%s prefix=%s slots=%s ctxIdx=%s/%s final=%s -> %s'):format(
            tostring(src), tostring(rawFromSlot), tostring(rawToSlot), tostring(rawFromExternal), tostring(rawToExternal),
            tostring(rawFromIndex), tostring(rawToIndex), tostring(ctx ~= nil), tostring(ctx and ctx.ownerType), tostring(ctx and ctx.ownerId),
            tostring(ctx and ctx.slotPrefix), tostring(ctx and ctx.slots), tostring(ctxFromIdx), tostring(ctxToIdx), tostring(fromSlot), tostring(toSlot)
        ))
    end

    dprint(('moveItem requested by player %s: %s -> %s'):format(src, fromSlot, toSlot))
    local ok, reason = MoveItemSmart(src, fromSlot, toSlot)
    if ok then
        dprint(('moveItem success for player %s: %s -> %s'):format(src, fromSlot, toSlot))
        notify(src, 'Item moved.', 'success')
    else
        dprint(('moveItem failed for player %s: %s -> %s reason=%s'):format(src, fromSlot, toSlot, tostring(reason)))
        if Config.Debug then
            notify(src, ('DEBUG MOVE FAIL | from=%s to=%s | ctx=%s | reason=%s'):format(tostring(fromSlot), tostring(toSlot), tostring(ctx ~= nil), tostring(reason)), 'error')
        else
            notify(src, reason or 'Move failed.', 'error')
        end
    end
    sendInventorySmart(src)
end)

RegisterNetEvent('cm-inventory:server:splitItem', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local ok, reason = SplitItemInternal(src, tostring(data.fromSlot or ''), tostring(data.toSlot or ''), tonumber(data.amount) or 0)
    if not ok then notify(src, reason or 'Split failed.', 'error') end
    sendInventorySmart(src)
end)
