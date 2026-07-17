local Config = CMVehicles.Config
local lastSpeed = 0.0
local engineAllowed = {}
local engineRestartReadyAt = {}
local engineStartInProgress = {}
local lastHardImpactAt = 0
local lastDriverVeh = 0

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


-- Admin/test/placement vehicles are created with a complete healthy condition
-- and never run the owned-vehicle finalizeSpawn pipeline. Treat cmAdmin as a
-- ready condition as a replication-safe fallback, while normal vehicles still
-- require the strict cmConditionReady flag.
local function isConditionReady(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local state = Entity(vehicle).state
    return state.cmAdmin == true or state.cmConditionReady == true
end

local function isAdminAutoEngine(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local state = Entity(vehicle).state
    return state.cmAdmin == true and state.cmAdminAutoEngine == true
end

local function playEngineStartAnimation(vehicle, done)
    local cfg = Config.Engine or {}
    local duration = math.max(350, tonumber(cfg.startAnimationDurationMs) or 1250)
    if cfg.startAnimation == false then
        done()
        return
    end

    CreateThread(function()
        local ped = PlayerPedId()
        local dict = tostring(cfg.startAnimationDict or 'anim@mp_player_intmenu@key_fob@')
        local clip = tostring(cfg.startAnimationClip or 'fob_click')
        RequestAnimDict(dict)
        local timeout = GetGameTimer() + 1500
        while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end

        if HasAnimDictLoaded(dict) and GetVehiclePedIsIn(ped, false) == vehicle then
            TaskPlayAnim(ped, dict, clip, 4.0, -4.0, duration, 48, 0.0, false, false, false)
        end
        Wait(duration)
        if HasAnimDictLoaded(dict) then
            StopAnimTask(ped, dict, clip, 1.0)
            RemoveAnimDict(dict)
        end
        done()
    end)
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

local function restoreExpectedCondition(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local state = Entity(vehicle).state
    local current = tonumber(GetVehicleEngineHealth(vehicle)) or 0.0

    -- Once initialization is complete, the live physical condition is the truth.
    -- Never restore state-bag health here: doing so repaired damage caused after
    -- the vehicle was recalled from the garage.
    if state.cmAdmin == true or state.cmConditionReady == true then
        return state.cmEngineDestroyed ~= true and current > destroyedEngineThreshold()
    end

    -- Before readiness, the vehicle remains quarantined/undriveable. The spawn
    -- finalizer owns the only legal convergence loop.
    SetVehicleEngineOn(vehicle, false, true, true)
    SetVehicleUndriveable(vehicle, true)
    return false
end

local function setEngine(vehicle, enabled)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    enabled = enabled == true
    local state = Entity(vehicle).state
    if enabled and not isConditionReady(vehicle) then
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleUndriveable(vehicle, true)
        engineAllowed[vehicle] = false
        return
    end
    if enabled and (state.cmEngineDestroyed == true
        or (tonumber(GetVehicleEngineHealth(vehicle)) or 0.0) <= destroyedEngineThreshold()) then
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleUndriveable(vehicle, true)
        engineAllowed[vehicle] = false
        return
    end

    -- A house-garage vehicle is parked/frozen in its assigned bay. Starting
    -- the engine is the explicit hand-off from parked display to drivable car.
    local garageDisplay = false
    pcall(function() garageDisplay = Entity(vehicle).state.cmHouseGarageDisplay == true end)
    if garageDisplay and enabled then
        restoreExpectedCondition(vehicle)
        SetEntityInvincible(vehicle, false)
        SetVehicleCanBeVisiblyDamaged(vehicle, true)
        pcall(function() SetEntityProofs(vehicle, false, false, false, false, false, false, false, false) end)
        pcall(function() SetEntityHasGravity(vehicle, true) end)
        FreezeEntityPosition(vehicle, false)
        SetVehicleHandbrake(vehicle, false)
        SetEntityCollision(vehicle, true, true)
        ResetEntityAlpha(vehicle)
    end

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

    -- Placement/admin vehicles explicitly spawned with engineOn=true should be
    -- immediately driveable. They are temporary known-good entities, not owned
    -- vehicles waiting for a player key/condition finalizer.
    if isAdminAutoEngine(vehicle) and isConditionReady(vehicle) then
        engineAllowed[vehicle] = true
        SetVehicleUndriveable(vehicle, false)
        SetVehicleEngineOn(vehicle, true, true, false)
        return
    end

    if engineAllowed[vehicle] ~= true or Entity(vehicle).state.cmEngineDestroyed == true then
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
        if not restoreExpectedCondition(vehicle) then
            setEngine(vehicle, false)
            CMVehicles.Client.Notify('Vehicle condition is still loading. Try again in a moment.')
            return
        end
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
    local netId = CMVehicles.Client.SafeNetId(veh)
    if not netId then
        CMVehicles.Client.Notify('This is a local display vehicle and cannot be driven.')
        return
    end
    local desired = engineAllowed[veh] ~= true

    if not desired then
        stopEngine(veh, 'Engine stopped.', false)
        return
    end

    if not isConditionReady(veh) then
        setEngine(veh, false)
        CMVehicles.Client.Notify('Vehicle condition is still loading. Try again in a moment.')
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
        if not isConditionReady(veh) then
            setEngine(veh, false)
            CMVehicles.Client.Notify('Vehicle condition is still loading. Try again in a moment.')
            return
        end
        if CMVehicles.Client.GetVehicleFuel(veh) <= 0.1 then
            setEngine(veh, false)
            CMVehicles.Client.Notify('Vehicle has no fuel.')
            return
        end
        if engineStartInProgress[veh] == true then return end
        engineStartInProgress[veh] = true
        CMVehicles.Client.Notify('Starting engine...')
        playEngineStartAnimation(veh, function()
            engineStartInProgress[veh] = nil
            local ped = PlayerPedId()
            if not DoesEntityExist(veh) or GetVehiclePedIsIn(ped, false) ~= veh or GetPedInVehicleSeat(veh, -1) ~= ped then return end
            if not isConditionReady(veh)
                or CMVehicles.Client.GetVehicleFuel(veh) <= 0.1
                or GetVehicleEngineHealth(veh) <= destroyedEngineThreshold() then
                return setEngine(veh, false)
            end
            setEngine(veh, true)
            CMVehicles.Client.Notify(message or 'Engine started.')
        end)
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
                engineAllowed[veh] = isAdminAutoEngine(veh) and isConditionReady(veh) or false
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
                    -- 4th arg = instantly (skip start sound/animation). Setting it
                    -- to true removes the gear-up/engine-on beep cue.
                    local instant = (Config.Engine and Config.Engine.playStartSound == false)
                    SetVehicleEngineOn(targetVeh, true, instant, false)
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

-- Seatbelt warning is now HUD-only. cm-hud reads LocalPlayer.state.cmVehicleHud
-- (see the HUD feed thread in client/main.lua) and shows a flashing belt icon.
-- We publish a lightweight flag here so the HUD knows the warning is active.
CMVehicles.Client.SeatbeltWarn = false

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
            local seatbeltCfg = Config.Seatbelt or {}
            local hasHarness = CMVehicles.Client.HasRacingHarness and CMVehicles.Client.HasRacingHarness(veh) == true

            -- Seatbelt warning: visual only, no chime. Active when moving unbelted.
            CMVehicles.Client.SeatbeltWarn = (not hasHarness and not CMVehicles.Client.Seatbelt and speed > 20)

            -- ── Hard impact handling ──────────────────────────────────
            -- A qualifying "hard impact" is a sudden speed drop above the
            -- configured thresholds. Every hard impact removes only ~1% of
            -- max engine health. The engine only *sometimes* dies, and only
            -- on a severe crash (higher speed + bigger drop) rolled at random.
            local minImpactSpeed = tonumber(damage.hardImpactMinSpeedKmh) or 55.0
            local impactDelta = tonumber(damage.hardImpactDeltaKmh) or 35.0
            local impactCooldown = tonumber(damage.hardImpactCooldownMs) or 1500
            local isHardImpact = lastSpeed > minImpactSpeed and delta > impactDelta

            if engineAllowed[veh] == true and isHardImpact and now - lastHardImpactAt >= impactCooldown then
                lastHardImpactAt = now

                -- 1% of max (1000) per hit.
                local pct = tonumber(damage.impactEngineDamagePercent) or 1.0
                local dmg = (pct / 100.0) * 1000.0
                if dmg > 0.0 then
                    local currentHealth = GetVehicleEngineHealth(veh)
                    SetVehicleEngineHealth(veh, math.max(0.0, currentHealth - dmg))
                end

                -- Hard + random stall: only severe crashes can stop the engine,
                -- and only on a dice roll. Most crashes just chip the 1%.
                local severeSpeed = tonumber(damage.stallOnCrashMinSpeedKmh) or 80.0
                local severeDelta = tonumber(damage.stallOnCrashMinDeltaKmh) or 55.0
                local stallChance = tonumber(damage.stallOnCrashChancePercent) or 22
                local isSevere = lastSpeed >= severeSpeed and delta >= severeDelta
                if isSevere and math.random(1, 100) <= stallChance then
                    engineRestartReadyAt[veh] = now + impactRestartDelayMs()
                    setEngine(veh, false)
                    CMVehicles.Client.Notify(('Severe crash killed the engine. Restart takes %d seconds.'):format(math.ceil(impactRestartDelayMs() / 1000)))
                end
            end

            -- Unbelted ejection is unchanged (severe crash, no harness, no belt).
            if not hasHarness and not CMVehicles.Client.Seatbelt and lastSpeed > (tonumber(seatbeltCfg.ejectSpeedKmh) or 85.0) and delta > (tonumber(seatbeltCfg.crashDeltaKmh) or 45.0) then
                ejectPlayer(veh)
            end
            lastSpeed = speed
        else
            lastSpeed = 0.0
            CMVehicles.Client.SeatbeltWarn = false
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
RegisterKeyMapping('cm_cruise', 'Toggle cruise control', 'keyboard', Config.Controls.cruiseKey or 'X')

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

-- Racing harness installation is server-authorized only.
-- cm-itemactions/cm-tuning must charge or consume the item before calling the server export.

-- ────────────────────────────────────────────────────────────────────
--  ENGINE PROTECT
--  GTA drains engine health hard on every collision, independently of our own
--  impact logic. Config alone can't slow that down. This loop watches the
--  native health each tick and gives most of the loss back, so the engine only
--  degrades by the small controlled amount we apply on hard impacts.
--  Result: an engine takes a long, sustained beating before it actually breaks.
-- ────────────────────────────────────────────────────────────────────
CreateThread(function()
    local dmg = Config.Damage or {}
    if dmg.engineProtect == false then return end

    local keep = tonumber(dmg.engineProtectKeepPercent) or 0.12
    if keep < 0.0 then keep = 0.0 end
    if keep > 1.0 then keep = 1.0 end

    local lastVeh, lastHealth = 0, nil

    while true do
        Wait(150)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local health = GetVehicleEngineHealth(veh) or 0.0

            if veh ~= lastVeh then
                lastVeh, lastHealth = veh, health
            elseif lastHealth and health < lastHealth then
                -- GTA took some engine health. Give back most of it.
                local lost = lastHealth - health
                -- Ignore our own deliberate impact damage (it is applied in one
                -- go and is small); this simply damps any drop by `keep`.
                local restored = health + (lost * (1.0 - keep))
                if restored > 1000.0 then restored = 1000.0 end
                SetVehicleEngineHealth(veh, restored)
                lastHealth = restored
            else
                lastHealth = health
            end
        else
            lastVeh, lastHealth = 0, nil
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════
--  RAIN GRIP FIX
--  GTA slashes tyre grip on wet roads far harder than it should. On a rainy
--  night a supercar becomes almost undriveable -- it slides on a straight.
--  SetVehicleReduceGrip is the native GTA itself uses for this; we simply stop
--  it applying, and restore grip each frame while it is raining.
-- ════════════════════════════════════════════════════════════════════
CreateThread(function()
    local cfg = Config.Rain or {}
    if cfg.fixGrip == false then return end

    while true do
        Wait(500)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local rain = 0.0
            pcall(function() rain = GetRainLevel() or 0.0 end)

            if rain > 0.0 then
                -- Stop GTA's wet-road grip penalty.
                pcall(function() SetVehicleReduceGrip(veh, false) end)

                -- Restore grip, scaled by how hard it is raining. A little rain
                -- should still be felt; a downpour should not be a death trap.
                local keep = tonumber(cfg.wetGripFloor) or 0.92
                local grip = 1.0 - ((1.0 - keep) * math.min(1.0, rain))

                -- A higher tyre level claws grip back on top of this.
                local tyreLvl = CMVehicles.Client.GetTyreLevel and CMVehicles.Client.GetTyreLevel(veh) or 0
                local tcfg = (Config.Tuning and Config.Tuning.Tyres) or {}
                grip = grip - (tyreLvl * (tonumber(tcfg.gripPerLevel) or 0.05))

                pcall(function() SetVehicleGripLevel(veh, math.max(0.75, grip)) end)
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════
--  RADIO OFF BY DEFAULT
--  Mute the radio whenever a player gets into a vehicle. They can still turn it
--  on themselves; it just does not blast on entry.
-- ════════════════════════════════════════════════════════════════════
CreateThread(function()
    if Config.Radio and Config.Radio.defaultOff == false then return end

    local lastVeh = 0
    while true do
        Wait(250)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        if veh ~= 0 and veh ~= lastVeh then
            lastVeh = veh
            SetVehicleRadioEnabled(veh, true)
            SetVehRadioStation(veh, 'OFF')
            pcall(function() SetUserRadioControlEnabled(true) end)
        elseif veh == 0 then
            lastVeh = 0
        end
    end
end)
