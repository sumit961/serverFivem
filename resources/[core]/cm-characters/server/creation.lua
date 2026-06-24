-- cm-characters/server/creation.lua

CreateThread(function()
    Wait(1000)
    pcall(function()
        exports['cm-core']:Query('ALTER TABLE characters ADD COLUMN IF NOT EXISTS has_spawned TINYINT(1) NOT NULL DEFAULT 0')
    end)
end)


RegisterNetEvent('cm-characters:server:create', function(accountId, charSlot, data)
    local src = source

    -- Always use server-authoritative account ID to prevent spoofing.
    local stateAccountId = tostring(Player(src).state.accountId or '')
    if stateAccountId ~= '' then accountId = stateAccountId end

    print('[CM-CHARACTERS] server:create called')
    print('[CM-CHARACTERS] accountId=' .. tostring(accountId) .. ' slot=' .. tostring(charSlot))
    print('[CM-CHARACTERS] data=' .. json.encode(data))

    -- Validate
    if not data.firstName or data.firstName == '' then
        print('[CM-CHARACTERS] ERROR: Empty firstName')
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'First name required')
        return
    end

    if not data.lastName or data.lastName == '' then
        print('[CM-CHARACTERS] ERROR: Empty lastName')
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Last name required')
        return
    end

    -- Check slot not taken
    local existing = exports['cm-core']:Query(
        'SELECT id FROM characters WHERE account_id = ? AND slot = ?',
        {tostring(accountId), tonumber(charSlot)}
    )
    if existing and #existing > 0 then
        print('[CM-CHARACTERS] ERROR: Slot already used')
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Character slot already used')
        return
    end

    local maxCharacters = tonumber(Config and Config.MaxCharacters) or 2

    -- Check max characters
    local count = exports['cm-core']:Scalar(
        'SELECT COUNT(*) FROM characters WHERE account_id = ?',
        {tostring(accountId)}
    )
    if count and count >= maxCharacters then
        print('[CM-CHARACTERS] ERROR: Max ' .. tostring(maxCharacters) .. ' characters reached')
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Maximum ' .. tostring(maxCharacters) .. ' characters reached')
        return
    end

    -- Check name not taken
    local nameTaken = exports['cm-core']:Query(
        'SELECT id FROM characters WHERE first_name = ? AND last_name = ?',
        {data.firstName, data.lastName}
    )
    if nameTaken and #nameTaken > 0 then
        print('[CM-CHARACTERS] ERROR: Name taken')
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Name already taken')
        return
    end

    local spawn = {x = -1037.0, y = -2737.0, z = 13.8, heading = 0.0}

    -- Fixed RP character ID.
    -- This is NOT the FiveM source/server ID. It is the permanent DB ID used everywhere.
    -- First created character = 0, next = 1, next = 2...
    local newCharId, idErr = CMAllocateCharacterId()
    if not newCharId then
        print('[CM-CHARACTERS] ERROR allocating fixed character ID: ' .. tostring(idErr))
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Could not allocate character ID')
        return
    end

    print('[CM-CHARACTERS] Allocated fixed charId: ' .. tostring(newCharId))

    -- Insert character
    local ok, err = pcall(function()
        exports['cm-core']:Query([[
            INSERT INTO characters 
            (id, account_id, slot, first_name, last_name, dob, gender, appearance_json, last_position, cash, bank, has_spawned)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            newCharId,
            tostring(accountId),
            tonumber(charSlot),
            data.firstName,
            data.lastName,
            data.dob or nil,
            data.gender or 'male',
            '{}',
            json.encode(spawn),
            500,
            2000,
            0
        })
        return true
    end)

    if not ok then
        print('[CM-CHARACTERS] ERROR creating character: ' .. tostring(err))
        TriggerClientEvent('cm-characters:client:createResult', src, false, 'Database error: ' .. tostring(err))
        return
    end

    print('[CM-CHARACTERS] Character created successfully: ' .. newCharId)

    TriggerClientEvent('cm-characters:client:createResult', src, true, {
        charId = newCharId,
        gender = data.gender,
        message = 'Character created'
    })
end)