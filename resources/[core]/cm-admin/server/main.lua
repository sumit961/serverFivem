local function notify(src, msg, msgType)
    TriggerClientEvent('cm-admin:client:notify', src, msg, msgType or 'info')
end

local function canUseNoclip(src)
    if src <= 0 then return true end
    if not Config.RequireAce then return true end
    return IsPlayerAceAllowed(src, Config.AcePermission)
end

local function requestToggle(src)
    if not canUseNoclip(src) then
        notify(src, 'You do not have permission to use noclip.', 'error')
        return
    end
    TriggerClientEvent('cm-admin:client:toggleNoclip', src)
end

CreateThread(function()
    for _, commandName in ipairs(Config.Commands or {}) do
        RegisterCommand(commandName, function(src)
            requestToggle(src)
        end, false)
    end
end)

RegisterNetEvent('cm-admin:server:requestNoclipToggle', function()
    requestToggle(source)
end)
