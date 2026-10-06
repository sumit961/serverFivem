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
local forceCancelRepair = false
local cancelActiveRepair -- forward-declared; defined alongside the repair session logic below

local panelTargets, panelBlips = {}, {}
local plateTargets, plateBlips = {}, {}

-- World repair prompts are shown through cm-ui's shared interact component,
-- each with its own owner so hiding one can never hide another (see
-- resources/[core]/cm-ui/client/interact.lua). The NPC keeps its own
-- separate owner in client/npc.lua.
local INTERACT_OWNER_PANEL = 'cm-electrician:panel'
local INTERACT_OWNER_PLATE = 'cm-electrician:plate'
local INTERACT_OWNER_OUTAGE = 'cm-electrician:outage'
local qaInteraction = { visible = false }

local function clearQaInteraction()
    qaInteraction = { visible = false }
end

local function dbg(...)
    if Config.Debug then print('[CM-ELECTRICIAN]', ...) end
end

local function hideAllTaskPrompts()
    clearQaInteraction()
    if GetResourceState('cm-ui') ~= 'started' then return end
    exports['cm-ui']:HideInteract(INTERACT_OWNER_PANEL)
    exports['cm-ui']:HideInteract(INTERACT_OWNER_PLATE)
    exports['cm-ui']:HideInteract(INTERACT_OWNER_OUTAGE)
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
-- Panel/deposit-plate task blips. The SERVER decides which indices are
-- active (server/main.lua) -- this file only ever renders whatever full list
-- it is sent via cm-electrician:client:assignments. It never picks a target
-- on its own.
-- ---------------------------------------------------------------------------

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

-- Numbers each active blip 1..N in its map icon so multiple simultaneous
-- panels/plates are distinguishable at a glance instead of showing as
-- identical unlabeled wrench icons.
local function renumberBlips(targets, blips)
    for i, index in ipairs(targets) do
        local blip = blips[index]
        if blip and DoesBlipExist(blip) then
            ShowNumberOnBlip(blip, i)
        end
    end
end

local function clearTargets(targets, blips)
    for index in pairs(blips) do
        removeTaskBlip(blips[index])
        blips[index] = nil
    end
    for i = #targets, 1, -1 do targets[i] = nil end
end

-- Diffs the server's authoritative index list against the blips we're
-- currently showing: removes anything no longer assigned, adds anything new.
local function applyTargets(list, targets, blips, def, indices)
    local wanted = {}
    for _, idx in ipairs(indices or {}) do wanted[tonumber(idx)] = true end

    for i = #targets, 1, -1 do
        local idx = targets[i]
        if not wanted[idx] then
            removeTaskBlip(blips[idx])
            blips[idx] = nil
            table.remove(targets, i)
        end
    end

    for idx in pairs(wanted) do
        if not blips[idx] and list[idx] then
            targets[#targets + 1] = idx
            blips[idx] = createTaskBlip(list[idx], def)
        end
    end

    renumberBlips(targets, blips)
end

local function applyPanelTargets(indices)
    applyTargets(Config.Panels, panelTargets, panelBlips, Config.TaskBlip.panel, indices)
end

local function applyPlateTargets(indices)
    applyTargets(Config.Plates, plateTargets, plateBlips, Config.TaskBlip.plate, indices)
end

local function clearPanelTargets()
    clearTargets(panelTargets, panelBlips)
end

local function clearPlateTargets()
    clearTargets(plateTargets, plateBlips)
end

RegisterNetEvent('cm-electrician:client:assignments', function(data)
    data = type(data) == 'table' and data or {}
    applyPanelTargets(data.panels)
    applyPlateTargets(data.plates)
end)

-- ---------------------------------------------------------------------------
-- Employment menu.
-- ---------------------------------------------------------------------------

local function openMenu()
    if menuOpen then return end
    if holding then return end -- can't fiddle with the menu mid-repair-hold
    menuOpen = true
    hideAllTaskPrompts()

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
end)

RegisterNetEvent('cm-electrician:client:employedSet', function(state, reason)
    local wasEmployed = employed
    employed = state == true

    if employed and not wasEmployed then
        beginShift()
        TriggerServerEvent('cm-electrician:server:requestStatus')
    elseif not employed and wasEmployed then
        endShift()
        clearPanelTargets()
        clearPlateTargets()
        returnJobVehicle()
        cancelActiveRepair()
        hideAllTaskPrompts()
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
    updateJobHud()
end)

RegisterNetEvent('cm-electrician:client:plateResult', function(data)
    data = type(data) == 'table' and data or {}
    platesCount = tonumber(data.plates) or platesCount
    level = tonumber(data.level) or level
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
-- are left alone. This is a convenience, not a security boundary -- the
-- server independently validates distance on every repair anyway.
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

-- Dying while on duty is handled server-side (cm-playerdata's death event
-- ends the shift authoritatively and pushes employedSet(false) back down),
-- so there is no client-side death polling here any more.

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

-- ---------------------------------------------------------------------------
-- Repair session: BEGIN/COMPLETE/CANCEL round trip with the server. The
-- server decides shock, verifies minimum hold duration, and is the only
-- thing that can grant a reward -- this file just plays the visuals and
-- reports what happened (held to completion, released early, or shocked).
-- ---------------------------------------------------------------------------

local awaitingRepairBegin = false
local activeRepair = nil

-- Sent once per E press (IsControlJustPressed at the call site, not a
-- continuous poll) -- the server is the one that decides whether this
-- becomes an authorized hold at all; nothing here runs a hold before that.
local function requestRepair(taskType, index)
    if holding or awaitingRepairBegin or activeRepair then return end
    awaitingRepairBegin = true
    dbg(('begin_repair_sent type=%s index=%s'):format(tostring(taskType), tostring(index or false)))
    TriggerServerEvent('cm-electrician:server:beginRepair', taskType, index or false)

    -- If the server silently rejects the request (distance/level/cooldown
    -- failures notify but don't send repairBegin), this clears the pending
    -- flag so the player can try again instead of getting stuck.
    CreateThread(function()
        Wait(2500)
        if awaitingRepairBegin and not activeRepair then
            awaitingRepairBegin = false
        end
    end)
end

-- shockAtMs (if set by the server) is a fixed point during the hold rather
-- than always right at the start, so an unlucky attempt doesn't just read as
-- an instant, guaranteed-early bail. Purely cosmetic here -- the server
-- independently rejects a shocked attempt at COMPLETE regardless of what we
-- report.
local function runRepairHold(data)
    local durationMs = tonumber(data.durationMs) or 3000
    local shockAtMs = tonumber(data.shockAtMs)
    local start = GetGameTimer()
    holding = true
    forceCancelRepair = false
    dbg(('hold_started token=%s'):format(tostring(data.token)))
    SendNUIMessage({ action = 'holdStart' })

    -- Native welding scenario (built-in sparks VFX) plays while the repair is
    -- held, instead of relying on a separate loaded anim dictionary.
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_WELDING', 0, true)

    local outcome = 'cancelled'
    while IsControlPressed(0, Config.interactKey) do
        if forceCancelRepair then break end
        Wait(0)
        local elapsed = GetGameTimer() - start

        if shockAtMs and elapsed >= shockAtMs then
            outcome = 'shocked'
            break
        end

        SendNUIMessage({ action = 'holdProgress', progress = math.min(100.0, (elapsed / durationMs) * 100.0) })

        if elapsed >= durationMs then
            outcome = 'completed'
            break
        end
    end

    local wasForceCancelled = forceCancelRepair
    forceCancelRepair = false

    ClearPedTasks(ped)
    holding = false
    SendNUIMessage({ action = 'holdEnd' })

    if outcome == 'shocked' then
        notify('You got shocked! The repair failed.', 'error')
        ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.4)
        SetPedToRagdoll(ped, 1500, 1500, 0, false, false, false)
        SetEntityHealth(ped, math.max(GetEntityHealth(ped) - 15, 105))
    end

    -- Require E to be released before another hold can start. Otherwise,
    -- finishing one repair while still physically holding E immediately
    -- re-triggers a second request on the same target before the server has
    -- even responded and refreshed it -- one press repairing two. Skipped on
    -- a forced cancel (shift ended, death, etc.) so cleanup isn't stuck
    -- waiting on a key release that may never come from this menu/state.
    if not wasForceCancelled then
        while IsControlPressed(0, Config.interactKey) do Wait(0) end
    end

    local token = data.token
    activeRepair = nil

    dbg(('hold_completed token=%s outcome=%s'):format(tostring(token), outcome))

    if outcome == 'completed' then
        TriggerServerEvent('cm-electrician:server:completeRepair', token)
    else
        TriggerServerEvent('cm-electrician:server:cancelRepair', token)
    end
end

RegisterNetEvent('cm-electrician:client:repairBegin', function(data)
    awaitingRepairBegin = false
    if type(data) ~= 'table' or not data.token then return end
    dbg(('repair_authorized type=%s token=%s duration=%s shockAt=%s'):format(
        tostring(data.type), tostring(data.token), tostring(data.durationMs), tostring(data.shockAtMs)))
    activeRepair = data
    runRepairHold(data)
end)

-- Forces the current hold (if any) to end as a cancel, for cleanup paths
-- (shift end, death, character switch, resource stop) that must not leave a
-- welding animation/hold bar running after the underlying session is gone.
cancelActiveRepair = function()
    if holding then
        forceCancelRepair = true
        return
    end
    if activeRepair then
        local token = activeRepair.token
        activeRepair = nil
        TriggerServerEvent('cm-electrician:server:cancelRepair', token)
    end
    awaitingRepairBegin = false
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

-- Small hysteresis on the repair prompt itself so standing right at the edge
-- of range doesn't flicker the prompt on/off: shows at the tighter distance,
-- only hides once past the looser one. This is purely a UI trigger -- the
-- server independently re-validates distance with its own (larger) security
-- radius at both begin and complete, so widening this never changes what
-- the server will actually accept.
local REPAIR_SHOW_DISTANCE = 1.5
local REPAIR_HIDE_DISTANCE = 1.9
local OUTAGE_SHOW_DISTANCE = 2.0
local OUTAGE_HIDE_DISTANCE = 2.5

-- Level 1: switchboard panel repairs (several server-assigned targets at
-- once -- draws a beacon toward each in range, but only the nearest one in
-- interact range is offered for the hold, through cm-ui's shared prompt).
CreateThread(function()
    if GetResourceState('cm-ui') ~= 'started' then
        print('[CM-ELECTRICIAN] cm-ui is not running -- panel repair prompts need it.')
        return
    end

    local promptShown = false

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

                if not nearestDistance or distance < nearestDistance then
                    nearestIndex, nearestDistance = index, distance
                end
            end

            local threshold = promptShown and REPAIR_HIDE_DISTANCE or REPAIR_SHOW_DISTANCE
            local inRange = nearestIndex and nearestDistance and nearestDistance < threshold

            if inRange then
                if not promptShown then
                    dbg(('panel_candidate index=%d distance=%.2f'):format(nearestIndex, nearestDistance))
                end
                promptShown = true
                exports['cm-ui']:ShowInteract({
                    owner = INTERACT_OWNER_PANEL,
                    priority = 20,
                    key = Config.interactKeyLabel or 'E',
                    label = 'HOLD TO REPAIR',
                    name = 'Switchboard Panel',
                    role = ('PANELS REPAIRED %d'):format(panelsCount),
                })
                qaInteraction = {
                    visible = true,
                    owner = INTERACT_OWNER_PANEL,
                    action = 'HOLD TO REPAIR',
                    key = Config.interactKeyLabel or 'E',
                    index = nearestIndex,
                }

                if IsControlJustPressed(0, Config.interactKey) then
                    dbg(('repair_input type=panel index=%d pressed=true'):format(nearestIndex))
                    requestRepair('panel', nearestIndex)
                end
            elseif promptShown then
                promptShown = false
                clearQaInteraction()
                exports['cm-ui']:HideInteract(INTERACT_OWNER_PANEL)
            end
        elseif promptShown then
            promptShown = false
            clearQaInteraction()
            exports['cm-ui']:HideInteract(INTERACT_OWNER_PANEL)
        end

        Wait(wait)
    end
end)

-- Level 2: city deposit-plate repairs (several server-assigned targets at once).
CreateThread(function()
    if GetResourceState('cm-ui') ~= 'started' then
        print('[CM-ELECTRICIAN] cm-ui is not running -- deposit plate repair prompts need it.')
        return
    end

    local promptShown = false

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

                if not nearestDistance or distance < nearestDistance then
                    nearestIndex, nearestDistance = index, distance
                end
            end

            local threshold = promptShown and REPAIR_HIDE_DISTANCE or REPAIR_SHOW_DISTANCE
            local inRange = nearestIndex and nearestDistance and nearestDistance < threshold

            if inRange then
                if not promptShown then
                    dbg(('plate_candidate index=%d distance=%.2f'):format(nearestIndex, nearestDistance))
                end
                promptShown = true
                exports['cm-ui']:ShowInteract({
                    owner = INTERACT_OWNER_PLATE,
                    priority = 20,
                    key = Config.interactKeyLabel or 'E',
                    label = 'HOLD TO REPAIR',
                    name = 'Deposit Plate',
                    role = ('PLATES REPAIRED %d'):format(platesCount),
                })

                if IsControlJustPressed(0, Config.interactKey) then
                    dbg(('repair_input type=plate index=%d pressed=true'):format(nearestIndex))
                    requestRepair('plate', nearestIndex)
                end
            elseif promptShown then
                promptShown = false
                exports['cm-ui']:HideInteract(INTERACT_OWNER_PLATE)
            end
        elseif promptShown then
            promptShown = false
            exports['cm-ui']:HideInteract(INTERACT_OWNER_PLATE)
        end

        Wait(wait)
    end
end)

-- Level 3: city power-outage response.
CreateThread(function()
    if GetResourceState('cm-ui') ~= 'started' then
        print('[CM-ELECTRICIAN] cm-ui is not running -- outage repair prompts need it.')
        return
    end

    local promptShown = false

    while true do
        local wait = 1000
        local canRespond = outageActive and outageLocation and employed and not menuOpen and not holding
            and level >= (Config.PowerOutage.unlockLevel or 3)

        if canRespond then
            local coords = GetEntityCoords(PlayerPedId())
            local distance = #(coords - outageLocation)

            if distance < BEACON_MAX_DISTANCE then
                wait = 0
                drawDestinationBeacon(outageLocation, distance)
            end

            local threshold = promptShown and OUTAGE_HIDE_DISTANCE or OUTAGE_SHOW_DISTANCE
            local inRange = distance < threshold

            if inRange then
                if not promptShown then
                    dbg(('outage_candidate distance=%.2f'):format(distance))
                end
                promptShown = true
                exports['cm-ui']:ShowInteract({
                    owner = INTERACT_OWNER_OUTAGE,
                    priority = 20,
                    key = Config.interactKeyLabel or 'E',
                    label = 'HOLD TO RESTORE POWER',
                    name = 'Power Outage',
                    role = 'CITY-WIDE POWER RESTORATION',
                })

                if IsControlJustPressed(0, Config.interactKey) then
                    dbg('repair_input type=outage pressed=true')
                    requestRepair('outage')
                end
            elseif promptShown then
                promptShown = false
                exports['cm-ui']:HideInteract(INTERACT_OWNER_OUTAGE)
            end
        elseif promptShown then
            promptShown = false
            exports['cm-ui']:HideInteract(INTERACT_OWNER_OUTAGE)
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
    cancelActiveRepair()
    hideAllTaskPrompts()
    if lightsOff then SetArtificialLightsState(false) end
end)

exports('QaInteractionSnapshot', function()
    if GetInvokingResource() ~= 'cm-qa' then return false, 'forbidden' end
    return true, {
        visible = qaInteraction.visible == true,
        owner = qaInteraction.owner,
        action = qaInteraction.action,
        key = qaInteraction.key,
        index = qaInteraction.index,
    }
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
