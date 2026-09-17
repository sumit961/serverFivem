-- cm-police 911/dispatch (client). Runs for every connected client, same as
-- impound.lua/cuffs.lua's own always-on threads -- /reportcrime itself is a
-- server-registered command (server/dispatch.lua), so this file only ever
-- reacts to events the server already decided to send it (the server-side
-- recipients() filter is the real gate, not anything here).

local activeBlips = {} -- [callId] = blipHandle
local activeCallCoords = {} -- [callId] = { x, y, z }

local function removeBlip(callId)
    local blip = activeBlips[callId]
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    activeBlips[callId] = nil
    activeCallCoords[callId] = nil
end

function PoliceSetDispatchRoute(callId)
    callId = tonumber(callId)
    local blip = callId and activeBlips[callId]
    local coords = callId and activeCallCoords[callId]
    if blip and DoesBlipExist(blip) then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, PoliceConfig.Dispatch.BlipColour or 3)
        return true
    end
    if coords then
        SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
        return true
    end
    return false
end

RegisterNetEvent('cm-police:client:dispatchCall', function(call)
    PoliceNotify(call.details, 'error', 'Dispatch')
    removeBlip(call.id)
    local blip = AddBlipForCoord(call.coords.x, call.coords.y, call.coords.z)
    SetBlipSprite(blip, PoliceConfig.Dispatch.BlipSprite or 161)
    SetBlipColour(blip, PoliceConfig.Dispatch.BlipColour or 3)
    SetBlipScale(blip, 1.0)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('Dispatch: %s'):format(call.details))
    EndTextCommandSetBlipName(blip)
    activeBlips[call.id] = blip
    activeCallCoords[call.id] = { x = call.coords.x, y = call.coords.y, z = call.coords.z }
    SendNUIMessage({ cmInterface = "police", action = 'dispatchRefresh' })
end)

RegisterNetEvent('cm-police:client:dispatchCallUpdated', function(_)
    SendNUIMessage({ cmInterface = "police", action = 'dispatchRefresh' })
end)

RegisterNetEvent('cm-police:client:dispatchCallResolved', function(callId)
    removeBlip(tonumber(callId))
    SendNUIMessage({ cmInterface = "police", action = 'dispatchRefresh' })
end)

-- cm-law owns the shared Police/Sheriff/FIB/Army incident feed. Its own
-- client creates the shared blip; these aliases only refresh Police's NUI.
RegisterNetEvent('cm-law:client:dispatchCall', function() SendNUIMessage({ cmInterface = "police", action = 'dispatchRefresh' }) end)
RegisterNetEvent('cm-law:client:dispatchCallUpdated', function() SendNUIMessage({ cmInterface = "police", action = 'dispatchRefresh' }) end)
RegisterNetEvent('cm-law:client:dispatchCallResolved', function() SendNUIMessage({ cmInterface = "police", action = 'dispatchRefresh' }) end)
RegisterNetEvent('cm-law:client:liveOperationsUpdated', function()
    if type(LocalPlayer.state.cmPolice) == 'table' then
        SendNUIMessage({ cmInterface = "police", action = 'liveOperationsRefresh' })
    end
end)
RegisterNetEvent('cm-law:client:dispatchAssigned', function(call)
    if type(LocalPlayer.state.cmPolice) ~= 'table' or type(call) ~= 'table' then return end
    PoliceNotify(('Assigned to call #%s · %s'):format(tostring(call.id), tostring(call.location or 'Unknown location')), 'success', 'Dispatch assignment')
    if type(call.coords) == 'table' and tonumber(call.coords.x) and tonumber(call.coords.y) then
        SetNewWaypoint(tonumber(call.coords.x) + 0.0, tonumber(call.coords.y) + 0.0)
    end
end)

RegisterNUICallback('police_dispatchLiveOperations', function(_, cb)
    cb(lib.callback.await('cm-law:server:liveOperations', false) or { ok = false, error = 'Live operations unavailable.' })
end)
RegisterNUICallback('police_setUnitStatus', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:setUnitStatus', false, data and data.status)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('police_setUnitCallsign', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:setUnitCallsign', false, data and data.callsign)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('police_dispatchAssignUnit', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:assignDispatchUnit', false, data and data.callId, data and data.characterId)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('police_dispatchReleaseUnit', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:releaseDispatchUnit', false, data and data.callId, data and data.characterId)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('police_dispatchSetPriority', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:setDispatchPriority', false, data and data.callId, data and data.priority)
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('police_dispatchRouteUnit', function(data, cb)
    local ok, message, coords = lib.callback.await('cm-law:server:routeToUnit', false, data and data.characterId)
    if ok and type(coords) == 'table' and tonumber(coords.x) and tonumber(coords.y) then
        SetNewWaypoint(tonumber(coords.x) + 0.0, tonumber(coords.y) + 0.0)
    end
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)
RegisterNUICallback('police_dispatchOnScene', function(data, cb)
    local ok, message = lib.callback.await('cm-law:server:setDispatchResponseStatus', false, data and data.callId, 'on_scene')
    cb({ ok = ok == true, message = ok and message or nil, error = not ok and message or nil })
end)

-- Backup request (server/dispatch.lua's requestBackup, fired from the J
-- quick-menu). Deliberately NOT tracked in activeBlips -- there's no call
-- id/resolve event for this, it's just a one-shot ping that expires itself
-- after PoliceConfig.Backup.BlipLifetimeMs.
local backupBlips = {}

function PoliceRequestBackup(priority, requireConfirmation)
    priority = tostring(priority or 'normal')
    local state = LocalPlayer.state.cmPolice
    if type(state) ~= 'table' or state.onDuty ~= true then
        return PoliceNotify('You must be an on-duty officer.', 'error')
    end
    if requireConfirmation then
        local panic = priority == 'panic'
        local confirmed = PoliceConfirm(
            panic and 'Activate Panic Button?' or 'Request Urgent Backup?',
            panic and 'Send an emergency panic alert and flashing GPS marker to every on-duty unit?'
                or 'Send a high-priority backup alert and GPS marker to every on-duty unit?',
            panic and 'Activate Panic' or 'Request Urgent Backup',
            'Cancel'
        )
        if not confirmed then return end
    end
    local ok, message = lib.callback.await('cm-law:server:createOfficerAlert', false, priority == 'panic' and 'panic' or 'backup')
    PoliceNotify(message, ok and 'success' or 'error')
end

RegisterNetEvent('cm-police:client:backupRequested', function(officerName, coords, priority)
    priority = tostring(priority or 'normal')
    local panic = priority == 'panic'
    local urgent = priority == 'urgent'
    local prefix = panic and 'PANIC BUTTON' or (urgent and 'URGENT BACKUP' or 'Backup requested')
    PoliceNotify(('%s by %s!'):format(prefix, tostring(officerName or 'an officer')), 'error', 'Dispatch')
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, PoliceConfig.Backup.BlipSprite or 161)
    SetBlipColour(blip, PoliceConfig.Backup.BlipColour or 1)
    SetBlipScale(blip, panic and 1.4 or (urgent and 1.3 or 1.2))
    if panic then SetBlipFlashes(blip, true) end
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('%s: %s'):format(prefix, tostring(officerName or 'an officer')))
    EndTextCommandSetBlipName(blip)
    backupBlips[blip] = true
    CreateThread(function()
        Wait(PoliceConfig.Backup.BlipLifetimeMs or 60000)
        if backupBlips[blip] and DoesBlipExist(blip) then RemoveBlip(blip) end
        backupBlips[blip] = nil
    end)
end)

RegisterCommand('policepanic', function()
    PoliceRequestBackup('panic', true)
end, false)
-- Physical F9 belongs to cm-core's organization dispatch router. The command
-- remains available to menus and manual/admin bindings.

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for callId in pairs(activeBlips) do removeBlip(callId) end
    for blip in pairs(backupBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    backupBlips = {}
end)
