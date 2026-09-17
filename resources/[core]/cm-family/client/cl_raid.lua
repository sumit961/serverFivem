-- cm-family | family raid client presentation and join circle.

local Raid = nil
local InRaid = false
local Eliminated = false
local RaidRadiusBlip = nil
local RaidCenterBlip = nil
local BoundarySegments = {}
local BoundaryGrounded = false
local BoundaryWarningUntil = 0
local RaidHudVisible = false

local function raidNow()
    -- FiveM client Lua does not guarantee the server-side `os` library.
    -- Cloud time is Unix time and matches the timestamps sent by sv_raid.lua.
    if GetCloudTimeAsInt then return GetCloudTimeAsInt() end
    return math.floor(GetGameTimer() / 1000)
end

local function clearRaidBlips()
    if RaidRadiusBlip and DoesBlipExist(RaidRadiusBlip) then RemoveBlip(RaidRadiusBlip) end
    if RaidCenterBlip and DoesBlipExist(RaidCenterBlip) then RemoveBlip(RaidCenterBlip) end
    RaidRadiusBlip, RaidCenterBlip = nil, nil
end

local function clearRaidBoundary()
    BoundarySegments = {}
    BoundaryGrounded = false
end

-- Keep the raid world boundary in lockstep with cm-gang's event boundary:
-- grounded segmented ring plus a translucent wall so it remains visible over
-- uneven terrain and in interiors/streets.
local function buildRaidBoundary(payload, useGround)
    clearRaidBoundary()
    local center = payload and payload.center
    local radius = tonumber(payload and payload.radius)
    -- Networked vector3 values arrive as either a native vector3 or a plain
    -- table depending on the msgpack path, so only require coordinates.
    if not center or not radius or radius <= 0 then return end
    local x, y, z = tonumber(center.x), tonumber(center.y), tonumber(center.z)
    if not x or not y or not z then return end

    BoundaryGrounded = false
    local baseZ = z + 0.05
    if useGround then
        RequestCollisionAtCoord(x, y, z)
        local found, ground = GetGroundZFor_3dCoord(x, y, z + 1000.0, false)
        -- Do not draw from the house/door Z when collision is not ready; that
        -- fallback is what makes the wall appear suspended in the air.
        if not found then return end
        baseZ = ground + 0.05
        BoundaryGrounded = true
    end
    local segments = math.max(48, math.min(128, math.floor(tonumber(payload.boundarySegments) or 96)))
    for index = 0, segments - 1 do
        local angle = (index / segments) * math.pi * 2.0
        local pointX = x + math.cos(angle) * radius
        local pointY = y + math.sin(angle) * radius
        BoundarySegments[#BoundarySegments + 1] = { x = pointX, y = pointY, z = baseZ }
    end
end

local function drawRaidBoundaryWall(center)
    if #BoundarySegments < 2 then return end
    local bottomZ = (BoundarySegments[1].z or center.z) - 60.0
    local topZ = bottomZ + 100.0
    local playerCoords = GetEntityCoords(PlayerPedId())
    local radius = tonumber(Raid and Raid.radius) or 50.0
    local dx, dy = playerCoords.x - center.x, playerCoords.y - center.y
    local inside = (dx * dx + dy * dy) <= (radius * radius)
    for index, pointA in ipairs(BoundarySegments) do
        local pointB = BoundarySegments[index % #BoundarySegments + 1]
        -- Open side panels only: embedded below the ground, full height, and
        -- no top/ceiling polygon. Use one winding to avoid alpha striping;
        -- reverse it for players standing inside the arena.
        if inside then
            DrawPoly(pointB.x, pointB.y, bottomZ, pointA.x, pointA.y, bottomZ,
                pointB.x, pointB.y, topZ, 0, 209, 255, 52)
            DrawPoly(pointA.x, pointA.y, topZ, pointB.x, pointB.y, topZ,
                pointA.x, pointA.y, bottomZ, 0, 209, 255, 52)
        else
            DrawPoly(pointA.x, pointA.y, bottomZ, pointB.x, pointB.y, bottomZ,
                pointB.x, pointB.y, topZ, 0, 209, 255, 52)
            DrawPoly(pointA.x, pointA.y, bottomZ, pointB.x, pointB.y, topZ,
                pointA.x, pointA.y, topZ, 0, 209, 255, 52)
        end
    end
end

local function refreshRaidBlips(payload)
    clearRaidBlips()
    local center = payload and payload.center
    local radius = tonumber(payload and payload.radius)
    if not center or not radius or radius <= 0 then return end
    local x, y, z = tonumber(center.x), tonumber(center.y), tonumber(center.z)
    if not x or not y or not z then return end

    RaidRadiusBlip = AddBlipForRadius(x, y, z, radius + 0.0)
    SetBlipColour(RaidRadiusBlip, 3)
    SetBlipAlpha(RaidRadiusBlip, 75)

    RaidCenterBlip = AddBlipForCoord(x, y, z)
    SetBlipSprite(RaidCenterBlip, 461)
    SetBlipColour(RaidCenterBlip, 3)
    SetBlipRoute(RaidCenterBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Family Raid')
    EndTextCommandSetBlipName(RaidCenterBlip)
end

local function clearRaidHud()
    if RaidHudVisible then
        TriggerEvent('cm-hud:client:clearRaidHud')
    end
    RaidHudVisible = false
end

local function publishRaidHud()
    if Raid then
        RaidHudVisible = true
        TriggerEvent('cm-hud:client:setRaidHud', {
            raidId = Raid.raidId,
            phase = Raid.phase,
            startsAt = Raid.startsAt,
            endsAt = Raid.endsAt,
            families = Raid.families or {}
        })
    else
        clearRaidHud()
    end
end

local function setRaidPayload(payload)
    if type(payload) ~= 'table' or not payload.raidId then return end
    Raid = payload
    Eliminated = false
    buildRaidBoundary(payload, false)
    refreshRaidBlips(payload)
    -- Do not let a later raidUpdate resurrect the event card while this
    -- participant is outside the circle grace window.
    if not (InRaid and BoundaryWarningUntil > raidNow()) then
        publishRaidHud()
    end
end

local function notify(message, kind)
    TriggerEvent('cm-hud:client:notify', tostring(message or ''), kind or 'inform')
end

local function drawRaidWidgetText(value, x, y, scale, colour, centred)
    SetTextProportional(true)
    SetTextFont(4)
    SetTextScale(0.0, scale)
    SetTextColour(colour[1], colour[2], colour[3], colour[4] or 235)
    SetTextCentre(centred == true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(tostring(value or ''))
    EndTextCommandDisplayText(x, y)
end

local function raidWidgetData()
    if not Raid then return nil end
    local now = raidNow()
    local target = tonumber(Raid.endsAt) or tonumber(Raid.startsAt) or now
    local remaining = math.max(0, target - now)
    local minutes = math.floor(remaining / 60)
    local seconds = remaining % 60
    local families = {}

    -- The server sends an array, but iterate with pairs so the widget also
    -- works with keyed payloads after a resource restart or late join.
    for _, family in pairs(Raid.families or {}) do
        if type(family) == 'table' then
            families[#families + 1] = {
                name = tostring(family.name or 'Family'),
                count = tonumber(family.alive) or tonumber(family.total) or 0
            }
        end
    end
    table.sort(families, function(a, b) return a.name < b.name end)
    if #families == 0 then families[1] = { name = 'YOUR FAMILY', count = 0 } end
    if #families == 1 then families[2] = { name = 'WAITING', count = 0 } end

    return ('%02d:%02d'):format(minutes, seconds), families
end

local function drawRaidWidget()
    local timer, families = raidWidgetData()
    if not timer then return end

    -- Compact top-left panel styled after the supplied raid HUD reference.
    local left, top = 0.015, 0.018
    local width, height = 0.205, 0.088
    DrawRect(left + width * 0.5, top + height * 0.5, width, height, 7, 13, 19, 218)
    DrawRect(left + width * 0.5, top + 0.002, width, 0.004, 224, 38, 58, 240)

    -- Timer medallion. Use only DrawRect primitives because DrawCircle is not
    -- exposed by every FiveM client build and would stop the render thread.
    DrawRect(left + 0.026, top + 0.034, 0.022, 0.022, 238, 183, 48, 235)
    DrawRect(left + 0.026, top + 0.034, 0.015, 0.015, 18, 29, 37, 245)
    DrawRect(left + 0.026, top + 0.030, 0.0015, 0.006, 238, 183, 48, 235)
    DrawRect(left + 0.028, top + 0.035, 0.004, 0.0015, 238, 183, 48, 235)
    drawRaidWidgetText(timer, left + 0.026, top + 0.051, 0.115, { 255, 221, 113, 245 }, true)

    drawRaidWidgetText('RAID', left + 0.052, top + 0.014, 0.21, { 245, 248, 252, 245 }, false)
    for index = 1, 2 do
        local family = families[index]
        local rowY = top + 0.041 + ((index - 1) * 0.025)
        local badgeColour = index == 1 and { 225, 65, 82, 235 } or { 238, 92, 110, 235 }
        DrawRect(left + 0.062, rowY + 0.007, 0.016, 0.018, badgeColour[1], badgeColour[2], badgeColour[3], badgeColour[4])
        drawRaidWidgetText(family.count, left + 0.062, rowY, 0.16, { 255, 255, 255, 245 }, true)
        local name = family.name
        if #name > 17 then name = name:sub(1, 17) .. '…' end
        drawRaidWidgetText(name, left + 0.075, rowY, 0.17, { 235, 238, 243, 235 }, false)
    end
end

local function circleCoords()
    return Raid and Raid.center and vector3(
        tonumber(Raid.center.x) or 0.0,
        tonumber(Raid.center.y) or 0.0,
        tonumber(Raid.center.z) or 0.0) or nil
end

local function isRaidJoinEdge(distance)
    local radius = tonumber(Raid and Raid.radius) or 50.0
    local band = tonumber(Config.Raid and Config.Raid.joinEdgeBand) or 3.0
    return distance >= math.max(0.0, radius - band) and distance <= radius + band
end

local function showJoinPrompt()
    pcall(function()
        exports['cm-ui']:ShowInteract({ key = 'E', label = 'JOIN FAMILY RAID' })
    end)
end

local function hideJoinPrompt()
    pcall(function() exports['cm-ui']:HideInteract() end)
end

RegisterNetEvent('cm-family:client:raidCircle', function(payload)
    InRaid = false
    Eliminated = false
    setRaidPayload(payload)
end)

RegisterNetEvent('cm-family:client:raidUpdate', function(payload)
    if not payload or not payload.raidId then return end
    if Eliminated then return end
    -- Accept the first update too: event ordering or a resource restart can
    -- drop raidCircle while raidUpdate still arrives.
    if not Raid or tostring(payload.raidId) == tostring(Raid.raidId) then
        setRaidPayload(payload)
    end
end)

RegisterNetEvent('cm-family:client:raidJoined', function(payload)
    Eliminated = false
    setRaidPayload(payload)
    InRaid = true
    notify('You joined the family raid. Stay inside the match bucket.', 'success')
end)

RegisterNetEvent('cm-family:client:raidEliminated', function(data)
    InRaid = false
    Eliminated = true
    BoundaryWarningUntil = 0
    clearRaidHud()
    Raid = nil
    clearRaidBlips()
    clearRaidBoundary()
    local message = 'You were eliminated from the family raid.'
    if data and data.reason == 'left_raid' then message = 'You left the raid.' end
    if data and data.reason == 'left_circle' then message = 'You left the raid circle and were eliminated.' end
    if data and data.reason == 'vehicle_in_raid' then message = 'Vehicles are not allowed inside the raid.' end
    notify(message, 'error')
end)

RegisterNetEvent('cm-family:client:raidBoundaryWarning', function(data)
    local seconds = math.max(1, tonumber(data and data.seconds) or 5)
    BoundaryWarningUntil = tonumber(data and data.deadline) or (raidNow() + seconds)
    -- The event card is only shown while the player is inside the event area.
    clearRaidHud()
    notify(('Return to the raid circle within %d seconds or you will be removed from the event.'):format(seconds), 'warning')
end)

RegisterNetEvent('cm-family:client:raidBoundaryReturned', function()
    if BoundaryWarningUntil > 0 then
        BoundaryWarningUntil = 0
        if InRaid then publishRaidHud() end
        notify('You returned to the raid circle.', 'success')
    end
end)

RegisterNetEvent('cm-family:client:raidFinished', function(result)
    InRaid = false
    BoundaryWarningUntil = 0
    Raid = nil
    publishRaidHud()
    clearRaidBlips()
    clearRaidBoundary()
    if result and result.winnerName then
        notify(('%s won the family raid. $%s was added to its family balance.'):format(
            tostring(result.winnerName), tostring(result.reward or 0)), 'success')
    else
        notify('The family raid ended without a winner.', 'inform')
    end
end)

RegisterNetEvent('cm-family:client:raidEnded', function(result)
    if result and Raid and tostring(result.raidId) == tostring(Raid.raidId) then
        Raid = nil
        BoundaryWarningUntil = 0
        publishRaidHud()
        clearRaidBlips()
        clearRaidBoundary()
    end
end)

CreateThread(function()
    while true do
        local sleep = 750
        if Raid then
            sleep = 0
            local center = circleCoords()
            if center then
                local ped = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)
                if InRaid and vehicle ~= 0 then
                    TaskLeaveVehicle(ped, vehicle, 16)
                end
                local coords = GetEntityCoords(ped)
                local distance = #(coords - center)
                if not BoundaryGrounded then buildRaidBoundary(Raid, true) end
                drawRaidBoundaryWall(center)

                local insideDisplayArea = InRaid or distance <= (tonumber(Raid.radius) or 50.0)
                local inGraceWarning = BoundaryWarningUntil > raidNow()
                if insideDisplayArea and not inGraceWarning then
                    if not RaidHudVisible then publishRaidHud() end
                else
                    clearRaidHud()
                end

                if not InRaid and not Eliminated and isRaidJoinEdge(distance)
                   and (Raid.phase == 'forming' or Raid.phase == 'countdown' or Raid.phase == 'active') then
                    showJoinPrompt()
                    if IsControlJustReleased(0, 38) then
                        local ok, message = lib.callback.await('cm-family:server:joinRaid', false, Raid.raidId)
                        if not ok then notify(message or 'You cannot join this raid.', 'error') end
                    end
                else
                    hideJoinPrompt()
                end
            end
        else
            hideJoinPrompt()
            clearRaidHud()
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        hideJoinPrompt()
        clearRaidHud()
        clearRaidBoundary()
        clearRaidBlips()
    end
end)

-- Event delivery is normally enough, but a client resource reload or a late
-- join can miss the initial broadcast. Poll only while no local state exists;
-- once a payload is present the normal event stream remains authoritative.
CreateThread(function()
    while true do
        if not Raid and not Eliminated then
            local ok, payload = pcall(lib.callback.await,
                'cm-family:server:getActiveRaid', false)
            if ok and type(payload) == 'table' and payload.raidId then
                setRaidPayload(payload)
            end
        end
        Wait(1000)
    end
end)
