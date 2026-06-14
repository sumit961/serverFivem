local Config = CMVehicles.Config
local lastSpeed = 0.0
local lastChime = 0
local engineAllowed = {}
local lastDriverVeh = 0

local function playChime()
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
end

local function ejectPlayer(vehicle)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local velocity = GetEntityVelocity(vehicle)
    TaskLeaveVehicle(ped, vehicle, 4160)
    Wait(1)
    SetEntityCoords(ped, coords.x, coords.y, coords.z + 0.5, true, true, true, false)
    SetPedToRagdoll(ped, 3000, 3000, 0, false, false, false)
    SetEntityVelocity(ped, velocity.x * 1.4, velocity.y * 1.4, velocity.z * 1.4)
end

local function setEngine(vehicle, enabled)
    if not vehicle or vehicle == 0 then return end
    enabled = enabled == true
    SetVehicleEngineOn(vehicle, enabled, true, true)
    SetVehicleUndriveable(vehicle, not enabled)
    engineAllowed[vehicle] = enabled
end

local function forceEngineOffUntilCtrl(vehicle)
    if not vehicle or vehicle == 0 then return end
    if engineAllowed[vehicle] ~= true then
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleUndriveable(vehicle, true)
    end
end

RegisterCommand('cm_engine', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end

    local plate = CMVehicles.Client.VehiclePlate(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    local desired = engineAllowed[veh] ~= true

    if not desired then
        setEngine(veh, false)
        CMVehicles.Client.Notify('Engine stopped.')
        return
    end

    if GetVehicleEngineHealth(veh) <= 0.0 then
        setEngine(veh, false)
        CMVehicles.Client.Notify('Engine is destroyed.')
        return
    end

    -- Server validates owner/temp key. No hotwire or lockpick fallback exists.
    TriggerServerEvent('cm-vehicles:server:requestEngineStart', plate, netId)
end, false)
RegisterKeyMapping('cm_engine', 'Start/stop vehicle engine', 'keyboard', Config.Controls.engineKey or 'LCONTROL')

RegisterNetEvent('cm-vehicles:client:engineStartResult', function(netId, allowed, message)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 then veh = GetVehiclePedIsIn(PlayerPedId(), false) end
    if not veh or veh == 0 then return end

    if allowed == true then
        setEngine(veh, true)
        CMVehicles.Client.Notify(message or 'Engine started.')
    else
        setEngine(veh, false)
        CMVehicles.Client.Notify(message or 'You do not have keys for this vehicle.')
    end
end)

-- Prevent GTA/FiveM default auto-start when a player enters the driver seat.
CreateThread(function()
    while true do
        Wait(0)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            if veh ~= lastDriverVeh then
                lastDriverVeh = veh
                engineAllowed[veh] = false
                SetVehicleNeedsToBeHotwired(veh, false)
                forceEngineOffUntilCtrl(veh)
            else
                forceEngineOffUntilCtrl(veh)
            end
        else
            lastDriverVeh = 0
        end
    end
end)

-- F behaviour: tap exits leaving engine running; hold exits and turns engine off.
CreateThread(function()
    while true do
        Wait(0)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and IsControlJustPressed(0, 75) then
            local start = GetGameTimer()
            while IsControlPressed(0, 75) do Wait(0) end
            local held = GetGameTimer() - start > 450
            if held then
                setEngine(veh, false)
            else
                if engineAllowed[veh] == true then
                    SetVehicleEngineOn(veh, true, true, false)
                end
            end
        end
    end
end)

RegisterCommand('cm_seatbelt', function()
    CMVehicles.Client.Seatbelt = not CMVehicles.Client.Seatbelt
    CMVehicles.Client.Notify(CMVehicles.Client.Seatbelt and 'Seatbelt on.' or 'Seatbelt off.')
end, false)
RegisterKeyMapping('cm_seatbelt', 'Toggle seatbelt', 'keyboard', Config.Controls.seatbeltKey or 'B')

CreateThread(function()
    while true do
        Wait(150)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local speed = GetEntitySpeed(veh) * 3.6
            local delta = lastSpeed - speed
            if not CMVehicles.Client.Seatbelt and speed > 20 and GetGameTimer() - lastChime > Config.Seatbelt.warningIntervalMs then
                playChime()
                lastChime = GetGameTimer()
            end
            if not CMVehicles.Client.Seatbelt and lastSpeed > Config.Seatbelt.ejectSpeedKmh and delta > Config.Seatbelt.crashDeltaKmh then
                ejectPlayer(veh)
            end
            lastSpeed = speed
        else
            lastSpeed = 0.0
        end
    end
end)

RegisterCommand('cm_cruise', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end
    CMVehicles.Client.Cruise = not CMVehicles.Client.Cruise
    if CMVehicles.Client.Cruise then
        SetEntityMaxSpeed(veh, GetEntitySpeed(veh))
        CMVehicles.Client.Notify('Cruise control on.')
    else
        SetEntityMaxSpeed(veh, GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel'))
        CMVehicles.Client.Notify('Cruise control off.')
    end
end, false)
RegisterKeyMapping('cm_cruise', 'Toggle cruise control', 'keyboard', Config.Controls.cruiseKey or 'CAPITAL')

RegisterNetEvent('cm-vehicles:client:useFakePlate', function(text, duration)
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then veh = CMVehicles.Client.GetActionVehicle(true) end
    if not veh or veh == 0 then return end
    SetVehicleNumberPlateText(veh, tostring(text or ''):sub(1, 8))
    SetTimeout((tonumber(duration) or 10) * 60000, function()
        if DoesEntityExist(veh) then SetVehicleNumberPlateText(veh, '        ') end
    end)
end)

CreateThread(function()
    while true do
        Wait(750)
        local ped = PlayerPedId()
        local trying = GetVehiclePedIsTryingToEnter(ped)
        if trying and trying ~= 0 then
            local plate = CMVehicles.Client.VehiclePlate(trying)
            local locked = Entity(trying).state.cmLocked == true
            if plate ~= '' and locked then
                SetVehicleAlarm(trying, true)
                StartVehicleAlarm(trying)
            end
        end
    end
end)
