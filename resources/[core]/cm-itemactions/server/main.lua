local ResourceName = GetCurrentResourceName()
local Registered = {}

local function registerUsable(itemName)
    itemName = tostring(itemName or ''):lower()

    if Registered[itemName] then
        return true
    end

    if GetResourceState('cm-inventory') ~= 'started' then
        print(('[CM-ITEMACTIONS] cm-inventory is not started yet for item: %s'):format(itemName))
        return false
    end

    -- Use colon style only. In this FiveM environment, dot style was causing a noisy failed first call.
    local ok, result = pcall(function()
        return exports['cm-inventory']:RegisterUseableItem(itemName, ResourceName, 'UseItem')
    end)

    if ok and result == true then
        Registered[itemName] = true
        print(('[CM-ITEMACTIONS] Registered usable item: %s'):format(itemName))
        return true
    end

    print(('[CM-ITEMACTIONS] Failed to register usable item: %s | ok=%s result=%s'):format(itemName, tostring(ok), tostring(result)))
    return false
end

local function result(success, removeAmount, message)
    return {
        success = success == true,
        remove = tonumber(removeAmount) or 0,
        message = message
    }
end

exports('UseItem', function(a, b, c, d)
    -- Normalize all common FiveM export call shapes.
    -- Expected/recommended: UseItem(itemName, src, item)
    -- Some environments/resources pass: UseItem(src, item)
    -- Colon-style may pass export table first: UseItem(self, itemName, src, item)
    local itemName, src, item

    if type(a) == 'table' and type(b) == 'string' then
        -- colon style with self table
        itemName = b
        src = c
        item = d
    elseif type(a) == 'string' then
        -- normal: itemName, src, item
        itemName = a
        src = b
        item = c
    elseif type(a) == 'number' and type(b) == 'table' then
        -- actual observed call on your server: src, item
        src = a
        item = b
        itemName = item.item_name or item.name or item.item or item.id
    elseif type(a) == 'table' and type(b) == 'number' and type(c) == 'table' then
        -- self table, src, item
        src = b
        item = c
        itemName = item.item_name or item.name or item.item or item.id
    else
        itemName = a
        src = b
        item = c
    end

    itemName = tostring(itemName or ''):lower()
    src = tonumber(src)

    if not src or src <= 0 then
        print(('[CM-ITEMACTIONS] UseItem invalid player. item=%s aType=%s a=%s bType=%s b=%s cType=%s c=%s dType=%s d=%s'):format(
            tostring(itemName), type(a), tostring(a), type(b), tostring(b), type(c), tostring(c), type(d), tostring(d)
        ))
        return result(false, 0, 'Invalid player.')
    end

    if itemName == '' or itemName == 'nil' then
        print(('[CM-ITEMACTIONS] UseItem invalid itemName. src=%s'):format(tostring(src)))
        return result(false, 0, 'Invalid item.')
    end

    if itemName == 'weapon_pistol' then
        return result(false, 0, 'Use weapon from inventory to equip it.')
    end

    if itemName == 'bandage' then
        TriggerClientEvent('cm-itemactions:client:heal', src, 25)
        return result(true, 1, 'You used a bandage.')
    end

    if itemName == 'medkit' then
        TriggerClientEvent('cm-itemactions:client:heal', src, 100)
        return result(true, 1, 'You used a medkit.')
    end

    if itemName == 'armor' then
        return result(false, 0, 'Use armor from inventory to equip it into the body armor slot.')
    end

    if itemName == 'water' then
        -- No hunger/thirst system. This is only an RP consume action.
        return result(true, 1, 'You drank water.')
    end

    if itemName == 'sandwich' then
        -- No hunger system. This is only an RP consume action.
        return result(true, 1, 'You ate a sandwich.')
    end

    if itemName == 'repairkit' then
        TriggerClientEvent('cm-itemactions:client:repairVehicle', src)
        return result(true, 1, 'You used a repair kit.')
    end

    if itemName == 'lockpick' then
        TriggerClientEvent('cm-itemactions:client:lockpickStart', src)
        return result(true, 1, 'You used a lockpick.')
    end

    if itemName == 'ammo_9mm' then
        return result(false, 0, 'Use ammo to move it into the ammo slot. It is consumed from inventory only when you shoot.')
    end

    if itemName == 'id_card' then
        TriggerClientEvent('cm-itemactions:client:showIdCard', src, item or {})
        return result(true, 0, 'You checked your ID card.')
    end

    return result(false, 0, 'No item action exists for ' .. itemName)
end)

local function registerAll()
    local items = {
        'weapon_pistol',
        'bandage',
        'medkit',
        'armor',
        'water',
        'sandwich',
        'repairkit',
        'lockpick',
        'id_card',
        'ammo_9mm'
    }

    for _, itemName in ipairs(items) do
        registerUsable(itemName)
    end
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'cm-inventory' or resourceName == ResourceName then
        CreateThread(function()
            Wait(750)
            registerAll()
        end)
    end
end)

CreateThread(function()
    for _ = 1, 30 do
        if GetResourceState('cm-inventory') == 'started' then
            Wait(750)
            registerAll()
            return
        end
        Wait(500)
    end

    print('[CM-ITEMACTIONS] cm-inventory did not start, usable items were not registered.')
end)
