-- cm-characters/server/barber_ownership.lua
-- Hair Salon / Barbershop Commercial Ownership & Management.
--
-- The buy/manage/pay-tax/withdraw engine, schema, seeding, and tax-forfeiture
-- threads live in the shared cm-commercial-ownership resource (also used by
-- nv_cloth's clothing stores). This file owns only what's barber-specific:
-- the styling-session proof, the per-haircut service cost/fee, and the net
-- events/dialogue wiring that cm-characters' client code expects.

local Config = Config or {}

local KEY = 'barber'
local CO = exports['cm-commercial-ownership']

local function barberShopIds()
    local ids = {}
    for _, shop in ipairs(Config.BarberShops or {}) do
        if shop and shop.id then ids[#ids + 1] = shop.id end
    end
    return ids
end

CO:Register(KEY, {
    table            = 'cm_barber_shops',
    reasonPrefix     = 'barber-shop',
    notifyPrefix     = '[SALON]',
    thingLabel       = 'hair salon',
    stockNoun        = 'Grooming supplies',
    stockOrderLabel  = 'grooming supplies',
    stockUnitLabel   = 'grooming supply',
    revenueLabel     = 'salon',
    shopIds          = barberShopIds(),
    enabled          = (Config.BarberOwnership or {}).enabled,
    purchasePrice    = (Config.BarberOwnership or {}).purchasePrice,
    taxAmount        = (Config.BarberOwnership or {}).taxAmount,
    defaultStock     = (Config.BarberOwnership or {}).defaultStock,
    maxStock         = (Config.BarberOwnership or {}).maxStock,
    restockUnitPrice = (Config.BarberOwnership or {}).restockUnitPrice,
    restockBatch     = (Config.BarberOwnership or {}).restockBatch,
    priceTiers       = (Config.BarberOwnership or {}).priceTiers,
    onPurchased = function(src, shopId)
        TriggerClientEvent('cm-characters:client:barberShopPurchased', src, shopId)
    end,
    onUpdated = function(src, shopId)
        TriggerClientEvent('cm-characters:client:barberShopUpdated', src, shopId)
    end,
})

function GetBarberShopRow(shopId)
    return CO:GetRow(KEY, shopId)
end

function GetBarberPriceMultiplier(shopId)
    return CO:GetPriceMultiplier(KEY, shopId)
end

function GetBarberServiceCost(shopId)
    local base = tonumber(Config.BarberCost or (Config.BarberOwnership and Config.BarberOwnership.baseCost) or 100) or 100
    local mult = GetBarberPriceMultiplier(shopId)
    return math.max(1, math.floor(base * mult))
end

function ProcessBarberServiceFee(shopId, customerSrc)
    if not shopId then return end
    local row = GetBarberShopRow(shopId)
    if not row then return end

    local cfg = Config.BarberOwnership or {}
    local totalFee = GetBarberServiceCost(shopId)

    -- Deduct 1 stock unit of grooming supplies if stock > 0
    local currentStock = math.max(0, (tonumber(row.stock) or 0) - 1)

    -- 80% revenue to owner if owned
    if row.owner_character_id then
        local sharePct = (tonumber(cfg.ownerRevenuePercent) or 80) / 100.0
        local ownerCut = math.max(0, math.floor(totalFee * sharePct))

        MySQL.update.await([[UPDATE cm_barber_shops
            SET stock = ?,
                business_balance = business_balance + ?,
                daily_income = daily_income + ?,
                weekly_income = weekly_income + ?
            WHERE shop_id = ?]],
            { currentStock, ownerCut, ownerCut, ownerCut, tostring(shopId) })
    else
        MySQL.update.await('UPDATE cm_barber_shops SET stock = ? WHERE shop_id = ?', { currentStock, tostring(shopId) })
    end
end

-- Barber styling sessions: proof the player actually walked up to a barber NPC
-- and started the interaction, rather than a modified client just firing
-- saveAppearance from anywhere within range of a shop's coords.
local barberSessions = {}

RegisterNetEvent('cm-characters:server:barberSessionStart', function(shopId)
    local src = source
    shopId = tostring(shopId or '')
    if shopId == '' then return end

    local shop = nil
    for _, s in ipairs(Config.BarberShops or {}) do
        if tostring(s.id) == shopId then
            shop = s
            break
        end
    end
    if not shop or not shop.coords then return end

    local ped = GetPlayerPed(src)
    local dist = #(GetEntityCoords(ped) - shop.coords)
    if dist > (Config.BarberNpcDistance or 45.0) then return end

    barberSessions[src] = { shopId = shopId, expires = GetGameTimer() + 120000 }
end)

AddEventHandler('playerDropped', function()
    barberSessions[source] = nil
end)

function IsBarberSessionActive(src, shopId)
    local session = barberSessions[src]
    if not session then return false end
    if GetGameTimer() > session.expires then
        barberSessions[src] = nil
        return false
    end
    if shopId and tostring(session.shopId) ~= tostring(shopId) then return false end
    return true
end

function ClearBarberSession(src)
    barberSessions[src] = nil
end

-- Server Event: Get Barber Shop Details (for dialogue and NUI)
RegisterNetEvent('cm-characters:server:getBarberShopDetails', function(shopId)
    local src = source
    shopId = tostring(shopId or '')
    local payload = CO:BuildDetailsPayload(KEY, shopId, src)
    payload.serviceCost = GetBarberServiceCost(shopId)
    TriggerClientEvent('cm-characters:client:barberShopDetailsResult', src, payload)
end)

-- Server Event: Buy Barber Shop
RegisterNetEvent('cm-characters:server:buyBarberShop', function(shopId)
    CO:Buy(KEY, shopId, source)
end)

-- Server Event: Manage Barber Shop (Price Tier & Restock)
RegisterNetEvent('cm-characters:server:manageBarberShop', function(data)
    CO:Manage(KEY, data, source)
end)

-- Server Event: Pay Barber Shop Tax (max 7 days, strictly from bank)
RegisterNetEvent('cm-characters:server:payBarberShopTax', function(shopId)
    CO:PayTax(KEY, shopId, source)
end)

-- Server Event: Withdraw Barber Shop Balance
RegisterNetEvent('cm-characters:server:withdrawBarberBalance', function(shopId)
    CO:Withdraw(KEY, shopId, source)
end)

exports('GetBarberShopRow', GetBarberShopRow)
exports('GetBarberPriceMultiplier', GetBarberPriceMultiplier)
exports('GetBarberServiceCost', GetBarberServiceCost)
exports('ProcessBarberServiceFee', ProcessBarberServiceFee)
