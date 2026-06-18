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


local CLOTHING_CATEGORIES = {
    tshirt   = { type = 'component', index = 8,  label = 'T-Shirt' },
    torso    = { type = 'component', index = 11, label = 'Torso' },
    pants    = { type = 'component', index = 4,  label = 'Pants' },
    legs     = { type = 'component', index = 4,  label = 'Pants' },
    shoes    = { type = 'component', index = 6,  label = 'Shoes' },
    chains   = { type = 'component', index = 7,  label = 'Chain' },
    bags     = { type = 'component', index = 5,  label = 'Bag' },
    hat      = { type = 'prop',      index = 0,  label = 'Hat' },
    glasses  = { type = 'prop',      index = 1,  label = 'Glasses' },
    earrings = { type = 'prop',      index = 2,  label = 'Earrings' },
    watches  = { type = 'prop',      index = 6,  label = 'Watch' },
}

local ClothingSwapRequests = {}
local ClothingReqCounter = 0

local function notify(src, msg, typ)
    TriggerClientEvent('cm-hud:client:notify', src, tostring(msg or ''), typ or 'info')
end

local function isClothingItem(itemName)
    return tostring(itemName or ''):find('clothing_', 1, true) == 1
end

local function clothingCategoryFromItem(itemName, metadata)
    local category = tostring((metadata and (metadata.categoryType or metadata.category)) or ''):lower()
    if category == '' then
        category = tostring(itemName or ''):lower():gsub('^clothing_', '')
    end
    return category
end

local function buildTakenOffMetadata(itemName, category, oldData)
    local def = CLOTHING_CATEGORIES[category]
    if not def then return nil end
    oldData = type(oldData) == 'table' and oldData or {}

    return {
        categoryType = category,
        componentType = def.type,
        componentIndex = def.index,
        drawableId = tonumber(oldData.drawableId or oldData.drawable) or 0,
        textureId = tonumber(oldData.textureId or oldData.texture) or 0,
        arms = tonumber(oldData.arms),
        armsTexture = tonumber(oldData.armsTexture) or 0,
        undershirt = tonumber(oldData.undershirt),
        undershirtTexture = tonumber(oldData.undershirtTexture) or 0,
        label = ('Old %s'):format(def.label),
        description = ('Clothing taken off: %s'):format(def.label),
        itemType = 'clothing',
        rarity = 'normal',
        swappedAt = os.date('!%Y-%m-%dT%H:%M:%SZ')
    }
end

local function startClothingSwap(src, itemName, item)
    local metadata = type(item) == 'table' and type(item.metadata) == 'table' and item.metadata or {}
    local category = clothingCategoryFromItem(itemName, metadata)
    local def = CLOTHING_CATEGORIES[category]

    if not def then
        return result(false, 0, 'This clothing category is not supported.')
    end

    local drawable = tonumber(metadata.drawableId or metadata.drawable)
    local texture = tonumber(metadata.textureId or metadata.texture or 0)
    if drawable == nil then
        return result(false, 0, 'This clothing item has no drawable metadata.')
    end

    ClothingReqCounter = ClothingReqCounter + 1
    local requestId = ('%s:%s:%s'):format(src, GetGameTimer(), ClothingReqCounter)

    metadata.categoryType = category
    metadata.componentType = def.type
    metadata.componentIndex = def.index
    metadata.drawableId = drawable
    metadata.textureId = texture or 0

    ClothingSwapRequests[requestId] = {
        src = src,
        itemName = itemName,
        metadata = metadata,
        created = GetGameTimer()
    }

    TriggerClientEvent('cm-itemactions:client:swapClothing', src, requestId, itemName, metadata)
    return result(true, 0, 'Changing clothing...')
end

RegisterNetEvent('cm-itemactions:server:clothingSwapComplete', function(requestId, payload)
    local src = source
    requestId = tostring(requestId or '')
    local pending = ClothingSwapRequests[requestId]
    if not pending or tonumber(pending.src) ~= tonumber(src) then return end
    ClothingSwapRequests[requestId] = nil

    payload = type(payload) == 'table' and payload or {}
    if payload.success ~= true then
        notify(src, payload.message or 'Could not change clothing.', 'error')
        return
    end

    local category = clothingCategoryFromItem(pending.itemName, pending.metadata)
    local removed = exports['cm-inventory']:RemoveItem(src, pending.itemName, 1, pending.metadata, 'clothing_swap_remove_new')
    if removed ~= true then
        notify(src, 'Could not remove clothing item from inventory.', 'error')
        return
    end

    local oldMeta = buildTakenOffMetadata(pending.itemName, category, payload.old)
    if oldMeta then
        exports['cm-inventory']:AddItem(src, 'clothing_' .. category, 1, oldMeta, 'clothing_swap_return_old')
    end

    if GetResourceState('cm-characters') == 'started' then
        exports['cm-characters']:SaveAppearance(src)
    end

    notify(src, 'Clothing equipped. Previous clothing returned to inventory.', 'success')
end)



CreateThread(function()
    while true do
        Wait(60000)
        local now = GetGameTimer()
        for requestId, data in pairs(ClothingSwapRequests) do
            if now - (data.created or now) > 120000 then
                ClothingSwapRequests[requestId] = nil
            end
        end
    end
end)

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

    if isClothingItem(itemName) then
        return startClothingSwap(src, itemName, item or {})
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

RegisterNetEvent('cm-itemactions:server:saveAppearance', function()
    local src = source
    if GetResourceState('cm-characters') == 'started' then
        exports['cm-characters']:SaveAppearance(src)
    end
end)

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
