-- ============================================================
--  cm-house | sv_door.lua
--  Lock, buy, sell. Money never touches this resource's tables:
--  cm-playerdata is the only money authority.
-- ============================================================

function PushOwnership(cid)
    local src = GetSrcByCid(cid)
    if not src then return end

    local owned = {}
    for id in pairs(Houses) do
        local allowed = CanAccessProperty(cid, id, ACTIONS.HOUSE_ENTER, false)
        if allowed then owned[id] = true end
    end
    TriggerClientEvent('cm-house:client:syncOwnership', src, owned)
end
exports('PushOwnership', PushOwnership)


-- ------------------------------------------------------------
--  Purchase reservations
--  Money and SQL live in different resources, so a traditional single SQL
--  transaction cannot cover both. This database reservation makes the house
--  race-safe, then every failure is compensated with an immediate refund or a
--  durable refund_pending record for automatic recovery.
-- ------------------------------------------------------------
function EnsureHouseSecurityTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_house_purchase_locks (
            house_id INT NOT NULL PRIMARY KEY,
            buyer_cid INT NOT NULL,
            buyer_source INT NOT NULL,
            token VARCHAR(96) NOT NULL,
            price INT NOT NULL,
            account VARCHAR(32) NOT NULL,
            status VARCHAR(24) NOT NULL DEFAULT 'reserved',
            expires_at DATETIME NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY uq_house_purchase_token (token),
            INDEX idx_house_purchase_buyer (buyer_cid, status),
            INDEX idx_house_purchase_expiry (status, expires_at),
            CONSTRAINT fk_house_purchase_house FOREIGN KEY (house_id)
                REFERENCES cm_houses (id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.update.await("DELETE FROM cm_house_purchase_locks WHERE status = 'reserved' AND expires_at < NOW()")

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_house_sale_journal (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            token VARCHAR(128) NOT NULL,
            house_id INT NOT NULL,
            seller_cid INT NOT NULL,
            seller_source INT NULL,
            payout INT NOT NULL,
            account VARCHAR(32) NOT NULL DEFAULT 'bank',
            old_family_id INT NULL,
            status VARCHAR(24) NOT NULL DEFAULT 'prepared',
            last_error VARCHAR(255) NULL,
            ownership_released_at DATETIME NULL,
            payment_started_at DATETIME NULL,
            paid_at DATETIME NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uq_house_sale_token (token),
            KEY idx_house_sale_house (house_id, status),
            KEY idx_house_sale_seller (seller_cid, status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end

local function purchaseToken(src, cid, houseId)
    return ('house:%s:%s:%s:%s'):format(
        tostring(houseId), tostring(cid), tostring(os.time()), tostring(math.random(100000, 999999)))
end

local function clearPurchaseLock(token)
    MySQL.update.await('DELETE FROM cm_house_purchase_locks WHERE token = ?', { token })
end

local function compensatePurchase(src, cid, token, account, amount, reason)
    local refunded = GiveMoney(src, account, amount, reason or 'house_purchase_refund')
    if refunded then
        clearPurchaseLock(token)
        LogHouse(nil, nil, cid, 'house_purchase_refund', { amount = amount, account = account })
        return true
    end

    MySQL.update.await([[
        UPDATE cm_house_purchase_locks
        SET status = 'refund_pending', expires_at = DATE_ADD(NOW(), INTERVAL 10 MINUTE)
        WHERE token = ?
    ]], { token })
    Audit(src, 'house_purchase_refund_pending', {
        cid = cid, token = token, amount = amount, account = account,
    })
    return false
end

local function recoverPurchaseLocks()
    local rows = MySQL.query.await([[
        SELECT l.*, h.owner_cid
        FROM cm_house_purchase_locks l
        LEFT JOIN cm_houses h ON h.id = l.house_id
        WHERE (l.status = 'reserved' AND l.expires_at < NOW())
           OR (l.status IN ('charged', 'refund_pending') AND l.expires_at < NOW())
           OR h.id IS NULL
    ]]) or {}

    for _, rec in ipairs(rows) do
        local owner = DbPositiveInteger(rec.owner_cid)
        local buyer = DbPositiveInteger(rec.buyer_cid)
        if not rec.house_id or owner == buyer then
            clearPurchaseLock(rec.token)
        elseif rec.status == 'reserved' then
            clearPurchaseLock(rec.token)
        else
            local online = buyer and GetSrcByCid(buyer) or nil
            if online then
                compensatePurchase(online, buyer, rec.token, rec.account,
                    tonumber(rec.price) or 0, 'house_purchase_recovery_refund')
            else
                MySQL.update.await([[
                    UPDATE cm_house_purchase_locks
                    SET status = 'refund_pending', expires_at = DATE_ADD(NOW(), INTERVAL 10 MINUTE)
                    WHERE token = ?
                ]], { rec.token })
            end
        end
    end
end

CreateThread(function()
    Wait(15000)
    while true do
        local ok, err = pcall(recoverPurchaseLocks)
        if not ok then
            print(('[cm-house] ^1purchase recovery failed: %s^7'):format(tostring(err)))
        end
        Wait(60000)
    end
end)

-- ------------------------------------------------------------
--  Lock / unlock
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:toggleLock', function(src, houseId)
    local cid   = GetCid(src)
    local house = Houses[houseId]
    if not cid or not house then return false, 'That house is not registered.' end

    local allowed, why = CanAccessProperty(cid, houseId, ACTIONS.HOUSE_LOCK)
    if not allowed then return false, why end

    house.locked = not house.locked
    MySQL.update('UPDATE cm_houses SET locked = ? WHERE id = ?', { house.locked and 1 or 0, houseId })

    LogHouse(houseId, house.family_id, cid, house.locked and 'door_lock' or 'door_unlock', nil)
    TriggerClientEvent('cm-house:client:syncLock', -1, houseId, house.locked)

    return true, house.locked and 'Door locked.' or 'Door unlocked.', house.locked
end)

-- ------------------------------------------------------------
--  Buy
-- ------------------------------------------------------------
lib.callback.register('cm-house:server:buyHouse', function(src, houseId)
    houseId = tonumber(houseId)
    local cid   = GetCid(src)
    local house = houseId and Houses[houseId] or nil
    if not cid or not house then return false, 'That house is not registered.' end

    if house.owner_cid then return false, 'Someone already owns this house.' end
    local orphanWeapons = HouseWeaponStorageCount and HouseWeaponStorageCount(houseId) or 0
    if orphanWeapons > 0 then
        return false, 'This property has secured weapons awaiting admin recovery and cannot be purchased yet.'
    end
    if not house.for_sale and not Config.Purchase.autoListUnowned then
        return false, 'This house is not on the market.'
    end

    local account = tostring(Config.Purchase.account or 'bank')
    local price = math.max(0, math.floor(tonumber(house.price) or 0))
    local ttl = math.max(30, math.floor(tonumber(Config.Purchase.reservationSeconds) or 120))
    local token = purchaseToken(src, cid, houseId)

    -- Remove only abandoned reservations. A charged/refund_pending record is
    -- never discarded because it represents real money that must be resolved.
    MySQL.update.await([[
        DELETE FROM cm_house_purchase_locks
        WHERE house_id = ? AND status = 'reserved' AND expires_at < NOW()
    ]], { houseId })

    -- INSERT ... SELECT is the atomic race gate. The first buyer gets one row;
    -- every simultaneous buyer gets affectedRows=0 before any money is taken.
    local reserved = MySQL.update.await([[
        INSERT IGNORE INTO cm_house_purchase_locks
            (house_id, buyer_cid, buyer_source, token, price, account, status, expires_at)
        SELECT h.id, ?, ?, ?, ?, ?, 'reserved', FROM_UNIXTIME(?)
        FROM cm_houses h
        WHERE h.id = ?
          AND (h.owner_cid IS NULL OR h.owner_cid <= 0)
          AND (h.for_sale = 1 OR ? = 1)
    ]], {
        cid, src, token, price, account, os.time() + ttl,
        houseId, Config.Purchase.autoListUnowned and 1 or 0,
    })

    if not reserved or tonumber(reserved) <= 0 then
        local row = MySQL.single.await('SELECT owner_cid FROM cm_houses WHERE id = ? LIMIT 1', { houseId })
        if row and DbPositiveInteger(row.owner_cid) then
            return false, 'Someone bought this property first.'
        end
        return false, 'Another buyer is already completing this purchase. Try again shortly.'
    end

    if not TakeMoney(src, account, price, 'house_purchase') then
        clearPurchaseLock(token)
        local held = GetMoney(src, account)
        return false, ('%s costs $%s. You have $%s in your %s.')
            :format(house.label or 'This property', Comma(price), Comma(held or 0), account)
    end

    local marked = MySQL.update.await([[
        UPDATE cm_house_purchase_locks
        SET status = 'charged', expires_at = DATE_ADD(NOW(), INTERVAL 5 MINUTE)
        WHERE token = ? AND buyer_cid = ? AND status = 'reserved'
    ]], { token, cid })

    if not marked or tonumber(marked) <= 0 then
        local refunded = compensatePurchase(src, cid, token, account, price, 'house_purchase_lock_refund')
        return false, refunded
            and 'The purchase reservation changed. Your payment was refunded.'
            or 'The purchase failed and your refund is queued for recovery. Contact an administrator.'
    end

    local paidUntil
    if Config.Purchase.firstWeekFree == false then
        paidUntil = os.date('%Y-%m-%d', os.time())
    else
        paidUntil = os.date('%Y-%m-%d', os.time() + (7 * 86400))
    end

    -- Finalize only while this exact charged reservation still owns the lock.
    local finalized = MySQL.update.await([[
        UPDATE cm_houses h
        INNER JOIN cm_house_purchase_locks l ON l.house_id = h.id
        SET h.owner_cid = ?, h.for_sale = 0, h.paid_until = ?, h.locked = 1
        WHERE h.id = ?
          AND (h.owner_cid IS NULL OR h.owner_cid <= 0)
          AND l.token = ? AND l.buyer_cid = ? AND l.status = 'charged'
    ]], { cid, paidUntil, houseId, token, cid })

    if not finalized or tonumber(finalized) <= 0 then
        local refunded = compensatePurchase(src, cid, token, account, price, 'house_purchase_finalize_refund')
        return false, refunded
            and 'Another purchase changed the property. Your payment was refunded.'
            or 'The property could not be finalized and your refund is queued for recovery.'
    end

    clearPurchaseLock(token)

    house.owner_cid = cid
    house.for_sale  = false
    house.paid_until = paidUntil
    house.locked    = true

    OwnerHouses[cid] = OwnerHouses[cid] or {}
    local alreadyIndexed = false
    for _, existing in ipairs(OwnerHouses[cid]) do
        if tonumber(existing) == houseId then alreadyIndexed = true break end
    end
    if not alreadyIndexed then OwnerHouses[cid][#OwnerHouses[cid] + 1] = houseId end

    LogHouse(houseId, nil, cid, 'house_buy', { price = price, account = account })
    Audit(src, 'house_purchase', { houseId = houseId, cid = cid, price = price, account = account })

    TriggerClientEvent('cm-house:client:syncHouse', -1, BuildClientHouse(house))
    PushOwnership(cid)

    return true, ('You bought %s for $%s.'):format(house.label, Comma(price))
end)

-- ------------------------------------------------------------
--  Sell
--  Owner-only, enforced by OWNER_ONLY in sv_access.lua.
--
--  A linked house is the family's authoritative home. The sale transaction
--  therefore clears the property and deletes the complete family atomically.
--  Payment happens only after ownership is released and is journaled so a
--  repeated request cannot pay the same property twice.
-- ------------------------------------------------------------
local houseSaleLocks = {}

local function saleToken(src, cid, houseId)
    return ('sale:%s:%s:%s:%s:%s'):format(
        tostring(houseId), tostring(cid), tostring(src), tostring(os.time()),
        tostring(math.random(100000, 999999)))
end

local function formatFamilyBankError(reason)
    local balance = tostring(reason or ''):match('^family_bank_not_empty:(%-?%d+)$')
    if balance then
        return ('Withdraw the family bank balance ($%s) before selling the family house.')
            :format(Comma(math.abs(tonumber(balance) or 0)))
    end
    return nil
end

local function claimAndPaySale(row, preferredSrc)
    if type(row) ~= 'table' or not row.token then return false, 'invalid_sale_journal' end
    local token = tostring(row.token)
    local claimed = tonumber(MySQL.update.await([[
        UPDATE cm_house_sale_journal
        SET status = 'processing', payment_started_at = NOW(), last_error = NULL
        WHERE token = ? AND status IN ('ownership_released', 'payout_pending')
    ]], { token })) or 0
    if claimed ~= 1 then return false, 'sale_payout_not_claimable' end

    local sellerCid = tonumber(row.seller_cid)
    local src = tonumber(preferredSrc) or (sellerCid and GetSrcByCid(sellerCid)) or nil
    if not src then
        MySQL.update.await([[
            UPDATE cm_house_sale_journal
            SET status = 'payout_pending', last_error = 'seller_offline'
            WHERE token = ? AND status = 'processing'
        ]], { token })
        return false, 'seller_offline'
    end

    local payout = math.max(0, math.floor(tonumber(row.payout) or 0))
    local account = tostring(row.account or 'bank')
    local paid = GiveMoney(src, account, payout, 'house_sale')
    if not paid then
        MySQL.update.await([[
            UPDATE cm_house_sale_journal
            SET status = 'payout_pending', last_error = 'economy_rejected_payment'
            WHERE token = ? AND status = 'processing'
        ]], { token })
        return false, 'economy_rejected_payment'
    end

    -- If this final marker ever fails, leave the row in processing. Automatic
    -- recovery never retries processing rows because the money may already have
    -- landed; this is the safe, non-duplicating ambiguity state for staff review.
    local marked = tonumber(MySQL.update.await([[
        UPDATE cm_house_sale_journal
        SET status = 'paid', paid_at = NOW(), last_error = NULL
        WHERE token = ? AND status = 'processing'
    ]], { token })) or 0
    if marked ~= 1 then
        print(('[cm-house] ^1CRITICAL: sale %s paid $%s but journal could not be marked paid; do not retry automatically^7')
            :format(token, tostring(payout)))
        return true, 'paid_journal_ambiguous'
    end
    return true, 'paid'
end

local function recoverPendingSalePayouts()
    local rows = MySQL.query.await([[
        SELECT token, house_id, seller_cid, seller_source, payout, account
        FROM cm_house_sale_journal
        WHERE status = 'payout_pending'
        ORDER BY id ASC
        LIMIT 25
    ]]) or {}
    for _, row in ipairs(rows) do
        local src = GetSrcByCid(tonumber(row.seller_cid))
        if src then claimAndPaySale(row, src) end
    end
end

CreateThread(function()
    Wait(20000)
    while true do
        local ok, err = pcall(recoverPendingSalePayouts)
        if not ok then
            print(('[cm-house] ^1sale payout recovery failed: %s^7'):format(tostring(err)))
        end
        Wait(60000)
    end
end)

lib.callback.register('cm-house:server:sellHouse', function(src, houseId)
    houseId = tonumber(houseId)
    local cid = GetCid(src)
    local house = houseId and Houses[houseId] or nil
    if not cid or not house then return false, 'That house is not registered.' end
    if houseSaleLocks[houseId] then return false, 'This property sale is already being processed.' end

    local allowed, why = CanAccessProperty(cid, houseId, ACTIONS.HOUSE_SELL)
    if not allowed then return false, why end

    local existing = MySQL.single.await([[
        SELECT token, status
        FROM cm_house_sale_journal
        WHERE house_id = ? AND status IN ('prepared','ownership_released','processing','payout_pending')
        ORDER BY id DESC LIMIT 1
    ]], { houseId })
    if existing then
        return false, 'This property already has an unfinished sale operation. Contact an administrator.'
    end

    local weaponCount = HouseWeaponStorageCount and HouseWeaponStorageCount(houseId) or 0
    if weaponCount > 0 then
        return false, ('Empty the family weapon storage first. It still contains %d item stack%s.')
            :format(weaponCount, weaponCount == 1 and '' or 's')
    end

    local familyOk, familyContext = CMHouseFamilyLifecycle.GetContext(house, { requireEmptyBank = true })
    if not familyOk then
        return false, formatFamilyBankError(familyContext)
            or ('The linked family could not be prepared for deletion: %s'):format(tostring(familyContext))
    end

    houseSaleLocks[houseId] = true
    local ok, result, message = xpcall(function()
        -- Vehicles are real entities and must be safely persisted/released before
        -- the database stops describing this location as a garage.
        local vehiclesReleased, releaseInfo = EvictVehicles(houseId, 'family_house_sale', cid)
        if not vehiclesReleased then
            return false, 'A parked vehicle could not be released: ' .. tostring(releaseInfo)
        end

        local payout = math.max(0, math.floor(tonumber(house.gov_value) or 0))
        local account = 'bank'
        local token = saleToken(src, cid, houseId)
        local journalId = tonumber(MySQL.insert.await([[
            INSERT INTO cm_house_sale_journal
                (token, house_id, seller_cid, seller_source, payout, account, old_family_id, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'prepared')
        ]], {
            token, houseId, cid, src, payout, account,
            familyContext and familyContext.id or nil,
        }))
        if not journalId or journalId <= 0 then
            return false, 'The sale journal could not be created. You still own the property.'
        end

        local statements = {
            {
                query = 'DELETE FROM inventory_items WHERE owner_type = ? AND owner_id LIKE ?',
                values = { 'house_storage', ('%d:%%'):format(houseId) },
            },
            {
                query = 'DELETE FROM inventory_items WHERE owner_type = ? AND owner_id LIKE ?',
                values = { 'house_wardrobe', ('%d:%%'):format(houseId) },
            },
            {
                query = 'DELETE FROM cm_house_access WHERE house_id = ?',
                values = { houseId },
            },
        }
        CMHouseFamilyLifecycle.AppendDeleteStatements(
            statements, familyContext and familyContext.id or nil, houseId)

        if familyContext and familyContext.id then
            statements[#statements + 1] = {
                query = [[
                    UPDATE cm_houses
                    SET owner_cid = NULL, family_id = NULL, for_sale = 1,
                        paid_until = NULL, locked = 1
                    WHERE id = ? AND owner_cid = ? AND family_id = ?
                ]],
                values = { houseId, cid, familyContext.id },
            }
        else
            statements[#statements + 1] = {
                query = [[
                    UPDATE cm_houses
                    SET owner_cid = NULL, family_id = NULL, for_sale = 1,
                        paid_until = NULL, locked = 1
                    WHERE id = ? AND owner_cid = ? AND family_id IS NULL
                ]],
                values = { houseId, cid },
            }
        end
        statements[#statements + 1] = {
            query = [[
                UPDATE cm_house_sale_journal
                SET status = 'ownership_released', ownership_released_at = NOW()
                WHERE token = ? AND status = 'prepared'
            ]],
            values = { token },
        }

        local committed = MySQL.transaction.await(statements)
        if committed ~= true then
            MySQL.update.await([[
                UPDATE cm_house_sale_journal
                SET status = 'failed', last_error = 'release_transaction_rejected'
                WHERE token = ? AND status = 'prepared'
            ]], { token })
            return false, 'The sale transaction failed. You still own the property.'
        end

        local persisted = MySQL.single.await(
            'SELECT owner_cid, family_id FROM cm_houses WHERE id = ? LIMIT 1', { houseId })
        if not persisted or DbPositiveInteger(persisted.owner_cid) or DbPositiveInteger(persisted.family_id) then
            MySQL.update.await([[
                UPDATE cm_house_sale_journal
                SET status = 'failed', last_error = 'post_commit_house_verification_failed'
                WHERE token = ? AND status = 'ownership_released'
            ]], { token })
            return false, 'The property state could not be verified. Contact an administrator before retrying.'
        end

        local oldFamily = familyContext and familyContext.id or nil
        house.owner_cid, house.family_id = nil, nil
        house.for_sale, house.paid_until, house.locked = true, nil, true

        if OwnerHouses[cid] then
            for i = #OwnerHouses[cid], 1, -1 do
                if tonumber(OwnerHouses[cid][i]) == houseId then table.remove(OwnerHouses[cid], i) end
            end
        end
        for _, set in pairs(Access) do set[houseId] = nil end

        CMHouseFamilyLifecycle.FinalizeDeletedFamily(familyContext, houseId, 'sold', cid)
        LogHouse(houseId, oldFamily, cid, 'family_house_sell', {
            payout = payout,
            familyDeleted = oldFamily ~= nil,
        })
        TriggerClientEvent('cm-house:client:syncHouse', -1, BuildClientHouse(house))
        PushOwnership(cid)

        local paid, payState = claimAndPaySale({
            token = token,
            seller_cid = cid,
            payout = payout,
            account = account,
        }, src)
        if paid then
            local familySuffix = oldFamily and ' The linked family was disbanded.' or ''
            return true, ('Sold for $%s.%s'):format(Comma(payout), familySuffix)
        end

        return true, ('The property was sold and the family was disbanded. Your $%s payout is safely queued because the bank is unavailable.')
            :format(Comma(payout))
    end, debug.traceback)

    houseSaleLocks[houseId] = nil
    if not ok then
        print(('[cm-house] house sale failed for house %s / cid %s: %s')
            :format(tostring(houseId), tostring(cid), tostring(result)))
        return false, 'The sale failed safely. Check the server log before retrying.'
    end
    return result, message
end)

-- ------------------------------------------------------------
-- characterLoaded fires with (src, safeData) -- a table, not a bare id.
AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    local cid = tonumber(data and data.charId) or GetCid(src)
    if not cid then return end
    InvalidateName(cid)   -- a fresh login may carry a renamed character
    PushOwnership(cid)

    -- The garage UI needs to know which cars are the player's OWN, so it can
    -- offer "share with family" only on cars they actually own.
    TriggerClientEvent('cm-house:client:setCid', src, cid)
end)
