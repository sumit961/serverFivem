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
    
    SendNUIMessage({action = 'showApp'})
    TriggerServerEvent('cm-characters:server:getSlots', accId)
end)

RegisterNetEvent('cm-characters:client:showSlots', function(slots, accountId)
    print('[CM-CHARACTERS] showSlots received!')
    
    SendNUIMessage({
        action = 'showSlots',
        slots = slots,
        accountId = accountId
    })
end)

-- REMOVED: spawn event is now in cm-spawn/client/main.lua
-- REMOVED: appearance application moved to cm-spawn/client/main.lua
-- REMOVED: camera cleanup moved to cm-spawn/client/main.lua

RegisterNetEvent('cm-characters:client:error', function(msg)
    print('[CM-CHARACTERS] error: ' .. tostring(msg))
    -- If spawn fails, show UI again so player can retry
    display = true
    SetNuiFocus(true, true)
    SendNUIMessage({action = 'error', message = msg})
end)

RegisterNetEvent('cm-characters:client:deleted', function(charId)
    if currentAccountId then
        TriggerServerEvent('cm-characters:server:getSlots', currentAccountId)
    end
end)

RegisterNUICallback('selectSlot', function(data, cb)
    print('[CM-CHARACTERS] selectSlot: ' .. json.encode(data))
    
    if data.charId then
        -- Hide UI immediately, let cm-spawn take over from here
        display = false
        SetNuiFocus(false, false)
        SendNUIMessage({action = 'hideAll'})
        
        TriggerServerEvent('cm-characters:server:selectCharacter', data.charId)
    else
        -- Open creator for empty slot
        TriggerEvent('cm-characters:client:openCreator', data.slot, currentAccountId)
    end
    
    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    display = false
    SetNuiFocus(false, false)
    cb('ok')
end)