-- cm-characters/client/creator.lua

local display = false
local currentSlot = nil
local currentAccountId = nil
local isCreating = false

AddEventHandler('cm-characters:client:openCreator', function(slot, accountId)
    currentSlot = slot
    currentAccountId = accountId
    display = true
    isCreating = false
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'showCreator',
        slot = slot
    })
    print('[CM-CHARACTERS] Creator opened for slot ' .. tostring(slot))
end)

RegisterNetEvent('cm-characters:client:createResult', function(success, data)
    print('[CM-CHARACTERS] createResult: success=' .. tostring(success) .. ' data=' .. tostring(data))
    isCreating = false
    
    if success then
        SendNUIMessage({action = 'hideCreator'})
        display = false
        SetNuiFocus(false, false)
        
        print('[CM-CHARACTERS] Opening appearance for charId=' .. tostring(data.charId))
        TriggerEvent('cm-characters:client:openAppearance', {
            charId = data.charId,
            slot = currentSlot,
            gender = data.gender,
            isNew = true
        })
    else
        -- Show error in creator form
        SendNUIMessage({
            action = 'error',
            message = tostring(data)
        })
        print('[CM-CHARACTERS] Creation failed: ' .. tostring(data))
    end
end)

RegisterNUICallback('createCharacter', function(data, cb)
    if isCreating then
        cb('ok')
        return
    end
    
    isCreating = true
    print('[CM-CHARACTERS] createCharacter: ' .. json.encode(data))
    
    TriggerServerEvent('cm-characters:server:create', currentAccountId, currentSlot, {
        firstName = data.firstName,
        lastName = data.lastName,
        dob = data.dob,
        gender = data.gender
    })
    
    cb('ok')
end)

RegisterNUICallback('closeCreator', function(data, cb)
    display = false
    SetNuiFocus(false, false)
    TriggerServerEvent('cm-characters:server:getSlots', currentAccountId)
    cb('ok')
end)