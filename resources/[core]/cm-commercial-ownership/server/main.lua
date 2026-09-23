-- cm-commercial-ownership/server/main.lua
--
-- Shared commercial-property ownership engine: buy / manage (price tier +
-- restock) / pay 7-day tax / withdraw business balance, plus the shared
-- schema-creation, shop-seeding, and tax-forfeiture background threads.
--
-- Resources that own a simple "commercial shop" table (barber shops, clothing
-- stores, ...) register a book with Register(key, opts) at startup and wire
-- their own net events / NUI messages around the exports below. This module
-- owns only the shared row logic -- never a caller's event names, session
-- rules, or per-item fee processing.

local books = {}

local function getPlayerData()
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    return exports['cm-playerdata']
end

local function characterId(src)
    local api = getPlayerData()
    if api then
        local ok, id = pcall(function() return api:GetCharacterId(src) end)
        if ok and tonumber(id) then return tonumber(id) end
    end
    local ply = Player(src)
    if ply and ply.state then
        local cid = ply.state.charId or ply.state.characterId
        if cid and tonumber(cid) then return tonumber(cid) end
    end
    return nil
end

local function getBank(src)
    local api = getPlayerData()
    if not api then return nil end
    local ok, amount = pcall(function() return api:GetBank(src) end)
    return ok and tonumber(amount) or nil
end

local function removeBank(src, amount, reason)
    local api = getPlayerData()
    if not api then return false end
    local ok, result = pcall(function() return api:RemoveBank(src, math.floor(amount), reason) end)
    return ok and result == true
end

local function addBank(src, amount, reason)
    local api = getPlayerData()
    if not api then return false end
    local ok, result = pcall(function() return api:AddBank(src, math.floor(amount), reason) end)
    return ok and result == true
end

local function notify(opts, src, message, kind)
    if GetResourceState('cm-hud') == 'started' then
        TriggerClientEvent('cm-hud:client:notify', src, tostring(message or ''), kind or 'info')
        return
    end
    TriggerClientEvent('chat:addMessage', src, {
        color = kind == 'error' and { 255, 60, 60 } or { 34, 245, 255 },
        multiline = false,
        args = { tostring(opts.notifyPrefix or ''), tostring(message or '') }
    })
end

local function computeTaxDueDays(taxDueAt, taxSecLeft)
    if taxSecLeft ~= nil then
        local s = tonumber(taxSecLeft) or 0
        if s <= 0 then return 0 end
        return math.min(7, math.ceil(s / 86400))
    end
    if not taxDueAt then return 0 end
    local secDiff = 0
    if type(taxDueAt) == 'string' then
        local y, m, d, h, mi, s = taxDueAt:match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')
        if y then
            local targetTime = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
            secDiff = os.difftime(targetTime, os.time())
        end
    elseif type(taxDueAt) == 'number' then
        secDiff = taxDueAt - os.time()
    end
    return math.max(0, math.min(7, math.ceil(secDiff / 86400)))
end

local function titleCase(s)
    s = tostring(s or '')
    if s == '' then return s end
    return s:sub(1, 1):upper() .. s:sub(2)
end

local function getRow(opts, shopId)
    if not MySQL or not shopId then return nil end
    return MySQL.single.await((
        'SELECT *, TIMESTAMPDIFF(SECOND, UTC_TIMESTAMP(), tax_due_at) AS tax_sec_left FROM %s WHERE shop_id = ? LIMIT 1'
    ):format(opts.table), { tostring(shopId) })
end

-- opts = {
--   table            = 'cm_barber_shops',     -- MySQL table name (created if missing)
--   reasonPrefix     = 'barber-shop',          -- bank ledger reason prefix (defaults to key)
--   notifyPrefix     = '[SALON]',              -- chat fallback prefix when cm-hud isn't running
--   thingLabel       = 'hair salon',           -- lowercase noun used in sentences
--   stockNoun        = 'Grooming supplies',    -- capacity message noun
--   stockOrderLabel  = 'grooming supplies',    -- "order X" message noun
--   stockUnitLabel   = 'grooming supply',      -- "+N X units" message noun
--   revenueLabel     = 'salon',                -- "$N X revenue transferred" noun
--   shopIds          = { 'davis', ... },       -- every valid shop id, for seeding
--   enabled, purchasePrice, taxAmount, defaultStock, maxStock,
--   restockUnitPrice, restockBatch, priceTiers = { low=, normal=, high= },
--   onPurchased = function(src, shopId) end,   -- called after a successful buy
--   onUpdated   = function(src, shopId) end,   -- called after manage/tax/withdraw/forfeiture
-- }
local function register(key, opts)
    opts = type(opts) == 'table' and opts or {}
    books[key] = opts

    CreateThread(function()
        Wait(1000)
        if not MySQL then
            print(('[cm-commercial-ownership] oxmysql is not ready; %s persistence is deferred.'):format(key))
            return
        end

        MySQL.query.await(([[CREATE TABLE IF NOT EXISTS %s (
            shop_id VARCHAR(50) NOT NULL PRIMARY KEY,
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
        )]]):format(opts.table))

        local defaultStock = tonumber(opts.defaultStock) or 0
        for _, shopId in ipairs(opts.shopIds or {}) do
            MySQL.insert.await(('INSERT IGNORE INTO %s (shop_id, stock) VALUES (?, ?)'):format(opts.table), { tostring(shopId), defaultStock })
        end
        print(('[cm-commercial-ownership] %s: table verified and seeded (%d shops).'):format(key, #(opts.shopIds or {})))
    end)

    CreateThread(function()
        while true do
            Wait(60000)
            if MySQL then
                local expired = MySQL.query.await((
                    'SELECT shop_id, owner_character_id, business_balance FROM %s ' ..
                    'WHERE owner_character_id IS NOT NULL AND tax_due_at IS NOT NULL AND tax_due_at <= UTC_TIMESTAMP()'
                ):format(opts.table)) or {}

                local defaultStock = tonumber(opts.defaultStock) or 0
                for _, row in ipairs(expired) do
                    MySQL.update.await((
                        "UPDATE %s SET owner_character_id = NULL, owner_name = NULL, price_tier = 'normal', business_balance = 0, stock = ?, tax_due_at = NULL " ..
                        'WHERE shop_id = ? AND owner_character_id = ?'
                    ):format(opts.table), { defaultStock, row.shop_id, row.owner_character_id })

                    print(('[cm-commercial-ownership] %s "%s" ownership removed from character %s due to unpaid property tax.'):format(key, tostring(row.shop_id), tostring(row.owner_character_id)))

                    for _, player in ipairs(GetPlayers()) do
                        local pSrc = tonumber(player)
                        if pSrc and characterId(pSrc) == tonumber(row.owner_character_id) then
                            notify(opts, pSrc, ('Your %s (%s) ownership has been removed due to unpaid property tax.'):format(opts.thingLabel or 'shop', tostring(row.shop_id)), 'error')
                            if opts.onUpdated then opts.onUpdated(pSrc, row.shop_id) end
                            break
                        end
                    end
                end
            end
        end
    end)
end

local function getPriceMultiplier(key, shopId)
    local opts = books[key]
    if not opts then return 1.0 end
    local row = getRow(opts, shopId)
    local tier = row and row.price_tier or 'normal'
    local tiers = opts.priceTiers or {}
    return tonumber(tiers[tier]) or tonumber(tiers.normal) or 1.00
end

local function buildDetailsPayload(key, shopId, src)
    local opts = books[key]
    if not opts then return {} end
    local row = getRow(opts, shopId)
    local charId = characterId(src)

    local isOwner = row and charId and tonumber(row.owner_character_id) == charId
    local isOwned = row and row.owner_character_id ~= nil

    local daysLeft = computeTaxDueDays(row and row.tax_due_at, row and row.tax_sec_left)
    local secLeft = tonumber(row and row.tax_sec_left) or 0
    local canPayTax = isOwner and (daysLeft < 7 and secLeft < (7 * 86400 - 3600))

    return {
        shopId = shopId,
        isOwned = isOwned,
        isOwner = isOwner,
        ownerName = row and row.owner_name or 'City Commercial Property',
        priceTier = row and row.price_tier or 'normal',
        priceMultiplier = tonumber(opts.priceTiers and opts.priceTiers[row and row.price_tier or 'normal']) or 1.0,
        stock = row and tonumber(row.stock) or (opts.defaultStock or 0),
        maxStock = opts.maxStock or 0,
        businessBalance = isOwner and tonumber(row.business_balance or 0) or 0,
        dailyIncome = isOwner and tonumber(row.daily_income or 0) or 0,
        weeklyIncome = isOwner and tonumber(row.weekly_income or 0) or 0,
        taxDueDays = isOwner and daysLeft or 0,
        canPayTax = canPayTax,
        purchasePrice = opts.purchasePrice or 0,
        taxAmount = opts.taxAmount or 0,
        restockBatch = opts.restockBatch or 0,
        restockCost = (opts.restockBatch or 0) * (opts.restockUnitPrice or 0),
    }
end

local function buy(key, shopId, src)
    local opts = books[key]
    if not opts then return false end
    shopId = tostring(shopId or '')
    local thing = opts.thingLabel or 'shop'

    if not opts.enabled then
        notify(opts, src, ('%s commercial ownership is not enabled.'):format(titleCase(thing)), 'error')
        return false
    end

    local charId = characterId(src)
    if not charId then
        notify(opts, src, 'Character identity not found.', 'error')
        return false
    end

    local row = getRow(opts, shopId)
    if not row then
        notify(opts, src, ('%s record not found.'):format(titleCase(thing)), 'error')
        return false
    end
    if row.owner_character_id then
        notify(opts, src, ('This %s is already owned by someone else.'):format(thing), 'error')
        return false
    end

    local price = math.max(0, math.floor(tonumber(opts.purchasePrice) or 0))
    local bankBalance = getBank(src) or 0
    if bankBalance < price then
        notify(opts, src, ('You need $%s in your bank account to purchase this %s.'):format(price, thing), 'error')
        return false
    end

    if not removeBank(src, price, (opts.reasonPrefix or key) .. '-purchase') then
        notify(opts, src, 'Payment failed. Could not process bank transaction.', 'error')
        return false
    end

    local api = getPlayerData()
    local fullName = (api and api.GetCharacterFullName and api:GetCharacterFullName(src)) or ('Character %d'):format(charId)

    local updated = MySQL.update.await((
        "UPDATE %s SET owner_character_id = ?, owner_name = ?, price_tier = 'normal', business_balance = 0, stock = ?, tax_due_at = DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 DAY) " ..
        'WHERE shop_id = ? AND owner_character_id IS NULL'
    ):format(opts.table), { charId, fullName, opts.defaultStock or 0, shopId })

    if updated ~= 1 then
        addBank(src, price, (opts.reasonPrefix or key) .. '-purchase-refund')
        notify(opts, src, ('The %s was just acquired by another citizen. Your funds were refunded.'):format(thing), 'error')
        return false
    end

    notify(opts, src, ('Congratulations! You are now the owner of %s. Property tax is due in 7 days.'):format(shopId), 'success')
    if opts.onPurchased then opts.onPurchased(src, shopId) end
    return true
end

local function manage(key, data, src)
    local opts = books[key]
    if not opts then return false end
    data = type(data) == 'table' and data or {}
    local shopId = tostring(data.shopId or '')
    local thing = opts.thingLabel or 'shop'
    local charId = characterId(src)
    if not charId then return false end

    local row = getRow(opts, shopId)
    if not row or tonumber(row.owner_character_id) ~= charId then
        notify(opts, src, ('You do not own this %s.'):format(thing), 'error')
        return false
    end

    local tier = tostring(data.priceTier or row.price_tier or 'normal'):lower()
    if not (opts.priceTiers or {})[tier] then
        notify(opts, src, 'Invalid price tier specified.', 'error')
        return false
    end

    local stock = tonumber(row.stock) or 0
    local maxStock = tonumber(opts.maxStock) or 0

    if data.restock == true then
        local batch = tonumber(opts.restockBatch) or 0
        local cost = math.floor(batch * (tonumber(opts.restockUnitPrice) or 0))
        if stock >= maxStock then
            notify(opts, src, ('%s storage is already at maximum capacity.'):format(opts.stockNoun or 'Stock'), 'error')
            return false
        end
        if not removeBank(src, cost, (opts.reasonPrefix or key) .. '-restock') then
            notify(opts, src, ('You need $%s in your bank account to order %s.'):format(cost, opts.stockOrderLabel or 'stock'), 'error')
            return false
        end
        stock = math.min(maxStock, stock + batch)
        notify(opts, src, ('Ordered +%d %s units for $%s.'):format(batch, opts.stockUnitLabel or 'stock', cost), 'success')
    end

    MySQL.update.await((
        'UPDATE %s SET price_tier = ?, stock = ? WHERE shop_id = ? AND owner_character_id = ?'
    ):format(opts.table), { tier, stock, shopId, charId })

    notify(opts, src, ('%s settings saved.'):format(titleCase(thing)), 'success')
    if opts.onUpdated then opts.onUpdated(src, shopId) end
    return true
end

local function payTax(key, shopId, src)
    local opts = books[key]
    if not opts then return false end
    shopId = tostring(shopId or '')
    local thing = opts.thingLabel or 'shop'
    local charId = characterId(src)
    if not charId then return false end

    local row = getRow(opts, shopId)
    if not row or tonumber(row.owner_character_id) ~= charId then
        notify(opts, src, ('You do not own this %s.'):format(thing), 'error')
        return false
    end

    local daysLeft = computeTaxDueDays(row.tax_due_at, row.tax_sec_left)
    local secLeft = tonumber(row.tax_sec_left) or 0
    if daysLeft >= 7 or secLeft >= (7 * 86400 - 3600) then
        notify(opts, src, 'Property tax is already paid for the maximum 7 days. You cannot pre-pay beyond 7 days.', 'error')
        return false
    end

    local taxAmount = math.max(0, math.floor(tonumber(opts.taxAmount) or 0))
    local bankBalance = getBank(src) or 0
    if bankBalance < taxAmount then
        notify(opts, src, ('You need $%s in your bank account to pay %s property tax.'):format(taxAmount, thing), 'error')
        return false
    end

    if not removeBank(src, taxAmount, (opts.reasonPrefix or key) .. '-tax') then
        notify(opts, src, ('Payment failed. You need $%s in your bank account to pay %s property tax.'):format(taxAmount, thing), 'error')
        return false
    end

    MySQL.update.await((
        'UPDATE %s SET tax_due_at = DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 DAY) WHERE shop_id = ? AND owner_character_id = ?'
    ):format(opts.table), { shopId, charId })

    notify(opts, src, ('%s property tax paid ($%s from bank). Coverage renewed for 7 days.'):format(titleCase(thing), taxAmount), 'success')
    if opts.onUpdated then opts.onUpdated(src, shopId) end
    return true
end

local function withdraw(key, shopId, src)
    local opts = books[key]
    if not opts then return false end
    shopId = tostring(shopId or '')
    local thing = opts.thingLabel or 'shop'
    local charId = characterId(src)
    if not charId then return false end

    local row = getRow(opts, shopId)
    if not row or tonumber(row.owner_character_id) ~= charId then
        notify(opts, src, ('You do not own this %s.'):format(thing), 'error')
        return false
    end

    local balance = math.max(0, math.floor(tonumber(row.business_balance) or 0))
    if balance <= 0 then
        notify(opts, src, ('There is no %s business balance available to withdraw.'):format(thing), 'error')
        return false
    end

    local changed = MySQL.update.await((
        'UPDATE %s SET business_balance = 0 WHERE shop_id = ? AND owner_character_id = ? AND business_balance = ?'
    ):format(opts.table), { shopId, charId, balance })

    if changed == 1 and addBank(src, balance, (opts.reasonPrefix or key) .. '-balance-withdrawal') then
        notify(opts, src, ('$%s %s revenue transferred to your bank account.'):format(balance, opts.revenueLabel or 'business'), 'success')
        if opts.onUpdated then opts.onUpdated(src, shopId) end
        return true
    end

    notify(opts, src, 'Withdrawal could not be completed.', 'error')
    return false
end

exports('Register', register)
exports('GetRow', function(key, shopId)
    local opts = books[key]
    if not opts then return nil end
    return getRow(opts, shopId)
end)
exports('GetPriceMultiplier', getPriceMultiplier)
exports('BuildDetailsPayload', buildDetailsPayload)
exports('Buy', buy)
exports('Manage', manage)
exports('PayTax', payTax)
exports('Withdraw', withdraw)
