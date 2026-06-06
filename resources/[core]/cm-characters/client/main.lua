-- cm-characters/client/main.lua

local display = false
local currentAccountId = nil

-- Open character selector (called by cm-auth after login)
RegisterNetEvent('cm-characters:client:openSelector', function(accountId)
    currentAccountId = accountId
    display = true
    SetNuiFocus(true, true)
    
    -- Request slots from server
    TriggerServerEvent('cm-characters:server:getSlots', accountId)
end)

-- Show slots UI
RegisterNetEvent('cm-characters:client:showSlots', function(slots, accountId)
    SendNUIMessage({
        action = 'showSlots',
        slots = slots,
        accountId = accountId
    })
end)

-- Create result
RegisterNetEvent('cm-characters:client:createResult', function(success, data)
    if success then
        -- Character created, select it
        TriggerServerEvent('cm-characters:server:selectCharacter', data)
    else
        SendNUIMessage({action = 'error', message = data})
    end
end)

-- Character selected, close UI and spawn
RegisterNetEvent('cm-characters:client:spawn', function(charData)
    display = false
    SetNuiFocus(false, false)
    
    -- Spawn player
    local spawn = charData.last_position or {x = -1037.0, y = -2737.0, z = 13.8, heading = 0.0}
    
    DoScreenFadeOut(500)
    Wait(500)
    
    local ped = PlayerPedId()
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z)
    SetEntityHeading(ped, spawn.heading or 0.0)
    FreezeEntityPosition(ped, false)
    SetPedDefaultComponentVariation(ped)
    
    DoScreenFadeIn(500)
    
    -- Set local state
    LocalPlayer.state:set('isLoggedIn', true, true)
end)

-- Error handler
RegisterNetEvent('cm-characters:client:error', function(msg)
    SendNUIMessage({action = 'error', message = msg})
end)

-- Deleted handler
RegisterNetEvent('cm-characters:client:deleted', function(charId)
    -- Refresh slots
    if currentAccountId then
        TriggerServerEvent('cm-characters:server:getSlots', currentAccountId)
    end
end)

-- NUI Callbacks
RegisterNUICallback('selectSlot', function(data, cb)
    if data.charId then
        -- Select existing character
        TriggerServerEvent('cm-characters:server:selectCharacter', data.charId)
    else
        -- Create new character in this slot
        SendNUIMessage({action = 'showCreator', slot = data.slot})
    end
    cb('ok')
end)

RegisterNUICallback('createCharacter', function(data, cb)
    TriggerServerEvent('cm-characters:server:create', currentAccountId, data.slot, {
        firstName = data.firstName,
        lastName = data.lastName,
        dob = data.dob,
        gender = data.gender,
        appearance = data.appearance or {}
    })
    cb('ok')
end)

RegisterNUICallback('deleteCharacter', function(data, cb)
    TriggerServerEvent('cm-characters:server:deleteCharacter', data.charId)
    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    display = false
    SetNuiFocus(false, false)
    cb('ok')
end)