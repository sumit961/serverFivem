-- nv_cloth/server/sv_clothing_stores.lua
-- Clothing Store Commercial Ownership & Management.
--
-- The buy/manage/pay-tax/withdraw engine, schema, seeding, and tax-forfeiture
-- threads live in the shared cm-commercial-ownership resource (also used by
-- cm-characters' barber shops). This file owns only what's clothing-store
-- specific: the shop id list and the net events/NUI wiring that cl_shop.lua
-- expects. Per-item purchase revenue/stock (a different flow entirely) stays
-- inline in sv_cloth.lua's checkout logic.

local Config = Config or {}

local KEY = 'clothing_store'
local CO = exports['cm-commercial-ownership']

local function clothingStoreShopIds()
    local ids = {}
    if type(Config.Shops) == 'table' then
        for _, shop in ipairs(Config.Shops) do
            if shop and shop.id then ids[#ids + 1] = shop.id end
        end
    end
    return ids
end

CO:Register(KEY, {
    table            = 'cm_clothing_stores',
    reasonPrefix     = 'clothing-store',
    notifyPrefix     = '[STORE]',
    thingLabel       = 'clothing store',
    stockNoun        = 'Store stock',
    stockOrderLabel  = 'stock',
    stockUnitLabel   = 'stock',
    revenueLabel     = 'business',
    shopIds          = clothingStoreShopIds(),
    enabled          = (Config.Ownership or {}).enabled,
    purchasePrice    = (Config.Ownership or {}).purchasePrice,
    taxAmount        = (Config.Ownership or {}).taxAmount,
    defaultStock     = (Config.Ownership or {}).defaultStock,
    maxStock         = (Config.Ownership or {}).maxStock,
    restockUnitPrice = (Config.Ownership or {}).restockUnitPrice,
    restockBatch     = (Config.Ownership or {}).restockBatch,
    priceTiers       = (Config.Ownership or {}).priceTiers,
    onPurchased = function(src, shopId)
        TriggerClientEvent('nv_cloth:client:storePurchased', src, shopId)
    end,
    onUpdated = function(src, shopId)
        TriggerClientEvent('nv_cloth:client:storeUpdated', src, shopId)
    end,
})

function GetClothingStoreRow(shopId)
    return CO:GetRow(KEY, shopId)
end

function GetClothingStorePriceMultiplier(shopId)
    return CO:GetPriceMultiplier(KEY, shopId)
end

-- Server Event: Get Store Details (for dialogue and NUI)
RegisterNetEvent('nv_cloth:server:getStoreDetails', function(shopId)
    local src = source
    shopId = tostring(shopId or '')
    local payload = CO:BuildDetailsPayload(KEY, shopId, src)
    TriggerClientEvent('nv_cloth:client:storeDetailsResult', src, payload)
end)

-- Server Event: Buy Store
RegisterNetEvent('nv_cloth:server:buyStore', function(shopId)
    CO:Buy(KEY, shopId, source)
end)

-- Server Event: Manage Store (Price Tier & Restock)
RegisterNetEvent('nv_cloth:server:manageStore', function(data)
    CO:Manage(KEY, data, source)
end)

-- Server Event: Pay Store Tax (max 7 days, strictly from bank)
RegisterNetEvent('nv_cloth:server:payStoreTax', function(shopId)
    CO:PayTax(KEY, shopId, source)
end)

-- Server Event: Withdraw Store Business Balance
RegisterNetEvent('nv_cloth:server:withdrawStoreBalance', function(shopId)
    CO:Withdraw(KEY, shopId, source)
end)

exports('GetClothingStoreRow', GetClothingStoreRow)
exports('GetClothingStorePriceMultiplier', GetClothingStorePriceMultiplier)
