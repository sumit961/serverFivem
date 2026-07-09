-- cm-store/server/main.lua
-- Hard-coded general item store. The catalog is defined in Config.Catalog (no
-- admin add UI). On start each entry is created as a cm-items definition so it
-- can be given / dropped / used, then offered for sale here.
-- What an item DOES when used is defined in code (cm-itemactions / owning
-- resource), keyed by name -- never here.

local RESOURCE = GetCurrentResourceName()
local Catalog = {}     -- ordered public list
local CatalogMap = {}  -- item_name -> entry
local Stock = {}       -- item_name -> remaining (finite stock only)

local function notify(src, msg, typ)
    if src == 0 then print(('[%s] %s'):format(RESOURCE, tostring(msg or ''))); return end
    TriggerClientEvent('cm-hud:client:notify', src, tostring(msg or ''), typ or 'info')
end

local function itemsResource() return Config.ItemsResource or 'cm-items' end

local function normalizeItemName(value)
    value = tostring(value or ''):lower():gsub('%s+', '_'):gsub('[^a-z0-9_%-%.]', '_'):gsub('_+', '_')
    return value:gsub('^_+', ''):gsub('_+$', ''):sub(1, 80)
end

-- ============================================================
-- Build catalog from config + seed cm-items definitions
-- ============================================================
local function currentStock(name)
    local s = Stock[name]
    return s ~= nil and s or -1
end

-- Pull the current image from cm-items so images set in the item preview show up
-- in the store immediately (cm-items is the single source of truth).
local function liveImage(name, fallback)
    if GetResourceState(itemsResource()) == 'started' then
        local ok, def = pcall(function() return exports[itemsResource()]:GetItem(name) end)
        if ok and type(def) == 'table' and def.image and def.image ~= '' then return def.image end
    end
    return fallback or ''
end

local function buildPublicEntry(entry)
    return {
        item_name = entry.name,
        label = entry.label,
        category = entry.category,
        price = entry.price,
        stock = currentStock(entry.name),
        enabled = entry.enabled ~= false,
        image = liveImage(entry.name, entry.image),
        description = entry.description or '',
    }
end

local function getCatalog()
    local out = {}
    for _, entry in ipairs(Catalog) do
        if entry.enabled ~= false then out[#out + 1] = buildPublicEntry(entry) end
    end
    return out
end

local function seedCatalog()
    Catalog, CatalogMap, Stock = {}, {}, {}
    local hasItems = GetResourceState(itemsResource()) == 'started'

    for _, raw in ipairs(Config.Catalog or {}) do
        local name = normalizeItemName(raw.name or raw.item_name)
        if name ~= '' and not CatalogMap[name] then
            local entry = {
                name = name,
                label = tostring(raw.label or name),
                category = tostring(raw.category or 'misc'):lower(),
                price = math.max(0, math.floor(tonumber(raw.price) or 0)),
                stock = math.floor(tonumber(raw.stock) or -1),
                weight = math.max(0, math.floor(tonumber(raw.weight) or 0)),
                usable = raw.usable == true,
                image = raw.image and tostring(raw.image) or '',
                description = tostring(raw.description or ''),
                enabled = raw.enabled ~= false,
            }

            -- Create/refresh the cm-items definition (identity only).
            if hasItems then
                local ok, res = pcall(function()
                    return exports[itemsResource()]:SaveCatalogItem({
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
                if ok and type(res) == 'table' and res.image then entry.image = res.image end
            end

            if entry.stock and entry.stock >= 0 then Stock[name] = entry.stock end
            Catalog[#Catalog + 1] = entry
            CatalogMap[name] = entry
        end
    end
    print(('[%s] catalog loaded: %s items'):format(RESOURCE, #Catalog))
end

CreateThread(function()
    -- Wait for cm-items so definitions seed cleanly.
    local tries = 0
    while GetResourceState(itemsResource()) ~= 'started' and tries < 60 do Wait(500); tries = tries + 1 end
    Wait(500)
    seedCatalog()
end)

-- ============================================================
-- Inventory + money
-- ============================================================
local function inventorySuccess(result)
    if result == true then return true end
    if type(result) == 'number' then return result > 0 end
    if type(result) == 'table' then
        return result.success == true or result.ok == true or result.added == true or result[1] == true
    end
    return false
end

local function giveItem(src, itemName, amount)
    if GetResourceState(itemsResource()) == 'started' then
        local ok, res = pcall(function() return exports[itemsResource()]:GiveCatalogItem(src, itemName, amount) end)
        if ok and res == true then return true end
    end
    if GetResourceState(Config.Inventory or 'cm-inventory') ~= 'started' then return false, 'inventory_not_available' end
    local inv = exports[Config.Inventory or 'cm-inventory']
    local ok, result = pcall(function() return inv:AddItem(src, itemName, amount, {}, nil, 'cm_store_purchase') end)
    if ok and inventorySuccess(result) then return true end
    return false, 'inventory_add_failed'
end

local function normalizeMoneyAccount(account)
    account = tostring(account or 'bank'):lower()
    if account == 'money' then account = 'cash' end
    if account ~= 'cash' and account ~= 'bank' then account = 'bank' end
    return account
end

local function playerdataMoneyAvailable() return GetResourceState('cm-playerdata') == 'started' end

local function removeMoney(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    account = normalizeMoneyAccount(account)
    if not playerdataMoneyAvailable() then return false, 'Wallet is not available.' end
    local pd = exports['cm-playerdata']
    local canOk, canPay = pcall(function() return pd:CanAfford(src, account, amount) end)
    if canOk and canPay == false then return false, ('Not enough %s.'):format(account) end
    local ok, result = pcall(function() return pd:RemoveMoney(src, account, amount, reason) end)
    if ok and result == true then return true end
    return false, ('Not enough %s.'):format(account)
end

local function refundMoney(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or not playerdataMoneyAvailable() then return false end
    account = normalizeMoneyAccount(account)
    local ok, result = pcall(function() return exports['cm-playerdata']:AddMoney(src, account, amount, reason) end)
    return ok and result == true
end

-- ============================================================
-- Purchase flow (proximity + per-player lock)
-- ============================================================
local PurchaseLock = {}
AddEventHandler('playerDropped', function() if source then PurchaseLock[source] = nil end end)

local function isNearShop(src)
    if not Config.Shops or #Config.Shops == 0 then return true end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pcoords = GetEntityCoords(ped)
    local maxDist = tonumber(Config.PurchaseDistance) or 15.0
    for _, shop in ipairs(Config.Shops) do
        local c = shop.coords or shop.pedCoords
        if c then
            local sx = tonumber(c.x) or tonumber(c[1])
            local sy = tonumber(c.y) or tonumber(c[2])
            local sz = tonumber(c.z) or tonumber(c[3])
            if sx and sy and sz and #(pcoords - vector3(sx, sy, sz)) <= maxDist then return true end
        end
    end
    return false
end

local function processPurchase(src, data)
    local itemName = normalizeItemName(data.item_name)
    local method = tostring(data.method or 'bank'):lower() == 'cash' and 'cash' or 'bank'
    local account = normalizeMoneyAccount(Config.Accounts and Config.Accounts[method] or method)

    local entry = CatalogMap[itemName]
    if not entry or entry.enabled == false then notify(src, 'This item does not exist.', 'error'); return false end
    if Stock[itemName] ~= nil and Stock[itemName] <= 0 then notify(src, 'This item is out of stock.', 'error'); return false end

    local total = math.max(0, math.floor(entry.price))
    local paid, payErr = removeMoney(src, account, total, 'store_buy_' .. itemName)
    if not paid then notify(src, tostring(payErr or 'You do not have enough money.'), 'error'); return false end

    local added, err = giveItem(src, itemName, 1)
    if not added then
        refundMoney(src, account, total, 'store_refund_' .. itemName)
        notify(src, ('Could not add item to inventory (%s). Money refunded.'):format(tostring(err)), 'error')
        return false
    end

    if Stock[itemName] ~= nil then Stock[itemName] = math.max(0, Stock[itemName] - 1) end
    notify(src, ('Purchased %s.'):format(entry.label), 'success')
    return true
end

RegisterNetEvent('cm-store:server:buyItem', function(data)
    local src = source
    data = type(data) == 'table' and data or {}

    if PurchaseLock[src] then
        notify(src, 'Please wait for your previous purchase to finish.', 'error')
        TriggerClientEvent('cm-store:client:purchaseResult', src, false)
        return
    end
    if not isNearShop(src) then
        notify(src, 'You are too far from a store.', 'error')
        TriggerClientEvent('cm-store:client:purchaseResult', src, false)
        return
    end

    PurchaseLock[src] = true
    local ok, result = pcall(processPurchase, src, data)
    PurchaseLock[src] = nil

    if not ok then
        print(('[%s] buyItem error: %s'):format(RESOURCE, tostring(result)))
        notify(src, 'Purchase failed due to a server error.', 'error')
        TriggerClientEvent('cm-store:client:purchaseResult', src, false)
        return
    end
    TriggerClientEvent('cm-store:client:purchaseResult', src, result == true)
end)

RegisterNetEvent('cm-store:server:requestCatalog', function()
    local src = source
    TriggerClientEvent('cm-store:client:openCatalog', src, 'store', getCatalog(), Config.Categories or {})
end)

exports('GetStoreCatalog', function() return getCatalog() end)
