local U = CMVehicles.Utils
local Config = CMVehicles.Config

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
        netId = NetworkGetNetworkIdFromEntity(veh)
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
        info.fuel = math.floor(((CMVehicles.Client.GetVehicleFuel(veh) or 100.0) * 10) + 0.5) / 10
        info.engineHealth = GetVehicleEngineHealth(veh)
        info.bodyHealth = GetVehicleBodyHealth(veh)
        info.tankHealth = GetVehiclePetrolTankHealth(veh)
        info.mileage = CMVehicles.Client.GetVehicleMileage(veh)
        info.racingHarness = CMVehicles.Client.HasRacingHarness(veh)
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
        CMVehicles.Client.CurrentMenuContext = CMVehicles.Client.GetVehicleContext(veh, false)
    else
        veh = CMVehicles.Client.GetLookedAtVehicle(tonumber(Config.Interaction.lookDistance) or tonumber(Config.Interaction.distance) or 7.5)
        if veh and veh ~= 0 then
            CMVehicles.Client.CurrentMenuContext = CMVehicles.Client.GetVehicleContext(veh, true)
        end
    end

    if not veh or veh == 0 then
        return CMVehicles.Client.Notify('Look at the vehicle to open the G menu.')
    end

    local plate = CMVehicles.Client.VehiclePlate(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    TriggerServerEvent('cm-vehicles:server:registerNetVehicle', plate, netId)
    TriggerServerEvent('cm-vehicles:server:requestInfo', plate, netId)
end, false)
RegisterKeyMapping('veh_menu', 'Vehicle interaction menu', 'keyboard', Config.Controls.menuKey or 'G')

RegisterCommand('veh_lock', function()
    local veh = CMVehicles.Client.GetActionVehicle(true)
    if not veh or veh == 0 then return CMVehicles.Client.Notify('No vehicle nearby.') end
    local plate = CMVehicles.Client.VehiclePlate(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    TriggerServerEvent('cm-vehicles:server:registerNetVehicle', plate, netId)
    TriggerServerEvent('cm-vehicles:server:toggleLock', plate, netId)
end, false)
RegisterKeyMapping('veh_lock', 'Lock/unlock vehicle', 'keyboard', Config.Controls.lockKey or 'L')

RegisterCommand('vehtrunk', function()
    local veh = CMVehicles.Client.GetActionVehicle(true)
    if not veh or veh == 0 then return CMVehicles.Client.Notify('No vehicle nearby.') end
    TriggerServerEvent('cm-vehicles:server:toggleTrunkDoor', CMVehicles.Client.VehiclePlate(veh), NetworkGetNetworkIdFromEntity(veh))
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
            TriggerServerEvent('cm-vehicles:server:saveState', CMVehicles.Client.VehicleId(veh), { neons = neons, metadata = { neons = neons } })
        end
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
    TriggerServerEvent('cm-vehicles:server:openSharedTrunkInventory', plate, NetworkGetNetworkIdFromEntity(veh))
    return true
end

exports('TryOpenNearbyTrunkInventory', tryOpenNearbyTrunkInventory)
RegisterCommand('vehtrunkinv', function() if not tryOpenNearbyTrunkInventory() then CMVehicles.Client.Notify('No open trunk nearby.') end end, false)

CreateThread(function()
    while true do
        local sleep = 700
        if not CMVehicles.Client.MenuOpen and not CMVehicles.Client.InTrunk then
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then
                local actionDistance = tonumber(Config.Interaction.distance) or 6.5
                local veh, dist = CMVehicles.Client.GetLookedAtVehicle(tonumber(Config.Interaction.lookDistance) or actionDistance)
                if veh and veh ~= 0 and dist and dist <= actionDistance then
                    sleep = 0
                    CMVehicles.Client.DrawVehiclePromptForVehicle(veh)
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
        Wait(sleep)
    end
end)
