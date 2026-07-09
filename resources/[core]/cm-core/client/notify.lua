RegisterNetEvent('cm-core:client:notify', function(data)
    data = type(data) == 'table' and data or { message = tostring(data or '') }
    local message = tostring(data.message or '')
    local notifyType = data.type or 'info'
    local duration = tonumber(data.duration) or 5000

    -- Preferred path for CM HUD notification system.
    if GetResourceState('cm-hud') == 'started' then
        local ok = pcall(function()
            exports['cm-hud']:Notify(message, notifyType, duration)
        end)
        if ok then return end
    end

    -- Safe GTA fallback.
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end)

exports('Notify', function(message, notifyType, duration)
    TriggerEvent('cm-core:client:notify', {
        message = message,
        type = notifyType or 'info',
        duration = duration,
    })
end)
