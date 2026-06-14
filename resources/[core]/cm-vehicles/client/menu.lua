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
    CMVehicles.Client.MenuOpen = true
    SetNuiFocus(true, true)
    CMVehicles.Client.Nui('openMenu', { vehicle = info })
end)

RegisterNetEvent('cm-vehicles:client:openTrunk', function(payload)
    CMVehicles.Client.TrunkOpen = true
    CMVehicles.Client.MenuOpen = false
    CMVehicles.Client.CurrentTrunkPlate = U.NormalizePlate(payload and payload.plate)
    SetNuiFocus(true, true)
    CMVehicles.Client.Nui('openTrunk', payload or {})
end)

RegisterNetEvent('cm-vehicles:client:updateTrunk', function(payload)
    if CMVehicles.Client.TrunkOpen then
        CMVehicles.Client.CurrentTrunkPlate = U.NormalizePlate(payload and payload.plate)
        CMVehicles.Client.Nui('updateTrunk', payload or {})
    end
end)

RegisterCommand('veh_menu', function()
    if CMVehicles.Client.InTrunk then CMVehicles.Client.ExitTrunk(); return end
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 then
        CMVehicles.Client.CurrentMenuContext = CMVehicles.Client.GetVehicleContext(veh, false)
    else
        veh = CMVehicles.Client.GetLookedAtVehicle(Config.Interaction.distance or 4.2)
        if veh and veh ~= 0 then CMVehicles.Client.CurrentMenuContext = CMVehicles.Client.GetVehicleContext(veh, true) end
    end
    if not veh or veh == 0 then return CMVehicles.Client.Notify('Look at the vehicle to open the menu.') end
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

RegisterNUICallback('vehicleAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    local action = tostring(data.action or '')
    local plate = U.NormalizePlate(data.plate)
    local veh = CMVehicles.Client.FindVehicleByPlate(plate) or CMVehicles.Client.GetActionVehicle(true)
    local netId = veh and veh ~= 0 and NetworkGetNetworkIdFromEntity(veh) or nil
    local ped = PlayerPedId()
    local inVehicle = IsPedInAnyVehicle(ped, false)

    if action == 'lock' then
        TriggerServerEvent('cm-vehicles:server:toggleLock', plate, netId)
    elseif action == 'engine' then
        ExecuteCommand('cm_engine')
    elseif action == 'trunk' then
        if inVehicle then CMVehicles.Client.Notify('You must be outside the vehicle to use the trunk.') else TriggerServerEvent('cm-vehicles:server:toggleTrunkDoor', plate, netId) end
    elseif action == 'key' then
        TriggerServerEvent('cm-vehicles:server:giveTempKey', plate, tonumber(data.target))
    elseif action == 'enterTrunk' then
        if inVehicle then CMVehicles.Client.Notify('You cannot get in the trunk while inside a vehicle.') elseif veh and veh ~= 0 then CMVehicles.Client.EnterTrunk(veh); CMVehicles.Client.CloseNui() end
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
    else
        CMVehicles.Client.Notify('This RP option is coming soon.')
    end
    cb({ ok = true })
end)

RegisterNUICallback('moveToTrunk', function(data, cb) TriggerServerEvent('cm-vehicles:server:moveToTrunk', data or {}); cb({ ok = true }) end)
RegisterNUICallback('takeFromTrunk', function(data, cb) TriggerServerEvent('cm-vehicles:server:takeFromTrunk', data or {}); cb({ ok = true }) end)

local function getNearbyOpenTrunkVehicle(maxDistance)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return nil, nil end
    local coords = GetEntityCoords(ped)
    local closest, closestDist = nil, tonumber(maxDistance) or (Config.Interaction.trunkDistance or 4.0)
    for _, veh in ipairs(GetGamePool('CVehicle')) do
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
    if CMVehicles.Client.MenuOpen or CMVehicles.Client.TrunkOpen or CMVehicles.Client.InTrunk then return false end
    local veh = getNearbyOpenTrunkVehicle(Config.Interaction.trunkDistance or 4.0)
    if not veh or veh == 0 then return false end
    local plate = CMVehicles.Client.VehiclePlate(veh)
    if plate == '' then return false end
    TriggerServerEvent('cm-vehicles:server:openTrunk', plate, NetworkGetNetworkIdFromEntity(veh))
    return true
end

exports('TryOpenNearbyTrunkInventory', tryOpenNearbyTrunkInventory)
RegisterCommand('vehtrunkinv', function() if not tryOpenNearbyTrunkInventory() then CMVehicles.Client.Notify('No open trunk nearby.') end end, false)

CreateThread(function()
    while true do
        local sleep = 700
        if not CMVehicles.Client.MenuOpen and not CMVehicles.Client.TrunkOpen and not CMVehicles.Client.InTrunk then
            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then
                local veh, dist = CMVehicles.Client.GetLookedAtVehicle(Config.Interaction.distance or 4.2)
                if veh and veh ~= 0 and dist <= (Config.Interaction.distance or 4.2) then
                    sleep = 0
                    local coords = GetEntityCoords(veh)
                    CMVehicles.Client.DrawText3D(coords.x, coords.y, coords.z + 0.95, '[G] Vehicle menu')
                end
            end
        elseif CMVehicles.Client.InTrunk then
            sleep = 0
            DisableAllControlActions(0)
            EnableControlAction(0, 245, true)
            EnableControlAction(0, 47, true)
            if IsControlJustPressed(0, 47) then CMVehicles.Client.ExitTrunk() end
        end
        Wait(sleep)
    end
end)
