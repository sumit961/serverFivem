-- cm-characters/server/creation.lua

RegisterNetEvent('cm-characters:server:create', function(accountId, charSlot, data)
    local src = source
    
    -- Validate
    local ok, err = exports['cm-core']:Validate('name', data.firstName)
    if not ok then
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Invalid first name: ' .. err)
        return
    end
    
    ok, err = exports['cm-core']:Validate('name', data.lastName)
    if not ok then
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Invalid last name: ' .. err)
        return
    end
    
    ok, err = exports['cm-core']:Validate('slot', charSlot)
    if not ok then
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Invalid slot')
        return
    end
    
    -- Check slot not taken
    local existing = exports['cm-core']:Query(
        'SELECT id FROM characters WHERE account_id = ? AND slot = ?',
        {accountId, charSlot}
    )
    if existing and #existing > 0 then
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Character slot already used')
        return
    end
    
    -- Check max characters (3 per account)
    local count = exports['cm-core']:Scalar(
        'SELECT COUNT(*) FROM characters WHERE account_id = ?',
        {accountId}
    )
    if count and count >= 3 then
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Maximum 3 characters reached')
        return
    end
    
    -- Check name not taken (globally unique)
    local nameTaken = exports['cm-core']:Query(
        'SELECT id FROM characters WHERE first_name = ? AND last_name = ?',
        {data.firstName, data.lastName}
    )
    if nameTaken and #nameTaken > 0 then
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Name already taken by another player')
        return
    end
    
    -- Create character - ID is AUTO_INCREMENT, starts from 1
    local spawn = exports['cm-core']:GetConfig('Spawn', 'defaultPosition')
    
    local ok2, result = pcall(function()
        return exports['cm-core']:Insert([[
            INSERT INTO characters 
            (account_id, slot, first_name, last_name, dob, gender, appearance_json, last_position, cash, bank)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            accountId, charSlot,
            data.firstName, data.lastName,
            data.dob or nil, data.gender or 'male',
            json.encode(data.appearance or {}),
            json.encode(spawn),
            exports['cm-core']:GetConfig('Economy', 'startingCash') or 500,
            exports['cm-core']:GetConfig('Economy', 'startingBank') or 2000
        })
    end)
    
    if not ok2 then
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Database error: ' .. tostring(result))
        return
    end
    
    -- result is the new auto-increment ID
    local newCharId = result
    
    exports['cm-core']:Log('cm-characters', 'info', 'Character created', {
        category = 'character',
        player_src = src,
        player_char_id = newCharId,
        account_id = accountId,
        name = data.firstName .. ' ' .. data.lastName,
        slot = charSlot
    })
    
    TriggerClientEvent('cm-characters:client:createResult', src, true, {
        charId = newCharId,
        message = 'Character #' .. newCharId .. ' created'
    })
end)