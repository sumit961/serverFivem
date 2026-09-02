-- CM License System — Client Checkpoint Management

Checkpoints = {}

Checkpoints.Checkpoints = {}
Checkpoints.CurrentCheckpoint = 0
Checkpoints.Monitoring = false
Checkpoints.RouteBlip = nil
Checkpoints.AwaitingAck = false
Checkpoints.ActiveHandle = nil
Checkpoints.ActiveIndex = nil

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
    Checkpoints.AwaitingAck = false
    if Checkpoints.RouteBlip and DoesBlipExist(Checkpoints.RouteBlip) then RemoveBlip(Checkpoints.RouteBlip) end
    Checkpoints.RouteBlip = nil
    if Checkpoints.ActiveHandle then DeleteCheckpoint(Checkpoints.ActiveHandle) end
    Checkpoints.ActiveHandle, Checkpoints.ActiveIndex = nil, nil
    print('^3[CM-License]^7 Checkpoint monitoring stopped')
end

-- Check if player is at next checkpoint
function Checkpoints.CheckProximity()
    if not Checkpoints.Monitoring or not Client.IsInTest() then
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
        Test.ReportCompletion()
        return
    end
    
    local cp = Checkpoints.Checkpoints[nextCheckpoint]
    if not cp then return end
    
    local cpCoords = vector3(cp.x, cp.y, cp.z)
    local distance = Utils.Distance(playerCoords, cpCoords)
    
    local licenseType = Client.ActiveTest and Client.ActiveTest.licenseType
    local touchRadius = licenseType == 'air' and 20.0 or licenseType == 'boat' and 8.0 or 4.0
    local isFinish = nextCheckpoint == Checkpoints.Checkpoints[#Checkpoints.Checkpoints]
    if isFinish and licenseType == 'air' then
        local vehicle = GetVehiclePedIsIn(ped, false)
        local verticalDifference = math.abs(playerCoords.z - cpCoords.z)
        if distance <= touchRadius and (verticalDifference > 3.0 or GetEntitySpeed(vehicle) > 2.5) then
            BeginTextCommandPrint('STRING')
            AddTextComponentSubstringPlayerName('~y~Land the helicopter safely and come to a complete stop.~s~')
            EndTextCommandPrint(1200, true)
            return
        end
    end
    if distance <= touchRadius and not Checkpoints.AwaitingAck then
        -- Checkpoint reached!
        Checkpoints.OnCheckpointReached(nextCheckpoint)
    end
end

-- Handle checkpoint reached
function Checkpoints.OnCheckpointReached(checkpointNumber)
    Checkpoints.AwaitingAck = true
    Test.ReportCheckpoint(checkpointNumber)
    
    print('^2[CM-License]^7 Checkpoint ' .. checkpointNumber .. ' reached')
    
end

local Tips = {
    driver = { 'Keep a safe following distance.', 'Check your mirrors before changing direction.', 'Brake smoothly and control your speed.', 'Stay in your lane and watch surrounding traffic.', 'Signal early before turning.' },
    boat = { 'Maintain a safe speed near docks.', 'Watch your heading and nearby vessels.', 'Allow extra distance when turning.', 'Keep clear of shallow water and obstacles.' },
    air = { 'Maintain a stable altitude and heading.', 'Use smooth control inputs.', 'Watch your airspeed during turns.', 'Plan your approach before descending.' }
}

function Checkpoints.ShowInstruction(index)
    local total = #Checkpoints.Checkpoints
    if index <= 0 then return end
    local licenseType = Client.ActiveTest and Client.ActiveTest.licenseType or 'driver'
    local tips = Tips[licenseType] or Tips.driver
    local text = index >= total and 'Stop safely and await your test result.'
        or tips[((index - 1) % #tips) + 1]
    BeginTextCommandPrint('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandPrint(6000, true)
end

-- Draw checkpoint markers
function Checkpoints.DrawMarkers()
    if not Client.IsInTest() then return end
    
    if Checkpoints.CurrentCheckpoint >= #Checkpoints.Checkpoints then
        return
    end
    
    local nextCheckpoint = Checkpoints.Checkpoints[Checkpoints.CurrentCheckpoint + 1]
    if not nextCheckpoint then return end
    
    local cpCoords = vector3(nextCheckpoint.x, nextCheckpoint.y, nextCheckpoint.z)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local distance = Utils.Distance(playerCoords, cpCoords)
    
    local isFinish = tostring(nextCheckpoint.point_type) == 'finish'
        or (Checkpoints.CurrentCheckpoint + 1) == #Checkpoints.Checkpoints
    local activeType = Client.ActiveTest and Client.ActiveTest.licenseType
    local markerZ = nextCheckpoint.z + 0.05
    if activeType == 'driver' then
        local foundGround, groundZ = GetGroundZFor_3dCoord(nextCheckpoint.x + 0.0, nextCheckpoint.y + 0.0, nextCheckpoint.z + 50.0, false)
        if foundGround then markerZ = groundZ + 0.05 end
    end
    local activeIndex = Checkpoints.CurrentCheckpoint + 1
    if Checkpoints.ActiveIndex ~= activeIndex then
        if Checkpoints.ActiveHandle then DeleteCheckpoint(Checkpoints.ActiveHandle) end
        local following = Checkpoints.Checkpoints[activeIndex + 1] or nextCheckpoint
        local diameter = activeType == 'air' and 12.0 or activeType == 'boat' and 8.0 or 5.0
        Checkpoints.ActiveHandle = CreateCheckpoint(isFinish and 16 or 14,
            nextCheckpoint.x + 0.0, nextCheckpoint.y + 0.0, markerZ,
            following.x + 0.0, following.y + 0.0, following.z + 0.0,
            diameter, 0, 229, 255, 190, 0)
        SetCheckpointCylinderHeight(Checkpoints.ActiveHandle, 3.0, 3.0, diameter * 0.5)
        Checkpoints.ActiveIndex = activeIndex
        if isFinish and activeType == 'air' then
            BeginTextCommandPrint('STRING')
            AddTextComponentSubstringPlayerName('~y~Land safely inside the finish checkpoint and come to a complete stop to pass.~s~')
            EndTextCommandPrint(7000, true)
        end
    end
    local startTouchRadius = activeType == 'air' and 20.0 or activeType == 'boat' and 8.0 or 4.0
    if not Checkpoints.Monitoring and distance <= startTouchRadius and not Test.BeginRequested then
        Test.BeginTest()
    end

    if distance > 12.0 then
        DrawLine(playerCoords.x, playerCoords.y, playerCoords.z + 0.5,
            cpCoords.x, cpCoords.y, markerZ + 1.5, 0, 229, 255, 220)
    end
    
end

-- Set checkpoints for route
function Checkpoints.SetCheckpoints(checkpointList)
    Checkpoints.Checkpoints = checkpointList or {}
    Checkpoints.CurrentCheckpoint = 0
    Checkpoints.AwaitingAck = false
    if Checkpoints.ActiveHandle then DeleteCheckpoint(Checkpoints.ActiveHandle) end
    Checkpoints.ActiveHandle, Checkpoints.ActiveIndex = nil, nil
    if Checkpoints.RouteBlip and DoesBlipExist(Checkpoints.RouteBlip) then RemoveBlip(Checkpoints.RouteBlip) end
    local first = Checkpoints.Checkpoints[1]
    if first then
        Checkpoints.RouteBlip = AddBlipForCoord(first.x + 0.0, first.y + 0.0, first.z + 0.0)
        SetBlipSprite(Checkpoints.RouteBlip, 1)
        SetBlipColour(Checkpoints.RouteBlip, 3)
        SetBlipScale(Checkpoints.RouteBlip, 0.85)
        SetBlipRoute(Checkpoints.RouteBlip, true)
        SetBlipRouteColour(Checkpoints.RouteBlip, 3)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('License Test Start')
        EndTextCommandSetBlipName(Checkpoints.RouteBlip)
    end
    print('^2[CM-License]^7 Route has ' .. #Checkpoints.Checkpoints .. ' checkpoints')
end

function Checkpoints.UpdateRouteBlip()
    if Checkpoints.ActiveHandle then DeleteCheckpoint(Checkpoints.ActiveHandle) end
    Checkpoints.ActiveHandle, Checkpoints.ActiveIndex = nil, nil
    local nextCheckpoint = Checkpoints.Checkpoints[Checkpoints.CurrentCheckpoint + 1]
    if not nextCheckpoint then
        if Checkpoints.RouteBlip and DoesBlipExist(Checkpoints.RouteBlip) then RemoveBlip(Checkpoints.RouteBlip) end
        Checkpoints.RouteBlip = nil
        return
    end
    if not Checkpoints.RouteBlip or not DoesBlipExist(Checkpoints.RouteBlip) then
        Checkpoints.RouteBlip = AddBlipForCoord(nextCheckpoint.x + 0.0, nextCheckpoint.y + 0.0, nextCheckpoint.z + 0.0)
    else
        SetBlipCoords(Checkpoints.RouteBlip, nextCheckpoint.x + 0.0, nextCheckpoint.y + 0.0, nextCheckpoint.z + 0.0)
    end
    SetBlipSprite(Checkpoints.RouteBlip, 1)
    SetBlipColour(Checkpoints.RouteBlip, 3)
    SetBlipRoute(Checkpoints.RouteBlip, true)
end

return Checkpoints
