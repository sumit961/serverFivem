-- cm-characters/client/admin.lua
-- NUI bridge for the character admin panel.

RegisterNetEvent('cm-characters:client:openAdmin', function()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openCharacterAdmin' })
end)

RegisterNetEvent('cm-characters:client:adminResults', function(results)
    SendNUIMessage({ action = 'characterAdminResults', results = results or {} })
end)

RegisterNetEvent('cm-characters:client:adminStatus', function(data)
    data = type(data) == 'table' and data or {}
    SendNUIMessage({ action = 'characterAdminStatus', ok = data.ok == true, message = data.message or '' })
end)

RegisterNUICallback('charAdminSearch', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('cm-characters:server:adminSearch', data.query or '')
    cb({ ok = true })
end)

RegisterNUICallback('charAdminAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('cm-characters:server:adminAction', data.actionName or '', data.payload or {})
    cb({ ok = true })
end)

RegisterNUICallback('charAdminClose', function(data, cb)
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterCommand('charadmin', function()
    TriggerServerEvent('cm-characters:server:requestOpenAdmin')
end, false)
