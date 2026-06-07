-- cm-characters/server/appearance.lua

RegisterNetEvent('cm-characters:server:saveAppearance', function(charId, appearanceData)
    local src = source

    if type(appearanceData) ~= 'table' then
        TriggerClientEvent('cm-characters:client:error', src, 'Invalid appearance data')
        return
    end

    local char = exports['cm-core']:Query('SELECT * FROM characters WHERE id = ?', {charId})
    if not char or #char == 0 then
        TriggerClientEvent('cm-characters:client:error', src, 'Character not found')
        return
    end
    
    local charFull = char[1]

    local appearanceJson = json.encode(appearanceData)

    -- Use Query for UPDATE (cm-core doesn't have Execute)
    local ok, result = pcall(function()
        exports['cm-core']:Query(
            'UPDATE characters SET appearance_json = ? WHERE id = ?',
            {appearanceJson, charId}
        )
        return true
    end)

    if not ok then
        print('[CM-CHARACTERS] ERROR saving appearance: ' .. tostring(result))
        TriggerClientEvent('cm-characters:client:error', src, 'Failed to save appearance')
        return
    end

    print('[CM-CHARACTERS] Appearance saved for char ' .. tostring(charId))

    exports['cm-core']:CacheInvalidate('char:' .. charId)

    Player(src).state:set('charId', charId, true)
    Player(src).state:set('isLoggedIn', true, true)
    Player(src).state:set('cash', charFull.cash or 0, true)
    Player(src).state:set('bank', charFull.bank or 0, true)

    TriggerClientEvent('cm-characters:client:applyAppearance', src, appearanceData)
    TriggerEvent('cm-core:characterLoaded', src, charId)

    local spawn = {x = -1037.0, y = -2737.0, z = 13.8, heading = 0.0}
    if charFull.last_position and charFull.last_position ~= '' and charFull.last_position ~= 'null' then
        local ok2, decoded = pcall(json.decode, charFull.last_position)
        if ok2 and decoded then
            spawn = decoded
        end
    end
    
    TriggerClientEvent('cm-characters:client:spawn', src, {
        last_position = spawn,
        appearance = appearanceData
    })
end)

RegisterNetEvent('cm-characters:client:cleanupAppearance')
AddEventHandler('cm-characters:client:cleanupAppearance', function()
    print('[CM-CHARACTERS] Cleaning up appearance camera')
    
    isInAppearance = false
    
    -- Delete camera if exists
    if appearanceCam and DoesCamExist(appearanceCam) then
        SetCamActive(appearanceCam, false)
        RenderScriptCams(false, true, 500, true, true)
        DestroyCam(appearanceCam, false)
        appearanceCam = nil
    end
    
    -- Clear timecycle
    ClearTimecycleModifier()
    
    -- Unfreeze player
    FreezeEntityPosition(PlayerPedId(), false)
    ClearPedTasks(PlayerPedId())
    ClearPedTasksImmediately(PlayerPedId())
    
    -- Reset NUI focus
    SetNuiFocus(false, false)
    
    -- Hide appearance UI
    SendNUIMessage({action = 'closeAppearance'})
end)