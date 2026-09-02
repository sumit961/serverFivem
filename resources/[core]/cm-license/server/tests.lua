-- CM License System — Test Session Management

Tests = {}
local MoneyAccount = 'cash'
local DefaultCheckpointRadius = 20.0

-- Active test sessions in memory (for quick lookup)
Tests.ActiveSessions = {}  -- [characterId] = { testId, licenseTypeId, ... }
Tests.StartLocks = {}

local function decodeObject(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' then return nil end
    local ok, decoded = pcall(json.decode, value)
    return ok and decoded or nil
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
        if session.vehicleKeyPlate then pcall(function() exports['cm-vehiclekeys']:RevokeAllForPlate(session.vehicleKeyPlate) end) end
    end
    if session.vehiclePlate and GetResourceState('cm-vehicles') == 'started' then
        pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(session.vehiclePlate) end)
    elseif session.vehicleEntity and DoesEntityExist(session.vehicleEntity) then
        DeleteEntity(session.vehicleEntity)
    end
end

local function spawnTestVehicle(src, characterId, licenseType, spawn)
    if GetResourceState('cm-vehicles') ~= 'started' then return nil, 'vehicle_service_unavailable' end
    if not spawn or not licenseType.vehicle_model then return nil, 'test_not_configured' end
    local result = exports['cm-vehicles']:SpawnAdminVehicle(src, licenseType.vehicle_model, spawn, {
        placementKind = placementKind(licenseType.vehicle_category, licenseType.vehicle_model),
        warp = true,
        invincible = false,
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
        state:set('cmTemporaryVehicle', true, true)
    end
    if GetResourceState('cm-vehiclekeys') == 'started' then
        local granted, keyReason = exports['cm-vehiclekeys']:GiveTempKey(0, src, result.plate, {
            durationSeconds = 7200, kind = 'license_exam', reason = 'license_exam'
        })
        local hasKey = granted == true
        if not hasKey then
            hasKey = exports['cm-vehiclekeys']:HasTempKey(src, result.plate) == true
        end
        local visualGranted = exports['cm-vehiclekeys']:GiveTempKey(0, src, 'LICENSE', {
            durationSeconds = 7200, kind = 'license_exam', reason = 'license_exam_visual_plate'
        })
        if visualGranted ~= true and exports['cm-vehiclekeys']:HasTempKey(src, 'LICENSE') ~= true then
            exports['cm-vehicles']:DeleteAdminVehicle(result.plate)
            return nil, 'temporary_key_failed'
        end
        result.keyPlate = 'LICENSE'
        if not hasKey then
            print(('^1[CM-License]^7 Temporary key grant failed: character=%s plate=%s reason=%s')
                :format(tostring(characterId), tostring(result.plate), tostring(keyReason or 'unknown')))
            exports['cm-vehicles']:DeleteAdminVehicle(result.plate)
            return nil, 'temporary_key_failed'
        end
    end
    return result
end

-- Start a new test session
function Tests.StartTest(src, characterId, licenseTypeId)
    if not src or not characterId or not licenseTypeId then
        return false, 'invalid_params'
    end
    
    -- Check character is loaded
    if not exports['cm-playerdata']:IsCharacterLoaded(src) then
        return false, 'character_not_loaded'
    end
    
    if Tests.StartLocks[characterId] then return false, 'request_in_progress' end
    Tests.StartLocks[characterId] = true
    local function finish(ok, value)
        Tests.StartLocks[characterId] = nil
        return ok, value
    end

    -- Check no active test already
    if Tests.ActiveSessions[characterId] then
        return finish(false, 'already_in_test')
    end
    
    local licenseType = Cache.GetLicenseType(licenseTypeId)
    if not licenseType then
        return finish(false, 'license_type_not_found')
    end
    
    -- Check player doesn't already have active license
    local hasLicense, _ = Licenses.HasLicense(characterId, licenseType.license_type)
    if hasLicense then
        return finish(false, 'already_licensed')
    end
    
    -- Check player can afford test fee
    -- Get route info
    local route = Cache.GetRoute(licenseTypeId)
    if not route then
        return finish(false, 'route_not_configured')
    end
    
    local checkpoints = Cache.GetCheckpoints(route.id)
    if not checkpoints or #checkpoints == 0 then
        return finish(false, 'route_not_configured')
    end

    local spawn = decodeObject(route.vehicle_spawn)
    local vehicle, vehicleError = spawnTestVehicle(src, characterId, licenseType, spawn)
    if not vehicle then return finish(false, vehicleError) end

    local price = math.max(0, math.floor(tonumber(licenseType.price) or 0))
    local ok, err = exports['cm-playerdata']:RemoveMoney(src, MoneyAccount, price, 'license_test_fee', {
        licenseTypeId = licenseTypeId, licenseType = licenseType.license_type
    })
    if not ok then
        deleteTestVehicle({ vehiclePlate = vehicle.plate, vehicleEntity = vehicle.entity })
        return finish(false, 'insufficient_funds')
    end
    
    -- Create test session in database
    local maxMistakes = licenseType.vehicle_category == Constants.VEHICLE_CATEGORY.GROUND and 3 or 0
    local testId = Database.CreateTestSession(characterId, licenseTypeId, #checkpoints, maxMistakes)
    
    if not testId then
        exports['cm-playerdata']:AddMoney(src, MoneyAccount, price, 'license_test_refund_db_error')
        deleteTestVehicle({ vehiclePlate = vehicle.plate, vehicleEntity = vehicle.entity })
        return finish(false, 'database_error')
    end
    
    -- Store in memory
    Tests.ActiveSessions[characterId] = {
        testId = testId,
        licenseTypeId = licenseTypeId,
        characterId = characterId,
        src = src,
        routeId = route.id,
        totalCheckpoints = #checkpoints,
        currentCheckpoint = 0,
        status = Constants.TEST_STATUS.WAITING_START,
        startedAt = os.time(),
        vehicleNetId = tonumber(vehicle.netId),
        vehicleEntity = tonumber(vehicle.entity),
        vehiclePlate = tostring(vehicle.plate or ''),
        vehicleKeyPlate = tostring(vehicle.keyPlate or ''),
        mistakes = 0,
        maxMistakes = maxMistakes
    }
    
    print('^2[CM-License]^7 Test started: character=' .. characterId .. ', license=' .. licenseType.license_type .. ', testId=' .. testId)
    
    return finish(true, {
        testId = testId,
        licenseType = licenseType.license_type,
        licenseLabel = licenseType.label,
        vehicleModel = licenseType.vehicle_model,
        vehicleSpawn = spawn,
        vehicleNetId = tonumber(vehicle.netId),
        checkpoints = checkpoints
    })
end

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
    Database.UpdateTestSession(session.testId, { status = session.status, vehicle_netid = vehicleNetId })
    return true
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
    local dx, dy, dz = coords.x - checkpoint.x, coords.y - checkpoint.y, coords.z - checkpoint.z
    local radius = math.max(2.0, math.min(tonumber(checkpoint.radius) or DefaultCheckpointRadius, 100.0))
    if (dx * dx + dy * dy + dz * dz) > radius * radius then return false, 'checkpoint_too_far' end
    if checkpointNumber == session.totalCheckpoints then
        local licenseType = Cache.GetLicenseType(session.licenseTypeId)
        if licenseType and licenseType.vehicle_category == Constants.VEHICLE_CATEGORY.AIR then
            if math.abs(coords.z - checkpoint.z) > 3.0 or GetEntitySpeed(vehicle) > 2.5 then
                return false, 'unsafe_landing'
            end
        end
    end
    
    session.currentCheckpoint = checkpointNumber
    Database.UpdateTestSession(session.testId, { current_checkpoint = checkpointNumber })
    
    return true
end

-- Complete test and issue license
function Tests.CompleteTest(characterId)
    local session = Tests.ActiveSessions[characterId]
    if not session then
        return false, 'no_active_test'
    end
    
    -- Validate all checkpoints completed
    if session.status ~= Constants.TEST_STATUS.IN_PROGRESS or session.currentCheckpoint ~= session.totalCheckpoints then
        return false, 'not_all_checkpoints_completed'
    end
    
    -- Mark as completing to prevent race conditions
    Database.UpdateTestSession(session.testId, { status = Constants.TEST_STATUS.COMPLETING })
    
    -- Issue license
    local ok, licenseData = Licenses.IssueLicense(characterId, session.licenseTypeId)
    if not ok then
        print('^1[CM-License]^7 Failed to issue license: ' .. tostring(licenseData))
        Database.UpdateTestSession(session.testId, { 
            status = Constants.TEST_STATUS.FAILED,
            fail_reason = 'license_issuance_failed'
        })
        Tests.ActiveSessions[characterId] = nil
        return false, 'license_issuance_failed'
    end
    
    -- Add inventory item
    local src = session.src
    if src and src > 0 then
        local licenseType = Cache.GetLicenseType(session.licenseTypeId)
        if licenseType then
            local invOk, invErr = Licenses.AddInventoryItem(src, characterId, licenseType.item_name, licenseType.valid_days, licenseData.expiresAt)
            if not invOk then
                print('^1[CM-License]^7 Failed to add inventory item: ' .. tostring(invErr))
            else
                Database.MarkLicenseDelivered(characterId, session.licenseTypeId)
            end
        end
    end
    
    -- Mark test as complete
    Database.UpdateTestSession(session.testId, { status = Constants.TEST_STATUS.COMPLETED })
    deleteTestVehicle(session)
    Tests.ActiveSessions[characterId] = nil
    
    print('^2[CM-License]^7 Test completed: character=' .. characterId)
    
    return true, {
        licenseType = session.licenseTypeId,
        licenseData = licenseData
    }
end

-- Fail a test
function Tests.FailTest(characterId, reason)
    local session = Tests.ActiveSessions[characterId]
    if not session then
        return false, 'no_active_test'
    end
    
    Database.UpdateTestSession(session.testId, { 
        status = Constants.TEST_STATUS.FAILED,
        fail_reason = reason
    })
    deleteTestVehicle(session)
    Tests.ActiveSessions[characterId] = nil
    
    print('^3[CM-License]^7 Test failed: character=' .. characterId .. ', reason=' .. reason)
    
    return true
end

-- Cancel test (player action)
function Tests.CancelTest(characterId)
    return Tests.FailTest(characterId, Constants.FAIL_REASON.CANCELLED)
end

-- Get active test info
function Tests.GetActiveTest(characterId)
    return Tests.ActiveSessions[characterId]
end

function Tests.DeleteVehicle(session)
    deleteTestVehicle(session)
end

-- Handle player disconnect
function Tests.OnPlayerDropped(characterId)
    if Tests.ActiveSessions[characterId] then
        Tests.FailTest(characterId, Constants.FAIL_REASON.DISCONNECTED)
    end
end

-- Clean up expired test sessions (more than 30 min old)
function Tests.CleanupExpiredSessions()
    local now = os.time()
    local maxAge = 30 * 60  -- 30 minutes
    
    for charId, session in pairs(Tests.ActiveSessions) do
        if (now - session.startedAt) > maxAge then
            Tests.FailTest(charId, Constants.FAIL_REASON.TIMEOUT)
        end
    end
end

-- Record checkpoint completion (for data tracking)
function Tests.RecordCheckpointCompletion(testId, checkpointNumber)
    -- Could be extended to track detailed progression history
    Database.UpdateTestSession(testId, { current_checkpoint = checkpointNumber })
end

return Tests
