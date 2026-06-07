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
    print('[CM-CHARACTERS] >>> selectCharacter called for charId=' .. tostring(charId) .. ' <<<')
    
    local char = exports['cm-core']:Query('SELECT * FROM characters WHERE id = ?', {charId})
    
    if not char or #char == 0 then
        print('[CM-CHARACTERS] ERROR: Character not found: ' .. tostring(charId))
        TriggerClientEvent('cm-characters:client:error', src, 'Character not found')
        return
    end
    
    char = char[1]
    print('[CM-CHARACTERS] Character found: ' .. tostring(char.first_name) .. ' ' .. tostring(char.last_name))
    
    -- Set player state
    Player(src).state:set('charId', charId, true)
    Player(src).state:set('isLoggedIn', true, true)
    Player(src).state:set('cash', char.cash or 0, true)
    Player(src).state:set('bank', char.bank or 0, true)
    
    -- Apply appearance
    local appearance = nil
    if char.appearance_json and char.appearance_json ~= '{}' and char.appearance_json ~= '' then
        local ok, decoded = pcall(json.decode, char.appearance_json)
        if ok and decoded then
            appearance = decoded
            print('[CM-CHARACTERS] Decoded appearance, sending to client')
            TriggerClientEvent('cm-characters:client:applyAppearance', src, appearance)
        else
            print('[CM-CHARACTERS] Failed to decode appearance')
        end
    else
        print('[CM-CHARACTERS] No appearance saved')
    end
    
    -- Get spawn position
    local spawn = {x = -1037.0, y = -2737.0, z = 13.8, heading = 0.0}
    if char.last_position and char.last_position ~= '' and char.last_position ~= 'null' then
        local ok, decoded = pcall(json.decode, char.last_position)
        if ok and decoded then
            spawn = decoded
        end
    end
    
    print('[CM-CHARACTERS] Spawning at: ' .. json.encode(spawn))
    
    -- FIX: Send spawn event with all data
    TriggerClientEvent('cm-characters:client:spawn', src, {
        last_position = spawn,
        appearance = appearance
    })
    
    print('[CM-CHARACTERS] >>> selectCharacter complete <<<')
    
    TriggerEvent('cm-core:characterLoaded', src, charId)
end)