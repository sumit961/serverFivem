-- CM License System — Client Checkpoint Management

local Constants = require 'shared.constants'
local Utils = require 'shared.utils'

local Checkpoints = {}

Checkpoints.Checkpoints = {}
Checkpoints.CurrentCheckpoint = 0
Checkpoints.Monitoring = false

function Checkpoints.Init()
    print('^2[CM-License Checkpoints]^7 Checkpoint system initialized')
end

-- Start monitoring checkpoints
function Checkpoints.StartMonitoring()
    Checkpoints.Monitoring = true
    print('^2[CM-License]^7 Checkpoint monitoring started')

    Citizen.CreateThread(function()
        while Checkpoints.Monitoring do
            Wait(100)
            Checkpoints.CheckProximity()
        end
    end)
end

-- Stop monitoring
function Checkpoints.StopMonitoring()
    Checkpoints.Monitoring = false
    Checkpoints.Checkpoints = {}
    Checkpoints.CurrentCheckpoint = 0
    print('^3[CM-License]^7 Checkpoint monitoring stopped')
end

-- Check if player is at next checkpoint
function Checkpoints.CheckProximity()
    if not Checkpoints.Monitoring or not require('client.main').IsInTest() then
        return
    end

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        return
    end

    local playerCoords = GetEntityCoords(ped)

    -- Check next checkpoint
    local nextCheckpoint = Checkpoints.CurrentCheckpoint + 1
    if nextCheckpoint > #Checkpoints.Checkpoints then
        -- All checkpoints completed
        require 'client.test'.ReportCompletion()
        return
    end

    local cp = Checkpoints.Checkpoints[nextCheckpoint]
    if not cp then return end

    local cpCoords = vector3(cp.x, cp.y, cp.z)
    local distance = Utils.Distance(playerCoords, cpCoords)

    if distance <= cp.radius then
        -- Checkpoint reached!
        Checkpoints.OnCheckpointReached(nextCheckpoint)
    end
end

-- Handle checkpoint reached
function Checkpoints.OnCheckpointReached(checkpointNumber)
    Checkpoints.CurrentCheckpoint = checkpointNumber
    require 'client.test'.ReportCheckpoint(checkpointNumber)

    print('^2[CM-License]^7 Checkpoint ' .. checkpointNumber .. ' reached')

    -- Visual feedback
    TriggerEvent('chat:addMessage', {
        args = { 'Checkpoint', checkpointNumber .. ' reached' },
        color = { 0, 255, 0 }
    })
end

-- Draw checkpoint markers
function Checkpoints.DrawMarkers()
    if not Checkpoints.Monitoring then return end

    if Checkpoints.CurrentCheckpoint >= #Checkpoints.Checkpoints then
        return
    end

    local nextCheckpoint = Checkpoints.Checkpoints[Checkpoints.CurrentCheckpoint + 1]
    if not nextCheckpoint then return end

    local cpCoords = vector3(nextCheckpoint.x, nextCheckpoint.y, nextCheckpoint.z)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local distance = Utils.Distance(playerCoords, cpCoords)

    -- Draw checkpoint marker
    DrawMarker(
        1,                          -- Type: cylinder
        cpCoords.x,                 -- X
        cpCoords.y,                 -- Y
        cpCoords.z,                 -- Z
        0, 0, 0,                    -- Direction
        0, 0, 0,                    -- Rotation
        nextCheckpoint.radius * 2,  -- Scale
        0, 229, 255, 127,           -- RGBA (cyan)
        false,                       -- Bob
        true,                        -- Fade distance
        2,                           -- Far alpha
        false,                       -- Unknown
        nil,                         -- Texture dict
        nil,                         -- Texture name
        false                        -- Draw on entities
    )

    -- Draw heading line if distance > 50
    if distance > 50 then
        DrawLine(
            playerCoords.x, playerCoords.y, playerCoords.z,
            cpCoords.x, cpCoords.y, cpCoords.z,
            0, 229, 255, 200
        )
    end
end

-- Set checkpoints for route
function Checkpoints.SetCheckpoints(checkpointList)
    Checkpoints.Checkpoints = checkpointList or {}
    Checkpoints.CurrentCheckpoint = 0
    print('^2[CM-License]^7 Route has ' .. #checkpointList .. ' checkpoints')
end

return Checkpoints
