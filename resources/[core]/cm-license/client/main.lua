-- CM License System — Client Main

Client = {
    ActiveTest = nil,
    NPCLocations = {},
    CurrentHUD = nil
}

-- Check if currently in test
function Client.IsInTest()
    return Client.ActiveTest ~= nil
end

-- Initialize client
AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    print('^2[CM-License Client]^7 Started')
    
    -- Initialize NPC interactions
    NPC.Init()
    
    -- Initialize test system
    Test.Init()
    
    -- Initialize checkpoint markers
    Checkpoints.Init()
    
    -- Initialize HUD
    HUD.Init()
end)

-- Test started event
RegisterNetEvent(Constants.EVENTS.CLIENT.TEST_STARTED, function(data)
    if not data then return end
    SendNUIMessage({ type = 'hideLoading' })
    SendNUIMessage({ type = 'builderHint', message = nil })
    
    Client.ActiveTest = {
        testId = data.testId,
        licenseType = data.licenseType,
        licenseLabel = data.licenseLabel,
        vehicleModel = data.vehicleModel,
        vehicleSpawn = data.vehicleSpawn,
        currentCheckpoint = 0,
        seatingGraceUntil = GetGameTimer() + 8000
    }

    local test = Test
    test.ActiveTest = Client.ActiveTest
    Checkpoints.SetCheckpoints(data.checkpoints or {})
    local netId = tonumber(data.vehicleNetId)
    local timeout = GetGameTimer() + 10000
    while netId and not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer() < timeout do Wait(50) end
    local vehicle = netId and NetToVeh(netId) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        TriggerServerEvent(Constants.EVENTS.SERVER.TEST_FAILED, 'vehicle_spawn_failed')
        Client.ActiveTest = nil
        test.ActiveTest = nil
        return
    end
    test.TestVehicle = vehicle
    Client.ActiveTest.vehicleNetId = netId
    SetEntityAsMissionEntity(vehicle, false, false)
    SetVehicleCustomPrimaryColour(vehicle, 0, 229, 255)
    SetVehicleCustomSecondaryColour(vehicle, 5, 28, 36)
    SetVehicleNumberPlateText(vehicle, 'LICENSE')
    SetVehicleNumberPlateTextIndex(vehicle, 0)
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= vehicle then
        TaskWarpPedIntoVehicle(ped, vehicle, -1)
    end
    
    print('^2[CM-License]^7 Test started: ' .. data.licenseLabel)
    
    -- Notify player
    TriggerEvent('chat:addMessage', {
        args = { 'License System', 'Test started! Proceed to the vehicle spawn location.' }
    })
    
    -- The driving timer begins only when the player reaches the start marker.
end)

-- Checkpoint update event
RegisterNetEvent(Constants.EVENTS.CLIENT.SET_CHECKPOINT, function(data)
    if not Client.ActiveTest then return end
    
    Client.ActiveTest.currentCheckpoint = data.currentCheckpoint
    Checkpoints.CurrentCheckpoint = data.currentCheckpoint
    Checkpoints.AwaitingAck = false
    Checkpoints.UpdateRouteBlip()
    local completed = data.currentCheckpoint >= data.totalCheckpoints
    PlaySoundFrontend(-1, completed and 'CHECKPOINT_PERFECT' or 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', true)
    Checkpoints.ShowInstruction(data.currentCheckpoint)
    
    print('^2[CM-License]^7 Checkpoint ' .. data.currentCheckpoint .. '/' .. data.totalCheckpoints)
    
    -- Update HUD
    HUD.UpdateCheckpoint(data)
    
    -- Show notification
    TriggerEvent('chat:addMessage', {
        args = { 'Checkpoint', data.currentCheckpoint .. ' / ' .. data.totalCheckpoints }
    })
end)

-- Test completed event
RegisterNetEvent(Constants.EVENTS.CLIENT.TEST_COMPLETED, function(data)
    if not Client.ActiveTest then return end
    
    print('^2[CM-License]^7 Test completed!')
    
    -- Stop HUD
    HUD.StopTest()
    
    Client.ActiveTest = nil
    Test.Cleanup()
    
    -- Show success screen
    TriggerEvent('chat:addMessage', {
        args = { 'Success', 'Test passed! License added to inventory.' },
        color = { 0, 255, 0 }
    })
end)

-- Test failed event
RegisterNetEvent(Constants.EVENTS.CLIENT.TEST_FAILED, function(data)
    SendNUIMessage({ type = 'hideLoading' })
    
    print('^3[CM-License]^7 Test failed: ' .. tostring(data.reason))
    
    -- Stop HUD
    HUD.StopTest()
    
    if Client.ActiveTest then
        Client.ActiveTest = nil
        Test.Cleanup()
    end
    
    -- Show failure message
    TriggerEvent('chat:addMessage', {
        args = { 'Test Failed', data.message or 'Unknown reason' },
        color = { 255, 0, 0 }
    })
end)

-- Update HUD event
RegisterNetEvent(Constants.EVENTS.CLIENT.UPDATE_HUD, function(data)
    if not Client.ActiveTest then return end
    HUD.Update(data)
end)

-- ============================================================================
-- KEYBINDS
-- ============================================================================

-- E key for interactions
Citizen.CreateThread(function()
    while true do
        Wait(0)
        
        if IsControlJustReleased(0, 38) then  -- E key
            -- Check if near NPC
            NPC.CheckNPCInteraction()
            
            -- Check if can start test at start point
            if Client.IsInTest() then
                Test.CheckStartPoint()
            end
        end
    end
end)

RegisterNetEvent('cm-license:client:checkpointRejected', function(message)
    Checkpoints.AwaitingAck = false
    if message then
        BeginTextCommandPrint('STRING')
        AddTextComponentSubstringPlayerName(('~y~%s~s~'):format(tostring(message)))
        EndTextCommandPrint(2500, true)
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Test.Cleanup()
    for _, ped in ipairs(NPC.Peds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    SetNuiFocus(false, false)
end)

Citizen.CreateThread(function()
    while true do
        if Client.IsInTest() then
            Wait(0)
            Checkpoints.DrawMarkers()
        else
            Wait(500)
        end
    end
end)

-- ============================================================================
-- MAIN LOOP
-- ============================================================================

Citizen.CreateThread(function()
    while true do
        Wait(500)  -- Update HUD every 500ms
        
        if Client.IsInTest() then
            Test.UpdateTestState()
            HUD.Update()
        end
    end
end)

print('^2[CM-License Client]^7 Client loaded')
