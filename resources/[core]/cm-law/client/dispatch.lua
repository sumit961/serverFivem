-- cm-law 911/dispatch (client). Runs for every connected client -- /reportlaw
-- is a server-registered command (server/dispatch.lua), so this file only
-- ever reacts to events the server already decided to send it (the
-- server-side recipients() filter is the real gate, not anything here).

local activeBlips = {} -- [callId] = blipHandle
local activeCallCoords = {} -- [callId] = { x, y, z }
local activeCallColours = {} -- [callId] = blip colour

local function removeBlip(callId)
    local blip = activeBlips[callId]
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    activeBlips[callId] = nil
    activeCallCoords[callId] = nil
    activeCallColours[callId] = nil
end

-- Bare global so a future quick-menu (or the F9 dispatch tab itself) can
-- offer a "set waypoint" button without duplicating the blip/coords lookup.
function LawSetDispatchRoute(callId)
    callId = tonumber(callId)
    local blip = callId and activeBlips[callId]
    local coords = callId and activeCallCoords[callId]
    if blip and DoesBlipExist(blip) then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, activeCallColours[callId] or Config.Dispatch.BlipColour or 5)
        return true
    end
    if coords then
        SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
        return true
    end
    return false
end

local function addCallBlip(call, notify)
    if type(call) ~= 'table' or not call.id or type(call.coords) ~= 'table' then return end
    local callType = call.callType or 'citizen'
    local colour = callType == 'panic' and (Config.Dispatch.PanicBlipColour or 1)
        or callType == 'backup' and (Config.Dispatch.BackupBlipColour or 47)
        or (Config.Dispatch.BlipColour or 5)
    if notify then
        TriggerEvent('cm-hud:client:notify', ('Dispatch: %s'):format(call.details), callType == 'panic' and 'error' or 'inform')
        PlaySoundFrontend(-1, callType == 'panic' and 'TIMER_STOP' or 'SELECT', 'HUD_MINI_GAME_SOUNDSET', true)
    end
    removeBlip(call.id)
    local blip = AddBlipForCoord(call.coords.x, call.coords.y, call.coords.z)
    SetBlipSprite(blip, Config.Dispatch.BlipSprite or 161)
    SetBlipColour(blip, colour)
    SetBlipScale(blip, callType == 'panic' and 1.2 or 1.0)
    if callType == 'panic' then SetBlipFlashes(blip, true) end
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('Dispatch: %s'):format(call.details))
    EndTextCommandSetBlipName(blip)
    activeBlips[call.id] = blip
    activeCallCoords[call.id] = { x = call.coords.x, y = call.coords.y, z = call.coords.z }
    activeCallColours[call.id] = colour
    SendNUIMessage({ action = 'dispatchRefresh' })
end

RegisterNetEvent('cm-law:client:dispatchCall', function(call)
    addCallBlip(call, true)
end)

RegisterNetEvent('cm-law:client:dispatchCallUpdated', function(_)
    SendNUIMessage({ action = 'dispatchRefresh' })
end)

RegisterNetEvent('cm-law:client:dispatchCallResolved', function(callId)
    removeBlip(tonumber(callId))
    SendNUIMessage({ action = 'dispatchRefresh' })
end)

function LawRequestOfficerAlert(alertType)
    alertType = tostring(alertType or ''):lower()
    if alertType ~= 'backup' and alertType ~= 'panic' then return false end
    local panic = alertType == 'panic'
    local result = lib.alertDialog({
        header = panic and 'Confirm panic button' or 'Confirm backup request',
        content = panic and 'Send an urgent officer-in-distress alert to every available legal unit?'
            or 'Send your current location and request additional units?',
        centered = true, cancel = true,
        labels = { confirm = panic and 'Activate panic' or 'Request backup', cancel = 'Cancel' },
    })
    if result ~= 'confirm' then return false end
    local ok, message = lib.callback.await('cm-law:server:createOfficerAlert', false, alertType)
    TriggerEvent('cm-hud:client:notify', message or 'Dispatch request failed.', ok and 'success' or 'error')
    return ok == true
end

RegisterCommand('lawbackup', function() LawRequestOfficerAlert('backup') end, false)
RegisterCommand('lawpanic', function() LawRequestOfficerAlert('panic') end, false)

local function syncActiveCalls()
    local calls = lib.callback.await('cm-law:server:dispatchActiveCalls', false) or {}
    local seen = {}
    for _, call in ipairs(calls) do
        seen[tonumber(call.id)] = true
        addCallBlip(call, false)
    end
    for callId in pairs(activeBlips) do
        if not seen[callId] then removeBlip(callId) end
    end
end

RegisterNetEvent('cm-law:client:membershipChanged', function()
    SetTimeout(750, syncActiveCalls)
end)

CreateThread(function()
    Wait(2500)
    syncActiveCalls()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for callId in pairs(activeBlips) do removeBlip(callId) end
end)
