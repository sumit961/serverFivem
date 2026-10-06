local active = false
local uiOpen = false
local teleporting = false
local activeSessionId = nil
local cooldownUntil = 0

local function dprint(message)
    if Config.Debug then
        print(('[CM-LIFT] %s'):format(tostring(message)))
    end
end

local function notify(message, notifyType)
    local ok = pcall(function()
        exports['cm-core']:Notify(message, notifyType or 'info', 4000)
    end)
    if not ok then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(tostring(message or ''))
        EndTextCommandThefeedPostTicker(false, false)
    end
end

local function hideUi(reason)
    local wasOpen = uiOpen
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    uiOpen = false
    SendNUIMessage({ action = 'forceClose', reason = reason })
    if wasOpen then dprint(('menu closed reason=%s'):format(tostring(reason or 'unknown'))) end
end

local function clearSession(cancelServer, reason)
    local sessionId = activeSessionId
    hideUi(reason)
    active = false
    teleporting = false
    activeSessionId = nil
    if cancelServer and sessionId then
        TriggerServerEvent('cm-lift:server:cancel', sessionId)
    end
end

local function menuDestinationCount(presentation)
    if type(presentation) ~= 'table' or type(presentation.floors) ~= 'table' then return 0 end

    local seen = {}
    local count = 0
    for _, floor in ipairs(presentation.floors) do
        if type(floor) == 'table' and type(floor.id) == 'string' and floor.id ~= '' and not seen[floor.id]
            and floor.current ~= true and floor.locked ~= true and floor.disabled ~= true then
            seen[floor.id] = true
            count = count + 1
        end
    end
    return count
end

local function isInVehicle()
    local ped = PlayerPedId()
    return ped ~= 0 and GetVehiclePedIsIn(ped, false) ~= 0
end

local function validDestination(destination)
    if type(destination) ~= 'table' then return false end
    local x, y, z, heading = tonumber(destination.x), tonumber(destination.y), tonumber(destination.z), tonumber(destination.heading)
    if not x or not y or not z or not heading then return false end
    if x ~= x or y ~= y or z ~= z or heading ~= heading then return false end
    if x < -10000 or x > 10000 or y < -10000 or y > 10000 or z < -1000 or z > 5000 then return false end
    return true
end

local function waitFor(predicate, timeoutMs)
    local startedAt = GetGameTimer()
    while GetGameTimer() - startedAt <= timeoutMs do
        if predicate() then return true end
        Wait(0)
    end
    return false
end

local function restoreAfterTeleport(success, originalCoords, originalHeading)
    local ped = PlayerPedId()
    ClearFocus()

    if not success and originalCoords and DoesEntityExist(ped) then
        SetEntityCoordsNoOffset(ped, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false)
        SetEntityHeading(ped, originalHeading)
    end

    FreezeEntityPosition(ped, false)
    SetPlayerControl(PlayerId(), true, 0)
    DoScreenFadeIn(Config.FadeInDurationMs)

    active = false
    teleporting = false
    activeSessionId = nil
    if success then cooldownUntil = GetGameTimer() + Config.TeleportCooldownMs end

    if not success then notify('ELEVATOR UNAVAILABLE', 'error') end
end

local function teleport(destination)
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) or not validDestination(destination) then
        restoreAfterTeleport(false)
        return
    end

    local originalCoords = GetEntityCoords(ped)
    local originalHeading = GetEntityHeading(ped)
    local fadedOut = false

    FreezeEntityPosition(ped, true)
    SetPlayerControl(PlayerId(), false, 0)
    DoScreenFadeOut(Config.FadeOutDurationMs)
    fadedOut = waitFor(IsScreenFadedOut, Config.FadeTimeoutMs)
    if not fadedOut then
        restoreAfterTeleport(false, originalCoords, originalHeading)
        return
    end

    SetFocusPosAndVel(destination.x, destination.y, destination.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(destination.x, destination.y, destination.z)
    SetEntityCoordsNoOffset(ped, destination.x, destination.y, destination.z, false, false, false)
    SetEntityHeading(ped, destination.heading)

    local collisionLoaded = waitFor(function()
        RequestCollisionAtCoord(destination.x, destination.y, destination.z)
        return HasCollisionLoadedAroundEntity(ped)
    end, Config.CollisionTimeoutMs)

    if not collisionLoaded then
        restoreAfterTeleport(false, originalCoords, originalHeading)
        return
    end

    restoreAfterTeleport(true)
end

local function openLift(presentation)
    if type(presentation) ~= 'table' or type(presentation.sessionId) ~= 'string' then return false end
    if active or teleporting then return false end
    if GetGameTimer() < cooldownUntil then return false end

    if isInVehicle() then
        TriggerServerEvent('cm-lift:server:cancel', presentation.sessionId)
        notify('EXIT YOUR VEHICLE TO USE THE ELEVATOR', 'error')
        return false
    end

    if presentation.direct ~= true and menuDestinationCount(presentation) < 2 then
        dprint('rejected empty floor payload')
        TriggerServerEvent('cm-lift:server:cancel', presentation.sessionId)
        hideUi('invalid_payload')
        notify('ELEVATOR UNAVAILABLE', 'error')
        return false
    end

    active = true
    activeSessionId = presentation.sessionId
    exports['cm-ui']:HideInteract()

    if presentation.direct == true then
        dprint(('direct destination, skipping menu session=%s'):format(presentation.sessionId))
        TriggerServerEvent('cm-lift:server:selectFloor', presentation.sessionId, presentation.directFloorId)
        return true
    end

    uiOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    dprint(('menu opened floors=%s session=%s'):format(menuDestinationCount(presentation), presentation.sessionId))
    SendNUIMessage({ action = 'openLift', payload = presentation })
    return true
end

exports('UseLift', function(presentation)
    -- This helper accepts only a server-issued presentation/session. It never
    -- accepts coordinates; owners should normally call server OpenLift.
    return openLift(presentation)
end)

RegisterNetEvent('cm-lift:client:open', function(presentation)
    openLift(presentation)
end)

RegisterNetEvent('cm-lift:client:beginDirect', function(payload)
    if type(payload) ~= 'table' or type(payload.sessionId) ~= 'string' or active or teleporting then return end
    if not validDestination(payload.destination) then
        dprint('direct session rejected reason=invalid_destination')
        notify('ELEVATOR UNAVAILABLE', 'error')
        return
    end

    active = true
    activeSessionId = payload.sessionId
    exports['cm-ui']:HideInteract()
    hideUi('direct')
    teleporting = true
    dprint(('direct session accepted session=%s'):format(payload.sessionId))
    CreateThread(function()
        teleport(payload.destination)
    end)
end)

RegisterNetEvent('cm-lift:client:beginTeleport', function(payload)
    if type(payload) ~= 'table' or payload.sessionId ~= activeSessionId or teleporting then return end
    if not validDestination(payload.destination) then
        clearSession(false, 'invalid_destination')
        notify('ELEVATOR UNAVAILABLE', 'error')
        return
    end

    hideUi()
    teleporting = true
    CreateThread(function()
        teleport(payload.destination)
    end)
end)

RegisterNetEvent('cm-lift:client:rejected', function(reason)
    if not active then return end

    local retryable = uiOpen and (reason == 'invalid_floor' or reason == 'locked_floor' or reason == 'current_floor' or reason == 'rate_limited')
    if retryable then
        SendNUIMessage({ action = 'selectionRejected' })
    else
        clearSession(false, reason or 'rejected')
    end

    if reason == 'in_vehicle' then
        notify('EXIT YOUR VEHICLE TO USE THE ELEVATOR', 'error')
    elseif reason == 'locked_floor' then
        notify('THAT FLOOR IS LOCKED', 'info')
    elseif reason == 'current_floor' then
        notify('YOU ARE ALREADY ON THIS FLOOR', 'info')
    else
        notify('ELEVATOR UNAVAILABLE', 'error')
    end
end)

RegisterNetEvent('cm-lift:client:sessionExpired', function(sessionId)
    if type(sessionId) ~= 'string' or sessionId ~= activeSessionId or teleporting then return end
    dprint('menu closed reason=session_expired')
    clearSession(false, 'session_expired')
end)

RegisterNUICallback('selectFloor', function(data, cb)
    if not active or teleporting or type(data) ~= 'table' then cb('ignored') return end
    local sessionId = data.sessionId
    local floorId = data.floorId
    if type(sessionId) ~= 'string' or sessionId ~= activeSessionId or type(floorId) ~= 'string' then
        cb('rejected')
        return
    end

    TriggerServerEvent('cm-lift:server:selectFloor', sessionId, floorId)
    cb('ok')
end)

RegisterNUICallback('closeLift', function(_, cb)
    if active and not teleporting then
        clearSession(true, 'escape')
    else
        hideUi('nui_close')
    end
    cb('ok')
end)

RegisterNUICallback('uiReady', function(_, cb)
    cb('ok')
end)

RegisterCommand('testlift', function(_, args)
    if not Config.Debug then return end
    TriggerServerEvent('cm-lift:server:runTest', args and args[1] or 'multi')
end, false)

local function resetForLifecycle(reason, cancelServer)
    if teleporting and reason ~= 'resource_start' then return end
    clearSession(cancelServer == true, reason)
end

RegisterNetEvent('cm-spawn:client:spawned', function()
    resetForLifecycle('spawn_complete', false)
end)

RegisterNetEvent('cm-spawn:client:spawnComplete', function()
    resetForLifecycle('spawn_complete', false)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    resetForLifecycle('resource_start', true)
    SendNUIMessage({ action = 'forceClose', reason = 'resource_start' })
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    hideUi('resource_stop')
    ClearFocus()
    FreezeEntityPosition(PlayerPedId(), false)
    SetPlayerControl(PlayerId(), true, 0)
    DoScreenFadeIn(Config.FadeInDurationMs)
    active = false
    teleporting = false
    activeSessionId = nil
end)
