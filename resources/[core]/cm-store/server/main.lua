-- cm-store/server/main.lua
-- Authoritative general store system with full persistence, ownership, pricing tiers,
-- stock & overstock management, business balance, and cm-inventory / cm-items integration.

local RESOURCE = GetCurrentResourceName()
local Config = Config or {}

local Catalog = {}     -- master catalog list
local CatalogMap = {}  -- item_name -> config entry
local OrderLocks = {}
local RequestCooldowns = {}
local RobberyCooldowns = {}

local function dbg(...)
    if Config.Debug then print(('[%s:DEBUG]'):format(RESOURCE), ...) end
end

local function notify(src, msg, typ)
    if src == 0 then print(('[%s] %s'):format(RESOURCE, tostring(msg or ''))); return end
    TriggerClientEvent('cm-hud:client:notify', src, tostring(msg or ''), typ or 'info')
end

local function itemsResource()
    return Config.ItemsResource or 'cm-items'
end

local function normalizeItemName(value)
    value = tostring(value or ''):lower():gsub('%s+', '_'):gsub('[^a-z0-9_%-%.]', '_'):gsub('_+', '_')
    return value:gsub('^_+', ''):gsub('_+$', ''):sub(1, 80)
end

-- ============================================================
-- PlayerData & Economy Helpers
-- ============================================================
local function playerData()
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    return exports['cm-playerdata']
end

local function characterId(src)
    local api = playerData()
    if not api then return nil end
    local ok, id = pcall(function() return api:GetCharacterId(src) end)
    return ok and tonumber(id) or nil
end

local function getCharacterName(src)
    local api = playerData()
    if not api then return ('Player %s'):format(src) end
    local ok, name = pcall(function() return api:GetCharacterFullName(src) end)
    if ok and name and name ~= '' then return name end
    return ('Character %s'):format(characterId(src) or src)
end

local function getCash(src)
    local api = playerData()
    if not api then return nil end
    local ok, amount = pcall(function() return api:GetCash(src) end)
    return (ok and type(amount) == 'number') and math.floor(amount) or 0
end

local function getBank(src)
    local api = playerData()
    if not api then return nil end
    local ok, amount = pcall(function() return api:GetBank(src) end)
    return (ok and type(amount) == 'number') and math.floor(amount) or 0
end

local function removeCash(src, amount, reason)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:RemoveCash(src, math.floor(amount), reason) end)
    return ok and result == true
end

local function addCash(src, amount, reason)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:AddCash(src, math.floor(amount), reason) end)
    return ok and result == true
end

local function removeBank(src, amount, reason)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:RemoveBank(src, math.floor(amount), reason) end)
    return ok and result == true
end

local function addBank(src, amount, reason)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:AddBank(src, math.floor(amount), reason) end)
    return ok and result == true
end

local function chargePlayer(src, method, amount, reason)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    method = tostring(method or 'bank'):lower()

    if method == 'cash' then
        local current = getCash(src)
        if current < amount then return false, ('Not enough cash. You need $%d.'):format(amount) end
        if not removeCash(src, amount, reason) then return false, 'Cash payment failed.' end
        return true
    else
        local current = getBank(src)
        if current < amount then return false, ('Not enough bank funds. You need $%d.'):format(amount) end
        if not removeBank(src, amount, reason) then return false, 'Bank payment failed.' end
        return true
    end
end

local function refundPlayer(src, method, amount, reason)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return true end
    method = tostring(method or 'bank'):lower()
    if method == 'cash' then
        return addCash(src, amount, reason)
    else
        return addBank(src, amount, reason)
    end
end

-- ============================================================
-- Inventory Delivery & Check Helpers
-- ============================================================
local function canCarry(src, itemName, count)
    if GetResourceState(Config.Inventory or 'cm-inventory') ~= 'started' then return true end
    local ok, result = pcall(function()
        return exports[Config.Inventory or 'cm-inventory']:CanCarryItem(src, itemName, count)
    end)
    if ok and type(result) == 'boolean' then return result end
    return true
end

local function giveItem(src, itemName, count)
    local invRes = Config.Inventory or 'cm-inventory'
    if GetResourceState(invRes) == 'started' then
        local ok, result = pcall(function()
            return exports[invRes]:AddItem(src, itemName, count, {}, nil, 'cm_store_purchase')
        end)
        if ok and (result == true or (type(result) == 'number' and result > 0) or (type(result) == 'table' and (result.success or result.ok or result[1]))) then
            return true
        end
    end

    local itmRes = itemsResource()
    if GetResourceState(itmRes) == 'started' then
        local ok, result = pcall(function()
            return exports[itmRes]:GiveCatalogItem(src, itemName, count)
        end)
        if ok and result == true then return true end
    end

    return false
end

-- ============================================================
-- Database & Store Row Management
-- ============================================================
local function storeRow(storeId)
    if not MySQL then return nil end
    return MySQL.single.await('SELECT * FROM cm_stores WHERE store_id = ? LIMIT 1', { tonumber(storeId) })
end

local function storePriceMultiplier(row)
    local tier = tostring(row and row.price_tier or 'normal'):lower()
    local tiers = (Config.Ownership or {}).priceTiers or {}
    local tierCfg = tiers[tier] or tiers.normal or { multiplier = 1.0 }
    return tonumber(tierCfg.multiplier) or 1.0
end

local function getShopConfig(storeId)
    storeId = tonumber(storeId) or 1
    for _, s in ipairs(Config.Shops or {}) do
        if tonumber(s.id) == storeId then return s end
    end
    return (Config.Shops and Config.Shops[1]) or { id = 1, name = 'Store', label = 'Convenience Store' }
end

local function isNearShop(src, storeId)
    local shop = getShopConfig(storeId)
    if not shop then return true end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pcoords = GetEntityCoords(ped)
    local c = shop.registerCoords or shop.coords or shop.pedCoords
    if not c then return true end
    local sx, sy, sz = tonumber(c.x or c[1]), tonumber(c.y or c[2]), tonumber(c.z or c[3])
    local maxDist = tonumber(Config.PurchaseDistance) or 15.0
    return #(pcoords - vector3(sx, sy, sz)) <= maxDist
end

-- ============================================================
-- Database Initialization & Row Seeding
-- ============================================================
CreateThread(function()
    Wait(1000)
    if not MySQL then
        print(('[%s] oxmysql is not ready; store persistence waiting...'):format(RESOURCE))
        return
    end

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_stores (
        store_id INT NOT NULL PRIMARY KEY,
        owner_character_id BIGINT NULL,
        owner_name VARCHAR(120) NULL,
        price_tier VARCHAR(12) NOT NULL DEFAULT 'normal',
        stock INT NOT NULL DEFAULT 1000,
        business_balance BIGINT NOT NULL DEFAULT 0,
        daily_income BIGINT NOT NULL DEFAULT 0,
        weekly_income BIGINT NOT NULL DEFAULT 0,
        tax_due_at DATETIME NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])

    for _, shop in ipairs(Config.Shops or {}) do
        local sid = tonumber(shop.id) or 1
        local defStock = (Config.Ownership or {}).defaultStock or 1000
        MySQL.insert.await('INSERT IGNORE INTO cm_stores (store_id, stock) VALUES (?, ?)', { sid, defStock })
    end
    print(('[%s] Database initialized and %d stores verified.'):format(RESOURCE, #(Config.Shops or {})))
end)

-- Periodic tax expiration loop (60s tick)
CreateThread(function()
    while true do
        Wait(60000)
        if MySQL then
            local expired = MySQL.query.await([[SELECT store_id, owner_character_id, business_balance
                FROM cm_stores WHERE owner_character_id IS NOT NULL AND tax_due_at IS NOT NULL AND tax_due_at < UTC_TIMESTAMP()]]) or {}
            for _, row in ipairs(expired) do
                local sid = tonumber(row.store_id)
                local formerOwner = tonumber(row.owner_character_id)
                local refund = math.floor(((Config.Ownership or {}).purchasePrice or 200000) * 0.20)
                MySQL.update.await([[UPDATE cm_stores
                    SET owner_character_id = NULL, owner_name = NULL, price_tier = 'normal', business_balance = 0,
                        stock = ?, tax_due_at = NULL
                    WHERE store_id = ? AND owner_character_id = ?]],
                    { (Config.Ownership or {}).defaultStock or 1000, sid, formerOwner })

                -- Refund 20% security deposit if player is active
                for _, player in ipairs(GetPlayers()) do
                    if characterId(tonumber(player)) == formerOwner then
                        addBank(tonumber(player), refund, 'cm-store-tax-forfeiture-refund')
                        notify(tonumber(player), ('Store #%d ownership forfeited due to unpaid tax. $%d refund deposited.'):format(sid, refund), 'warning')
                        break
                    end
                end
                print(('[%s] Store #%d forfeited due to overdue property tax.'):format(RESOURCE, sid))
            end
        end
    end
end)

-- ============================================================
-- Catalog Registration & cm-items Seeding
-- ============================================================
local function liveImage(name, fallback)
    if fallback and fallback ~= '' then return fallback end
    if GetResourceState(itemsResource()) == 'started' then
        local ok, def = pcall(function() return exports[itemsResource()]:GetItem(name) end)
        if ok and type(def) == 'table' and def.image and def.image ~= '' then return def.image end
    end
    return fallback or ''
end

local function seedCatalog()
    Catalog, CatalogMap = {}, {}
    local hasItems = GetResourceState(itemsResource()) == 'started'

    for _, raw in ipairs(Config.Catalog or {}) do
        local name = normalizeItemName(raw.name or raw.item_name)
        if name ~= '' and not CatalogMap[name] then
            local entry = {
                name = name,
                label = tostring(raw.label or name),
                category = tostring(raw.category or 'misc'):lower(),
                price = math.max(0, math.floor(tonumber(raw.price) or 0)),
                weight = math.max(0, math.floor(tonumber(raw.weight) or 0)),
                usable = raw.usable == true,
                image = raw.image and tostring(raw.image) or '',
                description = tostring(raw.description or ''),
                enabled = raw.enabled ~= false,
            }

            if hasItems then
                pcall(function()
                    exports[itemsResource()]:SaveCatalogItem({
                        name = name,
                        label = entry.label,
                        category = entry.category,
                        image = entry.image ~= '' and entry.image or nil,
                        weight = entry.weight,
                        stack = raw.stack ~= false,
                        usable = entry.usable,
                        description = entry.description,
                        createdBy = 'cm-store_seed',
                    })
                end)
            end

            entry.image = liveImage(name, entry.image)
            Catalog[#Catalog + 1] = entry
            CatalogMap[name] = entry
        end
    end
    print(('[%s] Loaded %d catalog items.'):format(RESOURCE, #Catalog))
end

CreateThread(function()
    local tries = 0
    while GetResourceState(itemsResource()) ~= 'started' and tries < 60 do
        Wait(500)
        tries = tries + 1
    end
    Wait(500)
    seedCatalog()
end)

-- ============================================================
-- Build Full Store Context Payload for Client
-- ============================================================
local function buildStoreContext(src, storeId)
    local shop = getShopConfig(storeId)
    local row = storeRow(storeId) or {}
    local charId = characterId(src)
    local isOwner = charId and row.owner_character_id and tonumber(row.owner_character_id) == charId
    local mult = storePriceMultiplier(row)

    local clientCatalog = {}
    for _, item in ipairs(Catalog) do
        if item.enabled ~= false then
            local dynamicPrice = math.max(1, math.ceil(item.price * mult))
            clientCatalog[#clientCatalog + 1] = {
                item_name = item.name,
                label = item.label,
                category = item.category,
                basePrice = item.price,
                price = dynamicPrice,
                weight = item.weight,
                usable = item.usable,
                image = item.image,
                description = item.description,
            }
        end
    end

    local ownershipCfg = Config.Ownership or {}
    local taxDaysLeft = 0
    if row.tax_due_at then
        -- Convert SQL datetime to seconds
        local yr, mo, da, hr, mi, se = tostring(row.tax_due_at):match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')
        if yr then
            local expSec = os.time({ year = tonumber(yr), month = tonumber(mo), day = tonumber(da), hour = tonumber(hr), min = tonumber(mi), sec = tonumber(se) })
            taxDaysLeft = math.max(0, math.ceil((expSec - os.time()) / 86400))
        end
    end

    return {
        storeId = storeId,
        storeName = shop.name or ('Store #%d'):format(storeId),
        storeLabel = shop.label or 'Convenience Store',
        owned = row.owner_character_id ~= nil,
        isOwner = isOwner == true,
        ownerName = row.owner_name or 'City of Los Santos',
        priceTier = tostring(row.price_tier or 'normal'):lower(),
        priceMultiplier = mult,
        stock = math.floor(tonumber(row.stock) or 0),
        maxStock = ownershipCfg.maxStock or 5000,
        overstockLimit = ownershipCfg.overstockLimit or 8000,
        businessBalance = math.floor(tonumber(row.business_balance) or 0),
        dailyIncome = math.floor(tonumber(row.daily_income) or 0),
        weeklyIncome = math.floor(tonumber(row.weekly_income) or 0),
        taxDueAt = row.tax_due_at,
        taxDaysLeft = taxDaysLeft,
        purchasePrice = ownershipCfg.purchasePrice or 200000,
        taxAmount = ownershipCfg.taxAmount or 12000,
        restockBatch = ownershipCfg.restockBatch or 500,
        restockUnitPrice = ownershipCfg.restockUnitPrice or 6,
        overstockUnitPrice = ownershipCfg.overstockUnitPrice or 8,
        cashBalance = getCash(src) or 0,
        bankBalance = getBank(src) or 0,
        catalog = clientCatalog,
        categories = Config.Categories or {},
    }
end

-- ============================================================
-- Net Events
-- ============================================================
RegisterNetEvent('cm-store:server:requestDialogue', function(storeId)
    local src = source
    storeId = tonumber(storeId) or 1

    if not isNearShop(src, storeId) then return end

    local charId = characterId(src)
    local row = storeRow(storeId)
    local isOwner = false
    if row and row.owner_character_id and charId and tonumber(row.owner_character_id) == tonumber(charId) then
        isOwner = true
    end

    TriggerClientEvent('cm-store:client:openDialogue', src, storeId, isOwner)
end)

RegisterNetEvent('cm-store:server:robStore', function(storeId)
    local src = source
    storeId = tonumber(storeId) or 1

    if not isNearShop(src, storeId) then
        return notify(src, 'You are too far from the store.', 'error')
    end

    local now = GetGameTimer()
    if (RobberyCooldowns[storeId] or 0) > now then
        local waitSec = math.ceil((RobberyCooldowns[storeId] - now) / 1000)
        return notify(src, ('The cash register is empty! This store was recently robbed. (%ds remaining)'):format(waitSec), 'error')
    end

    local charId = characterId(src)
    if not charId then return end

    -- 5-minute cooldown per store
    RobberyCooldowns[storeId] = now + (300 * 1000)

    -- Snatched register cash
    local lootAmount = math.random(450, 950)
    addCash(src, lootAmount, ('store_robbery_%d'):format(storeId))

    -- Server hook for crime logs, dispatch, or gang missions
    TriggerEvent('cm-store:server:onStoreRobbed', src, storeId, lootAmount)

    notify(src, ('You snatched $%d from the cash register! The clerk triggered the silent alarm!'):format(lootAmount), 'warning')
    dbg(('Player %s (char %s) robbed store #%d for $%d'):format(src, charId, storeId, lootAmount))
end)

RegisterNetEvent('cm-store:server:deliverStock', function(storeId)
    local src = source
    storeId = tonumber(storeId) or 1

    if not isNearShop(src, storeId) then
        return notify(src, 'You are too far from the store.', 'error')
    end

    local charId = characterId(src)
    if not charId then return end

    -- Extensible server event hook for logistics / delivery jobs
    TriggerEvent('cm-store:server:onDeliverStock', src, storeId)

    notify(src, 'Clerk: Checking shipping manifest... No pending supplier shipment assigned to you for this store.', 'info')
    dbg(('Player %s (char %s) requested stock delivery for store #%d'):format(src, charId, storeId))
end)

RegisterNetEvent('cm-store:server:requestStore', function(storeId, openView)
    local src = source
    storeId = tonumber(storeId) or 1

    local now = GetGameTimer()
    if now - (RequestCooldowns[src] or 0) < 400 then return end
    RequestCooldowns[src] = now

    if not isNearShop(src, storeId) then
        notify(src, 'You are too far from this store.', 'error')
        return
    end

    local ctx = buildStoreContext(src, storeId)
    ctx.initialView = openView or 'catalog'
    TriggerClientEvent('cm-store:client:openStore', src, ctx)
end)

-- Buy Store
RegisterNetEvent('cm-store:server:buyStore', function(storeId)
    local src = source
    storeId = tonumber(storeId) or 1
    local cfg = Config.Ownership or {}
    if not cfg.enabled then return notify(src, 'Store ownership is currently disabled.', 'error') end

    local charId = characterId(src)
    if not charId then return notify(src, 'Character identity unavailable.', 'error') end

    local row = storeRow(storeId)
    if not row then return notify(src, 'Invalid store location.', 'error') end
    if row.owner_character_id then return notify(src, 'This store is already privately owned.', 'error') end

    local price = math.max(0, math.floor(tonumber(cfg.purchasePrice) or 200000))
    if not removeBank(src, price, 'store-purchase-' .. storeId) then
        return notify(src, ('You need $%d in your bank account to purchase this store.'):format(price), 'error')
    end

    local ownerName = getCharacterName(src)
    local due = os.date('!%Y-%m-%d %H:%M:%S', os.time() + ((tonumber(cfg.taxPeriodDays) or 7) * 86400))
    local changed = MySQL.update.await([[UPDATE cm_stores
        SET owner_character_id = ?, owner_name = ?, price_tier = 'normal', business_balance = 0,
            stock = ?, tax_due_at = ?
        WHERE store_id = ? AND owner_character_id IS NULL]],
        { charId, ownerName, cfg.defaultStock or 1000, due, storeId })

    if changed ~= 1 then
        addBank(src, price, 'store-purchase-refund')
        return notify(src, 'This store was purchased by someone else.', 'error')
    end

    notify(src, ('Congratulations! You now own Store #%d. First tax is due in 7 days.'):format(storeId), 'success')
    local updatedCtx = buildStoreContext(src, storeId)
    updatedCtx.initialView = 'owner'
    TriggerClientEvent('cm-store:client:openStore', src, updatedCtx)
end)

-- Manage Store (Price Tier, Stock, Overstock)
RegisterNetEvent('cm-store:server:manageStore', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local storeId = tonumber(data.storeId) or 1
    local row = storeRow(storeId)
    local charId = characterId(src)

    if not row or not charId or tonumber(row.owner_character_id) ~= charId then
        return notify(src, 'You do not own this store.', 'error')
    end

    local cfg = Config.Ownership or {}
    local tier = tostring(data.priceTier or row.price_tier or 'normal'):lower()
    if not (cfg.priceTiers or {})[tier] then tier = 'normal' end

    local currentStock = math.floor(tonumber(row.stock) or 0)
    local maxStock = tonumber(cfg.maxStock) or 5000
    local overstockLimit = tonumber(cfg.overstockLimit) or 8000
    local batch = tonumber(cfg.restockBatch) or 500

    -- Standard restock (+500 up to maxStock)
    if data.restock == true then
        if currentStock >= maxStock then
            return notify(src, ('Store stock is already at full capacity (%d units). Use Overstock Delivery to order more.'):format(maxStock), 'warning')
        end
        local cost = math.floor(batch * (tonumber(cfg.restockUnitPrice) or 6))
        if not removeBank(src, cost, 'store-restock-' .. storeId) then
            return notify(src, ('You need $%d in the bank to order stock.'):format(cost), 'error')
        end
        currentStock = math.min(maxStock, currentStock + batch)
        notify(src, ('Ordered %d stock units for $%d.'):format(batch, cost), 'success')
    end

    -- Overstock delivery (+500 beyond maxStock up to overstockLimit)
    if data.overstock == true then
        if currentStock >= overstockLimit then
            return notify(src, ('Store has reached maximum overstock warehouse limit (%d units).'):format(overstockLimit), 'error')
        end
        local cost = math.floor(batch * (tonumber(cfg.overstockUnitPrice) or 8))
        if not removeBank(src, cost, 'store-overstock-' .. storeId) then
            return notify(src, ('You need $%d in the bank for an overstock shipment.'):format(cost), 'error')
        end
        currentStock = math.min(overstockLimit, currentStock + batch)
        notify(src, ('Overstock shipment delivered! +%d units added (Total: %d).'):format(batch, currentStock), 'success')
    end

    MySQL.update.await('UPDATE cm_stores SET price_tier = ?, stock = ? WHERE store_id = ? AND owner_character_id = ?',
        { tier, currentStock, storeId, charId })

    local updatedCtx = buildStoreContext(src, storeId)
    updatedCtx.initialView = 'owner'
    TriggerClientEvent('cm-store:client:openStore', src, updatedCtx)
    notify(src, 'Store management settings saved.', 'success')
end)

-- Pay Tax
RegisterNetEvent('cm-store:server:payTax', function(storeId)
    local src = source
    storeId = tonumber(storeId) or 1
    local row = storeRow(storeId)
    local charId = characterId(src)

    if not row or not charId or tonumber(row.owner_character_id) ~= charId then
        return notify(src, 'You do not own this store.', 'error')
    end

    local cfg = Config.Ownership or {}
    local tax = math.max(0, math.floor(tonumber(cfg.taxAmount) or 12000))
    if not removeBank(src, tax, 'store-tax-' .. storeId) then
        return notify(src, ('You need $%d in the bank to pay store property tax.'):format(tax), 'error')
    end

    local due = os.date('!%Y-%m-%d %H:%M:%S', os.time() + ((tonumber(cfg.taxPeriodDays) or 7) * 86400))
    MySQL.update.await('UPDATE cm_stores SET tax_due_at = ? WHERE store_id = ? AND owner_character_id = ?',
        { due, storeId, charId })

    notify(src, 'Property tax paid successfully for 7 days.', 'success')
    local updatedCtx = buildStoreContext(src, storeId)
    updatedCtx.initialView = 'owner'
    TriggerClientEvent('cm-store:client:openStore', src, updatedCtx)
end)

-- Withdraw Business Balance
RegisterNetEvent('cm-store:server:withdrawBusiness', function(storeId)
    local src = source
    storeId = tonumber(storeId) or 1
    local row = storeRow(storeId)
    local charId = characterId(src)

    if not row or not charId or tonumber(row.owner_character_id) ~= charId then
        return notify(src, 'You do not own this store.', 'error')
    end

    local balance = math.max(0, math.floor(tonumber(row.business_balance) or 0))
    if balance <= 0 then
        return notify(src, 'There is no revenue balance to withdraw.', 'warning')
    end

    local changed = MySQL.update.await('UPDATE cm_stores SET business_balance = 0 WHERE store_id = ? AND owner_character_id = ? AND business_balance = ?',
        { storeId, charId, balance })

    if changed == 1 and addBank(src, balance, 'store-business-withdrawal-' .. storeId) then
        notify(src, ('$%d transferred from store business account to your bank.'):format(balance), 'success')
    end

    local updatedCtx = buildStoreContext(src, storeId)
    updatedCtx.initialView = 'owner'
    TriggerClientEvent('cm-store:client:openStore', src, updatedCtx)
end)

-- ============================================================
-- Checkout / Cart Order
-- ============================================================
local function processCheckout(src, data)
    local storeId = tonumber(data.storeId) or 1
    local items = type(data.items) == 'table' and data.items or {}
    local method = tostring(data.method or 'bank'):lower()

    if #items == 0 then
        return false, 'Your shopping basket is empty.'
    end

    if not isNearShop(src, storeId) then
        return false, 'You are too far from the store counter.'
    end

    local row = storeRow(storeId) or {}
    local mult = storePriceMultiplier(row)
    local availableStock = math.floor(tonumber(row.stock) or 0)

    -- Count total units and calculate cost
    local totalUnits = 0
    local orderTotal = 0
    local verifiedItems = {}

    for _, orderItem in ipairs(items) do
        local name = normalizeItemName(orderItem.item_name or orderItem.name)
        local count = math.floor(tonumber(orderItem.count or orderItem.quantity) or 0)
        local entry = CatalogMap[name]

        if entry and entry.enabled ~= false and count > 0 then
            if not canCarry(src, name, count) then
                return false, ('You cannot carry %dx %s.'):format(count, entry.label)
            end
            local unitPrice = math.max(1, math.ceil(entry.price * mult))
            local lineCost = unitPrice * count
            orderTotal = orderTotal + lineCost
            totalUnits = totalUnits + count
            verifiedItems[#verifiedItems + 1] = {
                name = name,
                label = entry.label,
                count = count,
                cost = lineCost,
            }
        end
    end

    if #verifiedItems == 0 then
        return false, 'No valid items in your basket.'
    end

    -- Store stock check
    if availableStock < totalUnits then
        return false, ('This store is out of stock (%d units remaining). The owner needs to restock.'):format(availableStock)
    end

    -- Payment deduction
    local paid, payErr = chargePlayer(src, method, orderTotal, 'cm-store-order-' .. storeId)
    if not paid then
        return false, tostring(payErr or 'Payment failed.')
    end

    -- Deliver items
    local refund = 0
    local deliveredNames = {}
    local deliveredUnits = 0

    for _, item in ipairs(verifiedItems) do
        if giveItem(src, item.name, item.count) then
            deliveredUnits = deliveredUnits + item.count
            deliveredNames[#deliveredNames + 1] = ('%dx %s'):format(item.count, item.label)
        else
            refund = refund + item.cost
        end
    end

    if refund > 0 then
        refundPlayer(src, method, refund, 'cm-store-refund-' .. storeId)
        notify(src, ('Some items could not be delivered. $%d was refunded.'):format(refund), 'warning')
    end

    local actualPaid = orderTotal - refund
    if deliveredUnits == 0 then
        return false, 'Could not deliver items to your inventory. Full payment was refunded.'
    end

    -- Deduct stock and route owner revenue
    if actualPaid > 0 then
        local ownerSharePercent = (Config.Ownership or {}).ownerRevenuePercent or 80
        local ownerShare = math.floor(actualPaid * (ownerSharePercent / 100))
        MySQL.update.await([[UPDATE cm_stores
            SET stock = GREATEST(0, stock - ?),
                business_balance = business_balance + IF(owner_character_id IS NOT NULL, ?, 0),
                daily_income = daily_income + IF(owner_character_id IS NOT NULL, ?, 0),
                weekly_income = weekly_income + IF(owner_character_id IS NOT NULL, ?, 0)
            WHERE store_id = ?]],
            { deliveredUnits, ownerShare, ownerShare, ownerShare, storeId })
    end

    local receipt = ('Purchased %s for $%d.'):format(table.concat(deliveredNames, ', '), actualPaid)
    return true, receipt, actualPaid
end

RegisterNetEvent('cm-store:server:checkoutOrder', function(data)
    local src = source
    data = type(data) == 'table' and data or {}

    if OrderLocks[src] then
        TriggerClientEvent('cm-store:client:orderResult', src, { ok = false, message = 'Please wait a moment.' })
        return
    end

    OrderLocks[src] = true
    local ok, success, message, paid = pcall(processCheckout, src, data)
    OrderLocks[src] = nil

    if not ok then
        print(('[%s] Checkout error: %s'):format(RESOURCE, tostring(success)))
        TriggerClientEvent('cm-store:client:orderResult', src, { ok = false, message = 'Server error during checkout.' })
        return
    end

    TriggerClientEvent('cm-store:client:orderResult', src, {
        ok = success == true,
        message = tostring(message or ''),
        paid = paid or 0,
        cash = getCash(src) or 0,
        bank = getBank(src) or 0,
    })
end)

AddEventHandler('playerDropped', function()
    local src = source
    OrderLocks[src] = nil
    RequestCooldowns[src] = nil
end)
