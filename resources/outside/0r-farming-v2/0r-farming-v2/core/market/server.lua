local lib                             = lib

-- Dependencies
local Inventory                       = require "modules.inventory.server"

-- Delivery State
local pendingDeliveries               = {} -- [source] = deliveryData

-- Constants
local DEFAULT_DELIVERY_TIME <const>   = 60
local MIN_DELIVERY_TIME <const>       = 10
local DELIVERY_CHECK_INTERVAL <const> = 5000

local config                          = lib.load("core.market.config")

-- Market itemlerini type'a göre ayıran fonksiyonlar
local function getBuyItems()
    local buyItems = {}
    for _, item in pairs(config.items) do
        if item.type == nil or item.type == "buy" then
            table.insert(buyItems, item)
        end
    end
    return buyItems
end

local function getSellItems()
    local sellItems = {}
    for _, item in pairs(config.items) do
        if item.type == nil or item.type == "sell" then
            table.insert(sellItems, item)
        end
    end
    return sellItems
end

-- Utility Functions

---@param source number
---@param items table[]
local function givePlayerItems(source, items)
    for _, item in pairs(items) do
        Inventory.giveItem(source, item.itemName, item.count)
    end
end

---@param owner number
---@return table|false
local function getPlayerDelivery(owner)
    return pendingDeliveries[owner] or false
end

---@param owner number
---@return boolean
local function hasPlayerDelivery(owner)
    return pendingDeliveries[owner] ~= nil
end

---@param data table
---@return table
local function addPendingDelivery(data)
    local deliveryTime = math.max(MIN_DELIVERY_TIME, config.droneDelivery.time or DEFAULT_DELIVERY_TIME)
    data.endTime = GetGameTimer() + deliveryTime * 1000
    data.delivery_time = deliveryTime
    pendingDeliveries[data.owner] = data
    return data
end

local function getItemPrice(itemName)
    for _, item in pairs(config.items) do
        if item.itemName == itemName then
            return item.price
        end
    end

    return nil
end

local function getItemSellPrice(itemName)
    for _, item in pairs(config.items) do
        if item.itemName == itemName then
            return item.sellPrice
        end
    end

    return nil
end

-- Delivery Control Thread

Citizen.CreateThread(function()
    while true do
        local now = GetGameTimer()
        for owner, delivery in pairs(pendingDeliveries) do
            if delivery and not delivery.isDroneSpawned and delivery.endTime <= now then
                TriggerClientEvent(_e("client:market:spawnDeliveryDrone"), owner, delivery)
                delivery.isDroneSpawned = true
            end
        end
        Citizen.Wait(DELIVERY_CHECK_INTERVAL)
    end
end)

-- Callbacks

lib.callback.register(_e("server:market:payCart"), function(source, data)
    -- Sadece buy veya nil olan itemler alınabilir
    local validItems = getBuyItems()
    local validItemNames = {}
    for _, item in pairs(validItems) do
        validItemNames[item.itemName] = true
    end
    if hasPlayerDelivery(source) then
        return { error = locale("market.already_have_order") }
    end

    local paymentType = data.type
    local paymentAmount = 0
    local filteredCart = {}

    -- Check all items and calculate the paymentAmount including only those that are available.
    for _, item in pairs(data.items) do
        if not validItemNames[item.itemName] then
            return { error = locale("market.invalid_item", item.label or item.itemName) }
        end
        local itemPrice = getItemPrice(item.itemName)
        if not itemPrice then
            return { error = locale("market.invalid_item", item.label or item.itemName) }
        end
        local itemCount = math.max(1, math.min(100, item.count or 1))
        paymentAmount = paymentAmount + (itemPrice * item.count)
        table.insert(filteredCart, {
            itemName = item.itemName,
            count = itemCount,
            price = itemPrice
        })
    end

    local playerBalance = server.getPlayerBalance(source, paymentType)
    if playerBalance < paymentAmount then
        return { error = locale("dont_have_enough_money", paymentAmount) }
    end

    if paymentType == "cash" then
        if Config.CleanMoney.isItem then
            Inventory.removeItem(source, Config.CleanMoney.itemName, paymentAmount)
        elseif Config.CleanMoney.accountName then
            server.playerRemoveMoney(source, Config.CleanMoney.accountName, paymentAmount)
        end
    elseif paymentType == "bank" then
        server.playerRemoveMoney(source, "bank", paymentAmount)
    end

    local pendingDelivery = addPendingDelivery({ owner = source, items = filteredCart })

    return { pendingDelivery = pendingDelivery }
end)

lib.callback.register(_e("server:market:collectLootableBag"), function(source)
    local delivery = getPlayerDelivery(source)
    if not delivery then return false end
    if not delivery.isDroneSpawned then return false end

    TriggerClientEvent("farming-v2:client:market:onCustomerReceivedOrder", source, delivery.items)

    givePlayerItems(source, delivery.items)
    pendingDeliveries[source] = nil

    return true
end)

lib.callback.register(_e("server:market:getPlayerDelivery"), function(source)
    return getPlayerDelivery(source)
end)

lib.callback.register(_e("server:market:sellItems"), function(source, data)
    local itemsToSell = data.items
    if not itemsToSell or #itemsToSell == 0 then
        return { error = locale("market.no_items_to_sell") }
    end

    -- Sadece sell veya nil olan itemler satılabilir
    local validItems = getSellItems()
    local validItemNames = {}
    for _, item in pairs(validItems) do
        validItemNames[item.itemName] = true
    end

    local totalSaleValue = 0
    for _, item in pairs(itemsToSell) do
        if not validItemNames[item.itemName] then
            return { error = locale("market.invalid_item", item.label or item.itemName) }
        end
        if item.count <= 0 then
            return { error = locale("market.invalid_item_count", item.label or item.itemName) }
        end
        if not Inventory.hasItem(source, item.itemName, item.count) then
            return { error = locale("market.dont_have_enough_item", item.label or item.itemName) }
        end
        local itemPrice = getItemSellPrice(item.itemName)
        if not itemPrice then
            return { error = locale("market.invalid_item", item.label or item.itemName) }
        end
        totalSaleValue = totalSaleValue + (itemPrice * item.count)
    end

    if totalSaleValue <= 0 then
        return { error = locale("market.no_items_to_sell") }
    end

    for _, item in pairs(itemsToSell) do
        Inventory.removeItem(source, item.itemName, item.count)
    end

    if Config.CleanMoney.isItem then
        Inventory.giveItem(source, Config.CleanMoney.itemName, totalSaleValue)
    else
        server.playerAddMoney(source, Config.CleanMoney.accountName, totalSaleValue)
    end

    return { success = true }
end)
