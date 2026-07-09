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

-- ============================================================
-- Data-driven item actions.
-- Behaviour lives in the item's catalog metadata (cm-items), so admins can add
-- a new usable item from a store/admin UI with an `action` block and it just
-- works -- no code edits here. Example catalog metadata:
--   metadata = { action = { type = 'consume', anim = 'drink', heal = 15,
--                           message = 'You drank an energy drink.' } }
-- ============================================================

local function toBool(value, default)
    if value == nil then return default end
    return value == true or value == 1 or value == '1' or value == 'true'
end

-- Action-type handlers. Signature: (src, def, action, item) -> result table.
-- Other resources can add their own types via exports RegisterActionType.
local Handlers = {}

-- Custom events receive (src, item, action) so client handlers that read the
-- item stack (e.g. id_card -> item.metadata) keep working.
Handlers.consume = function(src, def, a, item)
    if tonumber(a.heal) then TriggerClientEvent('cm-itemactions:client:heal', src, tonumber(a.heal)) end
    if a.anim then TriggerClientEvent('cm-itemactions:client:playActionAnim', src, a.anim, tonumber(a.duration) or 900) end
    if a.client_event then TriggerClientEvent(a.client_event, src, item or {}, a) end
    if a.server_event then TriggerEvent(a.server_event, src, item or {}, a) end
    local remove = toBool(a.consume, true) and (math.max(1, math.floor(tonumber(a.amount) or 1))) or 0
    return result(true, remove, a.message or ('You used ' .. ((def and def.label) or 'the item') .. '.'))
end

Handlers.heal = function(src, def, a)
    TriggerClientEvent('cm-itemactions:client:heal', src, tonumber(a.amount) or 25)
    return result(true, toBool(a.consume, true) and 1 or 0, a.message or 'You used a healing item.')
end

Handlers.anim = function(src, def, a)
    TriggerClientEvent('cm-itemactions:client:playActionAnim', src, a.anim or 'use', tonumber(a.duration) or 900)
    return result(true, toBool(a.consume, true) and 1 or 0, a.message)
end

Handlers.event = function(src, def, a, item)
    if a.server_event then TriggerEvent(a.server_event, src, item or {}, a) end
    if a.client_event then TriggerClientEvent(a.client_event, src, item or {}, a) end
    return result(true, toBool(a.consume, false) and 1 or 0, a.message)
end

Handlers.notify = function(src, def, a)
    return result(true, toBool(a.consume, false) and 1 or 0, a.message or 'You used the item.')
end

exports('RegisterActionType', function(actionType, fn)
    actionType = tostring(actionType or ''):lower()
    if actionType == '' or type(fn) ~= 'function' then return false end
    Handlers[actionType] = fn
    return true
end)

-- ============================================================
-- Code-defined item functions (the primary model).
-- The behaviour of an item lives in CODE, in the resource that owns the mechanic:
--   cm-playerdata  -> heal / revive items
--   a vehicle res  -> repair kit
--   a fuel res     -> jerry can
-- Each of those calls, once, at startup:
--   exports['cm-itemactions']:RegisterItem('medkit', function(src, item, name)
--       ... do the work ...
--       return { success = true, remove = 1, message = 'You used a medkit.' }
--   end)
-- Items with no registered function (and no built-in below) cannot be used.
-- ============================================================
local ItemHandlers = {}

exports('RegisterItem', function(itemName, handler)
    itemName = tostring(itemName or ''):lower()
    if itemName == '' or type(handler) ~= 'function' then return false end
    ItemHandlers[itemName] = handler
    -- Make sure the inventory routes this item's "use" to us.
    pcall(function()
        if GetResourceState('cm-inventory') == 'started' then
            exports['cm-inventory']:RegisterUseableItem(itemName, GetCurrentResourceName(), 'UseItem')
        end
    end)
    return true
end)

exports('UnregisterItem', function(itemName)
    itemName = tostring(itemName or ''):lower()
    if itemName == '' then return false end
    ItemHandlers[itemName] = nil
    return true
end)

-- Legacy built-in items kept working exactly as before, expressed as data so the
-- dispatch path is uniform. Used only when a catalog item has no action defined.
local LegacyActions = {
    bandage   = { type = 'heal', amount = 25,  message = 'You used a bandage.' },
    medkit    = { type = 'heal', amount = 100, message = 'You used a medkit.' },
    water     = { type = 'consume', anim = 'use', message = 'You drank water.' },
    sandwich  = { type = 'consume', anim = 'use', message = 'You ate a sandwich.' },
    repairkit = { type = 'consume', client_event = 'cm-itemactions:client:repairVehicle', message = 'You used a repair kit.' },
    lockpick  = { type = 'consume', client_event = 'cm-itemactions:client:lockpickStart', message = 'You used a lockpick.' },
    id_card   = { type = 'event',   client_event = 'cm-itemactions:client:showIdCard', consume = false, message = 'You checked your ID card.' },
}

-- Items whose "use" is intentionally handled elsewhere (equip flow), not consumed.
local function equipOnlyMessage(itemName)
    if itemName:find('weapon_', 1, true) == 1 or itemName == 'weapon' then
        return 'Use the weapon from your inventory to equip it.'
    elseif itemName:find('ammo_', 1, true) == 1 or itemName == 'ammo' then
        return 'Move ammo to the ammo slot. It is consumed only when you shoot.'
    elseif itemName == 'armor' or itemName == 'bodyarmor' then
        return 'Use armor from your inventory to equip it into the body armor slot.'
    end
    return nil
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

    -- Clothing keeps its dedicated swap flow.
    if isClothingItem(itemName) then
        return startClothingSwap(src, itemName, item or {})
    end

    -- Weapon/ammo/armor are equipped, not "used" -- keep the informative message.
    local equipMsg = equipOnlyMessage(itemName)
    if equipMsg then
        return result(false, 0, equipMsg)
    end

    -- 1) Code-defined function registered by a domain resource (the main path).
    local handler = ItemHandlers[itemName]
    if handler then
        local ok, res = pcall(handler, src, item, itemName)
        if ok and type(res) == 'table' then return res end
        if ok and res == true then return result(true, 1) end
        if ok and res == false then return result(false, 0, 'You cannot use this item right now.') end
        print(('[CM-ITEMACTIONS] item handler error for %s: %s'):format(itemName, tostring(res)))
        return result(false, 0, 'This item could not be used right now.')
    end

    -- 2) Built-in items defined in code (in this resource). Move these into the
    --    owning resource with RegisterItem whenever you want; that overrides here.
    local action = LegacyActions[itemName]
    if type(action) == 'table' then
        local h = Handlers[tostring(action.type or ''):lower()]
        if h then
            local ok, res = pcall(h, src, nil, action, item)
            if ok and type(res) == 'table' then return res end
        end
    end

    -- 3) No function anywhere -> it just sits in the inventory.
    return result(false, 0, 'You cannot use this item.')
end)

-- Legacy built-ins that must always be usable even before the catalog loads.
local BaseUsable = {
    'weapon_pistol', 'bandage', 'medkit', 'armor', 'water',
    'sandwich', 'repairkit', 'lockpick', 'id_card',
    -- Fixed cm-weapons ammo items. These are equip-only/use-to-move items;
    -- inventory consumes one round only when a weapon fires.
    'ammo_9mm', 'ammo_44magnum', 'ammo_9x19_smg', 'ammo_556nato',
    'ammo_762nato', 'ammo_12gauge', 'ammo_308win'
}

-- Register every item that is flagged usable, from both the static definitions
-- and the dynamic cm-items catalog, so newly created store items become usable
-- without editing this resource.
local function registerAll()
    for _, itemName in ipairs(BaseUsable) do
        registerUsable(itemName)
    end
    -- Items whose behaviour was registered in code by a domain resource.
    for name in pairs(ItemHandlers) do
        registerUsable(name)
    end

    if GetResourceState('cm-items') ~= 'started' then return end
    local items
    local ok = pcall(function() items = exports['cm-items']:GetAllItems() end)
    if not ok or type(items) ~= 'table' then return end

    for name, def in pairs(items) do
        if type(def) == 'table' and def.usable == true then
            registerUsable(name)
        end
    end
end

-- Register a single item on demand when the catalog changes at runtime.
local function registerOne(name)
    name = tostring(name or ''):lower()
    if name == '' then return end
    registerUsable(name)
end

-- cm-items fires these when an admin/store creates or reloads catalog items.
AddEventHandler('cm-items:server:catalogItemSaved', function(name, def)
    if type(def) == 'table' and def.usable == false then return end
    registerOne(name)
end)

AddEventHandler('cm-items:server:catalogReloaded', function()
    CreateThread(function() Wait(250); registerAll() end)
end)

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
