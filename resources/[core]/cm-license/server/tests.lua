-- CM License System — Test Session Management

Tests = {}

-- Active test sessions in memory, keyed by character id.
Tests.ActiveSessions = {}
-- Secondary index so a session can still be found when cm-playerdata has
-- already released the character (disconnect ordering).
Tests.SessionsBySource = {}
Tests.StartLocks = {}

local function config()
    return CMLicenseConfig.TestSession
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

    local wantedPlate = CMLicenseConfig.TestVehicle.Plate
    local result = exports['cm-vehicles']:SpawnAdminVehicle(src, licenseType.vehicle_model, spawn, {
        placementKind = placementKind(licenseType.vehicle_category, licenseType.vehicle_model),
        warp = true,
        invincible = false,
        plate = wantedPlate,
        label = ('%s examination'):format(tostring(licenseType.label or 'License')),
    })
    if type(result) ~= 'table' or result.ok ~= true then
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
        local granted, keyReason = exports['cm-vehiclekeys']:GiveTempKey(0, src, result.plate, {
            durationSeconds = duration, kind = 'license_exam', reason = 'license_exam'
        })
        if granted ~= true and exports['cm-vehiclekeys']:HasTempKey(src, result.plate) ~= true then
            print(('^1[CM-License]^7 Temporary key grant failed: character=%s plate=%s reason=%s')
                :format(tostring(characterId), tostring(result.plate), tostring(keyReason or 'unknown')))
            exports['cm-vehicles']:DeleteAdminVehicle(result.plate)
            return nil, 'temporary_key_failed'
        end

        -- cm-vehicles may not honour the requested plate. When it does not, the
        -- client relabels the vehicle for immersion, so a key for the visible
        -- plate is needed as well.
        if tostring(result.plate) ~= wantedPlate then
            local visualGranted = exports['cm-vehiclekeys']:GiveTempKey(0, src, wantedPlate, {
                durationSeconds = duration, kind = 'license_exam', reason = 'license_exam_visual_plate'
            })
            if visualGranted ~= true and exports['cm-vehiclekeys']:HasTempKey(src, wantedPlate) ~= true then
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

-- Start a new test session
function Tests.StartTest(src, characterId, licenseTypeId)
    if not src or not characterId or not licenseTypeId then
        return false, 'invalid_params'
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

    -- One route is drawn at random from everything recorded for this type.
    local route = Cache.GetRandomRoute(licenseTypeId)
    if not route then
        return finish(false, 'route_not_configured')
    end

    local checkpoints = Cache.GetCheckpoints(route.id)
    if not checkpoints or #checkpoints < 2 then
        return finish(false, 'route_not_configured')
    end

    local playerPed = GetPlayerPed(src)
    local playerCoords = playerPed and playerPed > 0 and GetEntityCoords(playerPed) or nil
    local returnPosition = playerCoords and {
        x = playerCoords.x,
        y = playerCoords.y,
        z = playerCoords.z,
        heading = GetEntityHeading(playerPed)
    } or nil

    local spawn = Utils.DecodeObject(route.vehicle_spawn)
    local vehicle, vehicleError = spawnTestVehicle(src, characterId, licenseType, spawn)
    if not vehicle then return finish(false, vehicleError) end

    local price = math.max(0, math.floor(tonumber(licenseType.price) or 0))
    local paid = exports['cm-playerdata']:RemoveMoney(src, CMLicenseConfig.MoneyAccount, price, 'license_test_fee', {
        licenseTypeId = licenseTypeId, licenseType = licenseType.license_type
    })
    if not paid then
        deleteTestVehicle({ vehiclePlate = vehicle.plate, vehicleEntity = vehicle.entity })
        return finish(false, 'insufficient_funds')
    end

    local maxMistakes = licenseType.vehicle_category == Constants.VEHICLE_CATEGORY.GROUND
        and (tonumber(config().MaxMistakes) or 3) or 0
    local testId = Database.CreateTestSession(characterId, licenseTypeId, route.id, #checkpoints, maxMistakes)

    if not testId then
        exports['cm-playerdata']:AddMoney(src, CMLicenseConfig.MoneyAccount, price, 'license_test_refund_db_error')
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
        vehiclePlate = CMLicenseConfig.TestVehicle.Plate,
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
        return false, 'invalid_test_session'
    end

    vehicleNetId = tonumber(vehicleNetId)
    if not vehicleNetId or vehicleNetId ~= tonumber(session.vehicleNetId) then return false, 'invalid_vehicle' end

    local entity = NetworkGetEntityFromNetworkId(vehicleNetId)
    local ped = GetPlayerPed(session.src)
    if entity == 0 or not DoesEntityExist(entity) or ped == 0 or GetVehiclePedIsIn(ped, false) ~= entity then
        return false, 'invalid_vehicle'
    end

    session.vehicleNetId = vehicleNetId
    session.status = Constants.TEST_STATUS.IN_PROGRESS
    session.beganAt = os.time()
    Database.UpdateTestSession(session.testId, {
        status = session.status, vehicle_netid = vehicleNetId, test_began_at = session.beganAt
    })
    return true, { secondsRemaining = math.max(0, session.expiresAt - os.time()) }
end

-- Update test checkpoint progression
function Tests.ReportCheckpoint(characterId, checkpointNumber)
    local session = Tests.ActiveSessions[characterId]
    if not session then
        return false, 'no_active_test'
    end

    checkpointNumber = tonumber(checkpointNumber)
    if session.status ~= Constants.TEST_STATUS.IN_PROGRESS or checkpointNumber ~= session.currentCheckpoint + 1 then
        return false, 'wrong_checkpoint_order'
    end

    local checkpoints = Cache.GetCheckpoints(session.routeId)
    local checkpoint = checkpoints and checkpoints[checkpointNumber]
    local ped = GetPlayerPed(session.src)
    local vehicle = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if not checkpoint or vehicle == 0 or NetworkGetNetworkIdFromEntity(vehicle) ~= session.vehicleNetId then
        return false, 'invalid_vehicle'
    end

    local coords = GetEntityCoords(ped)
    local bounds = CMLicenseConfig.Checkpoint
    local radius = math.max(bounds.MinRadius, math.min(tonumber(checkpoint.radius) or bounds.DefaultRadius, bounds.MaxRadius))
    if Utils.DistanceSquared(coords, checkpoint) > radius * radius then
        return false, 'checkpoint_too_far'
    end

    if checkpointNumber == session.totalCheckpoints and session.category == Constants.VEHICLE_CATEGORY.AIR then
        if math.abs(coords.z - checkpoint.z) > bounds.LandingVerticalTolerance
            or GetEntitySpeed(vehicle) > bounds.LandingMaxSpeed then
            return false, 'unsafe_landing'
        end
    end

    session.currentCheckpoint = checkpointNumber
    Database.UpdateTestSession(session.testId, { current_checkpoint = checkpointNumber })

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

    if session.mistakes > session.maxMistakes then
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

    -- Hand over the physical card. If the inventory is full the entitlement
    -- stays pending and is delivered on the next load or maintenance pass.
    local delivered = false
    if session.src and session.src > 0 then
        local licenseType = Cache.GetLicenseType(session.licenseTypeId)
        if licenseType then
            local invOk, invErr = Licenses.AddInventoryItem(session.src, characterId, licenseType.item_name,
                licenseType.valid_days, licenseData.expiresAt)
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
        licenseData = licenseData,
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

function Tests.CancelTest(characterId)
    return Tests.FailTest(characterId, Constants.FAIL_REASON.CANCELLED)
end

function Tests.GetActiveTest(characterId)
    return Tests.ActiveSessions[characterId]
end

function Tests.GetActiveTestBySource(src)
    return Tests.SessionsBySource[src]
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
        Tests.FailTest(entry.charId, Constants.FAIL_REASON.TIMEOUT)
        if entry.src then
            TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_FAILED, entry.src, {
                reason = Constants.FAIL_REASON.TIMEOUT,
                message = Constants.RESULT_MESSAGES.timeout,
            })
            TriggerClientEvent(Constants.EVENTS.CLIENT.TEST_RESULT, entry.src, {
                passed = false,
                licenseType = entry.licenseType,
                category = entry.category,
                failReason = Constants.RESULT_MESSAGES.timeout,
                message = 'Speak to the instructor to try again.',
            })
        end
    end

    return #expired
end

return Tests
