local landmarks = {}
local dashboardOpen = false
local promptVisible = false
local nearestId

local function notify(message, kind)
    if type(lib) == 'table' and type(lib.notify) == 'function' then
        lib.notify({
            title = 'City Discovery',
            description = tostring(message or 'Discovery unavailable.'),
            type = kind or 'inform',
        })
    end
end

local function hidePrompt()
    if not promptVisible then return end
    promptVisible = false
    pcall(function() exports['cm-ui']:HideInteract('cm-discovery') end)
end

local function closeDashboard()
    if not dashboardOpen then return end
    dashboardOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    hidePrompt()
end

local function refreshLandmarks()
    if dashboardOpen then closeDashboard() end
    local ok, response = pcall(function()
        return lib.callback.await('cm-discovery:server:getWorldLandmarks', false)
    end)
    landmarks = ok and type(response) == 'table' and response or {}
    nearestId = nil
    hidePrompt()
end

local function openDashboard()
    if dashboardOpen then return end
    local ok, response = pcall(function()
        return lib.callback.await('cm-discovery:server:getChecklist', false)
    end)
    if not ok or type(response) ~= 'table' or response.ok ~= true then
        return notify((response and response.reason or 'discovery_unavailable'):gsub('_', ' '), 'error')
    end
    dashboardOpen = true
    hidePrompt()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = response })
end

local function discover(id)
    if not id or dashboardOpen then return end
    hidePrompt()
    local ok, response = pcall(function()
        return lib.callback.await('cm-discovery:server:discover', false, { landmarkId = id })
    end)
    if not ok or type(response) ~= 'table' or response.ok ~= true then
        return notify((response and response.reason or 'discovery_unavailable'):gsub('_', ' '), 'error')
    end
    local name = response.landmark and response.landmark.name or 'Landmark'
    if response.alreadyDiscovered then
        notify(('Already discovered: %s'):format(name), 'inform')
    else
        notify(('Discovered: %s'):format(name), 'success')
    end
end

RegisterCommand('discoveries', openDashboard, false)
RegisterNetEvent('cm-discovery:client:openDashboard', openDashboard)
RegisterNetEvent('cm-discovery:client:refreshLandmarks', refreshLandmarks)
RegisterNetEvent('cm-discovery:client:clear', function()
    landmarks = {}
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
        return lib.callback.await('cm-discovery:server:getChecklist', false)
    end)
    if ok and response and response.ok then SendNUIMessage({ action = 'data', data = response }) end
    cb(ok and response or { ok = false, reason = 'request_failed' })
end)

AddEventHandler('cm-playerdata:client:characterLoaded', refreshLandmarks)
AddEventHandler('cm-playerdata:client:loaded', refreshLandmarks)
AddEventHandler('cm-playerdata:client:characterUnloaded', function()
    TriggerEvent('cm-discovery:client:clear')
end)

CreateThread(function()
    Wait(750)
    refreshLandmarks()
end)

CreateThread(function()
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local canInteract = ped and ped ~= 0 and not IsEntityDead(ped) and not dashboardOpen
        local coords = canInteract and GetEntityCoords(ped) or nil
        local closest, closestDistance

        if coords then
            for _, landmark in ipairs(landmarks) do
                local distance = #(coords - vector3(landmark.x, landmark.y, landmark.z))
                if distance <= (tonumber(landmark.radius) or 0.0) and (not closestDistance or distance < closestDistance) then
                    closest, closestDistance = landmark, distance
                end
                if distance <= Config.Discovery.markerDistance then
                    wait = 0
                    local marker = Config.Discovery.marker
                    DrawMarker(marker.type, landmark.x, landmark.y, landmark.z - 0.9, 0.0, 0.0, 0.0,
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
                        owner = 'cm-discovery',
                        key = 'E',
                        label = closest.displayLabel or 'DISCOVER LANDMARK',
                        name = closest.name,
                        role = closest.category,
                        priority = 15,
                    })
                end)
            end
            if IsControlJustReleased(0, 38) then discover(closest.id) end
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
