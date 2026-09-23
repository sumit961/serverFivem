local Config = CMFarming.Config
CMFarming.Client = CMFarming.Client or {}

local menuOpen = false

local function dbg(...)
    if Config.Debug then print('[CM-FARMING]', ...) end
end

local function notify(message, kind)
    if GetResourceState('cm-hud') == 'started' then
        TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'info')
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message or ''))
    EndTextCommandThefeedPostTicker(false, false)
end

local function showInteract(label, name)
    if GetResourceState('cm-ui') ~= 'started' then return end
    exports['cm-ui']:ShowInteract({ key = Config.interactKeyLabel or 'E', label = label, name = name, role = 'CM FARMING' })
end

local function hideInteract()
    if GetResourceState('cm-ui') ~= 'started' then return end
    exports['cm-ui']:HideInteract()
end

RegisterNetEvent('cm-farming:client:notify', function(message, kind) notify(message, kind) end)
RegisterNetEvent('cm-farming:client:status', function() end) -- reserved for a future HUD widget

TriggerServerEvent('cm-farming:server:requestStatus')
TriggerServerEvent('cm-farming:server:requestFields')

-- ---------------------------------------------------------------------------
-- Blips
-- ---------------------------------------------------------------------------

local function createBlip(coords, def)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, def.sprite or 522)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, def.scale or 0.8)
    SetBlipColour(blip, def.color or 2)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(def.name or 'Farming')
    EndTextCommandSetBlipName(blip)
end

CreateThread(function()
    for _, field in ipairs(Config.Fields) do
        if field.blip and field.blip.enabled then createBlip(field.center, field.blip) end
    end
    if Config.Market.blip and Config.Market.blip.enabled then createBlip(Config.Market.coords, Config.Market.blip) end
end)

-- ---------------------------------------------------------------------------
-- Market NPC
-- ---------------------------------------------------------------------------

local marketPed = nil

CreateThread(function()
    local model = joaat(Config.Market.model)
    RequestModel(model)
    local attempts = 0
    while not HasModelLoaded(model) and attempts < 200 do Wait(10); attempts = attempts + 1 end
    if not HasModelLoaded(model) then return end

    local coords = Config.Market.coords
    marketPed = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w, false, true)
    SetEntityInvincible(marketPed, true)
    SetBlockingOfNonTemporaryEvents(marketPed, true)
    FreezeEntityPosition(marketPed, true)
    SetModelAsNoLongerNeeded(model)
end)

CreateThread(function()
    while true do
        local wait = 800
        local ped = PlayerPedId()
        if not menuOpen and DoesEntityExist(marketPed) then
            local coords = GetEntityCoords(ped)
            local marketCoords = Config.Market.coords
            local distance = #(coords - vector3(marketCoords.x, marketCoords.y, marketCoords.z))
            if not IsPedInAnyVehicle(ped, false) and distance <= (Config.npcInteractDistance or 2.2) then
                wait = 0
                showInteract('Open the farmers market', 'Farmer')
                if IsControlJustPressed(0, Config.interactKey) then
                    TriggerServerEvent('cm-farming:server:requestMenu')
                end
            end
        end
        Wait(wait)
    end
end)

-- ---------------------------------------------------------------------------
-- Field state + world props (client-rendered, server-authoritative --
-- points and their state come entirely from the server, this only mirrors
-- them visually with distance-culled local objects).
-- ---------------------------------------------------------------------------

local fieldsByKey = {}
for _, field in ipairs(Config.Fields) do fieldsByKey[field.key] = field end

local fieldState = {}    -- [fieldKey][index] = { x, y, state, crop, groundZ }
local pointEntities = {} -- [fieldKey][index] = entity handle

for _, field in ipairs(Config.Fields) do
    fieldState[field.key] = {}
    pointEntities[field.key] = {}
end

local function getGroundZ(x, y, fallbackZ)
    local found, groundZ = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, (fallbackZ or 0.0) + 15.0, false)
    if found then return groundZ end
    return fallbackZ or 0.0
end

local function getPointZ(fieldKey, point)
    if point.groundZ then return point.groundZ end
    local z = getGroundZ(point.x, point.y, fieldsByKey[fieldKey].center.z)
    point.groundZ = z
    return z
end

local modelCache = {}
local function ensureModel(modelName)
    local hash = type(modelName) == 'number' and modelName or joaat(modelName)
    if modelCache[hash] then return hash end
    RequestModel(hash)
    local attempts = 0
    while not HasModelLoaded(hash) and attempts < 200 do Wait(10); attempts = attempts + 1 end
    if HasModelLoaded(hash) then modelCache[hash] = true end
    return hash
end

local function modelForPoint(point)
    if point.state == 'grown' and point.crop then
        local crop = Config.Crops[point.crop]
        if crop then return crop.growModel end
        return nil
    end
    if point.state == 'planted' or point.state == 'watered' then
        return Config.SeedlingModel
    end
    return nil
end

local function despawnPointEntity(fieldKey, index)
    local entity = pointEntities[fieldKey][index]
    if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
    pointEntities[fieldKey][index] = nil
end

local function refreshPointEntity(fieldKey, index)
    local point = fieldState[fieldKey][index]
    if not point then return end

    local wantedModel = modelForPoint(point)
    despawnPointEntity(fieldKey, index)
    if not wantedModel then return end

    local hash = ensureModel(wantedModel)
    if not HasModelLoaded(hash) then return end

    local z = getPointZ(fieldKey, point)
    local entity = CreateObject(hash, point.x, point.y, z, false, false, false)
    if not DoesEntityExist(entity) then return end
    PlaceObjectOnGroundProperly(entity)
    FreezeEntityPosition(entity, true)
    SetEntityCollision(entity, false, false)
    pointEntities[fieldKey][index] = entity
end

RegisterNetEvent('cm-farming:client:fieldsInit', function(snapshot)
    for fieldKey, points in pairs(snapshot) do
        fieldState[fieldKey] = fieldState[fieldKey] or {}
        for index, point in pairs(points) do
            fieldState[fieldKey][index] = point
        end
    end
end)

RegisterNetEvent('cm-farming:client:pointUpdated', function(fieldKey, index, state, crop)
    fieldState[fieldKey] = fieldState[fieldKey] or {}
    local point = fieldState[fieldKey][index]
    if not point then return end
    point.state = state
    point.crop = crop

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    if #(coords - vector3(point.x, point.y, coords.z)) <= 55.0 then
        refreshPointEntity(fieldKey, index)
    else
        despawnPointEntity(fieldKey, index)
    end
end)

-- LOD: only nearby plots ever carry a real prop, so prop count stays bounded
-- regardless of how many fields/points are configured.
CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        for fieldKey, field in pairs(fieldsByKey) do
            if #(coords - field.center) <= (field.radius + 60.0) then
                for index, point in pairs(fieldState[fieldKey] or {}) do
                    local dist = #(coords - vector3(point.x, point.y, coords.z))
                    local hasEntity = pointEntities[fieldKey][index] ~= nil and DoesEntityExist(pointEntities[fieldKey][index])
                    if dist <= 45.0 and not hasEntity and modelForPoint(point) then
                        refreshPointEntity(fieldKey, index)
                    elseif dist > 55.0 and hasEntity then
                        despawnPointEntity(fieldKey, index)
                    end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Plot markers (drawn only while near a field -- cheap, bounded point count)
-- ---------------------------------------------------------------------------

local MARKER_COLORS = {
    empty = { r = 255, g = 255, b = 255, a = 110 },
    planted = { r = 255, g = 220, b = 80, a = 140 },
    watered = { r = 120, g = 200, b = 255, a = 140 },
    grown = { r = 90, g = 230, b = 120, a = 170 },
}

local function drawFieldMarkers(coords)
    for fieldKey, field in pairs(fieldsByKey) do
        if #(coords - field.center) <= (field.radius + 25.0) then
            for _, point in pairs(fieldState[fieldKey] or {}) do
                if #(coords - vector3(point.x, point.y, coords.z)) <= 25.0 then
                    local color = MARKER_COLORS[point.state] or MARKER_COLORS.empty
                    local z = getPointZ(fieldKey, point)
                    DrawMarker(1, point.x, point.y, z + 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        1.4, 1.4, 0.4, color.r, color.g, color.b, color.a, false, false, 2, false, nil, nil, false)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Hold-to-interact (water / harvest / feed / milk). The hold itself is
-- purely client-side UX -- the server re-validates distance/state/items
-- when the action event actually arrives, so nothing here is trusted.
-- ---------------------------------------------------------------------------

local activeHold = nil -- { kind, fieldKey, index, cowKey, durationMs, startedAt, label }

local function sendHold(visible, progress, label)
    SendNUIMessage({ action = 'hold', visible = visible == true, progress = progress or 0, label = label or '' })
end

local function cancelHold()
    if not activeHold then return end
    activeHold = nil
    sendHold(false)
end

local function startHold(kind, durationMs, label, target)
    target = target or {}
    activeHold = {
        kind = kind, durationMs = durationMs, startedAt = GetGameTimer(), label = label,
        fieldKey = target.fieldKey, index = target.index, cowKey = target.cowKey,
    }
end

local function completeHold()
    local hold = activeHold
    activeHold = nil
    sendHold(false)
    if not hold then return end
    if hold.kind == 'water' then
        TriggerServerEvent('cm-farming:server:waterAttempt', hold.fieldKey, hold.index)
    elseif hold.kind == 'harvest' then
        TriggerServerEvent('cm-farming:server:harvestAttempt', hold.fieldKey, hold.index)
    elseif hold.kind == 'feed' then
        TriggerServerEvent('cm-farming:server:feedAttempt', hold.cowKey)
    elseif hold.kind == 'milk' then
        TriggerServerEvent('cm-farming:server:milkAttempt', hold.cowKey)
    end
end

-- ---------------------------------------------------------------------------
-- Nearest plot lookup + crop interaction loop
-- ---------------------------------------------------------------------------

local function findNearestActionablePoint(coords)
    local nearestField, nearestIndex, nearestPoint, nearestDist
    for fieldKey, field in pairs(fieldsByKey) do
        if #(coords - field.center) <= (field.radius + 15.0) then
            for index, point in pairs(fieldState[fieldKey] or {}) do
                local dist = #(coords - vector3(point.x, point.y, coords.z))
                if dist <= (Config.interactDistance or 1.6) and (not nearestDist or dist < nearestDist) then
                    nearestField, nearestIndex, nearestPoint, nearestDist = fieldKey, index, point, dist
                end
            end
        end
    end
    return nearestField, nearestIndex, nearestPoint
end

-- Set by the crop loop each tick so the livestock loop below knows not to
-- also show its own prompt in the same instant (field/cow locations never
-- actually overlap, but this keeps the two loops from ever fighting).
local nearCropInteract = false

CreateThread(function()
    while true do
        local wait = 700
        local ped = PlayerPedId()

        if menuOpen or IsPedInAnyVehicle(ped, false) then
            nearCropInteract = false
            if not activeHold then hideInteract() end
        else
            local coords = GetEntityCoords(ped)

            local nearAnyField = false
            for _, field in pairs(fieldsByKey) do
                if #(coords - field.center) <= (field.radius + 25.0) then nearAnyField = true break end
            end
            if nearAnyField then
                wait = 0
                drawFieldMarkers(coords)
            end

            if activeHold then
                nearCropInteract = activeHold.fieldKey ~= nil
            else
                local fieldKey, index, point = findNearestActionablePoint(coords)
                nearCropInteract = point ~= nil

                if point then
                    wait = 0
                    local fieldLabel = fieldsByKey[fieldKey].label

                    if point.state == 'empty' then
                        showInteract('Plant crop', fieldLabel)
                        if IsControlJustPressed(0, Config.interactKey) then
                            TriggerServerEvent('cm-farming:server:plantAttempt', fieldKey, index)
                        end
                    elseif point.state == 'planted' then
                        showInteract('Hold to water (needs watering can)', fieldLabel)
                        if IsControlJustPressed(0, Config.interactKey) then
                            startHold('water', Config.Timings.waterMs, 'Watering...', { fieldKey = fieldKey, index = index })
                        end
                    elseif point.state == 'watered' then
                        showInteract('Growing...', fieldLabel)
                    elseif point.state == 'grown' then
                        showInteract('Hold to harvest', fieldLabel)
                        if IsControlJustPressed(0, Config.interactKey) then
                            startHold('harvest', Config.Timings.harvestMs, 'Harvesting...', { fieldKey = fieldKey, index = index })
                        end
                    end
                end
            end
        end

        Wait(wait)
    end
end)

-- ---------------------------------------------------------------------------
-- Livestock (cows) -- feed -> wait -> milk -> sell at the same market NPC.
-- Open access, same distance-poll pattern as the crop fields.
-- ---------------------------------------------------------------------------

local cowsByKey = {}
for _, cowDef in ipairs(Config.Livestock.Cows) do cowsByKey[cowDef.key] = cowDef end

local cowState = {} -- [key] = { state = 'hungry'|'fed'|'milkable' }
local cowPeds = {}

RegisterNetEvent('cm-farming:client:cowsInit', function(snapshot)
    for key, data in pairs(snapshot) do cowState[key] = data end
end)

RegisterNetEvent('cm-farming:client:cowUpdated', function(key, state)
    cowState[key] = cowState[key] or {}
    cowState[key].state = state
end)

TriggerServerEvent('cm-farming:server:requestCows')

CreateThread(function()
    for key, cowDef in pairs(cowsByKey) do
        local model = joaat(cowDef.model)
        RequestModel(model)
        local attempts = 0
        while not HasModelLoaded(model) and attempts < 200 do Wait(10); attempts = attempts + 1 end
        if HasModelLoaded(model) then
            local c = cowDef.coords
            local cowPed = CreatePed(28, model, c.x, c.y, c.z - 1.0, c.w, false, true)
            SetEntityInvincible(cowPed, true)
            SetBlockingOfNonTemporaryEvents(cowPed, true)
            FreezeEntityPosition(cowPed, true)
            SetModelAsNoLongerNeeded(model)
            cowPeds[key] = cowPed
        end
    end

    if Config.Livestock.blip and Config.Livestock.blip.enabled and Config.Livestock.Cows[1] then
        createBlip(Config.Livestock.Cows[1].coords, Config.Livestock.blip)
    end
end)

local function findNearestCow(coords)
    local nearestKey, nearestDist
    for key, cowDef in pairs(cowsByKey) do
        local c = cowDef.coords
        local dist = #(coords - vector3(c.x, c.y, coords.z))
        if dist <= (Config.Livestock.interactDistance or 1.8) and (not nearestDist or dist < nearestDist) then
            nearestKey, nearestDist = key, dist
        end
    end
    return nearestKey
end

CreateThread(function()
    while true do
        local wait = 700
        local ped = PlayerPedId()

        if menuOpen or IsPedInAnyVehicle(ped, false) or nearCropInteract then
            if not activeHold and not nearCropInteract then hideInteract() end
        elseif activeHold then
            -- The hold-progress driver thread owns the prompt/hold-bar while
            -- a hold (crop or cow) is in progress.
        else
            local coords = GetEntityCoords(ped)
            local key = findNearestCow(coords)
            if key then
                wait = 0
                local cow = cowState[key] or { state = 'hungry' }
                if cow.state == 'hungry' then
                    showInteract('Hold to feed (needs cow feed)', 'Dairy Cow')
                    if IsControlJustPressed(0, Config.interactKey) then
                        startHold('feed', Config.Livestock.feedMs, 'Feeding...', { cowKey = key })
                    end
                elseif cow.state == 'fed' then
                    showInteract('Settling in...', 'Dairy Cow')
                elseif cow.state == 'milkable' then
                    showInteract('Hold to milk', 'Dairy Cow')
                    if IsControlJustPressed(0, Config.interactKey) then
                        startHold('milk', Config.Livestock.milkMs, 'Milking...', { cowKey = key })
                    end
                end
            else
                hideInteract()
            end
        end

        Wait(wait)
    end
end)

-- ---------------------------------------------------------------------------
-- Hold-progress driver -- single place that ticks whichever hold (crop or
-- cow) is active, since the two prompt loops above only start one.
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        local wait = 700
        if activeHold and not menuOpen then
            wait = 0
            local elapsed = GetGameTimer() - activeHold.startedAt
            local progress = math.min(100, math.floor((elapsed / activeHold.durationMs) * 100))
            sendHold(true, progress, activeHold.label)

            local coords = GetEntityCoords(PlayerPedId())
            local stillValid
            if activeHold.kind == 'feed' or activeHold.kind == 'milk' then
                stillValid = findNearestCow(coords) == activeHold.cowKey
            else
                local fieldKey, index = findNearestActionablePoint(coords)
                stillValid = fieldKey == activeHold.fieldKey and index == activeHold.index
            end

            if not IsControlPressed(0, Config.interactKey) or not stillValid then
                cancelHold()
            elseif elapsed >= activeHold.durationMs then
                completeHold()
            end
        elseif activeHold and menuOpen then
            cancelHold()
        end
        Wait(wait)
    end
end)

-- ---------------------------------------------------------------------------
-- Plant crop picker (only shown when more than one owned seed type is
-- valid for the field -- a single valid seed auto-plants server-side)
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-farming:client:choosePlant', function(fieldKey, index, options)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'choosePlant', fieldKey = fieldKey, index = index, options = options })
end)

RegisterNUICallback('choosePlantSeed', function(data, cb)
    if data and data.fieldKey and data.index and data.cropName then
        TriggerServerEvent('cm-farming:server:plantChosen', data.fieldKey, data.index, data.cropName)
    end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeChoosePlant' })
    cb({ ok = true })
end)

RegisterNUICallback('cancelChoosePlant', function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeChoosePlant' })
    cb({ ok = true })
end)

-- ---------------------------------------------------------------------------
-- Market menu
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-farming:client:openMenu', function(payload)
    menuOpen = true
    hideInteract()
    cancelHold()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openMenu', payload = payload })
end)

local function closeMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeMenu' })
end

RegisterNUICallback('closeMenu', function(_, cb)
    closeMenu()
    cb({ ok = true })
end)

RegisterNUICallback('escape', function(_, cb)
    if menuOpen then closeMenu() end
    if activeHold then cancelHold() end
    cb({ ok = true })
end)

RegisterNUICallback('buyItem', function(data, cb)
    if data and data.kind and data.name then
        TriggerServerEvent('cm-farming:server:buyItem', data.kind, data.name, data.qty or 1)
    end
    cb({ ok = true })
end)

RegisterNUICallback('sellItem', function(data, cb)
    if data and data.name then
        TriggerServerEvent('cm-farming:server:sellItem', data.name, data.amount or 1)
    end
    cb({ ok = true })
end)

RegisterNUICallback('ready', function(_, cb)
    cb({ ok = true })
end)

-- ---------------------------------------------------------------------------
-- TEMPORARY: location-scouting helper for placing real farming
-- fields / cow shed spots. Stand where you want a point and run
-- /farmpos -- prints a ready-to-paste vector4(x, y, z, heading) to chat
-- and the F8 console, and drops a short-lived marker so you can see
-- exactly where it was captured. Remove this once all real-world
-- locations are set in shared/config.lua.
-- ---------------------------------------------------------------------------

RegisterCommand('farmpos', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local line = ('vector4(%.4f, %.4f, %.4f, %.2f)'):format(coords.x, coords.y, coords.z, heading)

    TriggerEvent('chat:addMessage', { args = { '[CM-FARMING]', line } })
    print(('[CM-FARMING] %s'):format(line))

    CreateThread(function()
        local endAt = GetGameTimer() + 4000
        while GetGameTimer() < endAt do
            DrawMarker(1, coords.x, coords.y, coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                1.5, 1.5, 1.0, 0, 240, 255, 160, false, false, 2, false, nil, nil, false)
            Wait(0)
        end
    end)
end, false)

-- ---------------------------------------------------------------------------
-- TEMPORARY: circular field scouting tool. Walk the edge of the area you
-- want as a field, marking boundary points as you go -- it fits a circle
-- to those points live so you can see (and adjust) the shape on the ground
-- before locking it in.
--   /farmzone start <name>   begin a new zone, clears any previous points
--   /farmzone mark           add your current position as a boundary point
--   /farmzone undo           remove the last marked point
--   /farmzone finish         print the fitted center/radius, end the zone
-- Remove this whole block (and /farmpos above) once all real-world
-- locations are set in shared/config.lua.
-- ---------------------------------------------------------------------------

local zoneActive = false
local zoneName = nil
local zonePoints = {} -- { {x,y,z}, ... }

local function zoneCircle()
    if #zonePoints == 0 then return nil end
    local sx, sy = 0.0, 0.0
    for _, p in ipairs(zonePoints) do sx = sx + p.x; sy = sy + p.y end
    local cx, cy = sx / #zonePoints, sy / #zonePoints
    local radius = 0.0
    for _, p in ipairs(zonePoints) do
        local d = math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2)
        if d > radius then radius = d end
    end
    return cx, cy, radius
end

local function zoneMsg(text)
    TriggerEvent('chat:addMessage', { args = { '[CM-FARMING]', text } })
end

RegisterCommand('farmzone', function(_, args)
    local sub = args[1] and args[1]:lower() or nil

    if sub == 'start' then
        zoneActive = true
        zoneName = args[2] or 'zone'
        zonePoints = {}
        zoneMsg(('Started zone "%s". Walk the edge of the area and run /farmzone mark at each boundary point.'):format(zoneName))
    elseif sub == 'mark' then
        if not zoneActive then
            zoneMsg('No active zone. Run /farmzone start <name> first.')
            return
        end
        local coords = GetEntityCoords(PlayerPedId())
        zonePoints[#zonePoints + 1] = { x = coords.x, y = coords.y, z = coords.z }
        local _, _, radius = zoneCircle()
        zoneMsg(('Marked point %d. Live radius: %.1fm'):format(#zonePoints, radius or 0.0))
    elseif sub == 'undo' then
        if #zonePoints > 0 then
            table.remove(zonePoints)
            zoneMsg(('Removed last point (%d remaining).'):format(#zonePoints))
        end
    elseif sub == 'finish' then
        if not zoneActive or #zonePoints < 2 then
            zoneMsg('Need at least 2 marked boundary points before finishing.')
            return
        end
        local cx, cy, radius = zoneCircle()
        local groundZ = GetEntityCoords(PlayerPedId()).z
        local centerLine = ('center = vector3(%.4f, %.4f, %.4f),'):format(cx, cy, groundZ)
        local radiusLine = ('radius = %.1f,'):format(math.ceil(radius))
        zoneMsg(('Zone "%s" finished (%d points):'):format(zoneName, #zonePoints))
        zoneMsg(centerLine)
        zoneMsg(radiusLine)
        print(('[CM-FARMING] Zone "%s": %s %s'):format(zoneName, centerLine, radiusLine))
        zoneActive = false
    else
        zoneMsg('Usage: /farmzone start <name> | mark | undo | finish')
    end
end, false)

-- Live circle preview (marker dots at each boundary point + a fitted
-- circle outline) while a zone is being defined.
CreateThread(function()
    while true do
        local wait = 500
        if zoneActive and #zonePoints > 0 then
            wait = 0
            local cx, cy, radius = zoneCircle()
            local z = GetEntityCoords(PlayerPedId()).z

            for _, p in ipairs(zonePoints) do
                DrawMarker(1, p.x, p.y, p.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.6, 0.6, 0.6, 255, 200, 0, 200, false, false, 2, false, nil, nil, false)
            end

            local segments = 32
            for i = 0, segments - 1 do
                local a1 = (i / segments) * 2 * math.pi
                local a2 = ((i + 1) / segments) * 2 * math.pi
                local x1, y1 = cx + math.cos(a1) * radius, cy + math.sin(a1) * radius
                local x2, y2 = cx + math.cos(a2) * radius, cy + math.sin(a2) * radius
                DrawLine(x1, y1, z, x2, y2, z, 0, 240, 255, 220)
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    hideInteract()
    if DoesEntityExist(marketPed) then DeleteEntity(marketPed) end
    for fieldKey, points in pairs(pointEntities) do
        for index in pairs(points) do despawnPointEntity(fieldKey, index) end
    end
    for _, cowPed in pairs(cowPeds) do
        if DoesEntityExist(cowPed) then DeleteEntity(cowPed) end
    end
end)
