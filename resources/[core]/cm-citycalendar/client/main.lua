local worldEvents = {}
local dashboardOpen = false
local promptVisible = false
local nearestId

local function notify(message, kind)
    if type(lib) == 'table' and type(lib.notify) == 'function' then
        lib.notify({
            title = 'City Calendar',
            description = tostring(message or 'Calendar action unavailable.'),
            type = kind or 'inform',
        })
    end
end

local function hidePrompt()
    if not promptVisible then return end
    promptVisible = false
    pcall(function() exports['cm-ui']:HideInteract('cm-citycalendar') end)
end

local function closeDashboard()
    dashboardOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    hidePrompt()
end

local function refreshWorldEvents()
    if dashboardOpen then closeDashboard() end
    local ok, response = pcall(function()
        return lib.callback.await('cm-citycalendar:server:getWorldEvents', false)
    end)
    worldEvents = ok and type(response) == 'table' and response or {}
    nearestId = nil
    hidePrompt()
end

local function openDashboard()
    if dashboardOpen then return end
    local ok, response = pcall(function()
        return lib.callback.await('cm-citycalendar:server:getDashboard', false)
    end)
    if not ok or type(response) ~= 'table' or response.ok ~= true then
        return notify((response and response.reason or 'calendar_unavailable'):gsub('_', ' '), 'error')
    end
    dashboardOpen = true
    hidePrompt()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = response })
end

local function checkIn(id)
    if not id or dashboardOpen then return end
    hidePrompt()
    local ok, response = pcall(function()
        return lib.callback.await('cm-citycalendar:server:checkIn', false, { eventId = id })
    end)
    if not ok or type(response) ~= 'table' or response.ok ~= true then
        return notify((response and response.reason or 'check_in_failed'):gsub('_', ' '), 'error')
    end
    local label = response.alreadyCheckedIn and 'Already checked in.' or 'Attendance recorded.'
    notify(label, 'success')
end

RegisterCommand('events', openDashboard, false)
RegisterCommand('citycalendar', openDashboard, false)
RegisterNetEvent('cm-citycalendar:client:openDashboard', openDashboard)
RegisterNetEvent('cm-citycalendar:client:refreshWorldEvents', refreshWorldEvents)
RegisterNetEvent('cm-citycalendar:client:clear', function()
    worldEvents = {}
    nearestId = nil
    closeDashboard()
    hidePrompt()
end)

RegisterNUICallback('close', function(_, cb)
    closeDashboard()
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    local ok, response = pcall(function()
        return lib.callback.await('cm-citycalendar:server:getDashboard', false)
    end)
    if ok and response and response.ok then SendNUIMessage({ action = 'data', data = response }) end
    cb(ok and response or { ok = false, reason = 'request_failed' })
end)

RegisterNUICallback('eventAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    local callback = data.action == 'rsvp' and 'cm-citycalendar:server:rsvp'
        or data.action == 'cancel' and 'cm-citycalendar:server:cancelRsvp'
    if not callback then cb({ ok = false, reason = 'invalid_action' }); return end
    local ok, response = pcall(function()
        return lib.callback.await(callback, false, { eventId = data.eventId })
    end)
    response = ok and response or { ok = false, reason = 'request_failed' }
    if response.ok then
        local freshOk, fresh = pcall(function()
            return lib.callback.await('cm-citycalendar:server:getDashboard', false)
        end)
        if freshOk and fresh and fresh.ok then SendNUIMessage({ action = 'data', data = fresh }) end
    else
        notify((response.reason or 'calendar_action_failed'):gsub('_', ' '), 'error')
    end
    cb(response)
end)

AddEventHandler('cm-playerdata:client:characterLoaded', refreshWorldEvents)
AddEventHandler('cm-playerdata:client:loaded', refreshWorldEvents)
AddEventHandler('cm-playerdata:client:characterUnloaded', function()
    TriggerEvent('cm-citycalendar:client:clear')
end)

CreateThread(function()
    Wait(750)
    refreshWorldEvents()
    while true do
        Wait(Config.Calendar.clientRefreshMs)
        if not dashboardOpen then refreshWorldEvents() end
    end
end)

CreateThread(function()
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local canInteract = ped and ped ~= 0 and not IsEntityDead(ped) and not dashboardOpen
        local coords = canInteract and GetEntityCoords(ped) or nil
        local closest, closestDistance

        if coords then
            for _, event in ipairs(worldEvents) do
                local distance = #(coords - vector3(event.x, event.y, event.z))
                if distance <= (tonumber(event.radius) or 0.0) and (not closestDistance or distance < closestDistance) then
                    closest, closestDistance = event, distance
                end
                if distance <= Config.Calendar.markerDistance then
                    wait = 0
                    local marker = Config.Calendar.marker
                    DrawMarker(marker.type, event.x, event.y, event.z - 0.9, 0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0, marker.scale.x, marker.scale.y, marker.scale.z,
                        marker.colour.r, marker.colour.g, marker.colour.b, marker.colour.a,
                        marker.bobUpAndDown, marker.faceCamera, 2, marker.rotate, nil, nil, false)
                end
            end
        end

        if closest and closest.id then
            if nearestId ~= closest.id then
                nearestId = closest.id
                promptVisible = true
                pcall(function()
                    exports['cm-ui']:ShowInteract({
                        owner = 'cm-citycalendar',
                        key = 'E',
                        label = closest.displayLabel or 'CHECK IN',
                        name = closest.title,
                        role = closest.category,
                        priority = 15,
                    })
                end)
            end
            if IsControlJustReleased(0, 38) then checkIn(closest.id) end
        else
            nearestId = nil
            hidePrompt()
        end
        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        if dashboardOpen and (IsEntityDead(PlayerPedId()) or IsPauseMenuActive()) then closeDashboard() end
        Wait(dashboardOpen and 500 or 1500)
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        closeDashboard()
        hidePrompt()
    end
end)
