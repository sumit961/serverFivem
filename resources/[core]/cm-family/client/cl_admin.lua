-- cm-family | resource-owned admin/recovery panel bridge.
local adminOpen = false

RegisterNetEvent('cm-family:client:openAdmin', function()
    local data = lib.callback.await('cm-family:server:adminData', false)
    if type(data) ~= 'table' then
        lib.notify({ description = 'You cannot open Family Admin.', type = 'error' })
        return
    end
    adminOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'family:adminOpen', data = data })
end)

RegisterNUICallback('familyAdminAction', function(payload, cb)
    payload = type(payload) == 'table' and payload or {}
    local ok, result = lib.callback.await('cm-family:server:adminAction', false,
        tostring(payload.action or ''), tonumber(payload.familyId))
    if ok then
        lib.notify({ description = result or 'Family recovery completed.', type = 'success' })
        local data = lib.callback.await('cm-family:server:adminData', false)
        SendNUIMessage({ action = 'family:adminRefresh', data = data })
    else
        lib.notify({ description = result or 'Family recovery failed.', type = 'error' })
    end
    cb({ ok = ok, message = result })
end)

RegisterNUICallback('familyAdminClose', function(_, cb)
    adminOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'family:adminClose' })
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and adminOpen then SetNuiFocus(false, false) end
end)
