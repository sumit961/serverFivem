local U = CMVehicles.Utils
local Config = CMVehicles.Config

-- ---------------------------------------------------------------------------
-- Single-prompt interaction arbiter (mirror of cm-playerdata).
-- When a player AND a vehicle are both targeted, only one G should show.
-- cm-playerdata publishes LocalPlayer.state.cmPlayerInteractDist; we publish
-- LocalPlayer.state.cmVehicleInteractDist and yield to the player using the SAME
-- settings, pulled live from cm-playerdata so they can never drift out of sync.
-- ---------------------------------------------------------------------------
local arbiter = { enabled = true, priority = 'closest', tie = 0.1 }

CreateThread(function()
    while true do
        if GetResourceState('cm-playerdata') == 'started' then
            local ok, s = pcall(function() return exports['cm-playerdata']:GetInteractionArbiter() end)
            if ok and type(s) == 'table' then
                arbiter.enabled = s.enabled ~= false
                arbiter.priority = tostring(s.priority or 'closest')
                arbiter.tie = tonumber(s.tie) or 0.1
            end
        end
        Wait(5000)
    end
end)

local lastVehInteractDist = false
local function PublishVehicleInteractDist(dist)
    local v = (type(dist) == 'number') and dist or false
    if v ~= lastVehInteractDist then
        lastVehInteractDist = v
        LocalPlayer.state:set('cmVehicleInteractDist', v, false) -- local only
    end
end

-- True when the player menu owns the prompt this frame, so we hide ours / don't open.
local function VehicleShouldYield(myVehDist)
    if not arbiter.enabled then return false end
    local pDist = LocalPlayer.state.cmPlayerInteractDist
    if type(pDist) ~= 'number' then return false end -- player has no target -> we're free

    local mode = arbiter.priority
    if mode == 'player' then return true end          -- player always wins when it has a target
    if mode == 'vehicle' then return false end         -- vehicle always wins when it has a target

    if type(myVehDist) ~= 'number' then return true end
    return pDist <= (myVehDist + (arbiter.tie or 0.1)) -- 'closest'; player wins near-ties
end

local function playKeyFob()
    local ped = PlayerPedId()
    RequestAnimDict('anim@mp_player_intmenu@key_fob@')
    while not HasAnimDictLoaded('anim@mp_player_intmenu@key_fob@') do Wait(0) end
    TaskPlayAnim(ped, 'anim@mp_player_intmenu@key_fob@', 'fob_click', 8.0, -8.0, 800, 48, 0, false, false, false)
end

local function blink(vehicle)
    CreateThread(function()
        for _ = 1, 2 do
            SetVehicleIndicatorLights(vehicle, 0, true)
            SetVehicleIndicatorLights(vehicle, 1, true)
            StartVehicleHorn(vehicle, 80, joaat('HELDDOWN'), false)
            Wait(220)
            SetVehicleIndicatorLights(vehicle, 0, false)
            SetVehicleIndicatorLights(vehicle, 1, false)
            Wait(220)
        end
    end)
end

local function getMenuVehicleFromData(data)
    data = type(data) == 'table' and data or {}
    local plate = U.NormalizePlate(data.plate or (CMVehicles.Client.CurrentMenuContext and CMVehicles.Client.CurrentMenuContext.plate))
    local netId = tonumber(data.netId or (CMVehicles.Client.CurrentMenuContext and CMVehicles.Client.CurrentMenuContext.netId))
    local veh = nil
    if netId then veh = NetworkGetEntityFromNetworkId(netId) end
    if not veh or veh == 0 then veh = CMVehicles.Client.FindVehicleByPlate(plate) end
    if not veh or veh == 0 then veh = CMVehicles.Client.GetActionVehicle(true) end
    if veh and veh ~= 0 then
        plate = CMVehicles.Client.VehiclePlate(veh)
        netId = CMVehicles.Client.SafeNetId(veh)
    end
    return veh, plate, netId
end

local function serverIdForPed(targetPed)
    if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) then return nil, nil end
    local player = NetworkGetPlayerIndexFromPed(targetPed)
    if player and player > -1 then
        return GetPlayerServerId(player), GetPlayerName(player)
    end
    return nil, nil
end

local function nearbyPlayersForVehicle(vehicle, maxDistance)
    local ped = PlayerPedId()
    local myPlayer = PlayerId()
    local myCoords = GetEntityCoords(ped)
    local vehCoords = vehicle and vehicle ~= 0 and GetEntityCoords(vehicle) or myCoords
    local distLimit = tonumber(maxDistance) or tonumber(Config.Interaction.keyGiveDistance) or 6.0
    local list = {}

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= myPlayer then
            local targetPed = GetPlayerPed(player)
            if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
                local targetCoords = GetEntityCoords(targetPed)
                local playerDist = #(targetCoords - myCoords)
                local carDist = #(targetCoords - vehCoords)
                if math.min(playerDist, carDist) <= distLimit then
                    list[#list + 1] = {
                        id = GetPlayerServerId(player),
                        name = GetPlayerName(player) or ('Player ' .. tostring(GetPlayerServerId(player))),
                        distance = math.floor(math.min(playerDist, carDist) * 10) / 10
                    }
                end
            end
        end
    end

    table.sort(list, function(a, b) return (a.distance or 999) < (b.distance or 999) end)
    return list
end

local function passengersInVehicle(vehicle)
    local list = {}
    if not vehicle or vehicle == 0 then return list end

    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) or 0
    for seat = 0, math.max(0, seats - 2) do
        local seatPed = GetPedInVehicleSeat(vehicle, seat)
        if seatPed and seatPed ~= 0 then
            local serverId, name = serverIdForPed(seatPed)
            if serverId then
                list[#list + 1] = { id = serverId, name = name or ('Player ' .. tostring(serverId)), seat = seat }
            end
        end
    end

    return list
end

RegisterNetEvent('cm-vehicles:client:lockVisuals', function(plate, netId, locked)
    local veh = netId and NetworkGetEntityFromNetworkId(tonumber(netId)) or nil
    if not veh or veh == 0 then veh = CMVehicles.Client.FindVehicleByPlate(plate) end
    if not veh or veh == 0 then return end
    playKeyFob()
    blink(veh)
    CMVehicles.Client.ApplyLock(veh, locked == true)
end)

RegisterNetEvent('cm-vehicles:client:setVehicleState', function(plate, netId, state)
    plate = U.NormalizePlate(plate)
    state = type(state) == 'table' and state or {}
    local veh = netId and NetworkGetEntityFromNetworkId(tonumber(netId)) or nil
    if not veh or veh == 0 then veh = CMVehicles.Client.FindVehicleByPlate(plate) end
    if not veh or veh == 0 then return end
    if state.locked ~= nil then CMVehicles.Client.ApplyLock(veh, state.locked == true) end
    if state.trunkOpen ~= nil then
        CMVehicles.Client.OpenTrunks[plate] = state.trunkOpen == true or nil
        if state.trunkOpen then SetVehicleDoorOpen(veh, 5, false, false) else SetVehicleDoorShut(veh, 5, false) end
    end
end)


-- ════════════════════════════════════════════════════════════════════
--  INSTALLED PARTS
--  Reads the upgrade level of every performance + visual slot straight off the
--  car, so the info screen always reflects what is actually fitted (no DB lag).
--  Level is 1-based for display: GTA index -1 = stock, 0 = level 1, and so on.
-- ════════════════════════════════════════════════════════════════════
-- Only the four upgrade paths the player actually cares about.
local PART_SLOTS = {
    { modType = 11, label = 'Engine',       perf = true },
    { modType = 15, label = 'Suspension',   perf = true },
    { modType = 13, label = 'Transmission', perf = true },
}

function CMVehicles.Client.ReadInstalledParts(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return {} end
    SetVehicleModKit(veh, 0)

    local out = {}

    for _, def in ipairs(PART_SLOTS) do
        local max = GetNumVehicleMods(veh, def.modType) or 0
        local idx = GetVehicleMod(veh, def.modType)
        idx = (idx == nil) and -1 or idx
        local level = (idx < 0) and 0 or (idx + 1)

        out[#out + 1] = {
            label = def.label,
            level = level,
            max = (max > 0) and max or 4,
            text = (level == 0) and 'Stock' or ('Level %d'):format(level),
        }
    end

    -- Tyres are a synthetic level (GTA has no tyre mod slot), stored in the
    -- saved mods and mirrored on the cmTyreLevel state bag.
    local tyre = CMVehicles.Client.GetTyreLevel and CMVehicles.Client.GetTyreLevel(veh) or 0
    out[#out + 1] = {
        label = 'Tyres',
        level = tyre,
        max = 4,
        text = (tyre == 0) and 'Stock' or ('Level %d'):format(tyre),
    }

    return out
end

RegisterNetEvent('cm-vehicles:client:openMenu', function(info)
    info = type(info) == 'table' and info or {}
    info.context = CMVehicles.Client.CurrentMenuContext or {}
    info.netId = tonumber(info.netId or info.context.netId)

    -- Use live entity values for UI when the vehicle is spawned. The DB row can be
    -- up to one save interval behind, and GTA native fuel can default around 60
    -- unless we apply cmFuel.
    local veh = info.netId and NetworkGetEntityFromNetworkId(info.netId) or nil
    if (not veh or veh == 0 or not DoesEntityExist(veh)) and info.plate then veh = CMVehicles.Client.FindVehicleByPlate(info.plate) end
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        if GetResourceState('cm-police') == 'started' then
            local ok, target = pcall(function()
                return exports['cm-police']:GetDraggedSuspectForVehicle(veh)
            end)
            info.policeDraggedSuspect = ok and tonumber(target) or nil
            local occupantOk, occupant = pcall(function()
                return exports['cm-police']:GetCuffedSuspectInVehicle(veh)
            end)
            info.policeCuffedOccupant = occupantOk and tonumber(occupant) or nil
        end
        info.fuel = math.floor(((CMVehicles.Client.GetVehicleFuel(veh) or 100.0) * 10) + 0.5) / 10
        local state = Entity(veh).state
        local nativeEngine = tonumber(GetVehicleEngineHealth(veh)) or 0.0
        local nativeBody = tonumber(GetVehicleBodyHealth(veh)) or 0.0
        local nativeTank = tonumber(GetVehiclePetrolTankHealth(veh)) or 0.0
        -- During garage stream-in the native can briefly be zero. Show the
        -- authoritative saved state instead of flashing a false 0% condition.
        info.engineHealth = nativeEngine > 0.0 and nativeEngine
            or tonumber(state.cmEngineHealth) or tonumber(info.engineHealth) or 1000.0
        info.bodyHealth = nativeBody > 0.0 and nativeBody
            or tonumber(state.cmBodyHealth) or tonumber(info.bodyHealth) or 1000.0
        info.tankHealth = nativeTank > 0.0 and nativeTank
            or tonumber(state.cmTankHealth) or tonumber(info.tankHealth) or 1000.0
        info.dirtLevel = GetVehicleDirtLevel(veh)
        info.mileage = CMVehicles.Client.GetVehicleMileage(veh)
        info.racingHarness = CMVehicles.Client.HasRacingHarness(veh)
        info.parts = CMVehicles.Client.ReadInstalledParts(veh)
        -- Current vs stock top speed, so the player can see what tuning bought.
        local base = (GetVehicleEstimatedMaxSpeed(veh) or 0.0)
        local mul = CMVehicles.Client.GetTuningMultiplier(veh)
        if mul > 0 then base = base / mul end
        info.topSpeedStock = math.floor(base * 3.6 + 0.5)
        info.topSpeed = math.floor(base * mul * 3.6 + 0.5)
    else
        -- Entity can be missing on this client near OneSync/routing-bucket boundaries.
        -- Keep the menu stable by falling back to safe DB payload defaults instead of reading a 0 entity.
        info.fuel = tonumber(info.fuel) or tonumber(Config.Fuel and Config.Fuel.defaultFuel) or 100.0
        info.engineHealth = tonumber(info.engineHealth) or tonumber(info.engine_health) or 1000.0
        info.bodyHealth = tonumber(info.bodyHealth) or tonumber(info.body_health) or 1000.0
        info.tankHealth = tonumber(info.tankHealth) or tonumber(info.tank_health) or 1000.0
        info.mileage = tonumber(info.mileage) or 0.0
        info.racingHarness = info.racingHarness == true
    end

    CMVehicles.Client.MenuOpen = true
    SetNuiFocus(true, true)
    CMVehicles.Client.Nui('openMenu', { vehicle = info })
end)

-- Vehicle item storage is handled only by cm-inventory now.
-- This legacy event is kept harmless for compatibility with older commands/scripts.
RegisterNetEvent('cm-vehicles:client:openTrunk', function()
    CMVehicles.Client.Notify('Open the trunk, then press I to use cm-inventory.')
end)

RegisterNetEvent('cm-vehicles:client:soldToState', function(netId, amount)
    CMVehicles.Client.CloseNui()
    local veh = netId and NetworkGetEntityFromNetworkId(tonumber(netId)) or nil
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        CMVehicles.Client.HasControl(veh, 1200)
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
        if DoesEntityExist(veh) then DeleteEntity(veh) end
    end
    CMVehicles.Client.Notify(('Vehicle sold to state for $%s.'):format(tostring(amount or 0)))
end)

RegisterNetEvent('cm-vehicles:client:updateTrunk', function()
    -- Removed: trunk inventory UI belongs to cm-inventory.
end)

RegisterCommand('veh_menu', function()
    if CMVehicles.Client.InTrunk then CMVehicles.Client.ExitTrunk(false, false); return end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if veh and veh ~= 0 then
        -- Seated in own vehicle: no player-target conflict, open normally.
        CMVehicles.Client.CurrentMenuContext = CMVehicles.Client.GetVehicleContext(veh, false)
    else
        local lookVeh, lookDist = CMVehicles.Client.GetLookedAtVehicle(tonumber(Config.Interaction.lookDistance) or tonumber(Config.Interaction.distance) or 7.5)
        if lookVeh and lookVeh ~= 0 then
            -- If the player menu owns the prompt this frame, let it handle G instead.
            if VehicleShouldYield(lookDist) then return end
            veh = lookVeh
            CMVehicles.Client.CurrentMenuContext = CMVehicles.Client.GetVehicleContext(veh, true)
        end
    end

    if not veh or veh == 0 then
        return CMVehicles.Client.Notify('Look at the vehicle to open the G menu.')
    end

    local plate = CMVehicles.Client.VehiclePlate(veh)
    local netId = CMVehicles.Client.SafeNetId(veh)
    if not netId then return CMVehicles.Client.Notify('This vehicle is not a networked CM vehicle.') end
    TriggerServerEvent('cm-vehicles:server:registerNetVehicle', plate, netId)
    TriggerServerEvent('cm-vehicles:server:requestInfo', plate, netId)
end, false)
RegisterKeyMapping('veh_menu', 'Vehicle interaction menu', 'keyboard', Config.Controls.menuKey or 'G')

RegisterCommand('veh_lock', function()
    local veh = CMVehicles.Client.GetActionVehicle(true)
    if not veh or veh == 0 then return CMVehicles.Client.Notify('No vehicle nearby.') end
    local plate = CMVehicles.Client.VehiclePlate(veh)
    local netId = CMVehicles.Client.SafeNetId(veh)
    if not netId then return CMVehicles.Client.Notify('This vehicle is not a networked CM vehicle.') end
    TriggerServerEvent('cm-vehicles:server:registerNetVehicle', plate, netId)
    TriggerServerEvent('cm-vehicles:server:toggleLock', plate, netId)
end, false)
RegisterKeyMapping('veh_lock', 'Lock/unlock vehicle', 'keyboard', Config.Controls.lockKey or 'L')

RegisterCommand('vehtrunk', function()
    local veh = CMVehicles.Client.GetActionVehicle(true)
    if not veh or veh == 0 then return CMVehicles.Client.Notify('No vehicle nearby.') end
    local netId = CMVehicles.Client.SafeNetId(veh)
    if not netId then return CMVehicles.Client.Notify('This vehicle is not a networked CM vehicle.') end
    TriggerServerEvent('cm-vehicles:server:toggleTrunkDoor', CMVehicles.Client.VehiclePlate(veh), netId)
end, false)

RegisterCommand('vehmenu', function() ExecuteCommand('veh_menu') end, false)
RegisterCommand('vehlock', function() ExecuteCommand('veh_lock') end, false)

RegisterNUICallback('close', function(_, cb) CMVehicles.Client.CloseNui(); cb({ ok = true }) end)

RegisterNUICallback('requestNearbyPlayers', function(data, cb)
    local veh = getMenuVehicleFromData(data)
    cb({ ok = true, players = nearbyPlayersForVehicle(veh, Config.Interaction.keyGiveDistance or 6.0) })
end)

RegisterNUICallback('requestVehiclePassengers', function(data, cb)
    local veh = getMenuVehicleFromData(data)
    cb({ ok = true, players = passengersInVehicle(veh) })
end)

RegisterNUICallback('vehicleAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    local action = tostring(data.action or '')
    local veh, plate, netId = getMenuVehicleFromData(data)
    local ped = PlayerPedId()
    local inVehicle = IsPedInAnyVehicle(ped, false)

    if action == 'lock' then
        TriggerServerEvent('cm-vehicles:server:toggleLock', plate, netId)
    elseif action == 'engine' then
        ExecuteCommand('cm_engine')
    elseif action == 'trunk' then
        TriggerServerEvent('cm-vehicles:server:toggleTrunkDoor', plate, netId)
    elseif action == 'key' then
        TriggerServerEvent('cm-vehicles:server:giveTempKey', plate, tonumber(data.target))
    elseif action == 'enterTrunk' then
        if inVehicle then
            CMVehicles.Client.Notify('You cannot get in the trunk while inside a vehicle.')
        else
            TriggerServerEvent('cm-vehicles:server:requestEnterTrunk', plate, netId)
            CMVehicles.Client.CloseNui()
        end
    elseif action == 'getOutTrunk' then
        TriggerServerEvent('cm-vehicles:server:forceOutTrunk', plate, netId)
    elseif action == 'ejectPassenger' then
        TriggerServerEvent('cm-vehicles:server:ejectPassenger', plate, netId, tonumber(data.target))
    elseif action == 'policePutDragged' then
        if GetResourceState('cm-police') == 'started' and netId then
            TriggerEvent('cm-police:client:putDraggedInSelectedVehicle', netId)
            CMVehicles.Client.CloseNui()
        end
    elseif action == 'policeRemoveCuffed' then
        if GetResourceState('cm-police') == 'started' and netId then
            TriggerEvent('cm-police:client:removeCuffedFromSelectedVehicle', netId)
            CMVehicles.Client.CloseNui()
        end
    elseif action == 'windows' then
        if veh and veh ~= 0 then for i = 0, 3 do if IsVehicleWindowIntact(veh, i) then RollDownWindow(veh, i) else RollUpWindow(veh, i) end end end
    elseif action == 'doors' then
        if veh and veh ~= 0 then for i = 0, 5 do if GetVehicleDoorAngleRatio(veh, i) > 0.1 then SetVehicleDoorShut(veh, i, false) else SetVehicleDoorOpen(veh, i, false, false) end end end
    elseif action == 'hood' then
        if veh and veh ~= 0 then if GetVehicleDoorAngleRatio(veh, 4) > 0.1 then SetVehicleDoorShut(veh, 4, false) else SetVehicleDoorOpen(veh, 4, false, false) end end
    elseif action == 'neons' then
        if veh and veh ~= 0 then
            local enabled = not IsVehicleNeonLightEnabled(veh, 0)
            local neons = {}
            for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, enabled); neons[i + 1] = enabled end
            TriggerServerEvent('cm-vehicles:server:saveState', CMVehicles.Client.VehicleId(veh), { netId = (CMVehicles.Client.SafeNetId(veh) or 0), neons = neons })
        end
    elseif action == 'refuel' then
        -- Uses a jerry can from the player's inventory. The server checks they
        -- actually have one, consumes it, then tells us to apply the fuel.
        if inVehicle then
            CMVehicles.Client.Notify('Get out of the vehicle to refuel it.')
        elseif not veh or veh == 0 then
            CMVehicles.Client.Notify('No vehicle nearby.')
        else
            TriggerServerEvent('cm-vehicles:server:useServiceItem', 'refuel', plate, netId)
        end
    elseif action == 'repair' then
        -- Uses a repair kit from the player's inventory.
        if inVehicle then
            CMVehicles.Client.Notify('Get out of the vehicle to repair it.')
        elseif not veh or veh == 0 then
            CMVehicles.Client.Notify('No vehicle nearby.')
        else
            TriggerServerEvent('cm-vehicles:server:useServiceItem', 'repair', plate, netId)
        end
    elseif action == 'wash' then
        -- Uses a wash kit from the player's inventory (sponge + bucket).
        if inVehicle then
            CMVehicles.Client.Notify('Get out of the vehicle to wash it.')
        elseif not veh or veh == 0 then
            CMVehicles.Client.Notify('No vehicle nearby.')
        else
            TriggerServerEvent('cm-vehicles:server:useServiceItem', 'wash', plate, netId)
        end
    elseif action == 'charge' then
        CMVehicles.Client.Notify('Charging is only available at an EV charger.')
    elseif action == 'sellState' then
        TriggerServerEvent('cm-vehicles:server:sellToState', plate, netId)
    elseif action == 'drift' then
        CMVehicles.Client.Notify('Drift settings menu is ready in UI. Connect it to your drift/handling resource when that system is added.')
    else
        CMVehicles.Client.Notify('This RP option is coming soon.')
    end
    cb({ ok = true })
end)

-- Removed legacy cm-vehicles trunk item callbacks. All storage movement now goes through cm-inventory.

local function getNearbyOpenTrunkVehicle(maxDistance)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return nil, nil end
    local coords = GetEntityCoords(ped)
    local closest, closestDist = nil, tonumber(maxDistance) or (Config.Interaction.trunkDistance or 4.0)
    for _, veh in ipairs(CMVehicles.Client.GetCachedVehicles()) do
        local plate = CMVehicles.Client.VehiclePlate(veh)
        if plate ~= '' and CMVehicles.Client.OpenTrunks[plate] == true then
            local boot = GetEntityBoneIndexByName(veh, 'boot')
            local target = boot >= 0 and GetWorldPositionOfEntityBone(veh, boot) or GetOffsetFromEntityInWorldCoords(veh, 0.0, -2.5, 0.0)
            local dist = #(coords - target)
            if dist <= closestDist then closest, closestDist = veh, dist end
        end
    end
    return closest, closestDist
end

local function tryOpenNearbyTrunkInventory()
    if CMVehicles.Client.MenuOpen or CMVehicles.Client.InTrunk then return false end
    local veh = getNearbyOpenTrunkVehicle(Config.Interaction.trunkDistance or 4.0)
    if not veh or veh == 0 then return false end
    local plate = CMVehicles.Client.VehiclePlate(veh)
    if plate == '' then return false end
    TriggerServerEvent('cm-vehicles:server:openSharedTrunkInventory', plate, (CMVehicles.Client.SafeNetId(veh) or 0))
    return true
end

exports('TryOpenNearbyTrunkInventory', tryOpenNearbyTrunkInventory)
RegisterCommand('vehtrunkinv', function() if not tryOpenNearbyTrunkInventory() then CMVehicles.Client.Notify('No open trunk nearby.') end end, false)

CreateThread(function()
    while true do
        local sleep = 700
        local vehTargetDist = nil
        if not CMVehicles.Client.MenuOpen and not CMVehicles.Client.InTrunk then
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then
                local actionDistance = tonumber(Config.Interaction.distance) or 6.5
                local veh, dist = CMVehicles.Client.GetLookedAtVehicle(tonumber(Config.Interaction.lookDistance) or actionDistance)
                if veh and veh ~= 0 and dist and dist <= actionDistance then
                    vehTargetDist = dist
                    -- Only show the vehicle G if the player menu isn't the closer/
                    -- priority target this frame, so at most one G is on screen.
                    if not VehicleShouldYield(dist) then
                        sleep = 0
                        CMVehicles.Client.DrawVehiclePromptForVehicle(veh)
                    end
                end
            end
        elseif CMVehicles.Client.InTrunk then
            sleep = 0
            local trunkVeh = CMVehicles.Client.TrunkVehicle
            if not trunkVeh or trunkVeh == 0 or not DoesEntityExist(trunkVeh) then
                -- Safety: if an admin deletes/despawns the vehicle while someone is inside,
                -- immediately restore the player instead of leaving them frozen/attached.
                CMVehicles.Client.ExitTrunk(true, false)
            else
                -- Keep camera/look controls free while hiding in the trunk.
                -- Only block movement, vehicle actions, weapons, and melee so the player cannot walk/shoot while attached.
                local blocked = {
                    21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36,
                    44, 45, 59, 60, 63, 64, 66, 67, 68, 69, 70, 71, 72,
                    73, 75, 76, 140, 141, 142, 143, 177, 200, 202, 257, 263, 264, 322
                }
                for _, control in ipairs(blocked) do DisableControlAction(0, control, true) end

                CMVehicles.Client.KeepTrunkSleepAnimAlive()

                if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 202) or IsDisabledControlJustPressed(0, 322)
                    or IsControlJustPressed(0, 177) or IsControlJustPressed(0, 200) or IsControlJustPressed(0, 202) or IsControlJustPressed(0, 322) then
                    CMVehicles.Client.ExitTrunk(false, false)
                end
            end
        end
        -- Share our current vehicle target distance (or clear it) so the player
        -- menu can arbitrate; false when we have no vehicle target this frame.
        PublishVehicleInteractDist(vehTargetDist)
        Wait(sleep)
    end
end)

-- ────────────────────────────────────────────────────────────────────
--  SERVICE ITEMS FROM THE G MENU (jerry can / repair kit)
--  Flow: G menu -> server validates + consumes the item -> server tells us to
--  apply the effect here. The item is the single source of truth, so this
--  reuses the exact same items sold at the gas station.
-- ────────────────────────────────────────────────────────────────────
-- Server confirmed the player HAS the item (not consumed yet). Run the timed
-- animation + progress bar. Only if it completes do we ask the server to
-- consume the item and apply the effect. Cancelling costs the player nothing.
RegisterNetEvent('cm-vehicles:client:beginServiceItem', function(kind, netId, token)
    local veh = 0
    if netId and netId ~= 0 and NetworkDoesNetworkIdExist(netId) then
        veh = NetworkGetEntityFromNetworkId(netId)
    end
    if veh == 0 then
        veh = CMVehicles.Client.GetActionVehicle and CMVehicles.Client.GetActionVehicle(true) or 0
    end
    if not veh or veh == 0 or not DoesEntityExist(veh) then
        CMVehicles.Client.Notify('Vehicle is no longer nearby.')
        return
    end

    -- Timed animation + progress bar.
    local ok = CMVehicles.Client.RunServiceProgress(kind, veh, nil)
    if not ok then return end   -- cancelled: item NOT consumed

    -- Ask the server to actually consume the item now.
    TriggerServerEvent('cm-vehicles:server:confirmServiceItem', kind, token, VehToNetSafe(veh))
end)

function VehToNetSafe(veh)
    if not veh or veh == 0 then return 0 end
    local ok, n = pcall(function() return (CMVehicles.Client.SafeNetId(veh) or 0) end)
    return ok and n or 0
end

-- Server consumed the item -> apply the effect.
RegisterNetEvent('cm-vehicles:client:applyServiceItem', function(kind, netId, patch)
    local veh = 0
    if netId and netId ~= 0 and NetworkDoesNetworkIdExist(netId) then
        veh = NetworkGetEntityFromNetworkId(netId)
    end
    if veh == 0 then veh = CMVehicles.Client.GetActionVehicle and CMVehicles.Client.GetActionVehicle(true) or 0 end
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    patch = type(patch) == 'table' and patch or {}

    if kind == 'refuel' then
        local fuel = tonumber(patch.fuel) or CMVehicles.Client.GetVehicleFuel(veh)
        CMVehicles.Client.SetVehicleFuel(veh, fuel)
        CMVehicles.Client.Notify(('Refueled. Tank at %d%%.'):format(math.floor(fuel + 0.5)))
    elseif kind == 'repair' then
        local engineBefore = GetVehicleEngineHealth(veh)
        local tankBefore = GetVehiclePetrolTankHealth(veh)
        local dirtBefore = GetVehicleDirtLevel(veh)
        SetVehicleFixed(veh)
        SetVehicleDeformationFixed(veh)
        SetVehicleBodyHealth(veh, tonumber(patch.bodyHealth) or 1000.0)
        SetVehicleEngineHealth(veh, engineBefore)
        SetVehiclePetrolTankHealth(veh, tankBefore)
        SetVehicleDirtLevel(veh, dirtBefore)
        CMVehicles.Client.Notify('Bodywork repaired. Engine still needs a mechanic.')
    elseif kind == 'wash' then
        SetVehicleDirtLevel(veh, tonumber(patch.dirtLevel) or 0.0)
        CMVehicles.Client.Notify('Vehicle washed.')
    end
end)

-- ────────────────────────────────────────────────────────────────────
--  SERVICE PROGRESS + ANIMATION (refuel / repair)
--  Shows a timed progress bar, plays the matching animation with a held prop,
--  and cancels if the player moves away, gets in a car, or presses ESC.
--  Returns true only if the full duration completed.
-- ────────────────────────────────────────────────────────────────────
local svcBusy = false

local function loadAnimDict(dict)
    if not dict or dict == '' then return false end
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local tries = 0
    while not HasAnimDictLoaded(dict) and tries < 100 do
        Wait(10); tries = tries + 1
    end
    return HasAnimDictLoaded(dict)
end

local function attachProp(ped, model, bone, off, rot)
    if not model or model == '' then return nil end
    local hash = GetHashKey(model)
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do
        Wait(10); tries = tries + 1
    end
    if not HasModelLoaded(hash) then return nil end

    local coords = GetEntityCoords(ped)
    local obj = CreateObject(hash, coords.x, coords.y, coords.z + 0.2, true, true, true)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, bone or 57005),
        off.x, off.y, off.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(hash)
    return obj
end

-- kind = 'refuel' | 'repair'
function CMVehicles.Client.RunServiceProgress(kind, vehicle, durationMs)
    if svcBusy then
        CMVehicles.Client.Notify('You are already busy.')
        return false
    end
    svcBusy = true

    local svc = Config.Service or {}
    local anim = svc.Anim or {}
    local ped = PlayerPedId()

    local isRepair = (kind == 'repair')
    local isWash   = (kind == 'wash')

    local dict, clip, propModel, defaultMs
    if isRepair then
        dict      = anim.repairDict or 'mini@repair'
        clip      = anim.repairClip or 'fixing_a_ped'
        propModel = anim.propRepair or 'prop_tool_wrench'
        defaultMs = tonumber(svc.repairDurationMs) or 12000
    elseif isWash then
        dict      = anim.washDict or 'timetable@floyd@clean_kitchen@base'
        clip      = anim.washClip or 'base'
        propModel = anim.propWash or 'prop_sponge_01'
        defaultMs = tonumber(svc.washDurationMs) or 10000
    else
        dict      = anim.refuelDict or 'weapon@w_sp_jerrycan'
        clip      = anim.refuelClip or 'fire'
        propModel = anim.propJerryCan or 'w_am_jerrycan'
        defaultMs = tonumber(svc.refuelDurationMs) or 8000
    end

    durationMs = tonumber(durationMs) or defaultMs

    -- Face the vehicle, then play the anim.
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        TaskTurnPedToFaceEntity(ped, vehicle, 800)
        Wait(400)
    end

    local prop
    if loadAnimDict(dict) then
        TaskPlayAnim(ped, dict, clip, 3.0, -3.0, -1, (isRepair or isWash) and 1 or 49, 0, false, false, false)
    end
    if isRepair then
        prop = attachProp(ped, propModel, 28422, vector3(0.09, 0.03, -0.02), vector3(-78.0, 13.0, 28.0))
    elseif isWash then
        prop = attachProp(ped, propModel, 57005, vector3(0.12, 0.02, -0.01), vector3(-50.0, 0.0, 0.0))
    else
        prop = attachProp(ped, propModel, 57005, vector3(0.35, 0.02, -0.02), vector3(-130.0, -50.0, 0.0))
    end

    local title = isRepair and 'Repairing bodywork' or (isWash and 'Washing vehicle' or 'Refueling')
    local sub   = isRepair and 'Panel beating, glass and doors…'
        or (isWash and 'Scrubbing off the dirt…' or 'Pouring the jerry can…')
    SendNUIMessage({ action = 'svcStart', kind = kind, title = title, sub = sub })

    local startAt = GetGameTimer()
    local startCoords = GetEntityCoords(ped)
    local completed = true

    while true do
        Wait(90)
        local now = GetGameTimer()
        local elapsed = now - startAt
        if elapsed >= durationMs then break end

        SendNUIMessage({ action = 'svcUpdate', pct = (elapsed / durationMs) * 100.0 })

        local pedNow = PlayerPedId()

        -- Cancel conditions
        if IsPedInAnyVehicle(pedNow, false) then
            completed = false; break
        end
        if #(GetEntityCoords(pedNow) - startCoords) > 3.0 then
            CMVehicles.Client.Notify('You moved away. Cancelled.')
            completed = false; break
        end
        if IsControlJustReleased(0, 322) then -- ESC
            CMVehicles.Client.Notify('Cancelled.')
            completed = false; break
        end
        if vehicle and vehicle ~= 0 and not DoesEntityExist(vehicle) then
            completed = false; break
        end

        -- Keep the anim alive if something interrupted it.
        if not IsEntityPlayingAnim(pedNow, dict, clip, 3) then
            TaskPlayAnim(pedNow, dict, clip, 3.0, -3.0, -1, (isRepair or isWash) and 1 or 49, 0, false, false, false)
        end
    end

    -- Cleanup
    SendNUIMessage({ action = 'svcStop' })
    ClearPedTasks(PlayerPedId())
    if prop and DoesEntityExist(prop) then
        DetachEntity(prop, true, true)
        DeleteEntity(prop)
    end
    RemoveAnimDict(dict)

    svcBusy = false
    return completed
end

-- Exposed so other resources (cm-gasstations item use, a future mechanic job)
-- get the same timed animation + progress bar without duplicating it.
exports('RunServiceProgress', function(kind, vehicle, durationMs)
    return CMVehicles.Client.RunServiceProgress(kind, vehicle, durationMs)
end)

-- Manual progress-bar control for resources that drive their own timer (e.g. a
-- drive-in car wash, where the player stays in the car and there is no ped anim).
exports('ShowServiceProgress', function(kind, title, sub)
    SendNUIMessage({ action = 'svcStart', kind = kind or 'wash', title = title, sub = sub })
end)
exports('UpdateServiceProgress', function(pct)
    SendNUIMessage({ action = 'svcUpdate', pct = tonumber(pct) or 0 })
end)
exports('HideServiceProgress', function()
    SendNUIMessage({ action = 'svcStop' })
end)
