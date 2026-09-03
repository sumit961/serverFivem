-- CM License System — Test Session Management

local Database = require 'server.database'
local Cache = require 'server.cache'
local Licenses = require 'server.licenses'
local Constants = require 'shared.constants'
local Utils = require 'shared.utils'

local Tests = {}

-- Active test sessions in memory (for quick lookup)
Tests.ActiveSessions = {}  -- [characterId] = { testId, licenseTypeId, ... }

-- Start a new test session
function Tests.StartTest(src, characterId, licenseTypeId)
    if not src or not characterId or not licenseTypeId then
        return false, 'invalid_params'
    end

    -- Check character is loaded
    if not exports['cm-playerdata']:IsLoaded(src) then
        return false, 'character_not_loaded'
    end

    -- Check no active test already
    if Tests.ActiveSessions[characterId] then
        return false, 'already_in_test'
    end

    local licenseType = Cache.GetLicenseType(licenseTypeId)
    if not licenseType then
        return false, 'license_type_not_found'
    end

    -- Check player doesn't already have active license
    local hasLicense, _ = Licenses.HasLicense(characterId, licenseType.license_type)
    if hasLicense then
        return false, 'already_licensed'
    end

    -- Check player can afford test fee
    if not exports['cm-playerdata']:CanAfford(src, 'cash', licenseType.price) then
        return false, 'insufficient_funds'
    end

    -- Deduct money
    local ok, err = exports['cm-playerdata']:RemoveMoney(src, 'cash', licenseType.price, 'license_test_fee')
    if not ok then
        print('^1[CM-License]^7 Failed to deduct money: ' .. tostring(err))
        return false, 'payment_failed'
    end

    -- Get route info
    local route = Cache.GetRoute(licenseTypeId)
    if not route then
        -- Refund money on error
        exports['cm-playerdata']:AddMoney(src, 'cash', licenseType.price, 'license_test_refund_route_not_found')
        return false, 'route_not_configured'
    end

    local checkpoints = Cache.GetCheckpoints(route.id)
    if not checkpoints or #checkpoints == 0 then
        exports['cm-playerdata']:AddMoney(src, 'cash', licenseType.price, 'license_test_refund_no_checkpoints')
        return false, 'route_not_configured'
    end

    -- Create test session in database
    local maxMistakes = licenseType.vehicle_category == Constants.VEHICLE_CATEGORY.GROUND and 3 or 0
    local testId = Database.CreateTestSession(characterId, licenseTypeId, #checkpoints, maxMistakes)

    if not testId then
        exports['cm-playerdata']:AddMoney(src, 'cash', licenseType.price, 'license_test_refund_db_error')
        return false, 'database_error'
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
        vehicleNetId = nil,
        mistakes = 0,
        maxMistakes = maxMistakes
    }

    print('^2[CM-License]^7 Test started: character=' .. characterId .. ', license=' .. licenseType.license_type .. ', testId=' .. testId)

    return true, {
        testId = testId,
        licenseType = licenseType.license_type,
        licenseLabel = licenseType.label,
        vehicleModel = licenseType.vehicle_model,
        vehicleSpawn = route.vehicle_spawn
    }
end

-- Update test checkpoint progression
function Tests.ReportCheckpoint(characterId, checkpointNumber)
    local session = Tests.ActiveSessions[characterId]
    if not session then
        return false, 'no_active_test'
    end

    -- Validate checkpoint order
    if checkpointNumber ~= session.currentCheckpoint + 1 then
        return false, 'wrong_checkpoint_order'
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
    if session.currentCheckpoint ~= session.totalCheckpoints then
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
                -- License is already issued, but item wasn't added
                -- This is a recovery scenario - log it but don't fail
            end
        end
    end

    -- Mark test as complete
    Database.UpdateTestSession(session.testId, { status = Constants.TEST_STATUS.COMPLETED })
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
