-- cm-characters/client/main.lua

local display = false
local currentAccountId = nil

print('[CM-CHARACTERS] main.lua loaded!')

RegisterNetEvent('cm-characters:client:openSelector', function(accountId)
    local accId = tostring(accountId)
    print('[CM-CHARACTERS] openSelector received! accountId=' .. accId)
    
    currentAccountId = accId
    display = true
    SetNuiFocus(true, true)
    
    SendNUIMessage({
        action = 'showApp'
    })
    
    TriggerServerEvent('cm-characters:server:getSlots', accId)
end)

RegisterNetEvent('cm-characters:client:showSlots', function(slots, accountId)
    print('[CM-CHARACTERS] showSlots received!')
    
    SendNUIMessage({
        action = 'showSlots',
        slots = slots,
        accountId = accountId
    })
    print('[CM-CHARACTERS] Sent slots to UI')
end)

RegisterNetEvent('cm-characters:client:spawn', function(charData)
    print('[CM-CHARACTERS] >>> SPAWN EVENT RECEIVED <<<')
    
    display = false
    
    -- FIX: Cleanup any existing camera from appearance editor
    TriggerEvent('cm-characters:client:cleanupAppearance')
    
    -- Hide UI
    SendNUIMessage({action = 'hideAll'})
    SetNuiFocus(false, false)

    local spawn = charData.last_position or {x = -1037.0, y = -2737.0, z = 13.8, heading = 0.0}

    DoScreenFadeOut(500)
    Wait(500)

    local ped = PlayerPedId()
    
    -- FIX: Ensure player is unfrozen before teleport
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    
    -- Teleport to spawn
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z)
    SetEntityHeading(ped, spawn.heading or 0.0)
    
    -- Reset camera
    RenderScriptCams(false, false, 0, true, true)
    SetCamActive(GetRenderingCam(), false)
    
    -- Wait for coords to set
    Wait(100)

    if charData.appearance then
        print('[CM-CHARACTERS] Applying appearance...')
        TriggerEvent('cm-characters:client:applyAppearance', charData.appearance)
    else
        print('[CM-CHARACTERS] No appearance, using default')
        SetPedDefaultComponentVariation(ped)
    end

    Wait(500)
    DoScreenFadeIn(500)
    
    -- Final unfreeze
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    
    LocalPlayer.state:set('isLoggedIn', true, true)
    
    print('[CM-CHARACTERS] >>> SPAWN COMPLETE <<<')
end)

RegisterNetEvent('cm-characters:client:error', function(msg)
    print('[CM-CHARACTERS] error: ' .. tostring(msg))
    SendNUIMessage({action = 'error', message = msg})
end)

RegisterNetEvent('cm-characters:client:deleted', function(charId)
    if currentAccountId then
        TriggerServerEvent('cm-characters:server:getSlots', currentAccountId)
    end
end)

RegisterNUICallback('selectSlot', function(data, cb)
    print('[CM-CHARACTERS] selectSlot callback: ' .. json.encode(data))
    if data.charId then
        print('[CM-CHARACTERS] Selecting character: ' .. tostring(data.charId))
        TriggerServerEvent('cm-characters:server:selectCharacter', data.charId)
    else
        print('[CM-CHARACTERS] Opening creator for slot: ' .. tostring(data.slot))
        TriggerEvent('cm-characters:client:openCreator', data.slot, currentAccountId)
    end
    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    display = false
    SetNuiFocus(false, false)
    cb('ok')
end)