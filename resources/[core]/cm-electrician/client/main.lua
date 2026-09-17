local Config = CMElectrician.Config
CMElectrician.Client = CMElectrician.Client or {}

local employed = false
local level = 1
local panelsCount = 0
local platesCount = 0
local menuOpen = false
local holding = false
local outageActive = false
local jobVehicleActive = false
local civilianOutfit = nil

local panelTargets, panelBlips = {}, {}
local plateTargets, plateBlips = {}, {}

local promptVisible = false
local promptTitle, promptLabel, promptHint = nil, nil, nil
local lastPromptSentAt = 0

local function dbg(...)
    if Config.Debug then print('[CM-ELECTRICIAN]', ...) end
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

local function sendInteraction(visible, title, label, hint, force)
    local sameState = promptVisible == visible
        and (not visible or (promptTitle == title and promptLabel == label and promptHint == hint))

    promptVisible, promptTitle, promptLabel, promptHint = visible, visible and title or nil, visible and label or nil, visible and hint or nil

    local now = GetGameTimer()
    if sameState and force ~= true and (now - lastPromptSentAt) < 800 then return end
    lastPromptSentAt = now

    SendNUIMessage({
        action = 'interaction',
        visible = visible == true,
        key = Config.interactKeyLabel or 'E',
        title = title or Config.JobTitle,
        label = label or '',
        hint = hint or '',
    })
end

local function updateJobHud()
    SendNUIMessage({
        action = 'jobHud',
        visible = employed,
        level = level,
        panels = panelsCount,
        plates = platesCount,
        showPlates = level >= 2,
    })
end

-- ---------------------------------------------------------------------------
-- Duty uniform. Only the slots listed in Config.Uniform are overridden, and
-- the player's exact previous values for those slots are restored on
-- resignation, on disconnect, and if the resource stops mid-shift.
-- ---------------------------------------------------------------------------

local function captureOutfit()
    local ped = PlayerPedId()
    local outfit = {}
    for index = 0, 11 do
        outfit[index] = {
            drawable = GetPedDrawableVariation(ped, index),
            texture = GetPedTextureVariation(ped, index),
            palette = GetPedPaletteVariation(ped, index),
        }
    end
    return outfit
end

local function applyOutfit(outfit)
    if type(outfit) ~= 'table' then return end
    local ped = PlayerPedId()
    for index, value in pairs(outfit) do
        if type(value) == 'table' then
            SetPedComponentVariation(ped, tonumber(index), tonumber(value.drawable) or 0, tonumber(value.texture) or 0, tonumber(value.palette) or 0)
        end
    end
end

local function applyUniform()
    local ped = PlayerPedId()
    local sex = GetEntityModel(ped) == joaat('mp_f_freemode_01') and 'female' or 'male'
    local uniform = Config.Uniform[sex]
    if not uniform then return end
    for index, value in pairs(uniform) do
        SetPedComponentVariation(ped, index, value.drawable, value.texture, 0)
    end
end

local function beginShift()
    if civilianOutfit then return end
    civilianOutfit = captureOutfit()
    applyUniform()
end

local function endShift()
    if not civilianOutfit then return end
    applyOutfit(civilianOutfit)
    civilianOutfit = nil
end

-- ---------------------------------------------------------------------------
-- Job blip.
-- ---------------------------------------------------------------------------

CreateThread(function()
    local blip = Config.Blip
    if blip.enabled == false then return end

    local handle = AddBlipForCoord(Config.Employment.coords.x, Config.Employment.coords.y, Config.Employment.coords.z)
    SetBlipSprite(handle, blip.sprite or 354)
    SetBlipDisplay(handle, 4)
    SetBlipScale(handle, blip.scale or 1.0)
    SetBlipColour(handle, blip.color or 26)
    SetBlipAsShortRange(handle, blip.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blip.name or Config.JobTitle)
    EndTextCommandSetBlipName(handle)
end)

-- The truck itself is spawned/owned server-side through cm-vehicles' trusted
-- placement bridge (server/main.lua), so returning it is just a request --
-- the server deletes the entity and we only track whether one is out.
local function returnJobVehicle()
    if not jobVehicleActive then return end
    jobVehicleActive = false
    TriggerServerEvent('cm-electrician:server:requestServiceTruck', false)
end

-- ---------------------------------------------------------------------------
-- Random multi-target tasks. Several panel and deposit-plate locations
-- (Config.TaskCount) are active at once, each shown as its own map blip, so
-- players can pick which to head to instead of following one forced route.
-- Each is replaced one-for-one by a new random location (never one already
-- active) as it gets repaired.
-- ---------------------------------------------------------------------------

math.randomseed(GetGameTimer())

local function removeTaskBlip(blip)
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

local function createTaskBlip(coords, def)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, def.sprite)
    SetBlipColour(blip, def.color)
    SetBlipScale(blip, def.scale or 0.65)
    -- Long-range (not short-range) blips get GTA's native small arrow at the
    -- edge of the minimap/radar pointing toward them when off-screen -- a
    -- small, modern GPS-style indicator, unlike the long drawn SetBlipRoute path.
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(def.label)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function pickRandomAvailableIndex(list, active)
    local activeSet = {}
    for _, index in ipairs(active) do activeSet[index] = true end
    if #list <= #active then return nil end

    local index
    local attempts = 0
    repeat
        index = math.random(1, #list)
        attempts = attempts + 1
    until not activeSet[index] or attempts > 50
    return not activeSet[index] and index or nil
end

-- Numbers each active blip 1..N in its map icon so multiple simultaneous
-- panels/plates (Config.TaskCount) are distinguishable at a glance instead
-- of showing as identical unlabeled wrench icons.
local function renumberBlips(targets, blips)
    for i, index in ipairs(targets) do
        local blip = blips[index]
        if blip and DoesBlipExist(blip) then
            ShowNumberOnBlip(blip, i)
        end
    end
end

local function addTarget(targets, blips, list, def)
    local index = pickRandomAvailableIndex(list, targets)
    if not index then return end
    targets[#targets + 1] = index
    blips[index] = createTaskBlip(list[index], def)
    renumberBlips(targets, blips)
end

local function removeTarget(targets, blips, fixedIndex)
    for i, index in ipairs(targets) do
        if index == fixedIndex then
            removeTaskBlip(blips[index])
            blips[index] = nil
            table.remove(targets, i)
            break
        end
    end
    renumberBlips(targets, blips)
end

local function clearTargets(targets, blips)
    for index in pairs(blips) do
        removeTaskBlip(blips[index])
        blips[index] = nil
    end
    for i = #targets, 1, -1 do targets[i] = nil end
end

local function refreshPanelTargets()
    local wanted = math.max(1, tonumber(Config.TaskCount.panels) or 3)
    while #panelTargets < wanted do
        local before = #panelTargets
        addTarget(panelTargets, panelBlips, Config.Panels, Config.TaskBlip.panel)
        if #panelTargets == before then break end
    end
end

local function replacePanelTarget(fixedIndex)
    removeTarget(panelTargets, panelBlips, fixedIndex)
    refreshPanelTargets()
end

local function clearPanelTargets()
    clearTargets(panelTargets, panelBlips)
end

local function refreshPlateTargets()
    local wanted = math.max(1, tonumber(Config.TaskCount.plates) or 2)
    while #plateTargets < wanted do
        local before = #plateTargets
        addTarget(plateTargets, plateBlips, Config.Plates, Config.TaskBlip.plate)
        if #plateTargets == before then break end
    end
end

local function replacePlateTarget(fixedIndex)
    removeTarget(plateTargets, plateBlips, fixedIndex)
    refreshPlateTargets()
end

local function clearPlateTargets()
    clearTargets(plateTargets, plateBlips)
end

-- ---------------------------------------------------------------------------
-- Employment menu.
-- ---------------------------------------------------------------------------

local function openMenu()
    if menuOpen then return end
    menuOpen = true
    sendInteraction(false, nil, nil, nil, true)

    TriggerServerEvent('cm-electrician:server:requestStatus')

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openMenu',
        ctx = {
            title = Config.JobTitle,
            description = Config.Description,
            requirements = Config.Requirements,
            employed = employed,
            level = level,
            panels = panelsCount,
            plates = platesCount,
            panelGoal = Config.LevelUp.panelsForLevel2,
            plateGoal = Config.LevelUp.platesForLevel3,
            perPanel = Config.Earnings.perPanel,
            perPlate = Config.Earnings.perPlate,
            perOutage = Config.Earnings.perOutageFix,
        }
    })
end

local function closeMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeMenu' })
end

RegisterNetEvent('cm-electrician:client:status', function(status)
    status = type(status) == 'table' and status or {}
    level = tonumber(status.level) or level
    panelsCount = tonumber(status.panels) or panelsCount
    platesCount = tonumber(status.plates) or platesCount

    if menuOpen then
        SendNUIMessage({
            action = 'updateStatus',
            level = level,
            panels = panelsCount,
            plates = platesCount,
            employed = employed,
        })
    end
    updateJobHud()

    if employed and level >= 2 then
        refreshPlateTargets()
    end
end)

RegisterNetEvent('cm-electrician:client:employedSet', function(state, reason)
    local wasEmployed = employed
    employed = state == true

    if employed and not wasEmployed then
        beginShift()
        refreshPanelTargets()
        if level >= 2 then
            refreshPlateTargets()
        end
        TriggerServerEvent('cm-electrician:server:requestStatus')
    elseif not employed and wasEmployed then
        endShift()
        clearPanelTargets()
        clearPlateTargets()
        returnJobVehicle()
    end

    SendNUIMessage({ action = 'employmentResult', employed = employed })
    if reason then notify(reason, 'error') end
    updateJobHud()
    closeMenu()
end)

RegisterNetEvent('cm-electrician:client:notify', function(message, kind)
    notify(message, kind)
end)

RegisterNetEvent('cm-electrician:client:panelResult', function(data)
    data = type(data) == 'table' and data or {}
    panelsCount = tonumber(data.panels) or panelsCount
    level = tonumber(data.level) or level

    replacePanelTarget(tonumber(data.index))
    if data.leveledUp and level >= 2 then
        refreshPlateTargets()
    end
    updateJobHud()
end)

RegisterNetEvent('cm-electrician:client:plateResult', function(data)
    data = type(data) == 'table' and data or {}
    platesCount = tonumber(data.plates) or platesCount
    level = tonumber(data.level) or level

    replacePlateTarget(tonumber(data.index))
    updateJobHud()
end)

local outageLocation = nil

RegisterNetEvent('cm-electrician:client:outageState', function(active, location)
    outageActive = active == true
    outageLocation = outageActive and location or nil
end)

RegisterNetEvent('cm-electrician:client:outageAlert', function(location)
    -- This also arrives as a catch-up (reconnect, admin level-set, opening
    -- the menu) when the initial outageState broadcast was missed entirely,
    -- so it must arm outageActive itself, not just the waypoint/notification.
    if location then
        outageLocation = location
        outageActive = true
    end
    if not employed or level < (Config.PowerOutage.unlockLevel or 3) or not outageLocation then return end
    notify('There is a power outage in the city. Head to the marked location on your GPS.', 'info')
    SetNewWaypoint(outageLocation.x, outageLocation.y)
end)

-- ---------------------------------------------------------------------------
-- Blackout atmosphere: while an outage is active, EVERYONE near the fault
-- (not just electricians) sees the streetlights/interior lights go dark,
-- restored the moment they leave the area or the fault is fixed.
--
-- SetArtificialLightsState is a hard on/off native -- GTA has no way to fade
-- world lighting -- so a single radius would flicker on/off if a player just
-- stood near the edge. Two radii (enter tighter, only leave once further
-- out) give hysteresis instead: once dark, you have to walk a bit further
-- away before it snaps back, which reads as a smooth transition rather than
-- a toggle that stutters at one line. Kept small so it only covers the
-- immediate area of the fault, not whole neighbourhoods.
-- ---------------------------------------------------------------------------

local BLACKOUT_ENTER_RADIUS = tonumber(Config.PowerOutage.blackoutEnterRadius) or 40.0
local BLACKOUT_EXIT_RADIUS = tonumber(Config.PowerOutage.blackoutExitRadius) or 60.0
local lightsOff = false

CreateThread(function()
    while true do
        if outageActive and outageLocation then
            local coords = GetEntityCoords(PlayerPedId())
            local distance = #(coords - outageLocation)

            if not lightsOff and distance < BLACKOUT_ENTER_RADIUS then
                lightsOff = true
                SetArtificialLightsState(true)
            elseif lightsOff and distance > BLACKOUT_EXIT_RADIUS then
                lightsOff = false
                SetArtificialLightsState(false)
            end
        elseif lightsOff then
            lightsOff = false
            SetArtificialLightsState(false)
        end

        Wait(500)
    end
end)

RegisterNUICallback('ready', function(_, cb)
    cb({ ok = true })
end)

RegisterNUICallback('toggleEmployment', function(_, cb)
    local wantEmployed = not employed
    TriggerServerEvent('cm-electrician:server:setEmployed', wantEmployed)
    -- Resigning always succeeds (setEmployed only validates becoming
    -- employed), so this is safe to confirm optimistically rather than
    -- waiting on a round trip -- the leash/death auto-resign paths already
    -- show their own specific reason, so this only covers the manual case.
    if not wantEmployed then
        notify('You clocked out and are no longer on duty.', 'info')
    end
    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb({ ok = true })
end)

RegisterNUICallback('escape', function(_, cb)
    closeMenu()
    cb({ ok = true })
end)

-- Employment sign-up/resignation now happens through the switchboard NPC
-- (client/npc.lua) and its cm-ui cinematic dialogue instead of a bare
-- interaction point, so there is no proximity thread here any more.

-- Level-1 job-area leash: wandering too far from the power plant auto-resigns
-- the player. Level 2+ intentionally roam the city (plates/outages), so they
-- are left alone.
CreateThread(function()
    while true do
        local wait = 3000

        if employed and level == 1 and not menuOpen then
            local coords = GetEntityCoords(PlayerPedId())
            if #(coords - Config.Employment.coords) > (Config.JobLeashRadius or 130.0) then
                TriggerServerEvent('cm-electrician:server:setEmployed', false)
                notify('You wandered too far from the job site and were let go.', 'error')
            end
        end

        Wait(wait)
    end
end)

-- Dying while on duty clocks the player out automatically. Without this
-- they'd stay "employed" through death/respawn -- uniform reverted, tasks
-- cleared and the truck returned all still need to happen, and the level-1
-- leash/distance checks have no way to catch someone who respawns clear
-- across the map.
CreateThread(function()
    local wasDead = false

    while true do
        local wait = 2000

        if employed then
            wait = 500
            local isDead = IsEntityDead(PlayerPedId())
            if isDead and not wasDead then
                TriggerServerEvent('cm-electrician:server:setEmployed', false)
                notify('You were taken off duty after dying.', 'error')
            end
            wasDead = isDead
        else
            wasDead = false
        end

        Wait(wait)
    end
end)

-- The service truck itself is spawned server-side through cm-vehicles'
-- trusted placement bridge, so it comes out owned by the player's own
-- character -- lockable, keyed, and fully integrated with cm-vehicles --
-- instead of a bare local prop. Renting/returning it is now requested from
-- the switchboard NPC's dialogue (client/npc.lua) rather than a separate
-- walk-up point.
local vehicleRequestPending = false

RegisterNetEvent('cm-electrician:client:serviceTruck', function(active)
    vehicleRequestPending = false
    jobVehicleActive = active == true
end)

local function requestTruck(wantVehicle)
    if vehicleRequestPending then return end
    vehicleRequestPending = true
    TriggerServerEvent('cm-electrician:server:requestServiceTruck', wantVehicle == true)
end

-- shockChance (0-1) is rolled once per hold; if it hits, the shock fires at a
-- random point during the hold instead of always right at the start, so an
-- unlucky attempt doesn't just read as an instant, guaranteed-early bail.
local function performHold(durationMs, shockChance)
    local start = GetGameTimer()
    holding = true
    SendNUIMessage({ action = 'holdStart' })

    -- Native welding scenario (built-in sparks VFX) plays while the repair is
    -- held, instead of relying on a separate loaded anim dictionary.
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_WELDING', 0, true)

    local shockAtMs = (math.random() < (tonumber(shockChance) or 0)) and math.random(300, math.max(300, durationMs)) or nil

    local completed = false
    local shocked = false
    while IsControlPressed(0, Config.interactKey) do
        Wait(0)
        local elapsed = GetGameTimer() - start

        if shockAtMs and elapsed >= shockAtMs then
            shocked = true
            break
        end

        SendNUIMessage({ action = 'holdProgress', progress = math.min(100.0, (elapsed / durationMs) * 100.0) })

        if elapsed >= durationMs then
            completed = true
            break
        end
    end

    ClearPedTasks(ped)
    holding = false
    SendNUIMessage({ action = 'holdEnd' })

    if shocked then
        notify('You got shocked! The repair failed.', 'error')
        ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.4)
        SetPedToRagdoll(ped, 1500, 1500, 0, false, false, false)
        SetEntityHealth(ped, math.max(GetEntityHealth(ped) - 15, 105))
    end

    -- Require E to be released before another hold can start. Otherwise,
    -- finishing one repair while still physically holding E immediately
    -- re-triggers a second hold on the same target before the server has
    -- even responded and refreshed it -- one press repairing two.
    while IsControlPressed(0, Config.interactKey) do Wait(0) end

    return completed
end

-- Thin vertical beam topped with a downward chevron and a floating
-- DESTINATION/distance label, visible from far away like a GPS waypoint.
--
-- DrawMarker meshes (the chevron) stop rendering past roughly 100-150 units
-- from the camera -- a native GTA limitation, not a bug -- so the tall shaft
-- itself is drawn with DrawLine instead, a cheap primitive that keeps
-- rendering from far away. The chevron mesh is only drawn once actually
-- close, and the projected 3D text works at any distance the point is on
-- screen since it is pure 2D projection, not a culled world mesh.
local function groundZAt(coords)
    local found, z = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 5.0, false)
    if found then return z end
    return coords.z
end

local function drawDestinationBeaconUnsafe(coords, distance)
    local beacon = Config.DestinationBeacon
    local color = beacon.color or { r = 255, g = 201, b = 77 }
    local height = tonumber(beacon.height) or 120.0
    local baseZ = groundZAt(coords)
    local topZ = baseZ + height

    DrawLine(coords.x, coords.y, baseZ, coords.x, coords.y, topZ, color.r, color.g, color.b, 200)

    if distance < 150.0 then
        local chevronScale = beacon.chevronScale or 1.05
        DrawMarker(beacon.chevronType or 2, coords.x, coords.y, topZ, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
            chevronScale, chevronScale, chevronScale * 0.85,
            color.r, color.g, color.b, 235, true, true, 2, false, nil, nil, false)
    end

    local onScreen, sx, sy = World3dToScreen2d(coords.x, coords.y, topZ + 1.0)
    if onScreen then
        SetTextScale(0.34, 0.34)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 220)
        SetTextDropShadow(0, 0, 0, 55)
        SetTextEdge(2, 0, 0, 0, 160)
        SetTextDropShadow()
        SetTextOutline()
        SetTextEntry('STRING')
        SetTextCentre(1)
        AddTextComponentString(('%s~n~%dm'):format(beacon.label or 'DESTINATION', math.floor(distance)))
        DrawText(sx, sy)
    end
end

local beaconErrorLogged = false

local function drawDestinationBeacon(coords, distance)
    local ok, err = pcall(drawDestinationBeaconUnsafe, coords, distance)
    if not ok and not beaconErrorLogged then
        beaconErrorLogged = true
        print('[CM-ELECTRICIAN] destination beacon draw error: ' .. tostring(err))
    end
end

-- Beacons stay visible up to this far away (matches native GTA draw distance
-- for tall markers); the hold-to-repair interaction still only offers up close.
local BEACON_MAX_DISTANCE = 1800.0

-- Once leveled past the panels, they become an optional side-task rather
-- than the main objective, so their beacon only shows up close instead of
-- pulling attention across the map while working elsewhere (plates/outages).
local PANEL_NEAR_ONLY_DISTANCE = 30.0

-- Level 1: switchboard panel repairs (several random targets at once --
-- draws a beacon toward each in range, but only the nearest one in
-- interact range is offered for the hold).
CreateThread(function()
    while true do
        local wait = 500

        if employed and #panelTargets > 0 and not menuOpen and not holding then
            local coords = GetEntityCoords(PlayerPedId())
            local maxDistance = level >= 2 and PANEL_NEAR_ONLY_DISTANCE or BEACON_MAX_DISTANCE
            local nearestIndex, nearestDistance = nil, nil

            for _, index in ipairs(panelTargets) do
                local point = Config.Panels[index]
                local distance = #(coords - point)

                if distance < maxDistance then
                    wait = 0
                    drawDestinationBeacon(point, distance)
                end

                if distance < 1.3 and (not nearestDistance or distance < nearestDistance) then
                    nearestIndex, nearestDistance = index, distance
                end
            end

            if nearestIndex then
                sendInteraction(true, 'Switchboard Panel', 'Hold to repair panel', ('Panels fixed: %d'):format(panelsCount))
                if IsControlPressed(0, Config.interactKey) then
                    if performHold(Config.Hold.panelMs, Config.ShockChance.panel) then
                        TriggerServerEvent('cm-electrician:server:fixPanel', nearestIndex)
                    end
                end
            elseif promptTitle == 'Switchboard Panel' then
                sendInteraction(false)
            end
        end

        Wait(wait)
    end
end)

-- Level 2: city deposit-plate repairs (several random targets at once).
CreateThread(function()
    while true do
        local wait = 800

        if employed and #plateTargets > 0 and not menuOpen and not holding and level >= 2 then
            local coords = GetEntityCoords(PlayerPedId())
            local nearestIndex, nearestDistance = nil, nil

            for _, index in ipairs(plateTargets) do
                local point = Config.Plates[index]
                local distance = #(coords - point)

                if distance < BEACON_MAX_DISTANCE then
                    wait = 0
                    drawDestinationBeacon(point, distance)
                end

                if distance < 1.4 and (not nearestDistance or distance < nearestDistance) then
                    nearestIndex, nearestDistance = index, distance
                end
            end

            if nearestIndex then
                sendInteraction(true, 'Deposit Plate', 'Hold to repair deposit plate', ('Plates fixed: %d'):format(platesCount))
                if IsControlPressed(0, Config.interactKey) then
                    if performHold(Config.Hold.plateMs, Config.ShockChance.plate) then
                        TriggerServerEvent('cm-electrician:server:fixPlate', nearestIndex)
                    end
                end
            elseif promptTitle == 'Deposit Plate' then
                sendInteraction(false)
            end
        end

        Wait(wait)
    end
end)

-- Level 3: city power-outage response.
CreateThread(function()
    while true do
        local wait = 1000
        local canRespond = outageActive and outageLocation and employed and not menuOpen and not holding
            and level >= (Config.PowerOutage.unlockLevel or 3)
        local shown = false

        if canRespond then
            local coords = GetEntityCoords(PlayerPedId())
            local distance = #(coords - outageLocation)

            if distance < BEACON_MAX_DISTANCE then
                wait = 0
                drawDestinationBeacon(outageLocation, distance)

                if distance < 2.2 then
                    shown = true
                    sendInteraction(true, 'Power Outage', 'Hold to fix the outage', 'City-wide power restoration')
                    if IsControlPressed(0, Config.interactKey) then
                        if performHold(Config.Hold.outageMs, Config.ShockChance.outage) then
                            TriggerServerEvent('cm-electrician:server:fixOutage')
                        end
                    end
                end
            end
        end

        if not shown and promptTitle == 'Power Outage' then
            sendInteraction(false)
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    clearPanelTargets()
    clearPlateTargets()
    endShift()
    if lightsOff then SetArtificialLightsState(false) end
end)

-- ---------------------------------------------------------------------------
-- Accessors for client/npc.lua, which handles the switchboard NPC's
-- interact prompt and cinematic dialogue (job sign-up/resignation and
-- service-truck rental) via cm-ui, but has no access to this file's locals.
-- ---------------------------------------------------------------------------

CMElectrician.Client.IsEmployed = function() return employed end
CMElectrician.Client.GetLevel = function() return level end
CMElectrician.Client.IsMenuOpen = function() return menuOpen end
CMElectrician.Client.IsVehicleActive = function() return jobVehicleActive end
CMElectrician.Client.OpenMenu = openMenu
CMElectrician.Client.RequestEmployment = function(wantEmployed)
    TriggerServerEvent('cm-electrician:server:setEmployed', wantEmployed == true)
end
CMElectrician.Client.RequestTruck = requestTruck
