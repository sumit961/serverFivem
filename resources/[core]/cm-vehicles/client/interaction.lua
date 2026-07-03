local Config = CMVehicles.Config
local lastSpeed = 0.0
local lastChime = 0
local engineAllowed = {}
local engineRestartReadyAt = {}
local engineStartInProgress = {}
local lastHardImpactAt = 0
local lastDriverVeh = 0

local function playChime()
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
end

local function vehicleSpeedKmh(vehicle)
    if not vehicle or vehicle == 0 then return 0.0 end
    return (GetEntitySpeed(vehicle) or 0.0) * 3.6
end

local function manualStopMaxSpeed()
    return tonumber(Config.Engine and Config.Engine.manualStopMaxSpeedKmh) or 20.0
end

local function destroyedEngineThreshold()
    return tonumber(Config.Damage and Config.Damage.destroyedEngineHealth) or 150.0
end

local function impactRestartDelayMs()
    return tonumber(Config.Damage and Config.Damage.restartDelayAfterImpactMs) or 5000
end

local function canManuallyStopEngine(vehicle)
    return vehicleSpeedKmh(vehicle) <= manualStopMaxSpeed()
end

local function notifyCannotStopWhileMoving(vehicle)
    CMVehicles.Client.Notify(('You cannot turn the engine off above %d km/h.'):format(math.floor(manualStopMaxSpeed() + 0.5)))
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
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    enabled = enabled == true
    SetVehicleEngineOn(vehicle, enabled, true, true)
    SetVehicleUndriveable(vehicle, not enabled)
    engineAllowed[vehicle] = enabled
end

local function stopEngine(vehicle, message, force)
    if not vehicle or vehicle == 0 then return false end
    if force ~= true and not canManuallyStopEngine(vehicle) then
        notifyCannotStopWhileMoving(vehicle)
        return false
    end
    setEngine(vehicle, false)
    if message and message ~= '' then CMVehicles.Client.Notify(message) end
    return true
end

local function forceEngineOffUntilCtrl(vehicle)
    if not vehicle or vehicle == 0 then return end
    if engineAllowed[vehicle] ~= true then
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleUndriveable(vehicle, true)
    end
end

local function requestServerEngineStart(vehicle, plate, netId)
    TriggerServerEvent('cm-vehicles:server:requestEngineStart', plate, netId)
end

local function startEngineWithDelayIfNeeded(vehicle, plate, netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if engineStartInProgress[vehicle] == true then
        CMVehicles.Client.Notify('Engine is already starting.')
        return
    end

    local now = GetGameTimer()
    local readyAt = tonumber(engineRestartReadyAt[vehicle]) or 0
    local delay = math.max(0, readyAt - now)

    local function finalCheckAndStart()
        if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
        local ped = PlayerPedId()
        if GetVehiclePedIsIn(ped, false) ~= vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped then return end
        if engineAllowed[vehicle] == true then return end
        if CMVehicles.Client.GetVehicleFuel(vehicle) <= 0.1 then
            setEngine(vehicle, false)
            CMVehicles.Client.Notify('Vehicle has no fuel.')
            return
        end
        if GetVehicleEngineHealth(vehicle) <= destroyedEngineThreshold() then
            setEngine(vehicle, false)
            CMVehicles.Client.Notify('Engine is too damaged to start. Repair it first.')
            return
        end
        requestServerEngineStart(vehicle, plate, netId)
    end

    if delay <= 0 then
        finalCheckAndStart()
        return
    end

    engineStartInProgress[vehicle] = true
    CMVehicles.Client.Notify(('Starting engine... %d seconds.'):format(math.ceil(delay / 1000)))
    CreateThread(function()
        local endAt = GetGameTimer() + delay
        while GetGameTimer() < endAt do
            Wait(250)
            if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
                engineStartInProgress[vehicle] = nil
                return
            end
            local ped = PlayerPedId()
            if GetVehiclePedIsIn(ped, false) ~= vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped then
                engineStartInProgress[vehicle] = nil
                return
            end
        end
        engineStartInProgress[vehicle] = nil
        finalCheckAndStart()
    end)
end

RegisterCommand('cm_engine', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end

    local plate = CMVehicles.Client.VehiclePlate(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    local desired = engineAllowed[veh] ~= true

    if not desired then
        stopEngine(veh, 'Engine stopped.', false)
        return
    end

    if CMVehicles.Client.GetVehicleFuel(veh) <= 0.1 then
        setEngine(veh, false)
        CMVehicles.Client.Notify('Vehicle has no fuel.')
        return
    end

    if GetVehicleEngineHealth(veh) <= destroyedEngineThreshold() then
        setEngine(veh, false)
        CMVehicles.Client.Notify('Engine is too damaged to start. Repair it first.')
        return
    end

    -- Server validates owner/temp key. No hotwire or lockpick fallback exists.
    startEngineWithDelayIfNeeded(veh, plate, netId)
end, false)
RegisterKeyMapping('cm_engine', 'Start/stop vehicle engine', 'keyboard', Config.Controls.engineKey or 'LCONTROL')

RegisterNetEvent('cm-vehicles:client:engineStartResult', function(netId, allowed, message)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 then veh = GetVehiclePedIsIn(PlayerPedId(), false) end
    if not veh or veh == 0 then return end

    if allowed == true then
        if CMVehicles.Client.GetVehicleFuel(veh) <= 0.1 then
            setEngine(veh, false)
            CMVehicles.Client.Notify('Vehicle has no fuel.')
            return
        end
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
-- Non-blocking: track press/release state instead of trapping this thread in a while loop.
local exitKeyStartedAt = nil
local exitKeyVehicle = nil
CreateThread(function()
    while true do
        Wait(0)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local driver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped

        if not driver then
            exitKeyStartedAt = nil
            exitKeyVehicle = nil
        else
            if IsControlJustPressed(0, 75) then
                exitKeyStartedAt = GetGameTimer()
                exitKeyVehicle = veh
            end

            if exitKeyStartedAt and IsControlJustReleased(0, 75) then
                local held = (GetGameTimer() - exitKeyStartedAt) > 450
                local targetVeh = (exitKeyVehicle and exitKeyVehicle ~= 0 and DoesEntityExist(exitKeyVehicle)) and exitKeyVehicle or veh
                if held then
                    stopEngine(targetVeh, 'Engine stopped.', false)
                elseif engineAllowed[targetVeh] == true then
                    SetVehicleEngineOn(targetVeh, true, true, false)
                end
                exitKeyStartedAt = nil
                exitKeyVehicle = nil
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
            local now = GetGameTimer()
            local speed = vehicleSpeedKmh(veh)
            local delta = lastSpeed - speed
            local damage = Config.Damage or {}
            local hasHarness = CMVehicles.Client.HasRacingHarness and CMVehicles.Client.HasRacingHarness(veh) == true

            if not hasHarness and not CMVehicles.Client.Seatbelt and speed > 20 and now - lastChime > Config.Seatbelt.warningIntervalMs then
                playChime()
                lastChime = now
            end

            -- Hard impact engine shutoff now uses the same crash severity as seatbelt ejection.
            -- This avoids shutting the engine off for small bumps. If the crash is strong enough
            -- that an unbelted player would be ejected, the vehicle engine dies and restart is delayed.
            local seatbeltCfg = Config.Seatbelt or {}
            local useSeatbeltCrash = damage.hardImpactUseSeatbeltCrashThreshold ~= false
            local minImpactSpeed = useSeatbeltCrash and (tonumber(seatbeltCfg.ejectSpeedKmh) or 85.0) or (tonumber(damage.hardImpactMinSpeedKmh) or 85.0)
            local impactDelta = useSeatbeltCrash and (tonumber(seatbeltCfg.crashDeltaKmh) or 45.0) or (tonumber(damage.hardImpactDeltaKmh) or 45.0)
            local impactCooldown = tonumber(damage.hardImpactCooldownMs) or 3000
            local ejectionLevelCrash = lastSpeed > minImpactSpeed and delta > impactDelta

            if engineAllowed[veh] == true and ejectionLevelCrash and now - lastHardImpactAt >= impactCooldown then
                lastHardImpactAt = now
                local impactDamage = tonumber(damage.impactEngineDamage) or 120.0
                if impactDamage > 0.0 then
                    local currentHealth = GetVehicleEngineHealth(veh)
                    SetVehicleEngineHealth(veh, math.max(0.0, currentHealth - impactDamage))
                end
                engineRestartReadyAt[veh] = now + impactRestartDelayMs()
                setEngine(veh, false)
                CMVehicles.Client.Notify(('Severe crash shut off the engine. Restart takes %d seconds.'):format(math.ceil(impactRestartDelayMs() / 1000)))
            end

            if not hasHarness and not CMVehicles.Client.Seatbelt and lastSpeed > (tonumber(Config.Seatbelt.ejectSpeedKmh) or 85.0) and delta > (tonumber(Config.Seatbelt.crashDeltaKmh) or 45.0) then
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

local lastStallCheck = 0
CreateThread(function()
    math.randomseed(GetGameTimer())
    while true do
        Wait(500)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and engineAllowed[veh] == true then
            local now = GetGameTimer()
            local damage = Config.Damage or {}
            local checkMs = tonumber(damage.stallCheckMs) or 4500
            if now - lastStallCheck >= checkMs then
                lastStallCheck = now
                local health = GetVehicleEngineHealth(veh)
                local destroyed = tonumber(damage.destroyedEngineHealth) or 150.0
                local stallBelow = tonumber(damage.stallEngineHealth) or 400.0
                local minSpeed = tonumber(damage.stallMinSpeedKmh) or 12.0
                local speed = vehicleSpeedKmh(veh)

                if health <= destroyed then
                    setEngine(veh, false)
                    CMVehicles.Client.Notify('Engine seized. Repair the vehicle before driving.')
                elseif health <= stallBelow and speed >= minSpeed then
                    local chance = tonumber(damage.stallChancePercent) or 16
                    if math.random(1, 100) <= chance then
                        setEngine(veh, false)
                        CMVehicles.Client.Notify('Engine stalled because it is badly damaged. Press Left Ctrl to try starting it again.')
                    end
                end
            end
        else
            Wait(500)
        end
    end
end)

-- Standalone fuel use. This prevents fuel from sitting at the random native 60% forever.
CreateThread(function()
    while true do
        local fuelCfg = Config.Fuel or {}
        local interval = tonumber(fuelCfg.consumeIntervalMs) or 5000
        Wait(interval)

        if fuelCfg.consumeEnabled ~= false then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                local engineActuallyOn = false
                pcall(function() engineActuallyOn = GetIsVehicleEngineRunning(veh) == true end)
                local shouldConsumeFuel = engineAllowed[veh] == true or engineActuallyOn == true

                if shouldConsumeFuel then
                    local fuel = CMVehicles.Client.GetVehicleFuel(veh)
                    if fuel <= 0.1 then
                        CMVehicles.Client.SetVehicleFuel(veh, 0.0)
                        setEngine(veh, false)
                        CMVehicles.Client.Notify('Vehicle ran out of fuel.')
                    else
                        local speed = vehicleSpeedKmh(veh)
                        local rpm = 0.0
                        pcall(function() rpm = GetVehicleCurrentRpm(veh) or 0.0 end)
                        local minutes = interval / 60000.0
                        local idle = tonumber(fuelCfg.idleDrainPerMinute) or 0.08
                        local speedDrain = tonumber(fuelCfg.speedDrainPerMinute) or 0.45
                        local rpmDrain = tonumber(fuelCfg.rpmDrainPerMinute) or 0.35
                        local drainPerMinute = idle + (math.min(speed, 180.0) / 120.0 * speedDrain) + (math.max(0.0, math.min(rpm, 1.0)) * rpmDrain)
                        local newFuel = CMVehicles.Client.SetVehicleFuel(veh, fuel - (drainPerMinute * minutes))
                        pcall(function() SetVehicleFuelLevel(veh, newFuel + 0.0) end)
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('cm-vehicles:client:useRacingHarness', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = CMVehicles.Client.GetActionVehicle(true) end
    if not veh or veh == 0 then return CMVehicles.Client.Notify('No vehicle nearby for harness installation.') end
    TriggerServerEvent('cm-vehicles:server:installRacingHarness', CMVehicles.Client.VehiclePlate(veh), NetworkGetNetworkIdFromEntity(veh))
end)

RegisterCommand('installharness', function()
    TriggerEvent('cm-vehicles:client:useRacingHarness')
end, false)
