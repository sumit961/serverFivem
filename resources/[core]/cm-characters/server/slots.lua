-- cm-characters/server/slots.lua

RegisterNetEvent('cm-characters:server:getSlots', function(accountId)
    local src = source
    
    print('[CM-CHARACTERS] getSlots called for accountId="' .. tostring(accountId) .. '"')
    
    local chars = exports['cm-core']:Query(
        'SELECT * FROM characters WHERE account_id = ? ORDER BY slot',
        {tostring(accountId)}
    )
    
    print('[CM-CHARACTERS] Query returned ' .. tostring(chars and #chars or 0) .. ' rows')
    
    local slots = {nil, nil}
    
    if chars then
        for _, char in ipairs(chars) do
            local slotNum = tonumber(char.slot)
            if slotNum and slotNum >= 1 and slotNum <= 2 then
                slots[slotNum] = {
                    uniqueId = char.id,
                    name = (char.first_name or '') .. ' ' .. (char.last_name or ''),
                    gender = char.gender or 'male',
                    cash = char.cash or 0,
                    bank = char.bank or 0,
                    rank = char.current_rank_id,
                    playtime = char.playtime_minutes,
                    created = char.created_at,
                    permanent = true
                }
                print('[CM-CHARACTERS] Added to slot ' .. slotNum .. ': ' .. slots[slotNum].name)
            end
        end
    end
    
    TriggerClientEvent('cm-characters:client:showSlots', src, slots, accountId)
end)

RegisterNetEvent('cm-characters:server:selectCharacter', function(charId)
    local src = source
    print('[CM-CHARACTERS] selectCharacter: ' .. tostring(charId))

    charId = tostring(charId)
    local char = exports['cm-core']:Query('SELECT * FROM characters WHERE id = ?', {charId})
    if not char or #char == 0 then
        TriggerClientEvent('cm-characters:client:error', src, 'Character not found')
        return
    end

    char = char[1]

    -- ONLY set identity state. Everything else is handled by downstream resources.
    local fixedCharId = tostring(char.id)
    Player(src).state:set('charId', fixedCharId, true)
    Player(src).state:set('characterId', fixedCharId, true)
    Player(src).state:set('isLoggedIn', true, true)

    -- This one event triggers cm-playerdata (load cash/health) and cm-spawn (tutorial/position/appearance)
    TriggerEvent('cm-core:characterLoaded', src, fixedCharId)

    -- appearance_json is only the base/body layer. Equipped clothes live in cm-inventory,
    -- so after any spawn/appearance load, force inventory equipment to overlay again.
    TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src)
    SetTimeout(1000, function() TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src) end)
    SetTimeout(3000, function() TriggerClientEvent('cm-inventory:client:requestEquipmentRefresh', src) end)

    exports['cm-core']:Log('cm-characters', 'info', 'Character selected', {
        player_src = src,
        player_char_id = fixedCharId,
        name = (char.first_name or '') .. ' ' .. (char.last_name or '')
    })
end)