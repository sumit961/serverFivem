-- CM License System — Client Test Management
--
-- Client.ActiveTest (declared in client/main.lua) is the single source of truth
-- for "am I in a test". This module never keeps a second copy of it.

Test = {}

Test.TestVehicle = nil
Test.BeginRequested = false
Test.CompletionPending = false
Test.CompletionSentAt = nil
Test.OutOfVehicleSince = nil
Test.LastReturnWarningSecond = nil
Test.LastBodyHealth = nil
Test.LastMistakeAt = 0
Test.StrayingSince = nil

function Test.Init()
    CMLog('Test system initialized')
end

local function session()
    return Client.ActiveTest
end

local function category()
    local active = session()
    return active and active.category or 'ground'
end

-- Check if player is at the start point and can begin the exam
function Test.CheckStartPoint()
    local active = session()
    if not active or Checkpoints.Monitoring or Test.BeginRequested then return end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or vehicle ~= Test.TestVehicle then
        Client.Notify('You must be in the test vehicle.', 'error')
        return
    end

    local startPoint = Checkpoints.Checkpoints[1]
    if not startPoint then return end

    local distance = Utils.Distance(GetEntityCoords(ped), vector3(startPoint.x, startPoint.y, startPoint.z))
    if distance > Utils.TouchRadius(category()) then
        Client.Notify('Drive to the cyan start marker first.', 'inform')
        return
    end

    Test.BeginTest()
end

-- Begin the exam (start the clock and checkpoint monitoring)
function Test.BeginTest()
    local active = session()
    if not active or Test.BeginRequested then return end
    Test.BeginRequested = true

    CMLog('Test beginning...')

    TriggerServerEvent(Constants.EVENTS.SERVER.START_TEST, active.testId, NetworkGetNetworkIdFromEntity(Test.TestVehicle))

    HUD.StartTest(active)
    Checkpoints.StartMonitoring()

    Test.LastBodyHealth = GetVehicleBodyHealth(Test.TestVehicle)
end

function Test.ReportCheckpoint(checkpointNumber)
    if not session() then return end
    TriggerServerEvent(Constants.EVENTS.SERVER.CHECKPOINT_REACHED, checkpointNumber)
end

function Test.ReportMistake(reason)
    if not session() then return end
    local now = GetGameTimer()
    if (now - Test.LastMistakeAt) < 3000 then return end
    Test.LastMistakeAt = now
    TriggerServerEvent(Constants.EVENTS.SERVER.REPORT_MISTAKE, reason)
end

-- Report a failure. The server confirms it; local state is cleared only when
-- that confirmation arrives, so a dropped packet cannot desync the two sides.
function Test.ReportFailure(reason)
    local active = session()
    if not active or active.failureReported then return end
    active.failureReported = true

    CMLog('Reporting test failure: ' .. tostring(reason))
    TriggerServerEvent(Constants.EVENTS.SERVER.TEST_FAILED, reason)
end

-- Ask the server to finish. Retried until it answers one way or the other.
function Test.ReportCompletion()
    if not session() or Test.CompletionPending then return end
    Test.CompletionPending = true
    Test.CompletionSentAt = GetGameTimer()
    TriggerServerEvent(Constants.EVENTS.SERVER.FINISH_TEST)
end

function Test.RetryCompletionIfStalled()
    if not Test.CompletionPending or not Test.CompletionSentAt then return end
    if (GetGameTimer() - Test.CompletionSentAt) < 4000 then return end
    Test.CompletionSentAt = GetGameTimer()
    TriggerServerEvent(Constants.EVENTS.SERVER.FINISH_TEST)
end

-- The server rejected the finish request: carry on from where it thinks we are.
function Test.ResumeAfterRejectedCompletion(data)
    Test.CompletionPending = false
    Test.CompletionSentAt = nil
    if data and tonumber(data.currentCheckpoint) then
        Checkpoints.CurrentCheckpoint = tonumber(data.currentCheckpoint)
        Checkpoints.AwaitingAck = false
        Checkpoints.UpdateRouteBlip()
    end
    Client.Notify('You still have checkpoints left to complete.', 'error')
end

-- Cleanup test state
function Test.Cleanup()
    Client.ActiveTest = nil
    Test.TestVehicle = nil
    Test.BeginRequested = false
    Test.CompletionPending = false
    Test.CompletionSentAt = nil
    Test.OutOfVehicleSince = nil
    Test.LastReturnWarningSecond = nil
    Test.LastBodyHealth = nil
    Test.StrayingSince = nil

    HUD.StopTest()
    Checkpoints.StopMonitoring()
end

local function handleOutOfVehicle(active)
    if GetGameTimer() < tonumber(active.seatingGraceUntil or 0) then return end

    local now = GetGameTimer()
    local limit = tonumber(CMLicenseConfig.TestSession.ReturnToVehicleSeconds) or 60
    Test.OutOfVehicleSince = Test.OutOfVehicleSince or now

    local remaining = math.max(0, limit - math.floor((now - Test.OutOfVehicleSince) / 1000))
    if remaining ~= Test.LastReturnWarningSecond then
        Test.LastReturnWarningSecond = remaining
        Client.Alert(('~r~RETURN TO THE TEST VEHICLE: %d SECONDS~s~'):format(remaining), 1200)
    end

    if remaining <= 0 then
        Test.ReportFailure(Constants.FAIL_REASON.ABANDONED_VEHICLE)
    end
end

-- Straying far past the next checkpoint counts as abandoning the route.
local function checkRouteAbandonment(coords)
    local nextIndex = Checkpoints.CurrentCheckpoint + 1
    local nextPoint = Checkpoints.Checkpoints[nextIndex]
    if not nextPoint or not Checkpoints.Monitoring then
        Test.StrayingSince = nil
        return
    end

    local allowance = tonumber(CMLicenseConfig.TestSession.AbandonedDistance) or 500
    local baseline = Checkpoints.LegStartDistance or 0
    local distance = Utils.Distance(coords, vector3(nextPoint.x, nextPoint.y, nextPoint.z))

    if distance <= (baseline + allowance) then
        if Test.StrayingSince then
            Test.StrayingSince = nil
            Client.Alert('~g~Back on route.~s~', 1500)
        end
        return
    end

    local grace = tonumber(CMLicenseConfig.TestSession.AbandonedGraceSeconds) or 30
    Test.StrayingSince = Test.StrayingSince or GetGameTimer()
    local remaining = math.max(0, grace - math.floor((GetGameTimer() - Test.StrayingSince) / 1000))

    if remaining <= 0 then
        Test.ReportFailure(Constants.FAIL_REASON.ABANDONED_ROUTE)
    else
        Client.Alert(('~r~RETURN TO THE ROUTE: %d SECONDS~s~'):format(remaining), 1200)
    end
end

-- Body damage counts as a driving mistake on ground exams only.
local function checkDrivingMistakes(vehicle)
    if category() ~= Constants.VEHICLE_CATEGORY.GROUND then return end
    if not Checkpoints.Monitoring then return end

    local bodyHealth = GetVehicleBodyHealth(vehicle)
    local previous = Test.LastBodyHealth or bodyHealth
    Test.LastBodyHealth = bodyHealth

    if (previous - bodyHealth) > 15.0 then
        Test.ReportMistake('collision')
    end
end

-- Update test state (seating, health, mistakes, straying)
function Test.UpdateTestState()
    local active = session()
    if not active or not Test.TestVehicle then return end

    Test.RetryCompletionIfStalled()

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= Test.TestVehicle then
        handleOutOfVehicle(active)
        return
    end

    Test.OutOfVehicleSince = nil
    Test.LastReturnWarningSecond = nil

    if GetVehicleEngineHealth(vehicle) <= 0 or IsEntityDead(vehicle) then
        Test.ReportFailure(Constants.FAIL_REASON.VEHICLE_DESTROYED)
        return
    end

    if IsPedDeadOrDying(ped, true) then
        Test.ReportFailure(Constants.FAIL_REASON.PLAYER_DIED)
        return
    end

    checkDrivingMistakes(vehicle)
    checkRouteAbandonment(GetEntityCoords(ped))
end

return Test
