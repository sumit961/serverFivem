-- CM License System — Test Session Management

Tests = {}

-- Active test sessions in memory, keyed by character id.
Tests.ActiveSessions = {}
-- Secondary index so a session can still be found when cm-playerdata has
-- already released the character (disconnect ordering).
Tests.SessionsBySource = {}
Tests.StartLocks = {}
local testPlateSequence = 0

local function config()
    return CMLicenseConfig.TestSession
end

local function debugLog(message)
    if CMLicenseConfig.Debug then
        print(('^3[CM-License]^7 %s'):format(tostring(message)))
    end
end

local function formatCoords(coords)
    if not coords then return 'n/a' end
    return ('%.2f,%.2f,%.2f'):format(coords.x, coords.y, coords.z)
end

local function checkpointTrace(session, requested, checkpoint)
    local ped = GetPlayerPed(session and session.src or 0)
    local actualVehicle = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    local playerCoords = ped ~= 0 and DoesEntityExist(ped) and GetEntityCoords(ped) or nil
    local vehicleCoords = actualVehicle ~= 0 and DoesEntityExist(actualVehicle)
        and GetEntityCoords(actualVehicle) or nil
    local driver = actualVehicle ~= 0 and GetPedInVehicleSeat(actualVehicle, -1) == ped
    local actualNetId = actualVehicle ~= 0 and DoesEntityExist(actualVehicle)
        and NetworkGetNetworkIdFromEntity(actualVehicle) or 0
    local measurement = tostring(session.category or 'ground') == Constants.VEHICLE_CATEGORY.GROUND
        and playerCoords or vehicleCoords
    local distance, vertical
    if checkpoint and measurement then
        distance, vertical = Utils.CheckpointDistance(measurement, checkpoint, session.category)
    end
    local radius = checkpoint and Utils.CheckpointRadius(checkpoint) or nil

    debugLog(('checkpoint_received char=%s testId=%s requested=%s expected=%s status=%s sessionNetId=%s actualNetId=%s driver=%s distance=%s vertical=%s radius=%s player=(%s) checkpoint=(%s)')
        :format(
            tostring(session.characterId), tostring(session.testId), tostring(requested),
            tostring((tonumber(session.currentCheckpoint) or 0) + 1), tostring(session.status),
            tostring(session.vehicleNetId), tostring(actualNetId), tostring(driver),
            distance and ('%.2f'):format(distance) or 'n/a',
            vertical and ('%.2f'):format(vertical) or 'n/a',
            radius and ('%.2f'):format(radius) or 'n/a',
            formatCoords(playerCoords), formatCoords(checkpoint)))

    return ped, actualVehicle, playerCoords, vehicleCoords, distance, vertical, radius
end

local function placementKind(category, model)
    category = tostring(category or ''):lower()
    if category == Constants.VEHICLE_CATEGORY.BOAT then return 'boat' end
    if category == Constants.VEHICLE_CATEGORY.AIR then
        local name = tostring(model or ''):lower()
        local helicopters = { frogger=true, maverick=true, swift=true, annihilator=true, cargobob=true,
            buzzard=true, police_maverick=true, volatus=true, akula=true, hunter=true, havok=true }
        return helicopters[name] and 'helicopter' or 'airplane'
    end
    return 'car'
end

local function deleteTestVehicle(session)
    if not session then return end
    if session.vehiclePlate and GetResourceState('cm-vehiclekeys') == 'started' then
        pcall(function() exports['cm-vehiclekeys']:RevokeAllForPlate(session.vehiclePlate) end)
        if session.vehicleKeyPlate and session.vehicleKeyPlate ~= session.vehiclePlate then
            pcall(function() exports['cm-vehiclekeys']:RevokeAllForPlate(session.vehicleKeyPlate) end)
        end
    end
    if session.vehiclePlate and GetResourceState('cm-vehicles') == 'started' then
        pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(session.vehiclePlate) end)
    elseif session.vehicleEntity and DoesEntityExist(session.vehicleEntity) then
        DeleteEntity(session.vehicleEntity)
    end
end

local function forgetSession(characterId)
    local session = Tests.ActiveSessions[characterId]
    if session and session.src then Tests.SessionsBySource[session.src] = nil end
    Tests.ActiveSessions[characterId] = nil
end

local function spawnTestVehicle(src, characterId, licenseType, spawn)
    if GetResourceState('cm-vehicles') ~= 'started' then return nil, 'vehicle_service_unavailable' end
    if not spawn or not licenseType.vehicle_model then return nil, 'test_not_configured' end

    testPlateSequence = (testPlateSequence + 1) % 100000
    local prefix = tostring(CMLicenseConfig.TestVehicle.Plate or 'LIC'):upper()
        :gsub('[^A-Z0-9]', ''):sub(1, 3)
    if prefix == '' then prefix = 'LIC' end
    local wantedPlate = ('%s%05d'):format(prefix, testPlateSequence)
    local spawnOk, result = pcall(function()
        return exports['cm-vehicles']:SpawnAdminVehicle(src, licenseType.vehicle_model, spawn, {
            placementKind = placementKind(licenseType.vehicle_category, licenseType.vehicle_model),
            warp = true,
            invincible = false,
            plate = wantedPlate,
            label = ('%s examination'):format(tostring(licenseType.label or 'License')),
        })
    end)
    if not spawnOk or type(result) ~= 'table' or result.ok ~= true then
        return nil, result and result.error or 'vehicle_spawn_failed'
    end

    local entity = tonumber(result.entity)
    if entity and entity > 0 and DoesEntityExist(entity) then
        local state = Entity(entity).state
        state:set('cmLicenseTest', true, true)
        state:set('cmLicenseOwner', tostring(characterId), true)
        state:set('cmLicenseType', tostring(licenseType.license_type), true)
        if CMLicenseConfig.TestVehicle.MarkTemporary then
            state:set('cmTemporaryVehicle', true, true)
        end
    end

    if GetResourceState('cm-vehiclekeys') == 'started' then
        local duration = tonumber(CMLicenseConfig.TestVehicle.TempKeySeconds) or 7200
        local keyOk, granted, keyReason = pcall(function()
            return exports['cm-vehiclekeys']:GiveTempKey(0, src, result.plate, {
                durationSeconds = duration, kind = 'license_exam', reason = 'license_exam'
            })
        end)
        local hasKey = false
        if granted ~= true then
            local hasKeyOk, hasKeyResult = pcall(function()
                return exports['cm-vehiclekeys']:HasTempKey(src, result.plate)
            end)
            hasKey = hasKeyOk and hasKeyResult == true
        end
        if not keyOk or (granted ~= true and not hasKey) then
            print(('^1[CM-License]^7 Temporary key grant failed: character=%s plate=%s reason=%s')
                :format(tostring(characterId), tostring(result.plate), tostring(keyReason or 'unknown')))
            exports['cm-vehicles']:DeleteAdminVehicle(result.plate)
            return nil, 'temporary_key_failed'
        end

        -- cm-vehicles may not honour the requested plate. When it does not, the
        -- client relabels the vehicle for immersion, so a key for the visible
        -- plate is needed as well.
        if tostring(result.plate) ~= wantedPlate then
            local visualOk, visualGranted = pcall(function()
                return exports['cm-vehiclekeys']:GiveTempKey(0, src, wantedPlate, {
                    durationSeconds = duration, kind = 'license_exam', reason = 'license_exam_visual_plate'
                })
            end)
            local hasVisualKey = false
            if visualGranted ~= true then
                local hasVisualKeyOk, hasVisualKeyResult = pcall(function()
                    return exports['cm-vehiclekeys']:HasTempKey(src, wantedPlate)
                end)
                hasVisualKey = hasVisualKeyOk and hasVisualKeyResult == true
            end
            if not visualOk or (visualGranted ~= true and not hasVisualKey) then
                exports['cm-vehicles']:DeleteAdminVehicle(result.plate)
                return nil, 'temporary_key_failed'
            end
            result.keyPlate = wantedPlate
        end
    end

    return result
end

-- Seconds left before a fail cooldown allows another attempt (0 = allowed)
local function retryCooldownRemaining(characterId, licenseTypeId)
    local minutes = tonumber(config().RetryCooldownMinutes) or 0
    if minutes <= 0 then return 0 end

    local last = Database.GetLastAttempt(characterId, licenseTypeId)
    local endedAt = last and tonumber(last.test_ended_at or last.test_started_at)
    if not endedAt then return 0 end

    local remaining = (endedAt + (minutes * 60)) - os.time()
    return remaining > 0 and remaining or 0
end

local function validRouteForTest(licenseType, route)
    if type(route) ~= 'table' or type(licenseType) ~= 'table' then return nil end
    if tostring(route.license_type_id) ~= tostring(licenseType.id) then return nil end

    local spawn = Utils.DecodeObject(route.vehicle_spawn)
    if not Utils.IsValidCoords(spawn) then return nil end
    spawn.h = tonumber(spawn.h or spawn.heading) or 0.0
    if type(licenseType.vehicle_model) ~= 'string' or licenseType.vehicle_model == '' then return nil end

    local checkpoints = Cache.GetCheckpoints(route.id)
    if type(checkpoints) ~= 'table' or #checkpoints < 2 then return nil end

    local bounds = CMLicenseConfig.Checkpoint
    for index, checkpoint in ipairs(checkpoints) do
        if not Utils.IsValidCoords(checkpoint)
            or tonumber(checkpoint.sequence) ~= index
            or (index == 1 and checkpoint.point_type ~= Constants.CHECKPOINT_TYPE.START)
            or (index == #checkpoints and checkpoint.point_type ~= Constants.CHECKPOINT_TYPE.FINISH)
        then
            return nil
        end

        local radius = tonumber(checkpoint.radius)
        if radius and (radius < bounds.MinRadius or radius > bounds.MaxRadius) then return nil end
        local minAltitude, maxAltitude = tonumber(checkpoint.min_altitude), tonumber(checkpoint.max_altitude)
        if minAltitude and maxAltitude and minAltitude > maxAltitude then return nil end
    end

    return { route = route, checkpoints = checkpoints, spawn = spawn }
end

local function chooseRoute(licenseTypeId, licenseType)
    local valid = {}
    for _, route in ipairs(Cache.GetRoutes(licenseTypeId)) do
        local candidate = validRouteForTest(licenseType, route)
        if candidate then valid[#valid + 1] = candidate end
    end
    if #valid == 0 then return nil end
    return valid[math.random(#valid)]
end

function Tests.HasUsableRoute(licenseTypeId, licenseType)
    for _, route in ipairs(Cache.GetRoutes(licenseTypeId)) do
        if validRouteForTest(licenseType, route) then return true end
    end
    return false
end

local function sessionVehicle(session)
    local ped = GetPlayerPed(session and session.src or 0)
    -- Server-side ped death is represented by entity health in this runtime;
    -- IsEntityDead/IsPedDeadOrDying are client-only natives here.
    if ped == 0 or not DoesEntityExist(ped) or GetEntityHealth(ped) <= 0 then
        return nil, Constants.FAIL_REASON.PLAYER_DIED
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle)
        or NetworkGetNetworkIdFromEntity(vehicle) ~= tonumber(session.vehicleNetId)
        or GetPedInVehicleSeat(vehicle, -1) ~= ped
    then
        return nil, 'invalid_vehicle'
    end

    if GetVehicleEngineHealth(vehicle) <= 0 or GetEntityHealth(vehicle) <= 0 then
        return nil, Constants.FAIL_REASON.VEHICLE_DESTROYED
    end

    return vehicle, nil
end

local function routeDistance(session, vehicle, checkpointIndex)
    if not session or not vehicle or not DoesEntityExist(vehicle) then return nil end
    local checkpoints = Cache.GetCheckpoints(session.routeId)
    local checkpoint = checkpoints and checkpoints[checkpointIndex]
    if not checkpoint then return nil end
    local distance = Utils.CheckpointDistance(GetEntityCoords(vehicle), checkpoint, session.category)
    return distance
end

local function sessionExamVehicle(session)
    local vehicle = tonumber(session and session.vehicleEntity)
    if not vehicle or vehicle <= 0 or not DoesEntityExist(vehicle) then return nil end
    if tonumber(NetworkGetNetworkIdFromEntity(vehicle)) ~= tonumber(session.vehicleNetId) then return nil end
    return vehicle
end

-- Start a new test session
function Tests.StartTest(src, characterId, licenseTypeId)
    if not src or not characterId or not licenseTypeId then
        return false, 'invalid_params'
    end
    if GetPlayerRoutingBucket(src) ~= 0 then
        return false, 'public_world'
    end

    if not exports['cm-playerdata']:IsCharacterLoaded(src) then
        return false, 'character_not_loaded'
    end

    if Tests.StartLocks[characterId] then return false, 'request_in_progress' end
    Tests.StartLocks[characterId] = true
    local function finish(ok, value)
        Tests.StartLocks[characterId] = nil
        return ok, value
    end

    if Tests.ActiveSessions[characterId] then
        return finish(false, 'already_in_test')
    end

    if Database.GetActiveTest(characterId) then
        return finish(false, 'already_in_test')
    end

    local licenseType = Cache.GetLicenseType(licenseTypeId)
    if not licenseType then
        return finish(false, 'license_type_not_found')
    end

    if Licenses.HasLicense(characterId, licenseType.license_type) then
        return finish(false, 'already_licensed')
    end

    local cooldown = retryCooldownRemaining(characterId, licenseTypeId)
    if cooldown > 0 then
        return finish(false, ('retry_cooldown:%d'):format(math.ceil(cooldown / 60)))
    end

    -- One route is drawn at random from valid routes only. Invalid or partial
    -- admin data must never reach payment or vehicle spawn.
    local selected = chooseRoute(licenseTypeId, licenseType)
    if not selected then
        return finish(false, 'route_not_configured')
    end
    local route, checkpoints, spawn = selected.route, selected.checkpoints, selected.spawn
    debugLog(('route_selected test_pending license=%s routeId=%s label=%s spawn=(%.2f,%.2f,%.2f,%.2f) checkpoints=%d')
        :format(tostring(licenseType.license_type), tostring(route.id), tostring(route.label or ''),
            tonumber(spawn.x) or 0.0, tonumber(spawn.y) or 0.0, tonumber(spawn.z) or 0.0,
            tonumber(spawn.h or spawn.heading) or 0.0, #checkpoints))

    local playerPed = GetPlayerPed(src)
    local playerCoords = playerPed and playerPed > 0 and GetEntityCoords(playerPed) or nil
    local returnPosition = playerCoords and {
        x = playerCoords.x,
        y = playerCoords.y,
        z = playerCoords.z,
        heading = GetEntityHeading(playerPed)
    } or nil

    local price = math.max(0, math.floor(tonumber(licenseType.price) or 0))
    local paid = exports['cm-playerdata']:RemoveMoney(src, CMLicenseConfig.MoneyAccount, price, 'license_test_fee', {
        licenseTypeId = licenseTypeId, licenseType = licenseType.license_type
    })
    if not paid then
        return finish(false, 'insufficient_funds')
    end

    local vehicle, vehicleError = spawnTestVehicle(src, characterId, licenseType, spawn)
    if not vehicle then
        local refunded = exports['cm-playerdata']:AddMoney(src, CMLicenseConfig.MoneyAccount, price,
            'license_test_refund_spawn_failed', { licenseTypeId = licenseTypeId, error = vehicleError })
        if not refunded then
            print(('^1[CM-License]^7 Failed to refund fee after vehicle spawn failure: character=%s reason=%s')
                :format(tostring(characterId), tostring(vehicleError)))
        end
        return finish(false, vehicleError)
    end

    local maxMistakes = licenseType.vehicle_category == Constants.VEHICLE_CATEGORY.GROUND
        and (tonumber(config().MaxMistakes) or 3) or 0
    local testId = Database.CreateTestSession(characterId, licenseTypeId, route.id, #checkpoints, maxMistakes)

    if not testId then
        local refunded = exports['cm-playerdata']:AddMoney(src, CMLicenseConfig.MoneyAccount, price,
            'license_test_refund_db_error', { licenseTypeId = licenseTypeId })
        if not refunded then
            print(('^1[CM-License]^7 Failed to refund fee after test-session DB failure: character=%s')
                :format(tostring(characterId)))
        end
        deleteTestVehicle({ vehiclePlate = vehicle.plate, vehicleEntity = vehicle.entity })
        return finish(false, 'database_error')
    end

    local timeoutMinutes = tonumber(config().TimeoutMinutes) or 20
    local session = {
        testId = testId,
        licenseTypeId = tonumber(licenseTypeId),
        licenseType = licenseType.license_type,
        licenseLabel = licenseType.label,
        category = licenseType.vehicle_category,
        validDays = tonumber(licenseType.valid_days) or 30,
        characterId = characterId,
        src = src,
        routeId = route.id,
        routeLabel = route.label,
        totalCheckpoints = #checkpoints,
        currentCheckpoint = 0,
        status = Constants.TEST_STATUS.WAITING_START,
        startedAt = os.time(),
        expiresAt = os.time() + (timeoutMinutes * 60),
        vehicleNetId = tonumber(vehicle.netId),
        vehicleEntity = tonumber(vehicle.entity),
        vehiclePlate = tostring(vehicle.plate or ''),
        vehicleKeyPlate = tostring(vehicle.keyPlate or vehicle.plate or ''),
        returnPosition = returnPosition,
        feePaid = price,
        mistakes = 0,
        maxMistakes = maxMistakes,
        legStartDistance = nil,
        routeAbandonmentSince = nil,
        vehicleSeparationSince = nil,
        outOfVehicleSince = nil,
    }

    Tests.ActiveSessions[characterId] = session
    Tests.SessionsBySource[src] = session

    print(('^2[CM-License]^7 Test started: character=%s, license=%s, route=%s, testId=%s')
        :format(characterId, licenseType.license_type, tostring(route.label or route.id), testId))

    return finish(true, {
        testId = testId,
        licenseType = licenseType.license_type,
        licenseLabel = licenseType.label,
        category = licenseType.vehicle_category,
        vehicleModel = licenseType.vehicle_model,
        vehicleSpawn = spawn,
        routeLabel = route.label,
        routeCount = #Cache.GetRoutes(licenseTypeId),
        vehicleNetId = tonumber(vehicle.netId),
        vehiclePlate = tostring(vehicle.plate or ''),
        plateAlreadySet = tostring(vehicle.plate) == CMLicenseConfig.TestVehicle.Plate,
        maxMistakes = maxMistakes,
        timeoutSeconds = timeoutMinutes * 60,
        secondsRemaining = session.expiresAt - os.time(),
        checkpoints = checkpoints,
    })
end

-- The player crossed the start marker: the exam is now live.
function Tests.BeginTest(characterId, testId, vehicleNetId)
    local session = Tests.ActiveSessions[characterId]
    if not session or session.testId ~= tonumber(testId) or session.status ~= Constants.TEST_STATUS.WAITING_START then
        debugLog(('begin rejected char=%s test=%s reason=invalid_test_session'):format(characterId, tostring(testId)))
        return false, 'invalid_test_session'
    end

    if GetPlayerRoutingBucket(session.src) ~= 0 then
        return false, Constants.FAIL_REASON.LEFT_PUBLIC_WORLD
    end

    vehicleNetId = tonumber(vehicleNetId)
    if not vehicleNetId or vehicleNetId ~= tonumber(session.vehicleNetId) then
        debugLog(('begin rejected char=%s test=%s reason=invalid_vehicle'):format(characterId, tostring(testId)))
        return false, 'invalid_vehicle'
    end

    local entity, vehicleError = sessionVehicle(session)
    if not entity then
        debugLog(('begin rejected char=%s test=%s reason=%s'):format(characterId, tostring(testId), tostring(vehicleError)))
        return false, vehicleError
    end
    if NetworkGetNetworkIdFromEntity(entity) ~= vehicleNetId then
        debugLog(('begin rejected char=%s test=%s reason=invalid_vehicle'):format(characterId, tostring(testId)))
        return false, 'invalid_vehicle'
    end

    if os.time() >= tonumber(session.expiresAt or 0) then
        Tests.FailTest(characterId, Constants.FAIL_REASON.TIMEOUT)
        debugLog(('begin rejected char=%s test=%s reason=timeout'):format(characterId, tostring(testId)))
        return false, Constants.FAIL_REASON.TIMEOUT
    end

    local checkpoints = Cache.GetCheckpoints(session.routeId)
    local firstCheckpoint = checkpoints[1]
    if not firstCheckpoint then
        debugLog(('begin rejected char=%s test=%s reason=invalid_test_session'):format(characterId, tostring(testId)))
        return false, 'invalid_test_session'
    end
    local bounds = CMLicenseConfig.Checkpoint
    local startRadius = math.max(bounds.MinRadius,
        math.min(tonumber(firstCheckpoint.radius) or bounds.DefaultRadius, bounds.MaxRadius))
    local ped = GetPlayerPed(session.src)
    if ped == 0 or not DoesEntityExist(ped) then
        debugLog(('begin rejected char=%s test=%s reason=player_ped_missing'):format(characterId, tostring(testId)))
        return false, 'invalid_vehicle'
    end

    local playerCoords = GetEntityCoords(ped)
    local withinStart, distance, vertical = Utils.IsWithinCheckpoint(playerCoords, firstCheckpoint,
        session.category, startRadius)
    debugLog(('begin test char=%s test=%s start=1 distance=%.2f vertical=%.2f radius=%.2f')
        :format(characterId, tostring(testId), distance, vertical, startRadius))
    if not withinStart then
        debugLog(('begin rejected char=%s test=%s reason=start_too_far distance=%.1f radius=%.1f')
            :format(characterId, tostring(testId), distance, startRadius))
        return false, 'start_too_far'
    end

    session.vehicleNetId = vehicleNetId
    session.status = Constants.TEST_STATUS.IN_PROGRESS
    session.beganAt = os.time()
    local updateOk, updated = pcall(function()
        return Database.UpdateTestSession(session.testId, {
            status = session.status,
            vehicle_netid = vehicleNetId,
            test_began_at = session.beganAt,
            current_checkpoint = 1,
        })
    end)
    if not updateOk or not updated or tonumber(updated) == 0 then
        session.status = Constants.TEST_STATUS.WAITING_START
        session.beganAt = nil
        debugLog(('begin rejected char=%s test=%s reason=database_error'):format(characterId, tostring(testId)))
        return false, 'database_error'
    end

    session.currentCheckpoint = 1
    session.legStartDistance = routeDistance(session, entity, 2)
    session.routeAbandonmentSince = nil
    debugLog(('begin accepted char=%s test=%s currentCheckpoint=1 next=2'):format(characterId, tostring(testId)))
    return true, {
        secondsRemaining = math.max(0, session.expiresAt - os.time()),
        currentCheckpoint = 1,
        totalCheckpoints = session.totalCheckpoints,
        nextCheckpoint = session.totalCheckpoints >= 2 and 2 or nil,
    }
end

-- Update test checkpoint progression
function Tests.ReportCheckpoint(characterId, checkpointNumber)
    local session = Tests.ActiveSessions[characterId]
    if not session then
        return false, 'no_active_test'
    end

    checkpointNumber = tonumber(checkpointNumber)
    if session.status ~= Constants.TEST_STATUS.IN_PROGRESS or checkpointNumber ~= session.currentCheckpoint + 1 then
        debugLog(('checkpoint rejected char=%s requested=%s expected=%s reason=wrong_checkpoint_order')
            :format(characterId, tostring(checkpointNumber), tostring(session.currentCheckpoint + 1)))
        return false, 'wrong_checkpoint_order'
    end

    local checkpoints = Cache.GetCheckpoints(session.routeId)
    local checkpoint = checkpoints and checkpoints[checkpointNumber]
    local ped, actualVehicle, playerCoords, vehicleCoords, tracedDistance, tracedVertical, tracedRadius =
        checkpointTrace(session, checkpointNumber, checkpoint)
    local vehicle, vehicleError = sessionVehicle(session)
    if not checkpoint or not vehicle then
        local reason = vehicleError or 'invalid_vehicle'
        debugLog(('checkpoint rejected char=%s requested=%s expected=%s reason=%s')
            :format(characterId, tostring(checkpointNumber), tostring(session.currentCheckpoint + 1), reason))
        return false, reason
    end

    local speedLimit = tonumber(checkpoint.max_speed)
    if speedLimit and speedLimit > 0 and (GetEntitySpeed(vehicle) * 3.6) > speedLimit then
        debugLog(('checkpoint rejected char=%s requested=%s expected=%s reason=speeding speedKmh=%.2f limitKmh=%.2f')
            :format(characterId, tostring(checkpointNumber), tostring(session.currentCheckpoint + 1),
                GetEntitySpeed(vehicle) * 3.6, speedLimit))
        local survived = Tests.ReportMistake(characterId, Constants.FAIL_REASON.SPEEDING)
        return false, survived and Constants.FAIL_REASON.SPEEDING or 'too_many_mistakes'
    end

    if session.category == Constants.VEHICLE_CATEGORY.AIR then
        local altitude = GetEntityCoords(vehicle).z
        local minAltitude, maxAltitude = tonumber(checkpoint.min_altitude), tonumber(checkpoint.max_altitude)
        if (minAltitude and altitude < minAltitude) or (maxAltitude and altitude > maxAltitude) then
            debugLog(('checkpoint rejected char=%s requested=%s expected=%s reason=altitude_violation altitude=%.2f min=%s max=%s')
                :format(characterId, tostring(checkpointNumber), tostring(session.currentCheckpoint + 1), altitude,
                    tostring(minAltitude or 'n/a'), tostring(maxAltitude or 'n/a')))
            local survived = Tests.ReportMistake(characterId, Constants.FAIL_REASON.ALTITUDE_VIOLATION)
            return false, survived and Constants.FAIL_REASON.ALTITUDE_VIOLATION or 'too_many_mistakes'
        end
    end

    local bounds = CMLicenseConfig.Checkpoint
    local coords = session.category == Constants.VEHICLE_CATEGORY.GROUND and playerCoords
        or GetEntityCoords(vehicle)
    local radius = tracedRadius or Utils.CheckpointRadius(checkpoint)
    local within, distance, vertical = Utils.IsWithinCheckpoint(coords, checkpoint, session.category, radius)
    debugLog(('checkpoint_validation char=%s requested=%s expected=%s distance=%.2f vertical=%.2f radius=%.2f')
        :format(characterId, tostring(checkpointNumber), tostring(session.currentCheckpoint + 1), distance, vertical, radius))
    if not within then
        debugLog(('checkpoint rejected char=%s requested=%s expected=%s reason=checkpoint_too_far distance=%.1f radius=%.1f')
            :format(characterId, tostring(checkpointNumber), tostring(session.currentCheckpoint + 1), distance, radius))
        return false, 'checkpoint_too_far'
    end

    if checkpointNumber == session.totalCheckpoints and session.category == Constants.VEHICLE_CATEGORY.AIR then
        if math.abs(coords.z - checkpoint.z) > bounds.LandingVerticalTolerance
            or GetEntitySpeed(vehicle) > bounds.LandingMaxSpeed then
            debugLog(('checkpoint rejected char=%s requested=%s expected=%s reason=unsafe_landing distance=%.2f vertical=%.2f radius=%.2f')
                :format(characterId, tostring(checkpointNumber), tostring(session.currentCheckpoint + 1), distance, vertical, radius))
            return false, 'unsafe_landing'
        end
    end

    session.currentCheckpoint = checkpointNumber
    session.legStartDistance = routeDistance(session, vehicle, checkpointNumber + 1)
    session.routeAbandonmentSince = nil
    Database.UpdateTestSession(session.testId, { current_checkpoint = checkpointNumber })

    debugLog(('checkpoint accepted char=%s current=%s total=%s')
        :format(characterId, tostring(session.currentCheckpoint), tostring(session.totalCheckpoints)))

    return true
end

-- Record a driving mistake. Returns whether the test survived it.
function Tests.ReportMistake(characterId, reason)
    local session = Tests.ActiveSessions[characterId]
    if not session or session.status ~= Constants.TEST_STATUS.IN_PROGRESS then
        return false, 'no_active_test'
    end

    -- Debounced server-side too: a single impact must not burn three attempts.
    local now = GetGameTimer()
    if session.lastMistakeAt and (now - session.lastMistakeAt) < 3000 then
        return true, { mistakes = session.mistakes, maxMistakes = session.maxMistakes }
    end
    session.lastMistakeAt = now

    session.mistakes = session.mistakes + 1
    Database.UpdateTestSession(session.testId, { mistakes = session.mistakes })

    if session.mistakes >= session.maxMistakes then
        Tests.FailTest(characterId, Constants.FAIL_REASON.TOO_MANY_MISTAKES)
        return false, 'failed'
    end

    return true, { mistakes = session.mistakes, maxMistakes = session.maxMistakes, reason = reason }
end

-- Complete test and issue license
function Tests.CompleteTest(characterId)
    local session = Tests.ActiveSessions[characterId]
    if not session then
        return false, 'no_active_test'
    end

    -- The client asked to finish too early. The session stays alive so the
    -- player can carry on rather than being locked out until the timeout.
    if session.status ~= Constants.TEST_STATUS.IN_PROGRESS or session.currentCheckpoint ~= session.totalCheckpoints then
        return false, 'not_all_checkpoints_completed'
    end

    if session.completionLock then return false, 'completion_in_progress' end
    session.completionLock = true

    local vehicle, vehicleError = sessionVehicle(session)
    if not vehicle then
        Tests.FailTest(characterId, vehicleError)
        return false, vehicleError
    end

    -- Captured server-side before spawning the exam vehicle; never trust client coordinates.
    local returnPosition = session.returnPosition

    session.status = Constants.TEST_STATUS.COMPLETING
    Database.UpdateTestSession(session.testId, { status = Constants.TEST_STATUS.COMPLETING })

    local ok, licenseData = Licenses.IssueLicense(characterId, session.licenseTypeId)
    if not ok then
        print('^1[CM-License]^7 Failed to issue license: ' .. tostring(licenseData))
        Database.EndTestSession(session.testId, Constants.TEST_STATUS.FAILED, Constants.FAIL_REASON.LICENSE_ISSUANCE_FAILED)
        deleteTestVehicle(session)
        forgetSession(characterId)
        return false, Constants.FAIL_REASON.LICENSE_ISSUANCE_FAILED
    end

    -- Trusted server-local hook for future consumers (for example onboarding).
    -- This is deliberately TriggerEvent-only; clients cannot emit or forge it.
    TriggerEvent(Constants.EVENTS.LOCAL.LICENSE_GRANTED, {
        src = session.src,
        characterId = characterId,
        licenseType = session.licenseType,
        licenseId = licenseData.licenseId,
    })

    -- Hand over the physical card. If the inventory is full the entitlement
    -- stays pending and is delivered on the next load or maintenance pass.
    local delivered = false
    if session.src and session.src > 0 then
        local licenseType = Cache.GetLicenseType(session.licenseTypeId)
        if licenseType then
            local invOk, invErr = Licenses.AddInventoryItem(session.src, characterId, licenseType.item_name,
                licenseType.valid_days, licenseData.expiresAt, licenseData.issuedAt)
            if invOk then
                delivered = Database.MarkLicenseDelivered(characterId, session.licenseTypeId)
            else
                print('^1[CM-License]^7 Failed to add inventory item: ' .. tostring(invErr))
            end
        end
    end

    Database.EndTestSession(session.testId, Constants.TEST_STATUS.COMPLETED, nil)
    deleteTestVehicle(session)
    forgetSession(characterId)

    print('^2[CM-License]^7 Test completed: character=' .. characterId)

    return true, {
        licenseTypeId = session.licenseTypeId,
        licenseType = session.licenseType,
        licenseLabel = session.licenseLabel,
        category = session.category,
        validDays = licenseData.validDays,
        delivered = delivered,
        returnPosition = returnPosition,
    }
end

-- Fail a test
function Tests.FailTest(characterId, reason)
    local session = Tests.ActiveSessions[characterId]
    if not session then
        return false, 'no_active_test'
    end

    reason = tostring(reason or Constants.FAIL_REASON.CANCELLED)
    local status = reason == Constants.FAIL_REASON.CANCELLED
        and Constants.TEST_STATUS.CANCELLED or Constants.TEST_STATUS.FAILED

    Database.EndTestSession(session.testId, status, reason)
    deleteTestVehicle(session)
    forgetSession(characterId)

    print('^3[CM-License]^7 Test failed: character=' .. characterId .. ', reason=' .. reason)

    return true, session
end

-- Single server-side failure notification path for watchdog/system failures.
function Tests.FailTestAndNotify(characterId, reason)
    local failed, session = Tests.FailTest(characterId, reason)
    if not failed or not session or not session.src then return failed, session end

    local message = Constants.RESULT_MESSAGES[tostring(reason)] or 'Test failed'
    TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, session.src, {
        reason = reason, message = message,
    })
    TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_RESULT, session.src, {
        passed = false,
        licenseType = session.licenseType,
        category = session.category,
        failReason = message,
        message = 'Speak to the instructor to try again.',
    })
    return failed, session
end

-- Client failure reports are hints only. Accept them immediately only when
-- the server can verify the corresponding authoritative state; the watchdog
-- remains responsible for all timing- and distance-based failures.
function Tests.ValidateClientFailure(characterId, reason)
    local session = Tests.ActiveSessions[characterId]
    if not session then return false end
    reason = tostring(reason or '')

    if reason == Constants.FAIL_REASON.PLAYER_DIED then
        local ped = GetPlayerPed(session.src)
        return ped ~= 0 and DoesEntityExist(ped) and GetEntityHealth(ped) <= 0
    end

    if reason == Constants.FAIL_REASON.VEHICLE_DESTROYED
        or reason == Constants.FAIL_REASON.VEHICLE_SPAWN_FAILED
    then
        return sessionExamVehicle(session) == nil
    end

    if reason == Constants.FAIL_REASON.ABANDONED_VEHICLE then
        return Tests.CheckVehicleAbandonment(characterId) == true
    end

    return false
end

-- The client may request a check when its visible countdown reaches zero, but
-- only this server-side timer decides whether the authoritative grace period
-- has actually elapsed.
function Tests.CheckVehicleAbandonment(characterId)
    local session = Tests.ActiveSessions[characterId]
    if not session or session.status ~= Constants.TEST_STATUS.IN_PROGRESS then return false end

    local src = tonumber(session.src)
    if not src or GetPlayerRoutingBucket(src) ~= 0 then return false end

    local ped = GetPlayerPed(src)
    local examVehicle = sessionExamVehicle(session)
    if ped == 0 or not DoesEntityExist(ped) or not examVehicle then return false end

    local currentVehicle = GetVehiclePedIsIn(ped, false)
    local driving = currentVehicle == examVehicle
        and GetPedInVehicleSeat(examVehicle, -1) == ped
    local now = GetGameTimer()
    if driving then
        session.outOfVehicleSince = nil
        session.vehicleSeparationSince = nil
        return false
    end

    local distance = #(GetEntityCoords(ped) - GetEntityCoords(examVehicle))
    local maxVehicleDistance = tonumber(CMLicenseConfig.TestSession.MaxPlayerVehicleDistance) or 50.0
    if distance > maxVehicleDistance then
        session.vehicleSeparationSince = session.vehicleSeparationSince or now
        session.outOfVehicleSince = nil
        local grace = (tonumber(CMLicenseConfig.TestSession.VehicleSeparationGraceSeconds) or 5) * 1000
        return (now - session.vehicleSeparationSince) >= grace
    end

    session.vehicleSeparationSince = nil
    session.outOfVehicleSince = session.outOfVehicleSince or now
    local grace = (tonumber(CMLicenseConfig.TestSession.ReturnToVehicleSeconds) or 60) * 1000
    return (now - session.outOfVehicleSince) >= grace
end

function Tests.CancelTest(characterId)
    return Tests.FailTest(characterId, Constants.FAIL_REASON.CANCELLED)
end

function Tests.GetActiveTest(characterId)
    return Tests.ActiveSessions[characterId]
end

function Tests.GetActiveTestBySource(src)
    return Tests.SessionsBySource[src]
end

-- Authoritative active-session checks. This deliberately runs at a modest
-- cadence rather than trusting client failure reports for security decisions.
function Tests.Watchdog()
    local failures = {}
    local now = GetGameTimer()
    local routeAllowance = tonumber(CMLicenseConfig.TestSession.AbandonedDistance) or 500.0
    local routeGrace = (tonumber(CMLicenseConfig.TestSession.AbandonedGraceSeconds) or 30) * 1000

    for characterId, session in pairs(Tests.ActiveSessions) do
        local src = tonumber(session.src)
        local reason
        if not src or not GetPlayerName(src) then
            reason = Constants.FAIL_REASON.DISCONNECTED
        elseif GetPlayerRoutingBucket(src) ~= 0 then
            reason = Constants.FAIL_REASON.LEFT_PUBLIC_WORLD
        elseif exports['cm-playerdata']:GetCharacterId(src) ~= characterId then
            reason = Constants.FAIL_REASON.CHARACTER_CHANGED
        else
            local ped = GetPlayerPed(src)
            if ped == 0 or not DoesEntityExist(ped) then
                reason = Constants.FAIL_REASON.DISCONNECTED
            elseif GetEntityHealth(ped) <= 0 then
                reason = Constants.FAIL_REASON.PLAYER_DIED
            else
                local examVehicle = sessionExamVehicle(session)
                if not examVehicle or GetVehicleEngineHealth(examVehicle) <= 0
                    or GetEntityHealth(examVehicle) <= 0
                then
                    reason = Constants.FAIL_REASON.VEHICLE_DESTROYED
                elseif session.status == Constants.TEST_STATUS.IN_PROGRESS then
                    if Tests.CheckVehicleAbandonment(characterId) then
                        reason = Constants.FAIL_REASON.ABANDONED_VEHICLE
                    end

                    if not reason then
                        local nextIndex = (tonumber(session.currentCheckpoint) or 0) + 1
                        local distance = routeDistance(session, examVehicle, nextIndex)
                        if distance then
                            session.legStartDistance = session.legStartDistance or distance
                            if distance > session.legStartDistance + routeAllowance then
                                session.routeAbandonmentSince = session.routeAbandonmentSince or now
                                if (now - session.routeAbandonmentSince) >= routeGrace then
                                    reason = Constants.FAIL_REASON.ABANDONED_ROUTE
                                end
                            else
                                session.routeAbandonmentSince = nil
                            end
                        else
                            session.routeAbandonmentSince = nil
                        end
                    end
                end
            end
        end

        if reason then failures[#failures + 1] = { characterId = characterId, reason = reason } end
    end

    for _, failure in ipairs(failures) do
        Tests.FailTestAndNotify(failure.characterId, failure.reason)
    end
    return #failures
end

-- Handle player disconnect. characterId may already be gone by the time this
-- runs, so the source index is the fallback.
function Tests.OnPlayerDropped(characterId, src)
    local session = (characterId and Tests.ActiveSessions[characterId]) or (src and Tests.SessionsBySource[src])
    if session then
        Tests.FailTest(session.characterId, Constants.FAIL_REASON.DISCONNECTED)
    end
end

-- Fail sessions that ran past the configured time limit.
function Tests.CleanupExpiredSessions()
    local now = os.time()
    local expired = {}
    for charId, session in pairs(Tests.ActiveSessions) do
        if now >= (session.expiresAt or 0) then
            expired[#expired + 1] = { charId = charId, src = session.src,
                licenseType = session.licenseType, category = session.category }
        end
    end

    for _, entry in ipairs(expired) do
        Tests.FailTestAndNotify(entry.charId, Constants.FAIL_REASON.TIMEOUT)
    end

    return #expired
end

return Tests
