-- cm-characters/server/main.lua
-- Safe exports for permanent character IDs.
-- Player(source) is only the temporary FiveM session ID; characters.id is the permanent RP ID.

local function getStateCharId(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end

    local player = Player(src)
    if not player or not player.state then return nil end

    local charId = player.state.charId or player.state.characterId
    if not charId then return nil end

    return tostring(charId)
end

local function getCharacterByIdRaw(charId)
    if charId == nil then return nil end
    charId = tostring(charId)

    return exports['cm-core']:CacheRemember('char:' .. charId, 30, function()
        local result = exports['cm-core']:Query('SELECT * FROM characters WHERE id = ?', {charId})
        return result and result[1] or nil
    end)
end

exports('GetCurrentCharacterId', function(src)
    return getStateCharId(src)
end)

exports('GetCharacter', function(src)
    local charId = getStateCharId(src)
    if not charId then return nil end
    return getCharacterByIdRaw(charId)
end)

exports('GetCharacterById', function(charId)
    return getCharacterByIdRaw(charId)
end)

exports('GetCharactersByAccount', function(accountId)
    if accountId == nil then return {} end

    return exports['cm-core']:Query(
        'SELECT * FROM characters WHERE account_id = ? ORDER BY slot',
        {tostring(accountId)}
    ) or {}
end)

exports('GetCharacterByUniqueId', function(uniqueId)
    -- Backwards compatible alias. Your unique character ID is now characters.id.
    return getCharacterByIdRaw(uniqueId)
end)
