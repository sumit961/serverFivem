local Config = CMFarming.Config
CMFarming.Server = CMFarming.Server or {}

local PLAYERDATA = 'cm-playerdata'
local INVENTORY = 'cm-inventory'

local function dbg(...)
    if Config.Debug then print('[CM-FARMING]', ...) end
end

local function notify(src, message, kind)
    TriggerClientEvent('cm-farming:client:notify', src, tostring(message or ''), kind or 'info')
end

-- ---------------------------------------------------------------------------
-- cm-playerdata bridge
-- ---------------------------------------------------------------------------

local function playerData()
    if GetResourceState(PLAYERDATA) ~= 'started' then return nil end
    return exports[PLAYERDATA]
end

local function getMeta(src, key, default)
    local api = playerData()
    if not api then return default end
    local ok, value = pcall(function() return api:GetMetadata(src, key) end)
    if ok and value ~= nil then return value end
    return default
end

local function setMeta(src, key, value)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:SetMetadata(src, key, value) end)
    return ok and result == true
end

local function addCash(src, amount, reason)
    local api = playerData()
    if not api then return false end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    local ok, result = pcall(function() return api:AddCash(src, amount, reason) end)
    return ok and result == true
end

local function removeCash(src, amount, reason)
    local api = playerData()
    if not api then return false end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    local ok, result = pcall(function() return api:RemoveCash(src, amount, reason) end)
    return ok and result == true
end

local function getCash(src)
    local api = playerData()
    if not api then return 0 end
    local ok, amount = pcall(function() return api:GetCash(src) end)
    if ok and type(amount) == 'number' then return math.floor(amount) end
    return 0
end

-- ---------------------------------------------------------------------------
-- cm-inventory bridge
-- ---------------------------------------------------------------------------

local function inventoryApi()
    if GetResourceState(INVENTORY) ~= 'started' then return nil end
    return exports[INVENTORY]
end

local function hasItem(src, itemName, amount)
    local api = inventoryApi()
    if not api then return false, 0 end
    local ok, has, count = pcall(function() return api:HasItem(src, itemName, amount or 1) end)
    if not ok then return false, 0 end
    return has == true, count or 0
end

local function canCarryItem(src, itemName, amount)
    local api = inventoryApi()
    if not api then return false end
    local ok, can = pcall(function() return api:CanCarryItem(src, itemName, amount or 1) end)
    return ok and can == true
end

local function addItem(src, itemName, amount, reason)
    local api = inventoryApi()
    if not api then return false end
    local ok, success = pcall(function() return api:AddItem(src, itemName, amount or 1, nil, reason) end)
    return ok and success == true
end

local function removeItem(src, itemName, amount, reason)
    local api = inventoryApi()
    if not api then return false end
    local ok, success = pcall(function() return api:RemoveItem(src, itemName, amount or 1, nil, reason) end)
    return ok and success == true
end

local function getOwnedCropCounts(src)
    local api = inventoryApi()
    if not api then return {} end
    local ok, inventory = pcall(function() return api:GetInventory(src) end)
    if not ok or type(inventory) ~= 'table' then return {} end

    local counts = {}
    for _, item in ipairs(inventory.items or {}) do
        for _, crop in pairs(Config.Crops) do
            if crop.cropItem == item.item_name then
                counts[item.item_name] = (counts[item.item_name] or 0) + (tonumber(item.quantity) or 0)
            end
        end
    end
    return counts
end

-- ---------------------------------------------------------------------------
-- Player progress (level/xp stored as cm-playerdata metadata)
-- ---------------------------------------------------------------------------

local MAX_LEVEL = 5

local function getLevel(src)
    return math.max(0, math.floor(tonumber(getMeta(src, 'cmFarmingLevel', 0)) or 0))
end

local function getXp(src)
    return math.max(0, math.floor(tonumber(getMeta(src, 'cmFarmingXp', 0)) or 0))
end

local function getStatus(src)
    local level = getLevel(src)
    return {
        level = level,
        xp = getXp(src),
        xpForNext = Config.LevelXP[level + 1],
        maxLevel = level >= MAX_LEVEL,
    }
end

local function awardXp(src, amount)
    local level = getLevel(src)
    local xp = getXp(src) + math.max(0, math.floor(tonumber(amount) or 0))
    local leveledUp = false

    while true do
        local needed = Config.LevelXP[level + 1]
        if needed and xp >= needed then
            xp = xp - needed
            level = level + 1
            leveledUp = true
        else
            break
        end
    end

    setMeta(src, 'cmFarmingXp', xp)
    if leveledUp then setMeta(src, 'cmFarmingLevel', level) end

    local status = getStatus(src)
    TriggerClientEvent('cm-farming:client:status', src, status)
    return status, leveledUp
end

-- Applied by cm-payday once xp banked from harvests is paid out at the hourly
-- payday -- a level-up notification still lands even though the harvest
-- itself only banked the xp rather than applying it instantly.
exports('AddXp', function(src, amount)
    local status, leveledUp = awardXp(src, amount)
    if leveledUp then
        notify(src, ('Farming level up! You are now level %d.'):format(status.level), 'success')
    end
    return status, leveledUp
end)

-- Cash from selling crops banks into cm-payday's hourly payout when it's
-- running; falls back to instant pay if cm-payday isn't started.
local function payJobCash(src, jobName, amount, reason)
    if GetResourceState('cm-payday') == 'started' then
        local ok, result = pcall(function() return exports['cm-payday']:AddPendingCash(src, jobName, amount, reason) end)
        if ok and result == true then return true end
    end
    return addCash(src, amount, reason)
end

-- Same banking pattern for harvest xp (falls back to instant awardXp).
local function bankXp(src, amount)
    if GetResourceState('cm-payday') == 'started' then
        local ok, result = pcall(function() return exports['cm-payday']:AddPendingXp(src, 'farming', amount) end)
        if ok and result == true then return end
    end
    awardXp(src, amount)
end

-- ---------------------------------------------------------------------------
-- Field / plot state (in-memory, server authoritative, open access --
-- any player can work any unclaimed plot; no party/lobby gating).
-- ---------------------------------------------------------------------------

local POINT_STATES = { EMPTY = 'empty', PLANTED = 'planted', WATERED = 'watered', GROWN = 'grown' }

local Fields = {} -- [fieldKey] = { def = fieldDef, points = { [index] = { x, y, state, crop, waterAt } } }

local function buildPoints(fieldDef)
    local points = {}
    local spacing = fieldDef.spacing or 5.0
    local radius = fieldDef.radius or 30.0
    local maxPoints = fieldDef.maxPoints or 36
    local rot = math.rad(fieldDef.rotation or 0)
    local cosr, sinr = math.cos(rot), math.sin(rot)
    local cx, cy = fieldDef.center.x, fieldDef.center.y

    local function tryAdd(gx, gy)
        if #points >= maxPoints then return end
        local lx, ly = gx * spacing, gy * spacing
        local rx = lx * cosr - ly * sinr
        local ry = lx * sinr + ly * cosr
        if math.sqrt(rx * rx + ry * ry) <= radius then
            points[#points + 1] = { x = cx + rx, y = cy + ry, state = POINT_STATES.EMPTY, crop = nil, waterAt = nil }
        end
    end

    local ring = 0
    while #points < maxPoints and ring < 20 do
        if ring == 0 then
            tryAdd(0, 0)
        else
            for gx = -ring, ring do
                for gy = -ring, ring do
                    if math.max(math.abs(gx), math.abs(gy)) == ring then
                        tryAdd(gx, gy)
                        if #points >= maxPoints then break end
                    end
                end
                if #points >= maxPoints then break end
            end
        end
        ring = ring + 1
    end

    return points
end

for _, fieldDef in ipairs(Config.Fields) do
    Fields[fieldDef.key] = { def = fieldDef, points = buildPoints(fieldDef) }
end

local function fieldsSnapshot()
    local snapshot = {}
    for key, field in pairs(Fields) do
        local points = {}
        for index, point in ipairs(field.points) do
            points[index] = { x = point.x, y = point.y, state = point.state, crop = point.crop }
        end
        snapshot[key] = points
    end
    return snapshot
end

local function broadcastPoint(fieldKey, index)
    local point = Fields[fieldKey].points[index]
    TriggerClientEvent('cm-farming:client:pointUpdated', -1, fieldKey, index, point.state, point.crop)
end

RegisterNetEvent('cm-farming:server:requestFields', function()
    local src = source
    TriggerClientEvent('cm-farming:client:fieldsInit', src, fieldsSnapshot())
end)

-- ---------------------------------------------------------------------------
-- Livestock (cows) -- open access like the fields, no ownership.
-- ---------------------------------------------------------------------------

local Cows = {} -- [key] = { def, state = 'hungry'|'fed'|'milkable', fedAt, milkRemaining }

for _, cowDef in ipairs(Config.Livestock.Cows) do
    Cows[cowDef.key] = { def = cowDef, state = 'hungry', fedAt = nil, milkRemaining = 0 }
end

local function cowsSnapshot()
    local snapshot = {}
    for key, cow in pairs(Cows) do
        snapshot[key] = { state = cow.state }
    end
    return snapshot
end

local function broadcastCow(key)
    local cow = Cows[key]
    TriggerClientEvent('cm-farming:client:cowUpdated', -1, key, cow.state)
end

RegisterNetEvent('cm-farming:server:requestCows', function()
    local src = source
    TriggerClientEvent('cm-farming:client:cowsInit', src, cowsSnapshot())
end)

local function playerPed(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

local function playerCoords(src)
    local ped = playerPed(src)
    if not ped then return nil end
    return GetEntityCoords(ped)
end

local function pointDistance(coords, point)
    return math.sqrt((coords.x - point.x) ^ 2 + (coords.y - point.y) ^ 2)
end

local function withinRange(src, point, baseDistance)
    local coords = playerCoords(src)
    if not coords then return false end
    return pointDistance(coords, point) <= (baseDistance + Config.Security.actionRangeSlack)
end

local function cowWithinRange(src, cow)
    local coords = playerCoords(src)
    if not coords then return false end
    local c = cow.def.coords
    local dist = math.sqrt((coords.x - c.x) ^ 2 + (coords.y - c.y) ^ 2)
    return dist <= ((Config.Livestock.interactDistance or 1.8) + Config.Security.actionRangeSlack)
end

-- Per-player action cooldown/lock to prevent double-fire from rapid client
-- events (e.g. spamming the interact key).
local actionCooldowns = {}

local function onCooldown(src)
    local now = GetGameTimer()
    if (actionCooldowns[src] or 0) > now then return true end
    actionCooldowns[src] = now + (tonumber(Config.Security.actionCooldownMs) or 500)
    return false
end

-- ---------------------------------------------------------------------------
-- Growth tick -- server authoritative, no per-owner client timer, so
-- progress never resets on disconnect/resource restart mid-grow.
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(Config.Timings.growthTickMs or 15000)
        local now = os.time()
        for fieldKey, field in pairs(Fields) do
            for index, point in ipairs(field.points) do
                if point.state == POINT_STATES.WATERED and point.crop then
                    local crop = Config.Crops[point.crop]
                    if crop and point.waterAt and (now - point.waterAt) >= (crop.growTimeSec or 300) then
                        point.state = POINT_STATES.GROWN
                        broadcastPoint(fieldKey, index)
                    end
                end
            end
        end

        for key, cow in pairs(Cows) do
            if cow.state == 'fed' and cow.fedAt and (now - cow.fedAt) >= (Config.Livestock.requiredFeedingTimeSec or 30) then
                cow.state = 'milkable'
                broadcastCow(key)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Plant
-- ---------------------------------------------------------------------------

local function findFieldAndPoint(fieldKey, index)
    local field = Fields[fieldKey]
    if not field then return nil end
    local point = field.points[index]
    if not point then return nil end
    return field, point
end

local function ownedAllowedSeeds(src, field)
    local owned = {}
    for _, cropName in ipairs(field.def.allowedCrops) do
        local crop = Config.Crops[cropName]
        if crop then
            local has = hasItem(src, crop.seedItem, 1)
            if has then owned[#owned + 1] = cropName end
        end
    end
    return owned
end

local function plantCrop(src, fieldKey, field, index, point, cropName)
    local crop = Config.Crops[cropName]
    if not crop then return false end
    if point.state ~= POINT_STATES.EMPTY then return false end
    if not withinRange(src, point, Config.interactDistance) then return false end
    if not hasItem(src, crop.seedItem, 1) then
        notify(src, ('You need %s to plant here.'):format(crop.seedLabel or crop.label), 'error')
        return false
    end
    if not removeItem(src, crop.seedItem, 1, 'farming_plant') then
        notify(src, ('You need %s to plant here.'):format(crop.seedLabel or crop.label), 'error')
        return false
    end

    point.state = POINT_STATES.PLANTED
    point.crop = cropName
    point.waterAt = nil
    broadcastPoint(fieldKey, index)
    notify(src, ('Planted %s.'):format(crop.label), 'success')
    return true
end

RegisterNetEvent('cm-farming:server:plantAttempt', function(fieldKey, index)
    local src = source
    if onCooldown(src) then return end

    local field, point = findFieldAndPoint(fieldKey, index)
    if not field or not point then return end
    if point.state ~= POINT_STATES.EMPTY then return end
    if not withinRange(src, point, Config.interactDistance) then return end

    local options = ownedAllowedSeeds(src, field)
    if #options == 0 then
        notify(src, 'You do not have any seeds for this field.', 'error')
        return
    end

    if #options == 1 then
        plantCrop(src, fieldKey, field, index, point, options[1])
        return
    end

    local labeled = {}
    for _, cropName in ipairs(options) do
        local crop = Config.Crops[cropName]
        labeled[#labeled + 1] = { name = cropName, label = crop.label, image = crop.cropItem .. '.png' }
    end
    TriggerClientEvent('cm-farming:client:choosePlant', src, fieldKey, index, labeled)
end)

RegisterNetEvent('cm-farming:server:plantChosen', function(fieldKey, index, cropName)
    local src = source
    if onCooldown(src) then return end

    local field, point = findFieldAndPoint(fieldKey, index)
    if not field or not point then return end
    if not Config.Crops[cropName] then return end

    local allowed = false
    for _, allowedCrop in ipairs(field.def.allowedCrops) do
        if allowedCrop == cropName then allowed = true break end
    end
    if not allowed then return end

    plantCrop(src, fieldKey, field, index, point, cropName)
end)

-- ---------------------------------------------------------------------------
-- Water (also waters nearby 'planted' plots in the same field -- area
-- effect, matches the source resource's watering-can behaviour)
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-farming:server:waterAttempt', function(fieldKey, index)
    local src = source
    if onCooldown(src) then return end

    local field, point = findFieldAndPoint(fieldKey, index)
    if not field or not point then return end
    if point.state ~= POINT_STATES.PLANTED then return end
    if not withinRange(src, point, Config.interactDistance) then return end

    local has = hasItem(src, 'watering_can', 1)
    if not has then
        notify(src, 'You need a watering can to do that.', 'error')
        return
    end

    local now = os.time()
    point.state = POINT_STATES.WATERED
    point.waterAt = now
    broadcastPoint(fieldKey, index)

    local radius = Config.Timings.waterAreaRadius or 5.0
    for otherIndex, otherPoint in ipairs(field.points) do
        if otherIndex ~= index and otherPoint.state == POINT_STATES.PLANTED then
            if pointDistance(point, otherPoint) <= radius then
                otherPoint.state = POINT_STATES.WATERED
                otherPoint.waterAt = now
                broadcastPoint(fieldKey, otherIndex)
            end
        end
    end

    notify(src, 'Watered the plot.', 'success')
end)

-- ---------------------------------------------------------------------------
-- Harvest
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-farming:server:harvestAttempt', function(fieldKey, index)
    local src = source
    if onCooldown(src) then return end

    local field, point = findFieldAndPoint(fieldKey, index)
    if not field or not point then return end
    if point.state ~= POINT_STATES.GROWN or not point.crop then return end
    if not withinRange(src, point, Config.interactDistance) then return end

    local crop = Config.Crops[point.crop]
    if not crop then return end

    if not canCarryItem(src, crop.cropItem, crop.harvestAmount or 1) then
        notify(src, 'You are carrying too much to harvest that.', 'error')
        return
    end

    if not addItem(src, crop.cropItem, crop.harvestAmount or 1, 'farming_harvest') then
        notify(src, 'You are carrying too much to harvest that.', 'error')
        return
    end

    point.state = POINT_STATES.EMPTY
    point.crop = nil
    point.waterAt = nil
    broadcastPoint(fieldKey, index)

    bankXp(src, crop.xpReward or 5)
    notify(src, ('Harvested %dx %s.'):format(crop.harvestAmount or 1, crop.label), 'success')
end)

-- ---------------------------------------------------------------------------
-- Livestock: feed / milk
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-farming:server:feedAttempt', function(cowKey)
    local src = source
    if onCooldown(src) then return end

    local cow = Cows[cowKey]
    if not cow then return end
    if cow.state ~= 'hungry' then return end
    if not cowWithinRange(src, cow) then return end

    local feedItem = Config.Livestock.feedItem
    if not hasItem(src, feedItem, 1) then
        notify(src, ('You need %s to feed the cow.'):format(Config.Livestock.feedLabel or 'cow feed'), 'error')
        return
    end
    if not removeItem(src, feedItem, 1, 'farming_cow_feed') then
        notify(src, ('You need %s to feed the cow.'):format(Config.Livestock.feedLabel or 'cow feed'), 'error')
        return
    end

    cow.state = 'fed'
    cow.fedAt = os.time()
    cow.milkRemaining = Config.Livestock.maxMilkPerCow or 3
    broadcastCow(cowKey)
    notify(src, 'Fed the cow.', 'success')
end)

RegisterNetEvent('cm-farming:server:milkAttempt', function(cowKey)
    local src = source
    if onCooldown(src) then return end

    local cow = Cows[cowKey]
    if not cow then return end
    if cow.state ~= 'milkable' or (cow.milkRemaining or 0) <= 0 then return end
    if not cowWithinRange(src, cow) then return end

    local milkItem = Config.Livestock.milkItem
    if not canCarryItem(src, milkItem, 1) then
        notify(src, 'You are carrying too much to milk the cow.', 'error')
        return
    end
    if not addItem(src, milkItem, 1, 'farming_milk') then
        notify(src, 'You are carrying too much to milk the cow.', 'error')
        return
    end

    cow.milkRemaining = cow.milkRemaining - 1
    if cow.milkRemaining <= 0 then
        cow.state = 'hungry'
        cow.fedAt = nil
    end
    broadcastCow(cowKey)

    bankXp(src, Config.Livestock.xpRewardPerMilk or 10)
    notify(src, 'Milked the cow.', 'success')
end)

-- ---------------------------------------------------------------------------
-- Market
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-farming:server:requestStatus', function()
    local src = source
    TriggerClientEvent('cm-farming:client:status', src, getStatus(src))
end)

local function marketDistanceOk(src)
    local coords = playerCoords(src)
    if not coords then return false end
    local marketCoords = Config.Market.coords
    return #(coords - vector3(marketCoords.x, marketCoords.y, marketCoords.z)) <= (Config.npcInteractDistance + Config.Security.actionRangeSlack)
end

local function buildMenuPayload(src)
    local level = getLevel(src)
    local seeds = {}
    for cropName, crop in pairs(Config.Crops) do
        seeds[#seeds + 1] = {
            name = crop.seedItem, cropName = cropName, label = crop.seedLabel or (crop.label .. ' Seeds'),
            price = crop.seedPrice, requiredLevel = crop.requiredLevel or 0, locked = (crop.requiredLevel or 0) > level,
            image = crop.seedItem .. '.png', description = crop.description,
        }
    end
    table.sort(seeds, function(a, b) return a.price < b.price end)

    local tools = {}
    for name, tool in pairs(Config.Tools) do
        tools[#tools + 1] = {
            name = name, label = tool.label, price = tool.price,
            image = tool.image or (name .. '.png'), description = tool.description,
        }
    end
    tools[#tools + 1] = {
        name = Config.Livestock.feedItem, label = Config.Livestock.feedLabel, price = Config.Livestock.feedPrice,
        image = 'default.png', description = 'Feed for cows at the dairy farm. Consumed when feeding.',
    }
    table.sort(tools, function(a, b) return a.price < b.price end)

    local owned = getOwnedCropCounts(src)
    local sellable = {}
    for _, crop in pairs(Config.Crops) do
        local count = owned[crop.cropItem] or 0
        if count > 0 then
            sellable[#sellable + 1] = {
                name = crop.cropItem, label = crop.label, price = crop.sellPrice,
                count = count, image = crop.cropItem .. '.png',
            }
        end
    end

    local _, milkCount = hasItem(src, Config.Livestock.milkItem, 1)
    if milkCount > 0 then
        sellable[#sellable + 1] = {
            name = Config.Livestock.milkItem, label = Config.Livestock.milkLabel, price = Config.Livestock.milkSellPriceRange.min,
            count = milkCount, image = 'default.png',
        }
    end
    table.sort(sellable, function(a, b) return a.label < b.label end)

    return {
        cash = getCash(src),
        status = getStatus(src),
        seeds = seeds,
        tools = tools,
        sellable = sellable,
    }
end

local function sendMenu(src)
    TriggerClientEvent('cm-farming:client:openMenu', src, buildMenuPayload(src))
end

RegisterNetEvent('cm-farming:server:requestMenu', function()
    local src = source
    if not marketDistanceOk(src) then return end
    sendMenu(src)
end)

-- Useable item: opens the menu from anywhere, no distance check needed.
exports('UseTablet', function(src)
    sendMenu(src)
end)

CreateThread(function()
    local attempts = 0
    while GetResourceState(INVENTORY) ~= 'started' and attempts < 40 do
        Wait(500)
        attempts = attempts + 1
    end
    if GetResourceState(INVENTORY) ~= 'started' then return end
    pcall(function()
        exports[INVENTORY]:RegisterUseableItem('farming_tablet', 'cm-farming', 'UseTablet')
    end)
end)

RegisterNetEvent('cm-farming:server:buyItem', function(kind, name, qty)
    local src = source
    if not marketDistanceOk(src) then return end

    qty = math.max(1, math.min(20, math.floor(tonumber(qty) or 1)))

    local itemName, price, label, requiredLevel
    if kind == 'seed' then
        for _, crop in pairs(Config.Crops) do
            if crop.seedItem == name then
                itemName, price, label, requiredLevel = crop.seedItem, crop.seedPrice, crop.seedLabel or crop.label, crop.requiredLevel
                break
            end
        end
    elseif kind == 'tool' then
        local tool = Config.Tools[name]
        if tool then
            itemName, price, label, requiredLevel = name, tool.price, tool.label, 0
        elseif name == Config.Livestock.feedItem then
            itemName, price, label, requiredLevel = name, Config.Livestock.feedPrice, Config.Livestock.feedLabel, 0
        end
    end

    if not itemName then return end

    if (requiredLevel or 0) > getLevel(src) then
        notify(src, ('You need farming level %d to buy this.'):format(requiredLevel), 'error')
        return
    end

    local totalPrice = price * qty
    if getCash(src) < totalPrice then
        notify(src, 'You cannot afford that.', 'error')
        return
    end

    if not canCarryItem(src, itemName, qty) then
        notify(src, 'You cannot carry that much.', 'error')
        return
    end

    if not removeCash(src, totalPrice, 'farming_market_purchase') then
        notify(src, 'You cannot afford that.', 'error')
        return
    end

    if not addItem(src, itemName, qty, 'farming_market_purchase') then
        addCash(src, totalPrice, 'farming_market_purchase_refund')
        notify(src, 'Purchase failed.', 'error')
        return
    end

    notify(src, ('Bought %dx %s for $%d.'):format(qty, label, totalPrice), 'success')
    sendMenu(src)
end)

RegisterNetEvent('cm-farming:server:sellItem', function(name, amount)
    local src = source
    if not marketDistanceOk(src) then return end

    if name == Config.Livestock.milkItem then
        local _, owned = hasItem(src, name, 1)
        if owned <= 0 then
            notify(src, 'You do not have any of that to sell.', 'error')
            return
        end

        local sellAmount = amount == 'all' and owned or math.max(1, math.min(owned, math.floor(tonumber(amount) or 1)))
        local range = Config.Livestock.milkSellPriceRange
        local unitPrice = math.random(range.min, range.max)
        local total = unitPrice * sellAmount

        if not removeItem(src, name, sellAmount, 'farming_sell_milk') then
            notify(src, 'You do not have any of that to sell.', 'error')
            return
        end

        payJobCash(src, 'farming', total, 'farming_sell_milk')
        notify(src, ('Sold %dx %s for $%d.'):format(sellAmount, Config.Livestock.milkLabel, total), 'success')
        sendMenu(src)
        return
    end

    local crop
    for _, candidate in pairs(Config.Crops) do
        if candidate.cropItem == name then crop = candidate break end
    end
    if not crop then return end

    local _, owned = hasItem(src, name, 1)
    if owned <= 0 then
        notify(src, 'You do not have any of that to sell.', 'error')
        return
    end

    local sellAmount = amount == 'all' and owned or math.max(1, math.min(owned, math.floor(tonumber(amount) or 1)))
    local total = crop.sellPrice * sellAmount

    if not removeItem(src, name, sellAmount, 'farming_sell') then
        notify(src, 'You do not have any of that to sell.', 'error')
        return
    end

    payJobCash(src, 'farming', total, 'farming_sell')
    notify(src, ('Sold %dx %s for $%d.'):format(sellAmount, crop.label, total), 'success')
    sendMenu(src)
end)

-- ---------------------------------------------------------------------------
-- Cleanup / admin
-- ---------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    actionCooldowns[source] = nil
end)

local function isAdminAllowed(src, permission)
    if tonumber(src) == 0 then return true end
    if GetResourceState('cm-admin') ~= 'started' then return false end
    local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(src, permission) end)
    return ok and allowed == true
end

local function reply(src, message)
    if tonumber(src) == 0 then
        print('[CM-FARMING] ' .. tostring(message))
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '[CM-FARMING]', tostring(message) } })
    end
end

RegisterCommand('setfarminglevel', function(src, args)
    if not isAdminAllowed(src, 'farming.admin.setlevel') then
        return reply(src, 'You do not have permission to do that.')
    end

    local level = math.floor(tonumber(args[1]) or -1)
    if level < 0 or level > MAX_LEVEL then
        return reply(src, ('Usage: /setfarminglevel <0-%d> [playerId]'):format(MAX_LEVEL))
    end

    local targetSrc = tonumber(args[2])
    if not targetSrc then
        if tonumber(src) == 0 then return reply(src, ('Usage from console: /setfarminglevel <0-%d> <playerId>'):format(MAX_LEVEL)) end
        targetSrc = tonumber(src)
    end
    if not GetPlayerName(targetSrc) then return reply(src, 'That player is not online.') end

    setMeta(targetSrc, 'cmFarmingLevel', level)
    setMeta(targetSrc, 'cmFarmingXp', 0)
    TriggerClientEvent('cm-farming:client:status', targetSrc, getStatus(targetSrc))
    notify(targetSrc, ('Your farming level was set to %d.'):format(level), 'info')
    reply(src, ('Set farming level %d for player %d.'):format(level, targetSrc))
end, false)
