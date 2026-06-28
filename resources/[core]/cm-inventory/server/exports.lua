-- cm-inventory/exports.lua
-- Split from legacy server/main.lua. Loaded by server/main.lua bootloader in this exact order.

exports('AddItem', function(...)
    local src, itemName, amount, metadata, reason, slot = normalizeExportArgs(...)
    local ok, placedSlotOrReason = AddItemInternal(src, itemName, amount, metadata, reason, slot)

    -- If another resource adds directly into an equipment slot, immediately apply it
    -- and refresh the UI. This is used by starter character clothes.
    if ok and src and tonumber(src) and tonumber(src) > 0 then
        local placedSlot = tostring(placedSlotOrReason or '')
        if isEquipmentSlot(placedSlot) then
            syncEquipmentSlot(tonumber(src), placedSlot)
        end
        sendInventory(tonumber(src))
    end

    return ok, placedSlotOrReason
end)

exports('RemoveItem', function(...)
    local src, itemName, amount, metadata, reason = normalizeExportArgs(...)
    return RemoveItemInternal(src, itemName, amount, metadata, reason)
end)

exports('MoveItem', function(...)
    local src, fromSlot, toSlot = normalizeExportArgs(...)
    return MoveItemInternal(src, tostring(fromSlot or ''), tostring(toSlot or ''))
end)

exports('HasItem', function(...)
    local src, itemName, amount = normalizeExportArgs(...)
    return HasItemInternal(src, itemName, amount)
end)

exports('CanCarryItem', function(...)
    local src, itemName, amount = normalizeExportArgs(...)
    local ownerType, ownerId = getOwner(src)
    if not ownerId then return false, 'No character owner found.' end
    return canCarry(ownerType, ownerId, itemName, amount)
end)

exports('GetInventory', function(...)
    local src = normalizeExportArgs(...)
    return buildInventoryPayload(src)
end)


exports('GiveItemToNearby', function(...)
    local src, slot, amount = normalizeExportArgs(...)
    return GiveItemInternal(src, tostring(slot or ''), tonumber(amount) or 1)
end)

exports('CreateUseableItem', function(...)
    -- Same-resource/local function support only. Cross-resource Lua callbacks are unreliable in FiveM exports.
    local itemName, cb = normalizeExportArgs(...)

    if type(itemName) == 'string' and type(cb) == 'function' then
        UseableItems[itemName:lower()] = cb
        print(('[CM-INVENTORY] Usable item registered with function: %s'):format(itemName:lower()))
        return true
    end

    print(('[CM-INVENTORY] CreateUseableItem failed. Use RegisterUseableItem(resource, export) for cross-resource items. itemName=%s cbType=%s'):format(tostring(itemName), type(cb)))
    return false
end)

exports('ReloadWeapon', function(...)
    local src = normalizeExportArgs(...)
    return ReloadWeaponInternal(src)
end)

exports('RegisterUseableItem', function(...)
    -- Recommended cross-resource registration:
    -- exports['cm-inventory'].RegisterUseableItem('bandage', 'cm-itemactions', 'UseItem')
    -- exports['cm-inventory']:RegisterUseableItem('bandage', 'cm-itemactions', 'UseItem')
    local itemName, resourceName, exportName = normalizeExportArgs(...)

    if type(itemName) ~= 'string' or itemName == '' then
        print('[CM-INVENTORY] RegisterUseableItem failed: invalid itemName')
        return false
    end

    if type(resourceName) ~= 'string' or resourceName == '' then
        print(('[CM-INVENTORY] RegisterUseableItem failed for %s: invalid resourceName'):format(itemName))
        return false
    end

    if type(exportName) ~= 'string' or exportName == '' then
        print(('[CM-INVENTORY] RegisterUseableItem failed for %s: invalid exportName'):format(itemName))
        return false
    end

    UseableItems[itemName:lower()] = {
        resource = resourceName,
        export = exportName
    }

    print(('[CM-INVENTORY] Usable item registered: %s -> %s.%s'):format(itemName:lower(), resourceName, exportName))
    return true
end)

CreateThread(function()
    math.randomseed(os.time())
    ensureTables()
    cleanupDrops()
    sendDrops(-1)
    print('[CM-INVENTORY] Started v4.0-exportfix')
end)
