-- CM License System — Client Main

local Constants = require 'shared.constants'
local Utils = require 'shared.utils'

local Client = {
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

    -- Initialize NUI callbacks
    require 'client.nui'

    -- Initialize NPC interactions
    require 'client.npc'.Init()

    -- Initialize test system
    require 'client.test'.Init()

    -- Initialize checkpoint markers
    require 'client.checkpoints'.Init()

    -- Initialize HUD
    require 'client.hud'.Init()
end)

-- Test started event
RegisterNetEvent(Constants.EVENTS.CLIENT.TEST_STARTED, function(data)
    if not data then return end

    Client.ActiveTest = {
        testId = data.testId,
        licenseType = data.licenseType,
        licenseLabel = data.licenseLabel,
        vehicleModel = data.vehicleModel,
        vehicleSpawn = data.vehicleSpawn,
        currentCheckpoint = 0
    }

    print('^2[CM-License]^7 Test started: ' .. data.licenseLabel)

    -- Notify player
    TriggerEvent('chat:addMessage', {
        args = { 'License System', 'Test started! Proceed to the vehicle spawn location.' }
    })

    -- Start HUD
    require 'client.hud'.StartTest(Client.ActiveTest)
end)

-- Checkpoint update event
RegisterNetEvent(Constants.EVENTS.CLIENT.SET_CHECKPOINT, function(data)
    if not Client.ActiveTest then return end

    Client.ActiveTest.currentCheckpoint = data.currentCheckpoint

    print('^2[CM-License]^7 Checkpoint ' .. data.currentCheckpoint .. '/' .. data.totalCheckpoints)

    -- Update HUD
    require 'client.hud'.UpdateCheckpoint(data)

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
    require 'client.hud'.StopTest()

    Client.ActiveTest = nil

    -- Show success screen
    TriggerEvent('chat:addMessage', {
        args = { 'Success', 'Test passed! License added to inventory.' },
        color = { 0, 255, 0 }
    })
end)

-- Test failed event
RegisterNetEvent(Constants.EVENTS.CLIENT.TEST_FAILED, function(data)
    if not Client.ActiveTest then return end

    print('^3[CM-License]^7 Test failed: ' .. tostring(data.reason))

    -- Stop HUD
    require 'client.hud'.StopTest()

    Client.ActiveTest = nil

    -- Show failure message
    TriggerEvent('chat:addMessage', {
        args = { 'Test Failed', data.message or 'Unknown reason' },
        color = { 255, 0, 0 }
    })
end)

-- Update HUD event
RegisterNetEvent(Constants.EVENTS.CLIENT.UPDATE_HUD, function(data)
    if not Client.ActiveTest then return end
    require 'client.hud'.Update(data)
end)

-- Open admin menu event
RegisterNetEvent('cm-license:client:openAdminMenu', function()
    require 'client.admin'.OpenMenu()
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
            require 'client.npc'.CheckNPCInteraction()

            -- Check if can start test at start point
            if Client.IsInTest() then
                require 'client.test'.CheckStartPoint()
            end
        end
    end
end)

-- G key for route creation (admin only)
Citizen.CreateThread(function()
    while true do
        Wait(0)

        if IsControlJustReleased(0, 47) then  -- G key
            -- Check if admin in route creator
            require 'client.admin'.CheckRouteFinish()
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
            require 'client.test'.UpdateTestState()
            require 'client.hud'.Update()
        end
    end
end)

print('^2[CM-License Client]^7 Client loaded')
