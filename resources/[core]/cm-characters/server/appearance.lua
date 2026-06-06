-- cm-characters appearance server
-- Handles saving character appearance data

-- Save appearance after character creation
RegisterNetEvent('cm-characters:server:saveAppearance', function(charId, appearanceData)
    local src = source

    -- Validate char exists and belongs to player
    local char = exports['cm-characters']:GetCharacterById(charId)
    if not char then
        TriggerClientEvent('cm-characters:client:error', src, 'Character not found')
        return
    end

    -- Validate appearance data structure
    if type(appearanceData) ~= 'table' then
        TriggerClientEvent('cm-characters:client:error', src, 'Invalid appearance data')
        return
    end

    -- Save to database
    local ok, result = pcall(function()
        return exports['cm-core']:Execute(
            'UPDATE characters SET appearance_json = ? WHERE id = ?',
            {json.encode(appearanceData), charId}
        )
    end)

    if not ok then
        TriggerClientEvent('cm-characters:client:error', src, 'Failed to save appearance')
        exports['cm-core']:Log('cm-characters', 'error', 'Appearance save failed', {
            category = 'appearance',
            player_src = src,
            char_id = charId,
            error = tostring(result)
        })
        return
    end

    -- Update cache
    exports['cm-core']:CacheInvalidate('char:' .. charId)

    -- Log success
    exports['cm-core']:Log('cm-characters', 'info', 'Appearance saved', {
        category = 'appearance',
        player_src = src,
        char_id = charId
    })

    -- Now spawn the character (same as selectCharacter)
    local charFull = exports['cm-characters']:GetCharacterById(charId)
    if charFull then
        -- Set state bags
        Player(src).state:set('charId', charId, true)
        Player(src).state:set('isLoggedIn', true, true)
        Player(src).state:set('cash', charFull.cash, true)
        Player(src).state:set('bank', charFull.bank, true)

        -- Apply appearance to ped (server-side state bag or client event)
        TriggerClientEvent('cm-characters:client:applyAppearance', src, appearanceData)

        -- Fire core event
        TriggerEvent('cm-core:characterLoaded', src, charId)

        -- Spawn player
        local spawn = json.decode(charFull.last_position) or {x = -1037.0, y = -2737.0, z = 13.8, heading = 0.0}
        TriggerClientEvent('cm-characters:client:spawn', src, {
            last_position = spawn,
            appearance = appearanceData
        })
    end
end)

-- Apply appearance to existing character (for re-logging)
RegisterNetEvent('cm-characters:server:loadAppearance', function(charId)
    local src = source
    local char = exports['cm-characters']:GetCharacterById(charId)

    if char and char.appearance_json then
        local appearance = json.decode(char.appearance_json)
        if appearance then
            TriggerClientEvent('cm-characters:client:applyAppearance', src, appearance)
        end
    end
end)
