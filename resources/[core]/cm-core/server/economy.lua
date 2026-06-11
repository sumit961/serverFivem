-- CM-Core v1.1 Safe Patch: Economy
-- Compatible with old cm-characters, but prefers the new cm-core Player Manager.

local function normalizeAccount(account)
    return account == 'cash' and 'cash' or 'bank'
end

local function getChar(src)
    local player = exports['cm-core']:GetPlayer(src)
    if player and player.Character then return player.Character, player end

    local ok, char = pcall(function()
        return exports['cm-characters']:GetCharacter(src)
    end)
    if ok and char then return char, nil end
    return nil, nil
end

local function setCachedMoney(src, player, char, account, value)
    value = tonumber(value) or 0
    if char then char[account] = value end
    if player and player.Character then player.Character[account] = value end
    pcall(function() Player(src).state:set(account, value, true) end)
end

local function logMoney(src, account, action, amount, reason, balanceAfter, targetCharId)
    pcall(function()
        exports['cm-core']:LogMoneyTransaction(src, account, action, amount, reason, balanceAfter, targetCharId)
    end)
end

exports('SetMoney', function(src, account, amount, reason)
    src = tonumber(src)
    account = normalizeAccount(account)
    amount = math.floor(tonumber(amount) or -1)
    if amount < 0 then return false, 'invalid_amount' end

    local char, player = getChar(src)
    if not char or not char.id then return false, 'no_character' end

    local maxKey = account == 'cash' and 'maxCash' or 'maxBank'
    local maxAmt = exports['cm-core']:GetConfig('Economy', maxKey) or 99999999
    if amount > maxAmt then amount = maxAmt end

    local ok = pcall(function()
        exports['cm-core']:Update('UPDATE characters SET ' .. account .. ' = ? WHERE id = ?', { amount, char.id })
    end)
    if not ok then return false, 'database_error' end

    local oldAmount = tonumber(char[account]) or 0
    setCachedMoney(src, player, char, account, amount)
    logMoney(src, account, 'set', amount - oldAmount, reason or 'set_money', amount)
    TriggerEvent('cm-core:moneyChanged', src, char.id, account, amount - oldAmount, reason or 'set_money', amount)
    return true, amount
end)

exports('AddMoney', function(src, account, amount, reason)
    src = tonumber(src)
    account = normalizeAccount(account)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end

    local char, player = getChar(src)
    if not char or not char.id then return false, 'no_character' end

    local current = tonumber(char[account]) or 0
    local maxKey = account == 'cash' and 'maxCash' or 'maxBank'
    local maxAmt = exports['cm-core']:GetConfig('Economy', maxKey) or 99999999
    local newAmt = current + amount
    if newAmt > maxAmt then newAmt = maxAmt end
    local delta = newAmt - current
    if delta <= 0 then return true, newAmt end

    local ok = pcall(function()
        exports['cm-core']:Update('UPDATE characters SET ' .. account .. ' = ? WHERE id = ?', { newAmt, char.id })
    end)
    if not ok then return false, 'database_error' end

    setCachedMoney(src, player, char, account, newAmt)
    logMoney(src, account, 'add', delta, reason or 'unknown', newAmt)
    TriggerEvent('cm-core:moneyChanged', src, char.id, account, delta, reason or 'unknown', newAmt)
    return true, newAmt
end)

exports('RemoveMoney', function(src, account, amount, reason)
    src = tonumber(src)
    account = normalizeAccount(account)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end

    local char, player = getChar(src)
    if not char or not char.id then return false, 'no_character' end

    local current = tonumber(char[account]) or 0
    if current < amount then return false, 'insufficient_funds' end

    local newAmt = current - amount
    local ok = pcall(function()
        exports['cm-core']:Update('UPDATE characters SET ' .. account .. ' = ? WHERE id = ?', { newAmt, char.id })
    end)
    if not ok then return false, 'database_error' end

    setCachedMoney(src, player, char, account, newAmt)
    logMoney(src, account, 'remove', -amount, reason or 'unknown', newAmt)
    TriggerEvent('cm-core:moneyChanged', src, char.id, account, -amount, reason or 'unknown', newAmt)
    return true, newAmt
end)

exports('GetMoney', function(src, account)
    account = normalizeAccount(account)
    local char = getChar(src)
    if not char then return 0 end
    return tonumber(char[account]) or 0
end)

exports('TransferMoney', function(fromSrc, toSrc, account, amount, reason)
    account = normalizeAccount(account)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end

    local toChar = getChar(toSrc)
    if not toChar then return false, 'target_no_character' end

    local removed, err = exports['cm-core']:RemoveMoney(fromSrc, account, amount, reason or 'transfer')
    if not removed then return false, err end

    local added, addErr = exports['cm-core']:AddMoney(toSrc, account, amount, reason or 'transfer')
    if not added then
        -- Refund sender if receiver update fails.
        exports['cm-core']:AddMoney(fromSrc, account, amount, 'transfer_refund')
        print('[CM-CORE] Transfer failed, sender refunded: ' .. tostring(addErr))
        return false, addErr or 'transfer_failed'
    end

    local fromChar = getChar(fromSrc)
    pcall(function()
        exports['cm-core']:LogMoneyTransaction(fromSrc, account, 'transfer_out', -amount, reason or 'transfer', exports['cm-core']:GetMoney(fromSrc, account), toChar.id)
        exports['cm-core']:LogMoneyTransaction(toSrc, account, 'transfer_in', amount, reason or 'transfer', exports['cm-core']:GetMoney(toSrc, account), fromChar and fromChar.id or nil)
    end)

    return true
end)

exports('CanAfford', function(src, account, amount)
    return exports['cm-core']:GetMoney(src, account) >= (tonumber(amount) or 0)
end)
