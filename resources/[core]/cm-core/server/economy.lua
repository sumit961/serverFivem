local function GetChar(src)
    if exports['cm-characters'] then
        return exports['cm-characters']:GetCharacter(src)
    end
    return nil
end

exports('AddMoney', function(src, account, amount, reason)
    if type(amount) ~= 'number' or amount <= 0 then return false, "invalid_amount" end
    local char = GetChar(src)
    if not char then return false, "no_character" end
    
    local col = account == 'cash' and 'cash' or 'bank'
    local maxKey = account == 'cash' and 'maxCash' or 'maxBank'
    local maxAmt = exports['cm-core']:GetConfig('Economy', maxKey) or 99999999
    local newAmt = (char[account] or 0) + amount
    if newAmt > maxAmt then newAmt = maxAmt end
    
    local ok = pcall(function()
        exports['cm-core']:Query('UPDATE characters SET ' .. col .. ' = ? WHERE id = ?', {newAmt, char.id})
    end)
    if not ok then return false, "database_error" end
    
    Player(src).state:set(account, newAmt, true)
    TriggerEvent('cm-core:moneyChanged', src, char.id, account, amount, reason or "unknown")
    return true, newAmt
end)

exports('RemoveMoney', function(src, account, amount, reason)
    if type(amount) ~= 'number' or amount <= 0 then return false, "invalid_amount" end
    local char = GetChar(src)
    if not char then return false, "no_character" end
    
    local current = char[account] or 0
    if current < amount then return false, "insufficient_funds" end
    
    local col = account == 'cash' and 'cash' or 'bank'
    local newAmt = current - amount
    
    local ok = pcall(function()
        exports['cm-core']:Query('UPDATE characters SET ' .. col .. ' = ? WHERE id = ?', {newAmt, char.id})
    end)
    if not ok then return false, "database_error" end
    
    Player(src).state:set(account, newAmt, true)
    TriggerEvent('cm-core:moneyChanged', src, char.id, account, -amount, reason or "unknown")
    return true, newAmt
end)

exports('GetMoney', function(src, account)
    local char = GetChar(src)
    if not char then return 0 end
    return char[account] or 0
end)

exports('TransferMoney', function(fromSrc, toSrc, account, amount, reason)
    local removed, err = exports['cm-core']:RemoveMoney(fromSrc, account, amount, reason)
    if not removed then return false, err end
    local added = exports['cm-core']:AddMoney(toSrc, account, amount, reason)
    if not added then
        print("[CM-CORE] CRITICAL: Transfer failed to add after removal")
        return false, "transfer_failed"
    end
    return true
end)

exports('CanAfford', function(src, account, amount)
    return exports['cm-core']:GetMoney(src, account) >= amount
end)