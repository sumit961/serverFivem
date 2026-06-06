local display = false
local currentSlot = nil
local currentAccountId = nil

-- Open character creator form (called after selecting empty slot)
RegisterNetEvent('cm-characters:client:openCreator', function(slot, accountId)
    currentSlot = slot
    currentAccountId = accountId
    display = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'showCreator',
        slot = slot
    })
end)

-- NUI Callback: Submit character creation form
RegisterNUICallback('submitCreator', function(data, cb)
    -- Validate and send to server
    TriggerServerEvent('cm-characters:server:create', currentAccountId, currentSlot, {
        firstName = data.firstName,
        lastName = data.lastName,
        dob = data.dob,
        gender = data.gender
    })
    cb({success = true})
end)

-- NUI Callback: Close creator
RegisterNUICallback('closeCreator', function(data, cb)
    display = false
    SetNuiFocus(false, false)
    -- Go back to slots
    TriggerServerEvent('cm-characters:server:getSlots', currentAccountId)
    cb('ok')
end)

-- Creation result - if success, go to appearance
RegisterNetEvent('cm-characters:client:createResult', function(success, data)
    if success then
        -- Hide creator UI, open appearance editor
        SendNUIMessage({action = 'hideCreator'})

        -- Trigger appearance editor with new char data
        TriggerEvent('cm-characters:client:openAppearance', {
            charId = data.charId,
            slot = currentSlot,
            gender = data.gender,
            isNew = true
        })
    else
        -- Show error in creator UI
        SendNUIMessage({
            action = 'creatorError',
            message = data
        })
    end
end)
