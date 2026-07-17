RegisterNetEvent('cm-vehiclekeys:client:notify', function(message, messageType)
    message = tostring(message or '')
    if message == '' then return end

    -- Prefer the shared CM notification surface when it exists, while keeping
    -- a native GTA fallback so this resource remains independently usable.
    if GetResourceState('cm-hud') == 'started' then
        local ok = pcall(function()
            exports['cm-hud']:Notify(message, messageType or 'info')
        end)
        if ok then return end
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end)
