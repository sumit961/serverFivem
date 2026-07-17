-- cm-inventory/events.lua
-- Split from legacy server/main.lua. Loaded by server/main.lua bootloader in this exact order.

RegisterNetEvent('cm-inventory:server:dropItem', function(data)
    local src = source
    if isPlayerDeadState(src) then return end
    data = type(data) == 'table' and data or {}
    local ok, reason = DropItemInternal(src, tostring(data.slot or ''), tonumber(data.amount) or 1)
    if not ok then notify(src, reason or 'Drop failed.', 'error') end
    sendInventorySmart(src)
end)

local UseCooldowns = {}

local function getUseProgress(itemName)
    itemName = tostring(itemName or ''):lower()
    local cfg = Config.Use or {}
    local progress = cfg.progress and cfg.progress[itemName]
    if type(progress) == 'table' then
        return tonumber(progress.ms) or 0, progress.label or 'Using item...'
    end
    return tonumber(cfg.defaultProgressMs) or 0, 'Using item...'
end

local function checkUseCooldown(src, itemName)
    itemName = tostring(itemName or ''):lower()
    local cfg = Config.Use or {}
    local cooldown = cfg.cooldowns and cfg.cooldowns[itemName] or cfg.defaultCooldownMs or 0
    cooldown = tonumber(cooldown) or 0
    if cooldown <= 0 then return true end

    local key = tostring(src) .. ':' .. itemName
    local now = GetGameTimer()
    local untilTime = UseCooldowns[key] or 0
    if untilTime > now then
        return false, ('Wait %.1fs before using this again.'):format((untilTime - now) / 1000)
    end
    UseCooldowns[key] = now + cooldown
    return true
end

local function UseItemWithProgress(src, slot)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    if not isValidSlot(slot) then return false, 'Invalid slot.' end
    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false, 'Slot is empty.' end
    local itemName = tostring(row.item_name or ''):lower()

    local cdOk, cdMsg = checkUseCooldown(src, itemName)
    if not cdOk then return false, cdMsg end

    local progressMs, progressLabel = getUseProgress(itemName)
    if progressMs > 0 then
        TriggerClientEvent('cm-inventory:client:useProgress', src, progressLabel, progressMs)
        Wait(progressMs)
    end

    return UseItemInternal(src, slot)
end

RegisterNetEvent('cm-inventory:server:useItem', function(data)
    local src = source
    if isPlayerDeadState(src) then return end
    data = type(data) == 'table' and data or {}
    local ok, reason = UseItemWithProgress(src, tostring(data.slot or ''))
    if not ok then notify(src, reason or 'Use failed.', 'error') end
    sendInventorySmart(src)
end)


local function quickSlotFromIndex(index)
    index = math.floor(tonumber(index) or 0)
    local maxQuick = Config.Slots and Config.Slots.quick and tonumber(Config.Slots.quick.count) or 5
    if index < 1 or index > maxQuick then return nil end
    return (Config.Slots.quick.prefix or 'quickaccess-') .. tostring(index), index
end

local function QuickAccessHotkeyInternal(src, index, weaponInHand)
    local quickSlot = quickSlotFromIndex(index)
    if not quickSlot then return false, 'Invalid fast access slot.' end

    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end

    local quickRow = getItemAt(ownerType, ownerId, quickSlot)
    local weaponRow = getItemAt(ownerType, ownerId, 'weapon')
    local quickIsWeapon = quickRow and isWeaponItemName(quickRow.item_name)
    local weaponIsEquipped = weaponRow and isWeaponItemName(weaponRow.item_name)

    -- 1) Fast slot has a gun: draw/swap that gun into the weapon equipment slot.
    --    If another gun is currently in-hand, it is swapped back into the pressed fast slot.
    if quickIsWeapon then
        local moved, moveErr = MoveItemInternal(src, quickSlot, 'weapon')
        if not moved then return false, moveErr or 'Could not equip fast access gun.' end

        local ammoReady, ammoMsg = EnsureAmmoSlotForWeaponInternal(src)
        if syncCurrentWeaponAmmo then syncCurrentWeaponAmmo(src) end

        if weaponIsEquipped or weaponInHand == true then
            notify(src, ammoReady and ('Changed weapon. ' .. tostring(ammoMsg or '')) or ('Changed weapon. ' .. tostring(ammoMsg or 'No matching ammo found.')), ammoReady and 'success' or 'info')
        else
            notify(src, ammoReady and ('Weapon equipped. ' .. tostring(ammoMsg or '')) or ('Weapon equipped. ' .. tostring(ammoMsg or 'No matching ammo found.')), ammoReady and 'success' or 'info')
        end
        return true
    end

    -- 2) Gun is physically in hand and pressed fast slot is empty: put the gun away into that slot.
    --    If the pressed fast slot has another gun this case is handled above. Non-gun items are protected.
    if weaponInHand == true and weaponIsEquipped then
        if quickRow then
            return false, 'Fast slot must be empty or contain another gun to store/change your weapon.'
        end

        local moved, moveErr = MoveItemInternal(src, 'weapon', quickSlot)
        if not moved then return false, moveErr or 'Could not store weapon.' end
        if syncCurrentWeaponAmmo then syncCurrentWeaponAmmo(src) end
        notify(src, ('Weapon stored in fast slot %s.'):format(tostring(index)), 'success')
        return true
    end

    -- 3) Normal fast access item use. Weapons never use directly from a fast slot; they first move to gun slot.
    if quickRow then
        return UseItemWithProgress(src, quickSlot)
    end

    return false, 'Fast access slot is empty.'
end

RegisterNetEvent('cm-inventory:server:quickAccessHotkey', function(data)
    local src = source
    if isPlayerDeadState(src) then return end
    data = type(data) == 'table' and data or {}
    local ok, reason = QuickAccessHotkeyInternal(src, data.index or data.slotIndex or data.hotkey, data.weaponInHand == true)
    if not ok then notify(src, reason or 'Fast access failed.', 'error') end
    sendInventorySmart(src)
end)

RegisterNetEvent('cm-inventory:server:reloadWeapon', function()
    local src = source
    if isPlayerDeadState(src) then return end
    local ok, reason = ReloadWeaponInternal(src)
    if ok then
        notify(src, reason or 'Weapon reloaded.', 'success')
    else
        notify(src, reason or 'Reload failed.', 'error')
    end
    sendInventorySmart(src)
end)

RegisterNetEvent('cm-inventory:server:weaponShot', function()
    local src = source
    if isPlayerDeadState(src) then return end
    local ok, reason = ConsumeEquippedWeaponAmmoInternal(src)
    if not ok then
        TriggerClientEvent('cm-inventory:client:noInventoryAmmo', src, reason or 'No ammo available.')
        return
    end
    sendInventorySmart(src)
end)

RegisterNetEvent('cm-inventory:server:giveItem', function(data)
    local src = source
    if isPlayerDeadState(src) then return end
    data = type(data) == 'table' and data or {}
    local ok, reason = GiveItemInternal(src, tostring(data.slot or ''), tonumber(data.amount) or 1)
    if not ok then
        notify(src, reason or 'Give failed.', 'error')
        sendInventorySmart(src)
    end
end)


RegisterNetEvent('cm-inventory:server:devGiveTest', function(itemName, amount)
    local src = source
    local ok, message = DevGiveTestInternal(src, itemName, amount)
    if ok then
        dprint(message)
        notify(src, message, 'success')
        sendInventorySmart(src)
    else
        dprint(('givetest failed for player %s item=%s reason=%s'):format(src, tostring(itemName), tostring(message)))
        notify(src, 'Give test failed: ' .. tostring(message), 'error')
    end
end)

RegisterNetEvent('cm-inventory:server:showTestReceiver', function()
    if not Config.Debug then return end
    ShowTestReceiverInternal(source)
end)

RegisterNetEvent('cm-inventory:server:clearTestReceiver', function()
    if not Config.Debug then return end
    ClearTestReceiverInternal(source)
end)

RegisterCommand('giveitem', function(src, args)
    if src <= 0 then print('[CM-INVENTORY] Use invgive from server console.') return end
    local itemName = tostring(args[1] or 'water'):lower()
    local amount = tonumber(args[2]) or 1
    local ok, reason = AddItemInternal(src, itemName, amount, {}, 'command_giveitem')
    if ok then
        dprint(('/giveitem added %sx %s to player %s'):format(amount, itemName, src))
        notify(src, ('Added %sx %s'):format(amount, itemName), 'success')
        sendInventorySmart(src)
    else
        dprint(('/giveitem failed for player %s item=%s reason=%s'):format(src, itemName, tostring(reason)))
        notify(src, 'Failed: ' .. tostring(reason), 'error')
    end
end, false)

RegisterCommand('invgive', function(src, args)
    if src ~= 0 then return end
    local target = tonumber(args[1])
    local itemName = tostring(args[2] or 'water'):lower()
    local amount = tonumber(args[3]) or 1
    if not target then print('Usage: invgive <serverId> <item> <amount>') return end
    local ok, reason = AddItemInternal(target, itemName, amount, {}, 'console_invgive')
    if ok then
        print(('[CM-INVENTORY] Console gave %sx %s to %s'):format(amount, itemName, target))
        notify(target, ('Added %sx %s'):format(amount, itemName), 'success')
        sendInventorySmart(target)
    else
        print(('[CM-INVENTORY] invgive failed: %s'):format(tostring(reason)))
    end
end, true)



RegisterCommand('givebag', function(src, args)
    if src <= 0 then print('[CM-INVENTORY] Use invgivebag from server console.') return end
    local level = math.max(1, math.min(4, math.floor(tonumber(args[1]) or 1)))
    local itemName = tostring(args[2] or 'clothing_bags'):lower()
    local metadata = { bagLevel = level, categoryType = 'bags', itemType = 'clothing', label = ('Level %s Bag'):format(level) }
    local ok, reason = AddItemInternal(src, itemName, 1, metadata, 'command_givebag')
    if ok then
        print(('[CM-INVENTORY] /givebag added %s with bagLevel=%s to player %s'):format(itemName, level, src))
        notify(src, ('Added Level %s bag'):format(level), 'success')
        sendInventorySmart(src)
    else
        print(('[CM-INVENTORY] /givebag failed player=%s item=%s level=%s reason=%s'):format(src, itemName, level, tostring(reason)))
        notify(src, 'Failed: ' .. tostring(reason), 'error')
    end
end, false)

RegisterCommand('invgivebag', function(src, args)
    if src ~= 0 then return end
    local target = tonumber(args[1])
    local level = math.max(1, math.min(4, math.floor(tonumber(args[2]) or 1)))
    local itemName = tostring(args[3] or 'clothing_bags'):lower()
    if not target then print('Usage: invgivebag <serverId> <bagLevel 1-4> [itemName]') return end
    local metadata = { bagLevel = level, categoryType = 'bags', itemType = 'clothing', label = ('Level %s Bag'):format(level) }
    local ok, reason = AddItemInternal(target, itemName, 1, metadata, 'console_invgivebag')
    if ok then
        print(('[CM-INVENTORY] invgivebag gave %s level=%s to %s'):format(itemName, level, target))
        notify(target, ('Added Level %s bag'):format(level), 'success')
        sendInventorySmart(target)
    else
        print(('[CM-INVENTORY] invgivebag failed: %s'):format(tostring(reason)))
    end
end, true)

RegisterCommand('invgivetest', function(src, args)
    if not Config.Debug then return end
    if src ~= 0 then return end
    local target = tonumber(args[1])
    local itemName = tostring(args[2] or 'water'):lower()
    local amount = tonumber(args[3]) or 1
    if not target then
        print('Usage: invgivetest <serverId> <item> <amount>')
        return
    end
    local ok, message = DevGiveTestInternal(target, itemName, amount)
    print(('[CM-INVENTORY] invgivetest result: %s | %s'):format(tostring(ok), tostring(message)))
    if target > 0 then sendInventorySmart(target) end
end, true)

RegisterCommand('invshowtest', function(src)
    if not Config.Debug then return end
    if src ~= 0 then return end
    ShowTestReceiverInternal(0)
end, true)

RegisterCommand('invcleartest', function(src)
    if not Config.Debug then return end
    if src ~= 0 then return end
    ClearTestReceiverInternal(0)
end, true)

RegisterCommand('refreshgear', function(src)
    if src <= 0 then return end
    syncAllEquipment(src)
    notify(src, 'Equipment refreshed.', 'success')
end, false)
