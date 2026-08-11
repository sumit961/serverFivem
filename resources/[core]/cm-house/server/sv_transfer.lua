-- cm-house | secure, recipient-confirmed player-to-player property transfers.
local ACTIONS_GMENU = { house_gift = 'gift', house_sell_player = 'sale' }
local pending = {}
local locks = {}

local function notify(src, message, kind)
    Notify(src, tostring(message), kind or 'inform')
end

local function ensureSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_house_transfer_journal (
          id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, token VARCHAR(128) NOT NULL,
          house_id INT NOT NULL, seller_cid INT NOT NULL, buyer_cid INT NOT NULL,
          mode ENUM('gift','sale') NOT NULL, price INT NOT NULL DEFAULT 0,
          account VARCHAR(32) NOT NULL DEFAULT 'bank', status VARCHAR(32) NOT NULL DEFAULT 'offered',
          last_error VARCHAR(255) NULL, expires_at DATETIME NOT NULL, paid_at DATETIME NULL,
          completed_at DATETIME NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (id), UNIQUE KEY uq_house_transfer_token (token),
          KEY idx_house_transfer_open (house_id,status), KEY idx_house_transfer_buyer (buyer_cid,status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end

local function ownerChoices(cid)
    local rows = {}
    for _, houseId in ipairs(OwnerHouses[tonumber(cid)] or {}) do
        local house = Houses[tonumber(houseId)]
        if house and not house.family_id then
            rows[#rows + 1] = { id = house.id, number = house.house_number }
        end
    end
    return rows
end

local function validateTarget(src, targetSrc, key)
    local ok, valid, resolved, reason = pcall(function()
        return exports['cm-playerdata']:ValidateInteractionTarget(src, targetSrc, key, 800)
    end)
    return ok and valid == true and tonumber(resolved) == tonumber(targetSrc), reason
end

local function blockers(houseId, ignoredToken)
    local house = Houses[tonumber(houseId)]
    if not house then return 'That property does not exist.' end
    if house.family_id then return 'Family-linked houses cannot be gifted or sold to a player.' end
    local recovery = tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM cm_house_weapon_recovery WHERE house_id = ? AND resolved = 0', { houseId })) or 0
    if recovery > 0 then return 'Resolve the property weapon-recovery rows first.' end
    local journal = tonumber(MySQL.scalar.await([[
        SELECT COUNT(*) FROM cm_house_sale_journal
        WHERE house_id = ? AND status IN ('prepared','ownership_released','processing','payout_pending')
    ]], { houseId })) or 0
    if journal > 0 then return 'The property has an unresolved recovery or government-sale operation.' end
    if GetResourceState('cm-vehicles') == 'started' then
        local ok, rows = pcall(function() return exports['cm-vehicles']:ListVehicleRecoveryProblems(200) end)
        if not ok then return 'Vehicle recovery status is unavailable; transfer is blocked safely.' end
        for _, vehicle in ipairs(type(rows) == 'table' and rows or {}) do
            if tonumber(vehicle.assigned_house_id) == tonumber(houseId) then
                return 'Resolve this property\'s vehicle-recovery rows first.'
            end
        end
    end
    local transfer = tonumber(MySQL.scalar.await([[
        SELECT COUNT(*) FROM cm_house_transfer_journal
        WHERE house_id = ? AND status IN ('offered','accepted','paid','committing')
          AND expires_at > NOW() AND (? = '' OR token <> ?)
    ]], { houseId, tostring(ignoredToken or ''), tostring(ignoredToken or '') })) or 0
    if transfer > 0 then return 'The property already has an active transfer.' end
    local ok, active = pcall(function() return exports['cm-house']:IsHouseGarageOperationActive(houseId) end)
    if not ok or active == true then return 'Wait for all garage calls, recalls, and assignment changes to finish.' end
    return nil
end

local function refreshOwnerCache(houseId, oldCid, newCid)
    oldCid, newCid = tonumber(oldCid), tonumber(newCid)
    local old = OwnerHouses[oldCid] or {}
    for i = #old, 1, -1 do if tonumber(old[i]) == tonumber(houseId) then table.remove(old, i) end end
    OwnerHouses[oldCid] = old
    OwnerHouses[newCid] = OwnerHouses[newCid] or {}
    OwnerHouses[newCid][#OwnerHouses[newCid] + 1] = tonumber(houseId)
    Houses[tonumber(houseId)].owner_cid = newCid
    Houses[tonumber(houseId)].for_sale = false
    if PushOwnership then PushOwnership(oldCid); PushOwnership(newCid) end
end

local function commitOwnership(row)
    local current = MySQL.single.await(
        'SELECT owner_cid, family_id FROM cm_houses WHERE id = ? LIMIT 1', { row.house_id })
    if not current or tonumber(current.owner_cid) ~= tonumber(row.seller_cid) or current.family_id ~= nil then
        return false, 'Property ownership changed before this transfer completed.'
    end
    local committed = MySQL.transaction.await({
        {
            query = [[UPDATE cm_houses SET owner_cid = ?, for_sale = 0, locked = 1
                      WHERE id = ? AND owner_cid = ? AND family_id IS NULL]],
            values = { row.buyer_cid, row.house_id, row.seller_cid },
        },
        { query = 'DELETE FROM cm_house_access WHERE house_id = ?', values = { row.house_id } },
        {
            query = [[UPDATE cm_house_transfer_journal
                      SET status = 'completed', completed_at = NOW(), last_error = NULL
                      WHERE token = ? AND status IN ('accepted','paid','committing')]],
            values = { row.token },
        },
    })
    if committed ~= true then return false, 'The ownership transaction was rolled back.' end
    local owner = tonumber(MySQL.scalar.await('SELECT owner_cid FROM cm_houses WHERE id = ?', { row.house_id }))
    if owner ~= tonumber(row.buyer_cid) then return false, 'The ownership transaction did not commit.' end
    for _, grants in pairs(Access or {}) do
        grants[tonumber(row.house_id)] = nil
        grants[tostring(row.house_id)] = nil
    end
    refreshOwnerCache(row.house_id, row.seller_cid, row.buyer_cid)
    LogHouse(row.house_id, nil, row.seller_cid, row.mode == 'gift' and 'house_gift' or 'house_player_sale', {
        to = row.buyer_cid, price = row.price, token = row.token,
    })
    return true
end

local function registerActions()
    if GetResourceState('cm-playerdata') ~= 'started' then return end
    for action in pairs(ACTIONS_GMENU) do
        TriggerEvent('cm-playerdata:server:registerInteractionAction', {
            id = action, event = 'cm-house:server:gMenuTransferAction',
            resource = GetCurrentResourceName(), allowDeadTarget = false,
        })
    end
end

AddEventHandler('cm-house:server:gMenuTransferAction', function(src, targetSrc, actionId, _, context)
    local mode = ACTIONS_GMENU[tostring(actionId)]
    local cid = type(context) == 'table' and tonumber(context.sourceCharacterId) or GetCid(src)
    if not mode or not cid then return end
    local houses = ownerChoices(cid)
    if #houses == 0 then return notify(src, 'You do not own a private house that can be transferred.', 'error') end
    TriggerClientEvent('cm-house:client:choosePropertyTransfer', src, {
        mode = mode, houses = houses, targetServerId = tonumber(targetSrc),
    })
end)

RegisterNetEvent('cm-house:server:createPropertyTransfer', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local targetSrc, houseId = tonumber(data.targetServerId), tonumber(data.houseId)
    local sellerCid, buyerCid = GetCid(src), targetSrc and GetCid(targetSrc)
    local mode = data.mode == 'sale' and 'sale' or data.mode == 'gift' and 'gift' or nil
    local valid, reason = validateTarget(src, targetSrc, 'house_transfer_offer')
    if not valid or not sellerCid or not buyerCid then return notify(src, reason or 'That player is unavailable.', 'error') end
    local house = Houses[houseId]
    if not mode or not house or tonumber(house.owner_cid) ~= sellerCid then return notify(src, 'You do not own that house.', 'error') end
    local blocked = blockers(houseId)
    if blocked then return notify(src, blocked, 'error') end
    local price = mode == 'sale' and math.floor(tonumber(data.price) or 0) or 0
    if mode == 'sale' and (price < 1 or price > 100000000) then return notify(src, 'Choose a valid sale price.', 'error') end
    local token = ('house-transfer:%d:%d:%d:%d'):format(houseId, sellerCid, buyerCid, os.time())
    MySQL.insert.await([[
        INSERT INTO cm_house_transfer_journal
          (token, house_id, seller_cid, buyer_cid, mode, price, account, status, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, 'bank', 'offered', DATE_ADD(NOW(), INTERVAL 30 SECOND))
    ]], { token, houseId, sellerCid, buyerCid, mode, price })
    pending[token] = { token = token, house_id = houseId, seller_cid = sellerCid, buyer_cid = buyerCid,
        sellerSrc = src, buyerSrc = targetSrc, mode = mode, price = price, expiresAt = os.time() + 30 }
    TriggerClientEvent('cm-house:client:confirmPropertyTransfer', targetSrc, {
        token = token, houseId = houseId, houseNumber = house.house_number, mode = mode,
        price = price, sellerName = GetCharName(sellerCid),
    })
    notify(src, 'Transfer offer sent. The recipient must confirm it.', 'success')
end)

RegisterNetEvent('cm-house:server:answerPropertyTransfer', function(token, accepted)
    local src = source
    local row = pending[tostring(token or '')]
    pending[tostring(token or '')] = nil
    if not row or src ~= row.buyerSrc or GetCid(src) ~= row.buyer_cid or os.time() > row.expiresAt then
        return notify(src, 'That property offer expired.', 'error')
    end
    if accepted ~= true then
        MySQL.update.await("UPDATE cm_house_transfer_journal SET status = 'declined' WHERE token = ? AND status = 'offered'", { row.token })
        notify(row.sellerSrc, 'The recipient declined the property transfer.', 'error')
        return
    end
    local valid, reason = validateTarget(row.sellerSrc, src, 'house_transfer_accept')
    if not valid or GetCid(row.sellerSrc) ~= row.seller_cid then return notify(src, reason or 'The owner is unavailable.', 'error') end
    local blocked = blockers(row.house_id, row.token)
    if blocked then return notify(src, blocked, 'error') end
    if locks[row.house_id] then return notify(src, 'That property is already being transferred.', 'error') end
    locks[row.house_id] = true
    MySQL.update.await("UPDATE cm_house_transfer_journal SET status = 'accepted' WHERE token = ? AND status = 'offered'", { row.token })
    if row.mode == 'sale' then
        local ok, why = exports['cm-playerdata']:TransferMoneyBetweenDetailed(
            src, row.sellerSrc, 'bank', row.price, 'house_player_sale', { houseId = row.house_id, token = row.token })
        if ok ~= true then
            MySQL.update.await("UPDATE cm_house_transfer_journal SET status = 'failed', last_error = ? WHERE token = ?", { tostring(why), row.token })
            locks[row.house_id] = nil
            return notify(src, 'The bank payment could not be completed.', 'error')
        end
        MySQL.update.await("UPDATE cm_house_transfer_journal SET status = 'paid', paid_at = NOW() WHERE token = ?", { row.token })
    end
    local ok, why = commitOwnership(row)
    locks[row.house_id] = nil
    if not ok then
        MySQL.update.await("UPDATE cm_house_transfer_journal SET status = 'review_required', last_error = ? WHERE token = ?", { tostring(why), row.token })
        return notify(src, 'The transfer requires administrator recovery; its journal was preserved.', 'error')
    end
    notify(src, 'The house is now yours. Its stored contents stayed with the property.', 'success')
    notify(row.sellerSrc, row.mode == 'sale' and 'The house sale completed.' or 'The house gift completed.', 'success')
end)

AddEventHandler('onResourceStart', function(name)
    if name ~= GetCurrentResourceName() and name ~= 'cm-playerdata' then return end
    CreateThread(function()
        Wait(400)
        ensureSchema()
        -- A crash after bank payment but before ownership commit is settled
        -- forward from the durable paid journal; payment is never repeated.
        for _, row in ipairs(MySQL.query.await([[
            SELECT * FROM cm_house_transfer_journal
            WHERE status IN ('paid','committing') ORDER BY id ASC LIMIT 25
        ]]) or {}) do
            local ok, why = commitOwnership(row)
            if not ok then
                MySQL.update.await([[
                    UPDATE cm_house_transfer_journal SET status = 'review_required', last_error = ? WHERE token = ?
                ]], { tostring(why), row.token })
            end
        end
        registerActions()
    end)
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for action in pairs(ACTIONS_GMENU) do TriggerEvent('cm-playerdata:server:unregisterInteractionAction', action) end
end)
