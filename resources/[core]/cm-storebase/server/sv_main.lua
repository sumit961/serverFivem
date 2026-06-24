local Stores = {}
local ResourceStores = {}

local function debugPrint(...)
    if CMStoreBase.Config.Debug then
        print('^3[cm-storebase]^7', ...)
    end
end

local function deepCopy(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function coordsToTable(coords)
    if type(coords) == 'vector3' or type(coords) == 'vector4' then
        return { x = coords.x, y = coords.y, z = coords.z, w = coords.w or coords.heading or 0.0 }
    end

    if type(coords) == 'table' then
        return {
            x = coords.x or coords[1] or 0.0,
            y = coords.y or coords[2] or 0.0,
            z = coords.z or coords[3] or 0.0,
            w = coords.w or coords.h or coords.heading or coords[4] or 0.0
        }
    end

    return { x = 0.0, y = 0.0, z = 0.0, w = 0.0 }
end

local function normalizeTier(tier)
    tier = tostring(tier or 'normal'):lower()
    if tier == 'cheap' then tier = 'normal' end
    if tier ~= 'high' and tier ~= 'normal' and tier ~= 'low' then tier = 'normal' end
    return tier
end

local function getEffectiveTier(store)
    if CMStoreBase.Config.ForceHighPriceWhenUnowned and not store.owner then
        return 'high'
    end
    return normalizeTier(store.priceTier or store.pricingTier or 'normal')
end

local function getItemPrice(store, item)
    local tier = getEffectiveTier(store)

    if type(item.prices) == 'table' then
        return tonumber(item.prices[tier] or item.prices.normal or item.prices.high or item.price or 0) or 0, tier
    end

    return tonumber(item.price or 0) or 0, tier
end

local function findItem(store, itemName)
    for index, item in ipairs(store.items or {}) do
        if item.name == itemName then
            return item, index
        end
    end
    return nil, nil
end

local function sanitizeStoreForClient(store)
    local safe = deepCopy(store)
    safe.coords = coordsToTable(store.coords)
    safe.effectivePriceTier = getEffectiveTier(store)

    for _, item in ipairs(safe.items or {}) do
        local original = findItem(store, item.name)
        local price = 0
        if original then price = getItemPrice(store, original) end

        item.price = price
        item.effectivePriceTier = safe.effectivePriceTier
        item.image = item.image or item.icon or CMStoreBase.Config.DefaultImage
        item.prices = nil -- client should never decide final price
    end

    return safe
end

local function syncStore(storeId)
    local store = Stores[storeId]
    if not store then return end
    TriggerClientEvent('cm-storebase:client:updateStore', -1, storeId, sanitizeStoreForClient(store))
end

local function syncAllToPlayer(src)
    local payload = {}
    for storeId, store in pairs(Stores) do
        payload[storeId] = sanitizeStoreForClient(store)
    end
    TriggerClientEvent('cm-storebase:client:setStores', src, payload)
end

local function mergeDefaults(store)
    store.pointDistance = tonumber(store.pointDistance or store.radius or CMStoreBase.Config.DefaultPointDistance) or 2.0
    store.drawDistance = tonumber(store.drawDistance or CMStoreBase.Config.DefaultDrawDistance) or 12.0
    store.ped = store.ped or deepCopy(CMStoreBase.Config.DefaultPed)
    store.blip = store.blip or deepCopy(CMStoreBase.Config.DefaultBlip)
    return store
end

local function normalizeStore(resourceName, store)
    assert(type(store) == 'table', 'store must be a table')
    assert(store.id, 'store.id is required')
    assert(store.coords, ('store %s requires coords'):format(store.id))

    store = deepCopy(store)
    store.resourceName = resourceName
    store.type = store.type or 'npc'
    store.owner = store.owner or nil
    store.vault = tonumber(store.vault or store.vaultBalance or 0) or 0
    store.priceTier = normalizeTier(store.priceTier or store.pricingTier or 'normal')
    store.items = store.items or {}
    store.pendingOrders = store.pendingOrders or {}
    store = mergeDefaults(store)

    for _, item in ipairs(store.items) do
        item.stock = tonumber(item.stock or 0) or 0
        item.maxStock = tonumber(item.maxStock or item.max or 999999) or 999999
        item.metadata = item.metadata or {}
        item.image = item.image or item.icon or CMStoreBase.Config.DefaultImage
    end

    return store
end

exports('RegisterStores', function(resourceName, storesTable)
    assert(type(resourceName) == 'string', 'resourceName must be a string')
    assert(type(storesTable) == 'table', 'storesTable must be a table')

    ResourceStores[resourceName] = ResourceStores[resourceName] or {}

    for _, rawStore in ipairs(storesTable) do
        local store = normalizeStore(resourceName, rawStore)
        Stores[store.id] = store
        ResourceStores[resourceName][store.id] = true
        debugPrint(('registered %s from %s'):format(store.id, resourceName))
        syncStore(store.id)
    end

    TriggerClientEvent('cm-storebase:client:requestFullSync', -1)
    return true
end)

exports('UpdateStoreData', function(storeId, key, value)
    local store = Stores[storeId]
    if not store then return false, 'store_not_found' end

    if key == 'priceTier' or key == 'pricingTier' then
        key = 'priceTier'
        value = normalizeTier(value)
    end

    if key == 'coords' then value = coordsToTable(value) end

    store[key] = value
    syncStore(storeId)
    return true
end)

exports('DeliverStock', function(storeId, itemsArray)
    local store = Stores[storeId]
    if not store then return false, 'store_not_found' end
    if type(itemsArray) ~= 'table' then return false, 'invalid_items_array' end

    for _, delivered in ipairs(itemsArray) do
        local name = delivered.name
        local qty = tonumber(delivered.quantity or delivered.amount or 0) or 0

        if name and qty > 0 then
            local remaining = qty
            for i = #store.pendingOrders, 1, -1 do
                local order = store.pendingOrders[i]
                if order.name == name and remaining > 0 then
                    local orderQty = tonumber(order.quantity or order.amount or 0) or 0
                    local removeQty = math.min(orderQty, remaining)
                    order.quantity = orderQty - removeQty
                    remaining = remaining - removeQty
                    if order.quantity <= 0 then table.remove(store.pendingOrders, i) end
                end
            end

            local item = findItem(store, name)
            if item then
                item.stock = math.min((item.stock or 0) + qty, item.maxStock or 999999)
            else
                table.insert(store.items, {
                    name = name,
                    label = delivered.label or name,
                    stock = qty,
                    maxStock = delivered.maxStock or 999999,
                    prices = delivered.prices or { high = delivered.price or 0, normal = delivered.price or 0, low = delivered.price or 0 },
                    metadata = delivered.metadata or {},
                    image = delivered.image or delivered.icon or CMStoreBase.Config.DefaultImage
                })
            end
        end
    end

    syncStore(storeId)
    TriggerEvent('cm-storebase:server:onStockDelivered', storeId, deepCopy(itemsArray))
    return true
end)

lib.callback.register('cm-storebase:server:getStoreData', function(source, storeId)
    local store = Stores[storeId]
    if not store then return { success = false, error = 'Store not found' } end
    return { success = true, store = sanitizeStoreForClient(store) }
end)

lib.callback.register('cm-storebase:server:purchaseItem', function(source, storeId, itemName, quantity)
    quantity = math.floor(tonumber(quantity or 1) or 1)
    if quantity < 1 then quantity = 1 end
    if quantity > 100 then quantity = 100 end

    local store = Stores[storeId]
    if not store then return { success = false, error = 'Store not found' } end

    local item = findItem(store, itemName)
    if not item then return { success = false, error = 'Item not found' } end

    local stock = tonumber(item.stock or 0) or 0
    if stock < quantity then return { success = false, error = 'Not enough stock' } end

    local unitPrice = getItemPrice(store, item)
    local total = unitPrice * quantity
    if total <= 0 then return { success = false, error = 'Invalid price' } end

    local paid = CMStoreBase.Config.ServerAdapters.RemoveMoney(source, total, store.currency or 'cash')
    if not paid then return { success = false, error = 'Not enough money' } end

    local added = CMStoreBase.Config.ServerAdapters.AddItem(source, item.name, quantity, item.metadata or {})
    if not added then
        TriggerEvent('cm-storebase:server:onPurchaseFailedAfterPayment', source, storeId, item.name, quantity, total)
        return { success = false, error = 'Could not add item' }
    end

    item.stock = stock - quantity

    local purchaseItem = {
        name = item.name,
        label = item.label or item.name,
        quantity = quantity,
        unitPrice = unitPrice,
        total = total,
        metadata = item.metadata or {}
    }

    TriggerEvent('cm-storebase:server:onPurchase', storeId, store.owner, purchaseItem, total)
    syncStore(storeId)

    return { success = true, message = 'Purchase successful', store = sanitizeStoreForClient(store) }
end)

RegisterNetEvent('cm-storebase:server:requestFullSync', function()
    syncAllToPlayer(source)
end)

AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(1500, function() syncAllToPlayer(src) end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    if not ResourceStores[resourceName] then return end

    for storeId in pairs(ResourceStores[resourceName]) do
        Stores[storeId] = nil
        TriggerClientEvent('cm-storebase:client:removeStore', -1, storeId)
    end

    ResourceStores[resourceName] = nil
end)
