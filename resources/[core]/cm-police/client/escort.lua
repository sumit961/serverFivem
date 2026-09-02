-- cm-police contextual cuffed-suspect interaction (E key). Additive on top
-- of the G-menu's own Grab/Release/Put in Vehicle/Take Out options
-- (client/gmenu.lua, server/cuffs.lua) -- this only adds a faster, always-
-- on-screen contextual prompt (mirrors cm-ems/client/stretcher.lua's own
-- proximity-prompt pattern: one key, no menu, no re-aiming) that fires the
-- exact same server-validated extension actions the G-menu already uses,
-- the same `TriggerServerEvent('cm-playerdata:server:extensionInteraction',
-- ...)` call client/cuffs.lua's X-key already makes. No new server logic.

local function eligible()
    if IsPedInAnyVehicle(PlayerPedId(), false) then return false end
    local state = LocalPlayer.state.cmPolice
    if type(state) ~= 'table' or state.onDuty ~= true then return false end
    local permissions = state.permissions or {}
    return state.isLeader == true or permissions['police.cuff'] == true
end

local function fireExtension(targetServerId, action)
    TriggerServerEvent('cm-playerdata:server:extensionInteraction', targetServerId, action, {})
end

local function nearestCuffedPlayer(myCoords, maxDistance)
    local myPlayerId = PlayerId()
    local closestServerId, closestDist = nil, maxDistance
    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= myPlayerId then
            local targetPed = GetPlayerPed(playerId)
            if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
                local serverId = GetPlayerServerId(playerId)
                if Player(serverId).state.cmCuffed == true then
                    local dist = #(myCoords - GetEntityCoords(targetPed))
                    if dist <= closestDist then closestServerId, closestDist = serverId, dist end
                end
            end
        end
    end
    return closestServerId
end

-- Cuffed player already seated in a vehicle I'm near, regardless of who (if
-- anyone) is currently escorting them -- Take Out doesn't require me to be
-- the one who put them in.
local function nearbySeatedCuffedPlayer(myCoords, maxDistance)
    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local targetPed = GetPlayerPed(playerId)
            if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) and IsPedInAnyVehicle(targetPed, false) then
                local serverId = GetPlayerServerId(playerId)
                if Player(serverId).state.cmCuffed == true then
                    local vehicle = GetVehiclePedIsIn(targetPed, false)
                    if vehicle ~= 0 and #(myCoords - GetEntityCoords(vehicle)) <= maxDistance then return serverId end
                end
            end
        end
    end
    return nil
end

local function nearbyFreeSeatVehicle(myCoords, maxDistance)
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and #(myCoords - GetEntityCoords(vehicle)) <= maxDistance then
            local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)
            for index = 0, maxSeats - 1 do
                if IsVehicleSeatFree(vehicle, index) then return vehicle end
            end
        end
    end
    return nil
end

-- { serverId, primaryAction, secondaryAction } -- recomputed every scan
-- tick; polled for E/Backspace every frame so a press is never missed
-- between scans.
local currentPrompt = nil

local function rescan()
    if not eligible() then return nil end

    local myCoords = GetEntityCoords(PlayerPedId())
    local vehicleDistance = Config.Cuffs.VehicleSeatDistance or 6.0

    local seatedTarget = nearbySeatedCuffedPlayer(myCoords, vehicleDistance)
    if seatedTarget then
        PoliceShowHint('[E] Take Suspect Out of Vehicle')
        return { serverId = seatedTarget, primaryAction = 'police_take_out_vehicle' }
    end

    local targetServerId = nearestCuffedPlayer(myCoords, Config.Cuffs.InteractDistance or 2.5)
    if not targetServerId then return nil end

    local escortedBy = Player(targetServerId).state.cmEscortedBy
    local iAmEscorting = type(escortedBy) == 'number' and escortedBy == GetPlayerServerId(PlayerId())
    local anyoneEscorting = type(escortedBy) == 'number' and escortedBy > 0

    if iAmEscorting then
        if nearbyFreeSeatVehicle(myCoords, vehicleDistance) then
            PoliceShowHint('[E] Put Suspect in Vehicle  ·  [Backspace] Release')
            return { serverId = targetServerId, primaryAction = 'police_put_in_vehicle', secondaryAction = 'police_escort_release' }
        end
        PoliceShowHint('[Backspace] Release Suspect')
        return { serverId = targetServerId, secondaryAction = 'police_escort_release' }
    elseif not anyoneEscorting then
        PoliceShowHint('[E] Grab Suspect')
        return { serverId = targetServerId, primaryAction = 'police_escort_grab' }
    end

    return nil
end

CreateThread(function()
    local nextScan = 0
    while true do
        -- Per-frame only while a prompt is on screen, because that is the only
        -- time IsControlJustPressed below needs polling. This thread used to
        -- run at Wait(0) permanently for every player on the server, including
        -- civilians who will never be law enforcement -- a constant baseline
        -- cost in resmon for no benefit. The 250ms rescan cadence below is
        -- unchanged, and prompt response time is identical.
        Wait(currentPrompt and 0 or 250)
        local now = GetGameTimer()
        if now >= nextScan then
            nextScan = now + 250
            local next = rescan()
            if not next and currentPrompt then PoliceHideHint() end
            currentPrompt = next
        end

        if currentPrompt then
            if currentPrompt.primaryAction and IsControlJustPressed(0, 38) then -- INPUT_PICKUP / E
                fireExtension(currentPrompt.serverId, currentPrompt.primaryAction)
            elseif currentPrompt.secondaryAction and IsControlJustPressed(0, 194) then -- INPUT_FRONTEND_DELETE / Backspace
                fireExtension(currentPrompt.serverId, currentPrompt.secondaryAction)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and currentPrompt then PoliceHideHint() end
end)
