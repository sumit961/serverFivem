-- Consent-based medicine sales. The medic creates an offer; the buyer must
-- accept before the server revalidates both players, transfers payment,
-- consumes hospital stock and delivers the authoritative shared item.

local PendingMedicineOffers = {} -- [buyerSrc] = { sellerSrc, itemName, expires }
local MedicineJournalReady = false
local MedicineCatalogValidated = false
local ValidMedicineItems = {}

local function medicineNotify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function catalogEntry(itemName)
    if not MedicineCatalogValidated or not ValidMedicineItems[tostring(itemName or '')] then return nil end
    for _, entry in ipairs((Config.MedicineSales or {}).catalog or {}) do
        if tostring(entry.item) == tostring(itemName or '') then return entry end
    end
end

local function saleRangeValid(sellerSrc, buyerSrc)
    if not GetPlayerName(sellerSrc) or not GetPlayerName(buyerSrc) then return false end
    if GetPlayerRoutingBucket(sellerSrc) ~= GetPlayerRoutingBucket(buyerSrc) then return false end
    local sellerPed, buyerPed = GetPlayerPed(sellerSrc), GetPlayerPed(buyerSrc)
    if not sellerPed or sellerPed == 0 or not buyerPed or buyerPed == 0 then return false end
    return #(GetEntityCoords(sellerPed) - GetEntityCoords(buyerPed))
        <= (tonumber((Config.MedicineSales or {}).maxDistance) or 3.0)
end

local function authorizedSeller(src)
    local sellerCid = cid(src)
    local member = sellerCid and memberFor(sellerCid)
    local permission = tostring((Config.MedicineSales or {}).permission or 'ems.sell_medicine')
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) or not has(member, permission) then
        return nil
    end
    return sellerCid
end

local function refund(sellerSrc, buyerSrc, price)
    if price <= 0 then return true end
    local refunded = false
    pcall(function()
        refunded = exports[Config.PlayerDataResource]:TransferMoneyBetweenDetailed(
            sellerSrc, buyerSrc, 'cash', price, 'ems_medicine_sale_refund') == true
    end)
    return refunded
end

local function completeSale(sellerSrc, buyerSrc, itemName)
    local entry = catalogEntry(itemName)
    local sellerCid = authorizedSeller(sellerSrc)
    if not entry or not sellerCid then return false, 'The medic is no longer authorized to sell this medicine.' end
    if not saleRangeValid(sellerSrc, buyerSrc) then return false, 'You are no longer close enough to complete the sale.' end

    local price = math.max(0, math.floor(tonumber(entry.price) or 0))
    local label = tostring(entry.label or entry.item)
    if not MedicineJournalReady then return false, 'Medicine payment service is still starting.' end
    local buyerCid = cid(buyerSrc)
    if not buyerCid then return false, 'The buyer character is not ready.' end
    local operationKey = ('sale:%s:%s:%d:%d'):format(sellerCid, buyerCid, os.time(), math.random(100000, 999999))
    local journalId = MySQL.insert.await([[INSERT INTO cm_ems_medicine_sales
        (operation_key, seller_cid, buyer_cid, item_name, price, status)
        VALUES (?, ?, ?, ?, ?, 'initiated')]], { operationKey, sellerCid, buyerCid, entry.item, price })
    if not journalId then return false, 'The medicine sale could not be started safely.' end
    local canCarry, carryError = false, nil
    pcall(function()
        canCarry, carryError = exports[Config.InventoryResource]:CanCarryItem(buyerSrc, entry.item, 1)
    end)
    if canCarry ~= true then return false, carryError or "You can't carry any more of that item." end

    local paid, paymentError = true, nil
    if price > 0 then
        pcall(function()
            paid, paymentError = exports[Config.PlayerDataResource]:TransferMoneyBetweenDetailed(
                buyerSrc, sellerSrc, 'cash', price, 'ems_medicine_sale')
        end)
        if paid ~= true then
            MySQL.update.await([[UPDATE cm_ems_medicine_sales SET status = 'failed', failure_reason = ?
                WHERE id = ?]], { tostring(paymentError or 'payment_failed'), journalId })
            return false, paymentError == 'insufficient_funds' and 'You do not have enough cash.'
                or 'The payment could not be completed.'
        end
    end
    MySQL.update.await([[UPDATE cm_ems_medicine_sales SET status = 'paid', updated_at = CURRENT_TIMESTAMP
        WHERE id = ?]], { journalId })

    if type(EMSConsumeMedicineStock) ~= 'function' then
        local refunded = refund(sellerSrc, buyerSrc, price)
        MySQL.update.await([[UPDATE cm_ems_medicine_sales SET status = ?, failure_reason = ?
            WHERE id = ?]], { refunded and 'refunded' or 'refund_pending', 'stock_not_ready', journalId })
        return false, 'Hospital medicine stock is not ready.'
    end

    local consumed, _, units, stockError = EMSConsumeMedicineStock(entry.item, 1, sellerCid, 'ems_medicine_sale')
    if consumed ~= true then
        local refunded = refund(sellerSrc, buyerSrc, price)
        MySQL.update.await([[UPDATE cm_ems_medicine_sales SET status = ?, failure_reason = ?
            WHERE id = ?]], { refunded and 'refunded' or 'refund_pending', tostring(stockError or 'stock_low'), journalId })
        return false, stockError or 'Hospital medicine stock is too low.'
    end
    MySQL.update.await([[UPDATE cm_ems_medicine_sales SET status = 'stock_consumed', stock_units = ?,
        updated_at = CURRENT_TIMESTAMP WHERE id = ?]], { units, journalId })

    local given = false
    pcall(function()
        given = exports[Config.InventoryResource]:AddItem(
            buyerSrc, entry.item, 1, nil, 'ems_medicine_sale') == true
    end)
    if not given then
        if type(EMSRestoreMedicineStock) == 'function' then
            EMSRestoreMedicineStock(units, sellerCid, 'ems_medicine_sale_rollback')
        end
        local refunded = refund(sellerSrc, buyerSrc, price)
        MySQL.update.await([[UPDATE cm_ems_medicine_sales SET status = ?, failure_reason = ?
            WHERE id = ?]], { refunded and 'refunded' or 'refund_pending', 'inventory_delivery_failed', journalId })
        return false, "Your inventory is full. The sale was cancelled."
    end

    MySQL.update.await([[UPDATE cm_ems_medicine_sales SET status = 'completed', completed_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP WHERE id = ?]], { journalId })
    log(sellerCid, 'medicine_sold', {
        buyerCid = buyerCid, item = entry.item, price = price, stockUnits = units,
    })
    medicineNotify(sellerSrc, ('Sold %s for $%d from hospital stock.'):format(label, price), 'success')
    return true, ('Bought %s for $%d.'):format(label, price)
end

AddEventHandler('cm-ems:server:medicineSaleAction', function(src, targetSrc, action)
    if (Config.MedicineSales or {}).enabled == false then return end
    src, targetSrc = tonumber(src), tonumber(targetSrc)
    if not src or not targetSrc or src == targetSrc then return end
    if not rateLimit(src, 'ems_sell_medicine_offer', 1200) then
        return medicineNotify(src, 'Please wait.', 'error')
    end
    local itemName = tostring(action or ''):match('^ems_sell_(.+)$')
    local entry, sellerCid = itemName and catalogEntry(itemName), authorizedSeller(src)
    if not entry then return medicineNotify(src, 'That item is not for sale.', 'error') end
    if not sellerCid then return medicineNotify(src, 'You must be an on-duty EMS medic with medicine-sale permission.', 'error') end
    if not saleRangeValid(src, targetSrc) then return medicineNotify(src, 'Move closer to that player.', 'error') end
    if PendingMedicineOffers[targetSrc] then return medicineNotify(src, 'That player already has a medicine offer.', 'error') end

    local timeoutMs = math.max(5000, math.min(tonumber((Config.MedicineSales or {}).offerTimeoutMs) or 15000, 30000))
    PendingMedicineOffers[targetSrc] = {
        sellerSrc = src, itemName = itemName, expires = GetGameTimer() + timeoutMs,
    }
    TriggerClientEvent('cm-ems:client:medicineOffer', targetSrc, {
        sellerName = nameFor(sellerCid),
        itemLabel = tostring(entry.label or entry.item),
        price = math.max(0, math.floor(tonumber(entry.price) or 0)),
        timeoutMs = timeoutMs,
    })
    medicineNotify(src, ('Medicine offer sent to Character ID %s.'):format(tostring(cid(targetSrc) or '?')), 'inform')
end)

RegisterNetEvent('cm-ems:server:medicineOfferResponse', function(accepted)
    local buyerSrc = source
    local offer = PendingMedicineOffers[buyerSrc]
    PendingMedicineOffers[buyerSrc] = nil
    if not offer then return end
    local sellerSrc = tonumber(offer.sellerSrc)
    if GetGameTimer() > offer.expires then
        if sellerSrc and GetPlayerName(sellerSrc) then medicineNotify(sellerSrc, 'The medicine offer expired.', 'error') end
        return
    end
    if accepted ~= true then
        if sellerSrc and GetPlayerName(sellerSrc) then medicineNotify(sellerSrc, 'The player refused the medicine offer.', 'error') end
        return medicineNotify(buyerSrc, 'Medicine offer refused.', 'inform')
    end
    if not rateLimit(buyerSrc, 'ems_medicine_offer_response', 800) then return end
    local ok, message = completeSale(sellerSrc, buyerSrc, offer.itemName)
    medicineNotify(buyerSrc, message, ok and 'success' or 'error')
    if not ok and sellerSrc and GetPlayerName(sellerSrc) then medicineNotify(sellerSrc, message, 'error') end
end)

AddEventHandler('playerDropped', function()
    local src = source
    PendingMedicineOffers[src] = nil
    for buyerSrc, offer in pairs(PendingMedicineOffers) do
        if offer.sellerSrc == src then
            PendingMedicineOffers[buyerSrc] = nil
            if GetPlayerName(buyerSrc) then medicineNotify(buyerSrc, 'The medicine offer was cancelled.', 'error') end
        end
    end
end)

CreateThread(function()
    local configured = {}
    for _, entry in ipairs((Config.MedicineSales or {}).catalog or {}) do
        configured[tostring(entry.item or '')] = true
    end
    for itemName in pairs(((Config.MedicineStock or {}).itemCosts or {})) do
        configured[tostring(itemName)] = true
    end
    for itemName in pairs(configured) do
        local exists = itemName ~= ''
        if exists then
            local ok, result = pcall(function() return exports['cm-items']:Exists(itemName, true) end)
            exists = ok and result == true
        end
        ValidMedicineItems[itemName] = exists
        if not exists then
            print(('[cm-ems] ERROR: Medicine item "%s" is not registered in cm-items; sales are disabled for it.')
                :format(itemName))
        end
    end
    MedicineCatalogValidated = true

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_ems_medicine_sales (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        operation_key VARCHAR(128) NOT NULL,
        seller_cid VARCHAR(64) NOT NULL,
        buyer_cid VARCHAR(64) NOT NULL,
        item_name VARCHAR(64) NOT NULL,
        price INT UNSIGNED NOT NULL DEFAULT 0,
        stock_units INT UNSIGNED NOT NULL DEFAULT 0,
        status ENUM('initiated','paid','stock_consumed','completed','failed','refunded','refund_pending') NOT NULL,
        failure_reason VARCHAR(160) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        completed_at TIMESTAMP NULL,
        PRIMARY KEY (id),
        UNIQUE KEY uniq_cm_ems_medicine_sale_operation (operation_key),
        KEY idx_cm_ems_medicine_sale_reconcile (status, updated_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MedicineJournalReady = true
    local interrupted = MySQL.query.await([[SELECT id, seller_cid, buyer_cid, price, stock_units, status
        FROM cm_ems_medicine_sales
        WHERE status IN ('paid','stock_consumed','refund_pending')]]) or {}
    for _, row in ipairs(interrupted) do
        local sellerSrc, buyerSrc = sourceFor(row.seller_cid), sourceFor(row.buyer_cid)
        if sellerSrc and buyerSrc then
            if tostring(row.status) == 'stock_consumed' and type(EMSRestoreMedicineStock) == 'function' then
                EMSRestoreMedicineStock(tonumber(row.stock_units) or 0, row.seller_cid, 'ems_sale_restart_reconcile')
            end
            local refunded = refund(sellerSrc, buyerSrc, tonumber(row.price) or 0)
            MySQL.update.await([[UPDATE cm_ems_medicine_sales SET status = ?, failure_reason = ? WHERE id = ?]], {
                refunded and 'refunded' or 'refund_pending', 'resource_restart_reconcile', row.id,
            })
        end
    end
    while true do
        Wait(1000)
        local now = GetGameTimer()
        for buyerSrc, offer in pairs(PendingMedicineOffers) do
            if now > offer.expires then
                PendingMedicineOffers[buyerSrc] = nil
                if GetPlayerName(offer.sellerSrc) then
                    medicineNotify(offer.sellerSrc, 'The medicine offer expired.', 'error')
                end
            end
        end
    end
end)
