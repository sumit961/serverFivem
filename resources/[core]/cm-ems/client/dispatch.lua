local latestDispatch
local dispatchBlips = {}
local dispatchMenuOpen = false
local activeResponseCallId
local routedCallId
local dispatchBoardCalls = {}
local autoOnSceneSent = {}

local function notify(message, kind)
    if lib and lib.notify then lib.notify({ title = 'EMS Dispatch', description = message, type = kind or 'inform' }) end
end

local function streetAndZone(coords)
    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or ''
    local zoneCode = GetNameOfZone(coords.x, coords.y, coords.z)
    local zone = zoneCode and GetLabelText(zoneCode) or ''
    if zone == 'NULL' then zone = '' end
    if street ~= '' and zone ~= '' then return ('%s, %s'):format(street, zone) end
    return street ~= '' and street or (zone ~= '' and zone or 'Location unavailable')
end

local function enrich(call)
    if type(call) ~= 'table' or type(call.coords) ~= 'table' then return call end
    local x, y, z = tonumber(call.coords.x), tonumber(call.coords.y), tonumber(call.coords.z)
    if not x or not y or not z then return call end
    call.location = streetAndZone(vector3(x, y, z))
    call.distance = math.floor(#(GetEntityCoords(PlayerPedId()) - vector3(x, y, z)) + 0.5)
    call.etaSeconds = math.max(15, math.floor(call.distance / 13.9))
    return call
end

CreateThread(function()
    while true do
        Wait(4000)
        local call = activeResponseCallId and (dispatchBoardCalls[tonumber(activeResponseCallId)]
            or (latestDispatch and tonumber(latestDispatch.id) == tonumber(activeResponseCallId) and latestDispatch))
        if call then
            enrich(call)
            local status = tostring(call.responseStatus or '')
            if call.distance and call.distance <= (tonumber(Config.Dispatch.onSceneDistance) or 30.0)
                and status ~= 'on_scene' and status ~= 'transporting' and status ~= 'at_hospital'
                and not autoOnSceneSent[tonumber(call.id)] then
                autoOnSceneSent[tonumber(call.id)] = true
                local ok = lib.callback.await('cm-ems:server:dispatchStatus', false, tonumber(call.id), 'on_scene')
                if ok then
                    call.responseStatus = 'on_scene'
                    notify('Dispatch automatically marked you on scene.', 'success')
                else
                    autoOnSceneSent[tonumber(call.id)] = nil
                end
            end
        end
    end
end)

local function removeDispatchBlip(callId)
    local blip = dispatchBlips[callId]
    dispatchBlips[callId] = nil
    if blip and DoesBlipExist(blip) then
        SetBlipRoute(blip, false)
        RemoveBlip(blip)
    end
    if tonumber(routedCallId) == tonumber(callId) then
        routedCallId = nil
        SetWaypointOff()
    end
end

local function setCallWaypoint(call)
    if type(call) ~= 'table' or type(call.coords) ~= 'table' then return end
    local x, y = tonumber(call.coords.x), tonumber(call.coords.y)
    local callId = tonumber(call.id)
    for otherId, otherBlip in pairs(dispatchBlips) do
        if tonumber(otherId) ~= callId and DoesBlipExist(otherBlip) then SetBlipRoute(otherBlip, false) end
    end
    SetWaypointOff()
    routedCallId = callId
    local blip = callId and dispatchBlips[callId]
    if blip and DoesBlipExist(blip) then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, 3)
    elseif x and y then
        SetNewWaypoint(x + 0.0, y + 0.0)
    end
end

local function closeDispatchMenu()
    if not dispatchMenuOpen then return end
    dispatchMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'dispatch:closeMenu' })
end

local function loadDispatchBoard()
    local board, reason = lib.callback.await('cm-ems:server:dispatchBoard', false)
    if not board then notify(reason or 'Dispatch is unavailable.', 'error'); return false end
    dispatchBoardCalls = {}
    for _, call in ipairs(board.calls or {}) do
        enrich(call)
        dispatchBoardCalls[tonumber(call.id)] = call
    end
    SendNUIMessage({ action = 'dispatch:openMenu', board = board })
    return true
end

local function refreshDispatchBoard()
    if not dispatchMenuOpen then return end
    local board = lib.callback.await('cm-ems:server:dispatchBoard', false)
    if not board then return closeDispatchMenu() end
    dispatchBoardCalls = {}
    for _, call in ipairs(board.calls or {}) do
        enrich(call)
        dispatchBoardCalls[tonumber(call.id)] = call
    end
    SendNUIMessage({ action = 'dispatch:updateMenu', board = board })
end

RegisterNetEvent('cm-ems:client:dispatchCall', function(payload)
    if type(payload) ~= 'table' or type(payload.coords) ~= 'table' then return end
    local x, y, z = tonumber(payload.coords.x), tonumber(payload.coords.y), tonumber(payload.coords.z)
    local callId = tonumber(payload.id)
    if not x or not y or not z or not callId then return end
    enrich(payload)
    latestDispatch = payload
    local panic = tostring(payload.emergencyType or '') == 'ems_panic'
    local fire = tostring(payload.emergencyType or '') == 'fire'
    if panic then PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true) end
    notify((panic and 'EMS PANIC' or ('New ambulance request #%d'):format(callId))
        .. ' · ' .. (payload.location or 'Location unavailable'), panic and 'error' or 'inform')
    SendNUIMessage({ action = 'dispatch:newCall', call = payload })
    removeDispatchBlip(callId)
    local blip = AddBlipForCoord(x, y, z)
    SetBlipSprite(blip, panic and 280 or fire and 436 or 153)
    SetBlipColour(blip, panic and 1 or fire and 47 or 1)
    SetBlipScale(blip, panic and 1.25 or fire and 1.15 or 1.0); SetBlipAsShortRange(blip, false)
    if panic then SetBlipFlashes(blip, true) end
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(panic and 'EMS PANIC' or ('Ambulance request #%d'):format(callId)); EndTextCommandSetBlipName(blip)
    dispatchBlips[callId] = blip
    SetTimeout(math.max(10000, tonumber(payload.blipLifetimeMs) or 300000), function() removeDispatchBlip(callId) end)
    refreshDispatchBoard()
end)

RegisterNetEvent('cm-ems:client:dispatchUpdated', function(action, call)
    if action == 'updated' and type(call) == 'table' and type(call.coords) == 'table' then
        local callId = tonumber(call.id)
        local blip = callId and dispatchBlips[callId]
        local x, y, z = tonumber(call.coords.x), tonumber(call.coords.y), tonumber(call.coords.z)
        if blip and DoesBlipExist(blip) and x and y and z then SetBlipCoords(blip, x, y, z) end
        if latestDispatch and tonumber(latestDispatch.id) == callId then latestDispatch = enrich(call) end
    end
    if action == 'removed' and type(call) == 'table' then
        local callId = tonumber(call.id)
        removeDispatchBlip(callId)
        if activeResponseCallId == callId then
            activeResponseCallId = nil
        end
        if latestDispatch and tonumber(latestDispatch.id) == callId then latestDispatch = nil end
    end
    refreshDispatchBoard()
end)

RegisterNetEvent('cm-ems:client:dispatchAccepted', function(call)
    latestDispatch = enrich(call)
    activeResponseCallId = tonumber(call.id)
    dispatchBoardCalls[activeResponseCallId] = latestDispatch
    setCallWaypoint(call)
    SendNUIMessage({ action = 'dispatch:accepted', callId = call.id })
end)

RegisterNetEvent('cm-ems:client:dispatchAssignmentRemoved', function(callId, message)
    callId = tonumber(callId)
    if activeResponseCallId == callId then
        activeResponseCallId = nil
        local blip = dispatchBlips[callId]
        if blip and DoesBlipExist(blip) then SetBlipRoute(blip, false) end
    end
    if routedCallId == callId then routedCallId = nil; SetWaypointOff() end
    notify(message or 'You were removed from that EMS response.', 'inform')
    refreshDispatchBoard()
end)

RegisterNetEvent('cm-ems:client:dispatchPatientResolved', function(callId, message)
    callId = tonumber(callId)
    removeDispatchBlip(callId)
    if activeResponseCallId == callId then
        activeResponseCallId = nil
    end
    if latestDispatch and tonumber(latestDispatch.id) == callId then latestDispatch = nil end
    notify(message or 'The patient is no longer awaiting EMS response.', 'error')
    refreshDispatchBoard()
end)

RegisterCommand('emsdispatchmenu', function()
    if type(LocalPlayer.state.cmEms) ~= 'table' then
        if type(LocalPlayer.state.cmLegalOrg) == 'table' then TriggerEvent('cm-law:client:openDispatch') end
        return
    end
    if dispatchMenuOpen then return closeDispatchMenu() end
    TriggerEvent('cm-ems:client:closeMenu')
    if not loadDispatchBoard() then return end
    dispatchMenuOpen = true
    SetNuiFocus(true, true)
end, false)
-- F10 is owned by cm-police/client/org_keys.lua so EMS and law dispatch never
-- compete for the same physical key. Keep the command for compatibility.

RegisterCommand('emsdispatchrespond', function()
    if not latestDispatch then return end
    TriggerServerEvent('cm-ems:server:acceptDispatch', latestDispatch.id)
end, false)
RegisterKeyMapping('emsdispatchrespond', 'Respond to latest EMS dispatch call', 'keyboard', tostring(Config.Dispatch.responseKey or 'Y'))

RegisterCommand('emsdispatchbackup', function()
    if not activeResponseCallId then return notify('You are not assigned to an active EMS call.', 'error') end
    CreateThread(function()
        local ok, message = lib.callback.await('cm-ems:server:dispatchBackup', false, activeResponseCallId)
        notify(message or 'Could not request backup.', ok and 'success' or 'error')
    end)
end, false)
RegisterKeyMapping('emsdispatchbackup', 'EMS: Request backup for active call', 'keyboard', tostring(Config.Dispatch.backupKey or 'B'))

RegisterCommand('emspanicbutton', function()
    -- F9 is also used by cm-law's organization dashboard. Civilians and
    -- non-EMS legal members must not receive an EMS permission warning when
    -- the shared key is pressed.
    if type(LocalPlayer.state.cmEms) ~= 'table' then return end
    TriggerServerEvent('cm-ems:server:activatePanic')
end, false)
RegisterKeyMapping('emspanicbutton', 'EMS: Panic button', 'keyboard', tostring(Config.Dispatch.panicKey or 'F9'))

RegisterNUICallback('dispatchClose', function(_, cb) closeDispatchMenu(); cb({ ok = true }) end)
RegisterNUICallback('dispatchRefresh', function(_, cb) refreshDispatchBoard(); cb({ ok = true }) end)
RegisterNUICallback('dispatchRoute', function(data, cb)
    local call = dispatchBoardCalls[tonumber(data and data.callId)]
    if not call then notify('That incident is no longer on your dispatch board.', 'error'); return cb({ ok = false }) end
    setCallWaypoint(call)
    notify(('GPS route set for %s.'):format(call.incidentNumber or ('#' .. tostring(call.id))), 'success')
    cb({ ok = true })
end)
RegisterNUICallback('dispatchTake', function(data, cb)
    local ok, message, call = lib.callback.await('cm-ems:server:takeDispatch', false, tonumber(data and data.callId))
    notify(message or (ok and 'Dispatch accepted.' or 'Could not accept dispatch.'), ok and 'success' or 'error')
    if ok and call then latestDispatch = enrich(call); activeResponseCallId = tonumber(call.id); setCallWaypoint(call) end
    refreshDispatchBoard()
    cb({ ok = ok == true })
end)
RegisterNUICallback('dispatchRemove', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:removeDispatch', false, tonumber(data and data.callId))
    notify(message or (ok and 'Dispatch removed.' or 'Could not remove dispatch.'), ok and 'success' or 'error')
    refreshDispatchBoard()
    cb({ ok = ok == true })
end)
RegisterNUICallback('dispatchGovernmentDoctor', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:sendGovernmentDoctor', false, tonumber(data and data.callId))
    notify(message or (ok and 'Government doctor dispatched.' or 'Could not dispatch government doctor.'), ok and 'success' or 'error')
    refreshDispatchBoard()
    cb({ ok = ok == true })
end)
RegisterNUICallback('dispatchReject', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:dispatchReject', false, tonumber(data and data.callId))
    notify(message, ok and 'success' or 'error'); refreshDispatchBoard(); cb({ ok = ok == true })
end)
RegisterNUICallback('dispatchBackup', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:dispatchBackup', false, tonumber(data and data.callId))
    notify(message, ok and 'success' or 'error'); refreshDispatchBoard(); cb({ ok = ok == true })
end)
RegisterNUICallback('dispatchAcknowledgePriority', function(data, cb)
    local ok, message, call = lib.callback.await('cm-ems:server:dispatchAcknowledgePriority', false, tonumber(data and data.callId))
    notify(message, ok and 'success' or 'error')
    if ok and call then
        latestDispatch = enrich(call)
        activeResponseCallId = tonumber(call.id)
        setCallWaypoint(call)
    end
    refreshDispatchBoard(); cb({ ok = ok == true })
end)
RegisterNUICallback('dispatchClearPriority', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:dispatchClearPriority', false, tonumber(data and data.callId))
    notify(message, ok and 'success' or 'error')
    if ok and activeResponseCallId == tonumber(data and data.callId) then activeResponseCallId = nil end
    if ok and routedCallId == tonumber(data and data.callId) then routedCallId = nil; SetWaypointOff() end
    refreshDispatchBoard(); cb({ ok = ok == true })
end)
RegisterNUICallback('dispatchStatus', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:dispatchStatus', false, tonumber(data and data.callId), data and data.status)
    notify(message, ok and 'success' or 'error')
    if ok and data.status == 'clear' and activeResponseCallId == tonumber(data.callId) then activeResponseCallId = nil end
    if ok and data.status == 'clear' and routedCallId == tonumber(data.callId) then routedCallId = nil; SetWaypointOff() end
    refreshDispatchBoard(); cb({ ok = ok == true })
end)
RegisterNUICallback('dispatchNote', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:addDispatchNote', false,
        tonumber(data and data.callId), data and data.note)
    notify(message, ok and 'success' or 'error')
    refreshDispatchBoard(); cb({ ok = ok == true })
end)
RegisterNUICallback('dispatchAssignUnit', function(data, cb)
    local ok, message = lib.callback.await('cm-ems:server:assignDispatchUnit', false,
        tonumber(data and data.callId), data and data.characterId, data and data.replace == true)
    notify(message, ok and 'success' or 'error')
    refreshDispatchBoard(); cb({ ok = ok == true })
end)

AddStateBagChangeHandler('cmEms', nil, function(bagName, _, value)
    if bagName ~= ('player:%s'):format(GetPlayerServerId(PlayerId())) then return end
    if type(value) ~= 'table' or value.onDuty ~= true or value.permissions == nil or value.permissions['ems.receive_dispatch'] ~= true then
        latestDispatch = nil
        SetWaypointOff()
        routedCallId = nil
        activeResponseCallId = nil
        dispatchBoardCalls = {}
        closeDispatchMenu()
        SendNUIMessage({ action = 'dispatch:clear' })
        local ids = {}
        for callId in pairs(dispatchBlips) do ids[#ids + 1] = callId end
        for _, callId in ipairs(ids) do removeDispatchBlip(callId) end
    end
end)
