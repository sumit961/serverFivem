-- CM License System — Client Test Management

local Constants = require 'shared.constants'
local Utils = require 'shared.utils'

local Test = {}

Test.ActiveTest = nil
Test.TestVehicle = nil
Test.CurrentCheckpoint = 0

function Test.Init()
    print('^2[CM-License Test]^7 Test system initialized')
end

-- Spawn test vehicle
function Test.SpawnVehicle(model, spawnCoords)
    if not model or not spawnCoords then
        return false, 'invalid_params'
    end

    local modelHash = GetHashKey(model)
    RequestModel(modelHash)

    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end

    if not HasModelLoaded(modelHash) then
        print('^1[CM-License]^7 Failed to load vehicle model: ' .. model)
        return false, 'model_load_failed'
    end

    -- Spawn vehicle
    local vehicle = CreateVehicle(modelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.heading or 0.0, true, false)

    if not DoesEntityExist(vehicle) then
        return false, 'spawn_failed'
    end

    -- Configure vehicle
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehicleBodyHealth(vehicle, 1000.0)
    SetVehicleDeformationFixed(vehicle)
    SmashVehicleWindow(vehicle, 0, false)
    SmashVehicleWindow(vehicle, 1, false)
    SmashVehicleWindow(vehicle, 2, false)
    SmashVehicleWindow(vehicle, 3, false)

    Test.TestVehicle = vehicle
    return true, vehicle
end

-- Check if player is at start point and can begin test
function Test.CheckStartPoint()
    if not Test.ActiveTest then return end

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        TriggerEvent('chat:addMessage', {
            args = { 'Error', 'You must be in the test vehicle' }
        })
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= Test.TestVehicle then
        TriggerEvent('chat:addMessage', {
            args = { 'Error', 'You must be in the test vehicle' }
        })
        return
    end

    -- Check if at start point (would need to validate coordinates)
    -- For now, just allow immediate start

    Test.BeginTest()
end

-- Begin test (start timer and checkpoint monitoring)
function Test.BeginTest()
    if not Test.ActiveTest then return end

    print('^2[CM-License]^7 Test beginning...')

    -- Notify server
    TriggerServerEvent(Constants.EVENTS.SERVER.START_TEST, Test.ActiveTest.testId)

    -- Start HUD
    require 'client.hud'.StartTest(Test.ActiveTest)

    -- Start checkpoint monitoring
    require 'client.checkpoints'.StartMonitoring()
end

-- Report checkpoint reached to server
function Test.ReportCheckpoint(checkpointNumber)
    if not Test.ActiveTest then return end

    TriggerServerEvent(Constants.EVENTS.SERVER.CHECKPOINT_REACHED, checkpointNumber)
end

-- Report test failure
function Test.ReportFailure(reason)
    if not Test.ActiveTest then return end

    print('^3[CM-License]^7 Test failed: ' .. reason)

    TriggerServerEvent(Constants.EVENTS.SERVER.TEST_FAILED, reason)

    Test.Cleanup()
end

-- Report test completion
function Test.ReportCompletion()
    if not Test.ActiveTest then return end

    TriggerServerEvent(Constants.EVENTS.SERVER.FINISH_TEST)

    Test.Cleanup()
end

-- Cleanup test state
function Test.Cleanup()
    if Test.TestVehicle and DoesEntityExist(Test.TestVehicle) then
        DeleteEntity(Test.TestVehicle)
    end

    Test.ActiveTest = nil
    Test.TestVehicle = nil
    Test.CurrentCheckpoint = 0

    require 'client.hud'.StopTest()
    require 'client.checkpoints'.StopMonitoring()
end

-- Update test state (health, distance, etc)
function Test.UpdateTestState()
    if not Test.ActiveTest or not Test.TestVehicle then return end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    -- Check if player left vehicle
    if vehicle ~= Test.TestVehicle then
        Test.ReportFailure(Constants.FAIL_REASON.ABANDONED_VEHICLE)
        return
    end

    -- Check vehicle health
    local health = GetVehicleEngineHealth(vehicle)
    if health <= 0 then
        Test.ReportFailure(Constants.FAIL_REASON.VEHICLE_DESTROYED)
        return
    end

    -- Check if player died
    if IsPedDeadOrDying(ped, true) then
        Test.ReportFailure(Constants.FAIL_REASON.PLAYER_DIED)
        return
    end
end

return Test
