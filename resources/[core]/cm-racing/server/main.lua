CMRacing = CMRacing or {}
CMRacing.Server = CMRacing.Server or {}

local Config = CMRacing.Config
local Progression = CMRacing.Server.Progression
local Validation = CMRacing.Server.Validation

local ActiveSessions = {} -- [src] = sessionData
local SessionByToken = {} -- [token] = src

local function getPlayerData()
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    return exports['cm-playerdata']
end

local function getCharId(src)
    local pd = getPlayerData()
    if not pd then return nil end
    local ok, charId = pcall(function() return pd:GetCharacterId(src) end)
    if ok and charId and tostring(charId) ~= '' then
        return tostring(charId)
    end
    return nil
end

local function notify(src, message, kind)
    if GetResourceState('cm-hud') == 'started' then
        pcall(function() TriggerClientEvent('cm-hud:client:notify', src, message, kind or 'info') end)
    else
        TriggerClientEvent('cm-racing:client:notify', src, message, kind or 'info')
    end
end

local function generateToken()
    return string.format('race_%d_%d_%d', os.time(), math.random(10000, 99999), math.random(1000, 9999))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Menu Data Request
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('cm-racing:server:requestMenuData', function()
    local src = source
    local charId = getCharId(src)
    if not charId then
        TriggerClientEvent('cm-racing:client:receiveMenuData', src, { ok = false, error = 'character_not_loaded' })
        return
    end

    local profile = Progression.GetProfile(src)
    local routeList = {}

    for id, route in pairs(Config.Routes) do
        local onCooldown, remaining = Progression.IsOnCooldown(charId, id)
        local isUnlocked = (profile.level >= route.requiredLevel)
        local pb = profile.personalBests[id]

        table.insert(routeList, {
            id = id,
            name = route.name,
            category = route.category,
            description = route.description,
            requiredLevel = route.requiredLevel,
            unlocked = isUnlocked,
            cooldown = onCooldown,
            cooldownSeconds = remaining,
            reward = route.reward,
            xp = route.xp,
            checkpointCount = #route.checkpoints,
            personalBest = pb,
            staging = route.staging,
            allowedClasses = route.allowedClasses
        })
    end

    table.sort(routeList, function(a, b) return a.requiredLevel < b.requiredLevel end)

    -- Check current vehicle status
    local vehOk, vehReason, vehInfo = Validation.ValidateDriverAndVehicle(src, nil)

    TriggerClientEvent('cm-racing:client:receiveMenuData', src, {
        ok = true,
        profile = profile,
        routes = routeList,
        vehicle = {
            inVehicle = vehOk,
            reason = vehReason,
            info = vehInfo
        }
    })
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Request Race Start
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('cm-racing:server:requestStartRace', function(routeId)
    local src = source
    local charId = getCharId(src)
    if not charId then
        notify(src, 'Unable to verify character identity.', 'error')
        return
    end

    local pd = getPlayerData()
    if pd and pd:IsDead(src) then
        notify(src, 'You cannot participate while injured or incapacitated.', 'error')
        return
    end

    if ActiveSessions[src] then
        notify(src, 'You already have an active race in progress.', 'error')
        return
    end

    local route = Config.Routes[routeId]
    if not route then
        notify(src, 'Invalid race route selected.', 'error')
        return
    end

    local profile = Progression.GetProfile(src)
    if profile.level < route.requiredLevel then
        notify(src, ('You need Racing License Level %d to enter this track.'):format(route.requiredLevel), 'error')
        return
    end

    local onCooldown, remaining = Progression.IsOnCooldown(charId, routeId)
    if onCooldown then
        notify(src, ('Track cooldown in progress. Please wait %d seconds.'):format(remaining), 'warning')
        return
    end

    -- Authoritative Driver & Vehicle Validation
    local vehOk, vehErr, vehData = Validation.ValidateDriverAndVehicle(src, routeId)
    if not vehOk then
        if vehErr == 'must_be_in_vehicle' or vehErr == 'must_be_driver' then
            notify(src, 'You must be in the driver seat of a vehicle to race.', 'error')
        elseif vehErr == 'vehicle_class_ineligible' then
            notify(src, 'This vehicle class is not permitted in this sanctioned tier.', 'error')
        elseif vehErr == 'vehicle_not_authorized' then
            notify(src, 'Vehicle registration unverified. You must drive a registered road vehicle.', 'error')
        elseif vehErr == 'vehicle_too_damaged' then
            notify(src, 'Vehicle engine is too damaged to meet racing safety regulations.', 'error')
        else
            notify(src, 'Vehicle eligibility verification failed.', 'error')
        end
        return
    end

    -- Staging proximity check
    local vehCoords = GetEntityCoords(vehData.entity)
    local stagingCoords = vector3(route.staging.x, route.staging.y, route.staging.z)
    local stagingDist = #(vehCoords - stagingCoords)
    if stagingDist > Config.Validation.MaxStagingDistance then
        notify(src, ('You must stage your vehicle near the starting grid (%.1fm away).'):format(stagingDist), 'warning')
        return
    end

    local token = generateToken()
    local session = {
        token = token,
        src = src,
        charId = charId,
        routeId = routeId,
        vehicleNetId = vehData.netId,
        vehiclePlate = vehData.plate,
        status = 'staging',
        stagedAtMs = GetGameTimer(),
        startedAtMs = 0,
        lastCheckpointTimeMs = 0,
        currentCheckpoint = 0,
        outOfVehicleSince = nil,
    }

    ActiveSessions[src] = session
    SessionByToken[token] = src

    TriggerClientEvent('cm-racing:client:startCountdown', src, {
        token = token,
        route = route,
        countdownSeconds = Config.Validation.CountdownSeconds
    })
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Countdown Complete (Race Begun)
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('cm-racing:server:countdownFinished', function(token)
    local src = source
    local session = ActiveSessions[src]
    if not session or session.token ~= token or session.status ~= 'staging' then
        return
    end

    session.status = 'racing'
    session.startedAtMs = GetGameTimer()
    session.lastCheckpointTimeMs = session.startedAtMs

    TriggerClientEvent('cm-racing:client:raceStarted', src, {
        token = token,
        startedAtMs = session.startedAtMs
    })
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Checkpoint Reached
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('cm-racing:server:reachCheckpoint', function(token, checkpointIndex)
    local src = source
    local session = ActiveSessions[src]
    if not session or session.token ~= token then
        return
    end

    checkpointIndex = tonumber(checkpointIndex)
    local ok, errCode, info = Validation.ValidateCheckpoint(session, checkpointIndex)
    if not ok then
        print(('[CM-RACING] Checkpoint rejected for src=%s: %s'):format(tostring(src), tostring(errCode)))
        TriggerClientEvent('cm-racing:client:checkpointRejected', src, {
            token = token,
            expected = session.currentCheckpoint + 1,
            reason = errCode
        })
        return
    end

    session.currentCheckpoint = checkpointIndex
    session.lastCheckpointTimeMs = info.nowMs

    -- Acknowledge checkpoint to client
    TriggerClientEvent('cm-racing:client:checkpointAck', src, {
        token = token,
        checkpointIndex = checkpointIndex,
        totalCheckpoints = #Config.Routes[session.routeId].checkpoints,
        elapsedMs = info.nowMs - session.startedAtMs
    })

    -- Check if this was the finish line
    if info.isFinish then
        local route = Config.Routes[session.routeId]
        local finalTimeMs = info.nowMs - session.startedAtMs

        -- Sanity check: minimum plausible race time (at least 35% of estimated duration)
        local minPlausibleTotalMs = math.floor((route.estDurationSeconds * 0.35) * 1000)
        if finalTimeMs < minPlausibleTotalMs then
            print(('[CM-RACING] Exploitation detected for src=%s: total race time %d ms is below min plausible %d ms'):format(
                tostring(src), finalTimeMs, minPlausibleTotalMs
            ))
            ActiveSessions[src] = nil
            SessionByToken[token] = nil
            notify(src, 'Race disqualified: Implausible completion time detected.', 'error')
            TriggerClientEvent('cm-racing:client:raceFailed', src, 'disqualified_speed')
            return
        end

        -- Mark finished & remove session (Idempotent completion)
        session.status = 'finished'
        ActiveSessions[src] = nil
        SessionByToken[token] = nil

        -- Set route cooldown
        Progression.SetCooldown(session.charId, route.id, route.cooldownSeconds)

        -- Record time and progression
        local isPb, profile = Progression.AddRaceResult(src, route.id, finalTimeMs, route.xp)

        -- Payout Attribution (Fail-Closed: cm-payday lacks idempotent settlement API)
        local uniqueRef = ('RACE-%s-%s-%d'):format(tostring(session.charId or '0'), tostring(route.id), os.time())
        Progression.RetainPendingWage(src, route.reward, 'pending_payroll_integration', uniqueRef)

        notify(src, ('Race complete! Time: %.2fs. Payout ($%d) stored in durable racing records (cash cannot currently be collected in-game pending safe payroll integration).'):format(
            finalTimeMs / 1000, route.reward
        ), 'info')

        if isPb then
            notify(src, 'New Personal Best recorded!', 'success')
        end

        TriggerClientEvent('cm-racing:client:raceFinished', src, {
            routeId = route.id,
            routeName = route.name,
            finalTimeMs = finalTimeMs,
            isPersonalBest = isPb,
            reward = route.reward,
            paidViaPayday = false,
            payoutRef = uniqueRef,
            xpGained = route.xp,
            newLevel = profile.level
        })
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Cancel / Abandon Race
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('cm-racing:server:abandonRace', function()
    local src = source
    local session = ActiveSessions[src]
    if not session then return end

    SessionByToken[session.token] = nil
    ActiveSessions[src] = nil
    notify(src, 'Race abandoned.', 'warning')
    TriggerClientEvent('cm-racing:client:raceFailed', src, 'abandoned')
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Watchdog Loop (Runs every 1000ms)
-- ─────────────────────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(1000)
        local nowMs = GetGameTimer()

        for src, session in pairs(ActiveSessions) do
            local failReason = nil

            -- Check player existence
            if GetPlayerPing(src) <= 0 then
                failReason = 'player_disconnected'
            else
                local pd = getPlayerData()
                if pd and pd:IsDead(src) then
                    failReason = 'driver_incapacitated'
                end

                -- Timeout check
                if session.status == 'racing' and (nowMs - session.startedAtMs) > (Config.Validation.RaceTimeoutSeconds * 1000) then
                    failReason = 'race_timed_out'
                end

                -- Vehicle presence check
                if not failReason and session.status == 'racing' then
                    local veh = NetworkGetEntityFromNetworkId(session.vehicleNetId)
                    if not veh or veh == 0 or not DoesEntityExist(veh) then
                        failReason = 'vehicle_destroyed'
                    else
                        local ped = GetPlayerPed(src)
                        local inVeh = (GetVehiclePedIsIn(ped, false) == veh and GetPedInVehicleSeat(veh, -1) == ped)
                        if not inVeh then
                            if not session.outOfVehicleSince then
                                session.outOfVehicleSince = nowMs
                                notify(src, ('Return to your vehicle! %d seconds remaining.'):format(Config.Validation.VehicleExitGraceSeconds), 'error')
                            elseif (nowMs - session.outOfVehicleSince) > (Config.Validation.VehicleExitGraceSeconds * 1000) then
                                failReason = 'abandoned_vehicle'
                            end
                        else
                            session.outOfVehicleSince = nil
                        end
                    end
                end
            end

            if failReason then
                SessionByToken[session.token] = nil
                ActiveSessions[src] = nil
                if GetPlayerPing(src) > 0 then
                    notify(src, ('Race failed: %s'):format(failReason), 'error')
                    TriggerClientEvent('cm-racing:client:raceFailed', src, failReason)
                end
            end
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Disconnect & Resource Cleanup
-- ─────────────────────────────────────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    local src = source
    local session = ActiveSessions[src]
    if session then
        SessionByToken[session.token] = nil
        ActiveSessions[src] = nil
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for src, session in pairs(ActiveSessions) do
        TriggerClientEvent('cm-racing:client:raceFailed', src, 'resource_stopped')
    end
    ActiveSessions = {}
    SessionByToken = {}
end)

RegisterNetEvent('cm-playerdata:characterLoaded', function(charData)
    local src = source
    if not src or src <= 0 then return end
    SetTimeout(3500, function()
        if GetPlayerPing(src) <= 0 then return end
        local profile = Progression.GetProfile(src)
        if profile and (profile.pendingWages or 0) > 0 then
            notify(src, ('Sanctioned Racing: You have $%d in pending race winnings stored in durable records. Cash cannot currently be collected in-game pending safe payroll integration.'):format(profile.pendingWages), 'info')
        end
    end)
end)
