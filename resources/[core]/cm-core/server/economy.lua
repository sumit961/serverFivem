-- CM-Core money compatibility bridge.
-- Real cash/bank ownership should be implemented in cm-playerdata.
-- Price/payout/reward calculations should be implemented in cm-economy.

CM = CM or {}
CM.LegacyMoneyWarned = CM.LegacyMoneyWarned or false

local function normalizeAccount(account)
    account = tostring(account or 'cash'):lower()
    if account == 'bank' then return 'bank' end
    if account == 'dirty' or account == 'black_money' then return 'dirty' end
    return 'cash'
end

local function getCharacterId(src)
    local player = exports['cm-core']:GetPlayer(src)
    if player and player.CharacterId then return player.CharacterId end
    local ok, charId = pcall(function()
        if GetResourceState('cm-playerdata') == 'started' then
            return exports['cm-playerdata']:GetCharacterId(src)
        end
    end)
    if ok and charId then return charId end
    local stateOk, stateChar = pcall(function() return Player(src).state.charId end)
    return stateOk and stateChar or nil
end

local function callPlayerData(exportName, src, account, amount, reason)
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end

    local ok, a, b = pcall(function()
        if exportName == 'GetMoney' then
            return exports['cm-playerdata']:GetMoney(src, account)
        elseif exportName == 'SetMoney' then
            return exports['cm-playerdata']:SetMoney(src, account, amount, reason)
        elseif exportName == 'AddMoney' then
            return exports['cm-playerdata']:AddMoney(src, account, amount, reason)
        elseif exportName == 'RemoveMoney' then
            return exports['cm-playerdata']:RemoveMoney(src, account, amount, reason)
        end
        return nil
    end)

    if ok then return a, b end
    return nil
end

local function legacyEnabled()
    local cfg = exports['cm-core']:GetConfig('Core') or {}
    return cfg.legacyMoneyBridge == true
end

local function legacyWarn()
    if CM.LegacyMoneyWarned then return end
    CM.LegacyMoneyWarned = true
    exports['cm-core']:Log('cm-core', 'warn', 'Using legacy cm-core money bridge. Move cash/bank ownership to cm-playerdata.', { category = 'migration' })
end

local function getCachedPlayer(src)
    local player = exports['cm-core']:GetPlayer(src)
    if player and player.Character then return player end
    return nil
end

local function setState(src, account, value)
    pcall(function() Player(src).state:set(account, tonumber(value) or 0, true) end)
end

local function legacyGetMoney(src, account)
    if account ~= 'cash' and account ~= 'bank' then return 0 end
    if not legacyEnabled() then return 0 end
    legacyWarn()
    local player = getCachedPlayer(src)
    if player and player.Character then
        return tonumber(player.Character[account]) or 0
    end
    local charId = getCharacterId(src)
    if not charId then return 0 end
    return tonumber(exports['cm-core']:Scalar(('SELECT %s FROM characters WHERE id = ?'):format(account), { charId }) or 0) or 0
end

local function legacySetMoney(src, account, amount, reason)
    if account ~= 'cash' and account ~= 'bank' then return false, 'unsupported_legacy_account' end
    if not legacyEnabled() then return false, 'money_owned_by_cm_playerdata' end
    legacyWarn()

    amount = math.floor(tonumber(amount) or -1)
    if amount < 0 then return false, 'invalid_amount' end

    local charId = getCharacterId(src)
    if not charId then return false, 'no_character' end

    local maxKey = account == 'cash' and 'maxCash' or 'maxBank'
    local maxAmt = exports['cm-core']:GetConfig('Economy', maxKey) or 999999999
    if amount > maxAmt then amount = maxAmt end

    local ok = exports['cm-core']:Update(('UPDATE characters SET %s = ? WHERE id = ?'):format(account), { amount, charId })
    if ok == nil or ok == false then return false, 'database_error' end

    local player = getCachedPlayer(src)
    if player and player.Character then player.Character[account] = amount end
    setState(src, account, amount)
    exports['cm-core']:LogMoneyTransaction(src, account, 'set', amount, reason or 'set_money', amount)
    TriggerEvent('cm-core:moneyChanged', src, charId, account, amount, reason or 'set_money', amount)
    return true, amount
end

exports('GetMoney', function(src, account)
    src = tonumber(src)
    if not src then return 0 end
    account = normalizeAccount(account)

    local result = callPlayerData('GetMoney', src, account)
    if result ~= nil then return tonumber(result) or 0 end
    return legacyGetMoney(src, account)
end)

exports('SetMoney', function(src, account, amount, reason)
    src = tonumber(src)
    account = normalizeAccount(account)
    amount = math.floor(tonumber(amount) or -1)
    if not src or amount < 0 then return false, 'invalid_amount' end

    local ok, err = callPlayerData('SetMoney', src, account, amount, reason)
    if ok ~= nil then return ok, err end
    return legacySetMoney(src, account, amount, reason)
end)

exports('AddMoney', function(src, account, amount, reason)
    src = tonumber(src)
    account = normalizeAccount(account)
    amount = math.floor(tonumber(amount) or 0)
    if not src or amount <= 0 then return false, 'invalid_amount' end

    local ok, err = callPlayerData('AddMoney', src, account, amount, reason)
    if ok ~= nil then return ok, err end

    local current = legacyGetMoney(src, account)
    return legacySetMoney(src, account, current + amount, reason or 'add_money')
end)

exports('RemoveMoney', function(src, account, amount, reason)
    src = tonumber(src)
    account = normalizeAccount(account)
    amount = math.floor(tonumber(amount) or 0)
    if not src or amount <= 0 then return false, 'invalid_amount' end

    local ok, err = callPlayerData('RemoveMoney', src, account, amount, reason)
    if ok ~= nil then return ok, err end

    local current = legacyGetMoney(src, account)
    if current < amount then return false, 'insufficient_funds' end
    return legacySetMoney(src, account, current - amount, reason or 'remove_money')
end)

exports('CanAfford', function(src, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    return exports['cm-core']:GetMoney(src, account) >= amount
end)

exports('TransferMoney', function(fromSrc, toSrc, account, amount, reason)
    fromSrc, toSrc = tonumber(fromSrc), tonumber(toSrc)
    account = normalizeAccount(account)
    amount = math.floor(tonumber(amount) or 0)
    if not fromSrc or not toSrc or amount <= 0 then return false, 'invalid_transfer' end

    local removed, removeErr = exports['cm-core']:RemoveMoney(fromSrc, account, amount, reason or 'transfer')
    if not removed then return false, removeErr end

    local added, addErr = exports['cm-core']:AddMoney(toSrc, account, amount, reason or 'transfer')
    if not added then
        exports['cm-core']:AddMoney(fromSrc, account, amount, 'transfer_refund')
        return false, addErr or 'transfer_failed'
    end

    return true
end)
