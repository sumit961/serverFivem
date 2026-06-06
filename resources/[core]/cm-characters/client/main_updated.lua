-- Updated main.lua - connects slots to creator to appearance

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

-- Create result - NOW goes to appearance instead of spawn
RegisterNetEvent('cm-characters:client:createResult', function(success, data)
    if success then
        -- Character created, now open appearance editor
        -- The creator.lua will handle hiding its UI and triggering this
        TriggerEvent('cm-characters:client:openAppearance', {
            charId = data.charId,
            slot = data.slot,
            gender = data.gender,
            isNew = true
        })
    else
        SendNUIMessage({action = 'error', message = data})
    end
end)

-- Character selected, close UI and spawn (for existing characters)
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

    -- Apply saved appearance if exists
    if charData.appearance then
        TriggerEvent('cm-characters:client:applyAppearance', charData.appearance)
    else
        SetPedDefaultComponentVariation(ped)
    end

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
        -- Select existing character -> spawn directly
        TriggerServerEvent('cm-characters:server:selectCharacter', data.charId)
    else
        -- Empty slot -> open character creator form
        TriggerEvent('cm-characters:client:openCreator', data.slot, currentAccountId)
    end
    cb('ok')
end)

RegisterNUICallback('deleteCharacter', function(data, cb)
    -- NO DELETE - characters are permanent
    -- This callback exists for compatibility but does nothing
    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    display = false
    SetNuiFocus(false, false)
    cb('ok')
end)
