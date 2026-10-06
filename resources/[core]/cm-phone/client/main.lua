-- cm-phone client: NUI host, key/command binding, notifications, phone prop. The client never decides
-- identity, ownership, price or call state: every NUI request is forwarded to a whitelisted server callback.
local Config = CMPhone.Config

local isOpen = false
local opening = false
local contactNames = {}       -- number -> display name (cache for notifications only)
local callState = nil         -- last call payload from the server
local propEntity = nil
local animDict = 'cellphone@'
local animName = 'cellphone_text_read_base'
local animActive = false

-- NUI endpoint -> server callback. Anything else is rejected.
local ENDPOINTS = {
    bootstrap = true, contactSave = true, contactDelete = true, block = true, unblock = true,
    conversations = true, openConversation = true, markRead = true, send = true, sendLocation = true,
    groupCreate = true, groupAdd = true, groupRemove = true, groupLeave = true,
    dial = true, answer = true, decline = true, hangup = true, calls = true,
    adverts = true, advertPost = true, emergency = true,
    services = true, serviceStatus = true, serviceRequest = true, serviceCancel = true,
}

local function notify(message, kind)
    if GetResourceState('cm-hud') == 'started' then
        TriggerEvent('cm-hud:client:notify', message, kind or 'info')
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

local function nameFor(number)
    return contactNames[number] or number or 'Unknown'
end

local function cacheContacts(list)
    if type(list) ~= 'table' then return end
    contactNames = {}
    for _, c in ipairs(list) do
        if c.number and c.name then contactNames[c.number] = c.name end
    end
end

-- Phone prop / animation (cosmetic; cleaned on every close path) -------------
local function stopProp()
    if animActive then
        local ped = PlayerPedId()
        if IsEntityPlayingAnim(ped, animDict, animName, 3) then StopAnimTask(ped, animDict, animName, 2.0) end
        animActive = false
    end
    if propEntity and DoesEntityExist(propEntity) then
        DetachEntity(propEntity, true, true)
        DeleteEntity(propEntity)
    end
    propEntity = nil
end

local function startProp()
    if not Config.Prop.enabled then return end
    CreateThread(function()
        local ped = PlayerPedId()
        local model = joaat(Config.Prop.model)
        RequestModel(model)
        RequestAnimDict(animDict)
        local waited = 0
        while (not HasModelLoaded(model) or not HasAnimDictLoaded(animDict)) and waited < 2000 do
            Wait(50)
            waited = waited + 50
        end
        if not isOpen then
            SetModelAsNoLongerNeeded(model)
            return
        end
        if HasAnimDictLoaded(animDict) and not IsPedInAnyVehicle(ped, false) then
            TaskPlayAnim(ped, animDict, animName, 3.0, 3.0, -1, 49, 0.0, false, false, false)
            animActive = true
        end
        if HasModelLoaded(model) then
            local coords = GetEntityCoords(ped)
            propEntity = CreateObject(model, coords.x, coords.y, coords.z + 0.2, false, false, false)
            local p, r = Config.Prop.offset, Config.Prop.rotation
            AttachEntityToEntity(propEntity, ped, GetPedBoneIndex(ped, Config.Prop.bone), p.x, p.y, p.z, r.x, r.y, r.z, true, true, false, true, 1, true)
            SetModelAsNoLongerNeeded(model)
        end
    end)
end

-- Open / close ---------------------------------------------------------------
local function closePhone(silent)
    if not isOpen and not opening then
        SetNuiFocus(false, false)
        return
    end
    isOpen = false
    opening = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    stopProp()
    if not silent then TriggerEvent('cm-phone:client:closed') end
end

local function openPhone()
    if isOpen or opening then return end
    if IsEntityDead(PlayerPedId()) then return end
    opening = true
    local result = lib.callback.await('cm-phone:bootstrap', false)
    if not opening then return end -- closed/force-closed while loading
    if type(result) ~= 'table' or not result.ok then
        opening = false
        notify('Your phone is not available right now.', 'error')
        return
    end
    cacheContacts(result.data.contacts)
    callState = result.data.call
    isOpen = true
    opening = false
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = result.data })
    startProp()
end

RegisterCommand(Config.OpenCommand, function()
    if isOpen then closePhone() else openPhone() end
end, false)
RegisterKeyMapping(Config.OpenCommand, 'Open phone', 'keyboard', Config.OpenKey)

RegisterNUICallback('close', function(_, cb)
    closePhone()
    cb({ ok = true })
end)

RegisterNUICallback('api', function(data, cb)
    data = type(data) == 'table' and data or {}
    local endpoint = tostring(data.endpoint or '')
    if not ENDPOINTS[endpoint] then
        cb({ ok = false, error = 'invalid_request' })
        return
    end
    local payload = data.payload
    if endpoint == 'serviceRequest' and type(payload) == 'table' and type(payload.fields) == 'table' then
        -- Waypoint destinations are read here from the player's own map marker (client-observed, shape and range
        -- re-validated by the server). A missing marker is reported without contacting the server.
        for key, value in pairs(payload.fields) do
            if value == '@waypoint' then
                local blip = GetFirstBlipInfoId(8)
                if not blip or not DoesBlipExist(blip) then
                    cb({ ok = false, error = 'no_waypoint' })
                    return
                end
                local c = GetBlipInfoIdCoord(blip)
                payload.fields[key] = { x = c.x, y = c.y }
            end
        end
    end
    local result = lib.callback.await('cm-phone:' .. endpoint, false, payload)
    if type(result) ~= 'table' then result = { ok = false, error = 'internal_error' } end
    if result.ok and type(result.data) == 'table' and result.data.contacts then cacheContacts(result.data.contacts) end
    cb(result)
end)

RegisterNUICallback('setGps', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if not x or not y or x ~= x or y ~= y or math.abs(x) > 10000.0 or math.abs(y) > 10000.0 then
        cb({ ok = false })
        return
    end
    SetNewWaypoint(x + 0.0, y + 0.0)
    notify('GPS set to the shared location.', 'success')
    cb({ ok = true })
end)

-- Live server events ----------------------------------------------------------
RegisterNetEvent('cm-phone:client:message', function(payload)
    if type(payload) ~= 'table' then return end
    if isOpen then
        SendNUIMessage({ action = 'message', data = payload })
        return
    end
    -- Closed phone: a short toast, never the message body.
    local who = payload.group or nameFor(payload.from)
    notify(('New message from %s'):format(tostring(who)), 'info')
end)

-- Service request status pushed by a source owner (already reduced to the public shape by the server).
RegisterNetEvent('cm-phone:client:serviceStatus', function(payload)
    if type(payload) ~= 'table' or type(payload.service) ~= 'string' or type(payload.status) ~= 'table' then return end
    if isOpen then
        SendNUIMessage({ action = 'serviceStatus', data = payload })
    elseif type(payload.message) == 'string' then
        notify(payload.message, 'info')
    end
end)

RegisterNetEvent('cm-phone:client:notify', function(payload)
    if type(payload) ~= 'table' or type(payload.message) ~= 'string' then return end
    if isOpen then SendNUIMessage({ action = 'toast', data = payload }) else notify(payload.message, 'info') end
end)

RegisterNetEvent('cm-phone:client:call', function(payload)
    if type(payload) ~= 'table' then return end
    callState = payload.state ~= 'ended' and payload or nil
    if isOpen then SendNUIMessage({ action = 'call', data = payload }) end
    if payload.state == 'incoming' and not isOpen then
        notify(('Incoming call from %s - press %s to open the phone'):format(nameFor(payload.number), Config.OpenKey), 'info')
    elseif payload.state == 'ended' and not isOpen and payload.reason == 'timeout' and payload.role == 'callee' then
        notify(('Missed call from %s'):format(nameFor(payload.number)), 'warning')
    end
end)

-- Ring loop: audible/visible reminder only while an incoming call is ringing.
CreateThread(function()
    while true do
        if callState and callState.state == 'incoming' then
            PlaySoundFrontend(-1, 'Remote_Ring', 'Phone_SoundSet_Default', true)
            if not isOpen then
                notify(('Incoming call from %s'):format(nameFor(callState.number)), 'info')
            end
            Wait(4500)
        else
            Wait(500)
        end
    end
end)

-- Quick call commands for when the phone is closed.
RegisterCommand('phoneanswer', function()
    lib.callback.await('cm-phone:answer', false)
end, false)
RegisterCommand('phonehangup', function()
    lib.callback.await('cm-phone:hangup', false)
end, false)
RegisterCommand('phonedecline', function()
    lib.callback.await('cm-phone:decline', false)
end, false)

-- Force-close paths ------------------------------------------------------------
CreateThread(function()
    while true do
        if isOpen then
            if IsEntityDead(PlayerPedId()) then closePhone() end
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

RegisterNetEvent('cm-playerdata:client:characterUnloaded', function() callState = nil closePhone(true) end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    stopProp()
end)
