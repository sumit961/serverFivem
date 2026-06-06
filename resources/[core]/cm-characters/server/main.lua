-- cm-characters/server/main.lua

-- Get character by unique ID (auto-increment number)
exports('GetCharacter', function(src)
    local charId = Player(src).state.charId
    if not charId then return nil end
    return exports['cm-core']:CacheRemember('char:' .. charId, 30, function()
        local result = exports['cm-core']:Query('SELECT * FROM characters WHERE id = ?', {charId})
        return result and result[1] or nil
    end)
end)

exports('GetCharacterById', function(charId)
    return exports['cm-core']:CacheRemember('char:' .. charId, 30, function()
        local result = exports['cm-core']:Query('SELECT * FROM characters WHERE id = ?', {charId})
        return result and result[1] or nil
    end)
end)

exports('GetCharactersByAccount', function(accountId)
    return exports['cm-core']:Query(
        'SELECT * FROM characters WHERE account_id = ? ORDER BY slot',
        {accountId}
    )
end)

-- Get character by unique ID (for admin/commands)
exports('GetCharacterByUniqueId', function(uniqueId)
    return exports['cm-core']:CacheRemember('char_uid:' .. uniqueId, 60, function()
        local result = exports['cm-core']:Query('SELECT * FROM characters WHERE id = ?', {uniqueId})
        return result and result[1] or nil
    end)
end)