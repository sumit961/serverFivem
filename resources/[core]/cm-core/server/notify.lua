exports('Notify', function(src, message, notifyType, duration)
    src = tonumber(src)
    if not src then return false end

    TriggerClientEvent('cm-core:client:notify', src, {
        message = tostring(message or ''),
        type = notifyType or 'info',
        duration = tonumber(duration) or ((CM.Shared and CM.Shared.Notify and CM.Shared.Notify.duration) or 5000),
    })
    return true
end)

RegisterNetEvent('cm-core:server:notify', function()
    -- Do not allow clients to trigger arbitrary notifications through the server.
    -- Server resources should use exports['cm-core']:Notify(source, ...).
end)
