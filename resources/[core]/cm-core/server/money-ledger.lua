-- CM-Core v1.1 Safe Patch: Money Ledger

local function getCharacterId(src)
    local player = exports['cm-core']:GetPlayer(src)
    if player and player.CharacterId then return player.CharacterId end

    local ok, char = pcall(function()
        return exports['cm-characters']:GetCharacter(src)
    end)
    if ok and char then return char.id end
    return nil
end

exports('LogMoneyTransaction', function(src, account, action, amount, reason, balanceAfter, targetCharId)
    local charId = getCharacterId(src)
    pcall(function()
        exports['cm-core']:Query([[INSERT INTO money_ledger
            (character_id, target_character_id, account_type, action, amount, balance_after, reason)
            VALUES (?, ?, ?, ?, ?, ?, ?)]], {
            charId,
            targetCharId,
            account == 'cash' and 'cash' or 'bank',
            tostring(action or 'unknown'),
            tonumber(amount) or 0,
            tonumber(balanceAfter) or 0,
            tostring(reason or 'unknown'):sub(1, 100)
        })
    end)
    return true
end)

exports('GetMoneyLedger', function(characterId, limit)
    limit = tonumber(limit) or 50
    if limit > 200 then limit = 200 end
    return exports['cm-core']:Query('SELECT * FROM money_ledger WHERE character_id = ? ORDER BY id DESC LIMIT ?', {
        characterId,
        limit
    }) or {}
end)
