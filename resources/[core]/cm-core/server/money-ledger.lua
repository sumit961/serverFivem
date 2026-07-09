-- Compatibility money ledger. Real economy transaction ownership should later move to cm-playerdata/cm-economy.

local function getCharacterId(src)
    src = tonumber(src)
    if not src then return nil end

    local player = exports['cm-core']:GetPlayer(src)
    if player and player.CharacterId then return player.CharacterId end

    if GetResourceState('cm-playerdata') == 'started' then
        local ok, charId = pcall(function() return exports['cm-playerdata']:GetCharacterId(src) end)
        if ok and charId then return charId end
    end

    local ok, stateChar = pcall(function() return Player(src).state.charId end)
    return ok and stateChar or nil
end

exports('LogMoneyTransaction', function(src, account, action, amount, reason, balanceAfter, targetCharId)
    local charId = getCharacterId(src)
    pcall(function()
        exports['cm-core']:Query([[INSERT INTO money_ledger
            (character_id, target_character_id, account_type, action, amount, balance_after, reason)
            VALUES (?, ?, ?, ?, ?, ?, ?)]], {
            charId,
            targetCharId,
            tostring(account or 'cash'):sub(1, 20),
            tostring(action or 'unknown'):sub(1, 30),
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
    if not characterId then return {} end
    return exports['cm-core']:Query('SELECT * FROM money_ledger WHERE character_id = ? ORDER BY id DESC LIMIT ?', {
        characterId,
        limit
    }) or {}
end)
