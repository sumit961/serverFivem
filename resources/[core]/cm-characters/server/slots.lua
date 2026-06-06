-- cm-characters/server/slots.lua

RegisterNetEvent('cm-characters:server:getSlots', function(accountId)
    local src = source
    local chars = exports['cm-characters']:GetCharactersByAccount(accountId)
    
    -- Format for UI
    local slots = {}
    for i = 1, 2 do
        slots[i] = nil -- empty slot
    end
    
    if chars then
        for _, char in ipairs(chars) do
            slots[char.slot] = {
                uniqueId = char.id,           -- Auto-increment ID (1, 2, 3, 4, 5...)
                name = char.first_name .. ' ' .. char.last_name,
                gender = char.gender,
                cash = char.cash,
                bank = char.bank,
                rank = char.current_rank_id,
                playtime = char.playtime_minutes,
                created = char.created_at,
                -- CANNOT DELETE - show this in UI
                permanent = true
            }
        end
    end
    
    TriggerClientEvent('cm-characters:client:showSlots', src, slots, accountId)
end)

RegisterNetEvent('cm-characters:server:selectCharacter', function(charId)
    local src = source
    local char = exports['cm-characters']:GetCharacterById(charId)
    
    if not char then
        TriggerClientEvent('cm-characters:client:error', src, 'Character not found')
        return
    end
    
    -- Set state and fire global event
    Player(src).state:set('charId', charId, true)
    Player(src).state:set('isLoggedIn', true, true)
    
    -- Give money state bags
    Player(src).state:set('cash', char.cash, true)
    Player(src).state:set('bank', char.bank, true)
    
    -- Fire core event (cm-spawn will listen)
    TriggerEvent('cm-core:characterLoaded', src, charId)
    
    exports['cm-core']:Log('cm-characters', 'info', 'Character selected', {
        category = 'character',
        player_src = src,
        player_char_id = charId,
        unique_id = char.id,
        name = char.first_name .. ' ' .. char.last_name
    })
end)

-- NO DELETE FUNCTION - characters are permanent
-- If you want to "disable" a character, add an is_active flag instead
-- But per your request: NO DELETION EVER