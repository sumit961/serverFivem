-- CM License System — Client Checkpoint Management

Checkpoints = {}

Checkpoints.Checkpoints = {}
Checkpoints.CurrentCheckpoint = 0
Checkpoints.Monitoring = false
Checkpoints.RouteBlip = nil
Checkpoints.AwaitingAck = false
Checkpoints.AwaitingIndex = nil
Checkpoints.AwaitingSince = nil
Checkpoints.AwaitingAttempts = 0
Checkpoints.ActiveHandle = nil
Checkpoints.ActiveIndex = nil
Checkpoints.LegStartDistance = 0

local ACK_RETRY_MS = 2000
local ACK_MAX_ATTEMPTS = 5
local lastCandidateTraceAt = 0

local function debugLog(message)
    if CMLicenseConfig.Debug then
        print(('^3[CM-License Client]^7 %s'):format(tostring(message)))
    end
end

function Checkpoints.Init()
    CMLog('Checkpoint system initialized')
end

local function activeCategory()
    return Client.ActiveTest and Client.ActiveTest.category or 'ground'
end

local function touchRadius()
    return Utils.TouchRadius(activeCategory())
end

function Checkpoints.StartMonitoring()
    if Checkpoints.Monitoring then return end
    Checkpoints.Monitoring = true
    Checkpoints.ResetLegDistance()
    CMLog('Checkpoint monitoring started')

    CreateThread(function()
        while Checkpoints.Monitoring do
            Wait(100)
            Checkpoints.CheckProximity()
        end
    end)
end

function Checkpoints.StopMonitoring()
    Checkpoints.Monitoring = false
    Checkpoints.Checkpoints = {}
    Checkpoints.CurrentCheckpoint = 0
    Checkpoints.ClearAck()

    if Checkpoints.RouteBlip and DoesBlipExist(Checkpoints.RouteBlip) then RemoveBlip(Checkpoints.RouteBlip) end
    Checkpoints.RouteBlip = nil

    if Checkpoints.ActiveHandle then DeleteCheckpoint(Checkpoints.ActiveHandle) end
    Checkpoints.ActiveHandle, Checkpoints.ActiveIndex = nil, nil

    CMLog('Checkpoint monitoring stopped')
end

function Checkpoints.ClearAck()
    Checkpoints.AwaitingAck = false
    Checkpoints.AwaitingIndex = nil
    Checkpoints.AwaitingSince = nil
    Checkpoints.AwaitingAttempts = 0
end

-- Distance to the next checkpoint at the moment the leg started; used as the
-- baseline for the "you have left the route" check.
function Checkpoints.ResetLegDistance()
    local nextPoint = Checkpoints.Checkpoints[Checkpoints.CurrentCheckpoint + 1]
    if not nextPoint then
        Checkpoints.LegStartDistance = 0
        return
    end
    Checkpoints.LegStartDistance = Utils.Distance(GetEntityCoords(PlayerPedId()),
        vector3(nextPoint.x, nextPoint.y, nextPoint.z))
end

local function isFinishIndex(index)
    return index >= #Checkpoints.Checkpoints
end

local function checkpointVisual(category, isFinish)
    local visual = CMLicenseConfig.Checkpoint.Visual or {}
    category = tostring(category or Constants.VEHICLE_CATEGORY.GROUND):lower()

    local diameter = tonumber(visual.groundDiameter) or 7.0
    local zOffset = tonumber(visual.groundZOffset) or 0.20
    if category == Constants.VEHICLE_CATEGORY.BOAT then
        diameter = tonumber(visual.boatDiameter) or 8.0
        zOffset = tonumber(visual.boatZOffset) or 0.05
    elseif category == Constants.VEHICLE_CATEGORY.AIR then
        diameter = tonumber(visual.airDiameter) or 12.0
        zOffset = tonumber(visual.airZOffset) or 0.05
    end

    return {
        type = isFinish and 16 or 14,
        diameter = diameter,
        zOffset = zOffset,
        cylinderHeight = tonumber(visual.cylinderHeight) or 3.0,
    }
end

-- An unacknowledged checkpoint is re-sent rather than left to stall the exam.
local function retryPendingAck()
    if not Checkpoints.AwaitingAck or not Checkpoints.AwaitingSince then return end
    if (GetGameTimer() - Checkpoints.AwaitingSince) < ACK_RETRY_MS then return end

    if Checkpoints.AwaitingAttempts >= ACK_MAX_ATTEMPTS then
        -- Give up waiting; drive back through the marker to try again.
        Checkpoints.ClearAck()
        Client.Alert('~y~Checkpoint not confirmed. Drive through it again.~s~', 3000)
        return
    end

    Checkpoints.AwaitingAttempts = Checkpoints.AwaitingAttempts + 1
    Checkpoints.AwaitingSince = GetGameTimer()
    Test.ReportCheckpoint(Checkpoints.AwaitingIndex)
end

function Checkpoints.CheckProximity()
    if not Checkpoints.Monitoring or not Client.IsInTest() then return end

    retryPendingAck()

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end

    local nextIndex = Checkpoints.CurrentCheckpoint + 1
    if nextIndex > #Checkpoints.Checkpoints then
        Test.ReportCompletion()
        return
    end

    local cp = Checkpoints.Checkpoints[nextIndex]
    if not cp then return end

    local playerCoords = GetEntityCoords(ped)
    local cpCoords = vector3(cp.x, cp.y, cp.z)
    local category = activeCategory()
    local distance, vertical = Utils.CheckpointDistance(playerCoords, cp, category)
    local radius = Utils.EffectiveTouchRadius(category, cp)
    local within = Utils.IsWithinCheckpoint(playerCoords, cp, category, radius)

    local vehicle = GetVehiclePedIsIn(ped, false)
    local driver = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
    local exactVehicle = vehicle ~= 0 and vehicle == Test.TestVehicle
    if distance <= radius and not Checkpoints.AwaitingAck and (GetGameTimer() - lastCandidateTraceAt) >= 1000 then
        lastCandidateTraceAt = GetGameTimer()
        debugLog(('checkpoint_candidate requested=%s current=%s distance=%.2f vertical=%.2f touchRadius=%.2f within=%s player=(%.2f,%.2f,%.2f) checkpoint=(%.2f,%.2f,%.2f) vehicleNetId=%s vehicle=%s exactTestVehicle=%s driver=%s')
            :format(nextIndex, Checkpoints.CurrentCheckpoint, distance, vertical, radius, tostring(within),
                playerCoords.x, playerCoords.y, playerCoords.z,
                cp.x, cp.y, cp.z,
                vehicle ~= 0 and tostring(NetworkGetNetworkIdFromEntity(vehicle)) or '0',
                tostring(vehicle), tostring(exactVehicle), tostring(driver)))
    end

    if not within or Checkpoints.AwaitingAck then return end

    if vehicle == 0 or vehicle ~= Test.TestVehicle or not driver then return end

        debugLog(('checkpoint_send requested=%s current=%s awaitingAck=false distance=%.2f vertical=%.2f touchRadius=%.2f player=(%.2f,%.2f,%.2f) checkpoint=(%.2f,%.2f,%.2f) vehicleNetId=%s vehicle=%s exactTestVehicle=true driver=%s')
        :format(nextIndex, Checkpoints.CurrentCheckpoint, distance, vertical, radius,
            playerCoords.x, playerCoords.y, playerCoords.z,
            cp.x, cp.y, cp.z,
            tostring(NetworkGetNetworkIdFromEntity(vehicle)), tostring(vehicle), tostring(driver)))

    -- Air exams finish with a landing, not a fly-through.
    if isFinishIndex(nextIndex) and activeCategory() == Constants.VEHICLE_CATEGORY.AIR then
        local vehicle = GetVehiclePedIsIn(ped, false)
        local bounds = CMLicenseConfig.Checkpoint
        if math.abs(playerCoords.z - cpCoords.z) > bounds.LandingVerticalTolerance
            or GetEntitySpeed(vehicle) > bounds.LandingMaxSpeed then
            Client.Alert('~y~Land the helicopter safely and come to a complete stop.~s~', 1200)
            return
        end
    end

    Checkpoints.OnCheckpointReached(nextIndex)
end

function Checkpoints.OnCheckpointReached(checkpointNumber)
    Checkpoints.AwaitingAck = true
    Checkpoints.AwaitingIndex = checkpointNumber
    Checkpoints.AwaitingSince = GetGameTimer()
    Checkpoints.AwaitingAttempts = 0

    Test.ReportCheckpoint(checkpointNumber)
    CMLog('Checkpoint ' .. checkpointNumber .. ' reached')
end

-- The server refused the checkpoint. Resync to what it believes and let the
-- player trigger it again instead of leaving the exam stuck.
function Checkpoints.OnCheckpointRejected(data)
    data = type(data) == 'table' and data or {}
    Checkpoints.ClearAck()

    if CMLicenseConfig.Debug then
        debugLog(('checkpoint_ack_rejected reason=%s expected=%s'):format(
            tostring(data.reason or 'unknown'), tostring(data.expected or 'unknown')))
        Client.Alert(('~y~CHECKPOINT NOT ACCEPTED: %s~s~'):format(tostring(data.reason or 'unknown')), 2500)
    end

    if tonumber(data.expected) then
        Checkpoints.CurrentCheckpoint = math.max(0, tonumber(data.expected) - 1)
        Checkpoints.UpdateRouteBlip()
    end

    if data.message and not CMLicenseConfig.Debug then
        Client.Alert(('~y~%s~s~'):format(tostring(data.message)), 2500)
    end
end

local Tips = {
    ground = { 'Keep a safe following distance.', 'Check your mirrors before changing direction.', 'Brake smoothly and control your speed.', 'Stay in your lane and watch surrounding traffic.', 'Signal early before turning.' },
    boat = { 'Maintain a safe speed near docks.', 'Watch your heading and nearby vessels.', 'Allow extra distance when turning.', 'Keep clear of shallow water and obstacles.' },
    air = { 'Maintain a stable altitude and heading.', 'Use smooth control inputs.', 'Watch your airspeed during turns.', 'Plan your approach before descending.' }
}

function Checkpoints.ShowInstruction(index)
    local total = #Checkpoints.Checkpoints
    if index <= 0 then return end

    local tips = Tips[activeCategory()] or Tips.ground
    local text = index >= total and 'Stop safely and await your test result.'
        or tips[((index - 1) % #tips) + 1]

    Client.Alert(text, 6000)
end

-- Draw the active checkpoint and the guide line to it
function Checkpoints.DrawMarkers()
    if not Client.IsInTest() then return end

    local activeIndex = Checkpoints.CurrentCheckpoint + 1
    local nextCheckpoint = Checkpoints.Checkpoints[activeIndex]
    if not nextCheckpoint then return end

    local cpCoords = vector3(nextCheckpoint.x, nextCheckpoint.y, nextCheckpoint.z)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local distance = Utils.Distance(playerCoords, cpCoords)
    local activeType = activeCategory()
    local isFinish = tostring(nextCheckpoint.point_type) == 'finish' or isFinishIndex(activeIndex)

    local visual = checkpointVisual(activeType, isFinish)
    local markerZ = nextCheckpoint.z + visual.zOffset

    if Checkpoints.ActiveIndex ~= activeIndex then
        if Checkpoints.ActiveHandle then DeleteCheckpoint(Checkpoints.ActiveHandle) end

        local following = Checkpoints.Checkpoints[activeIndex + 1] or nextCheckpoint
        Checkpoints.ActiveHandle = CreateCheckpoint(visual.type,
            nextCheckpoint.x + 0.0, nextCheckpoint.y + 0.0, markerZ,
            following.x + 0.0, following.y + 0.0, following.z + 0.0,
            visual.diameter, 0, 229, 255, 190, 0)
        SetCheckpointCylinderHeight(Checkpoints.ActiveHandle,
            visual.cylinderHeight, visual.cylinderHeight, visual.diameter * 0.5)
        Checkpoints.ActiveIndex = activeIndex

        if isFinish and activeType == Constants.VEHICLE_CATEGORY.AIR then
            Client.Alert('~y~Land safely inside the finish checkpoint and come to a complete stop to pass.~s~', 7000)
        end
    end

    -- Before the exam starts, touching the first marker begins it.
    if not Checkpoints.Monitoring and not Test.BeginRequested
        and Utils.IsWithinCheckpoint(playerCoords, nextCheckpoint, activeType,
            Utils.EffectiveTouchRadius(activeType, nextCheckpoint))
    then
        Test.BeginTest()
    end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local drivingTestVehicle = vehicle ~= 0 and vehicle == Test.TestVehicle
        and GetPedInVehicleSeat(vehicle, -1) == ped
    if distance > 12.0 and drivingTestVehicle then
        DrawLine(playerCoords.x, playerCoords.y, playerCoords.z + 0.5,
            cpCoords.x, cpCoords.y, markerZ + 1.5, 0, 229, 255, 220)
    end
end

-- Set checkpoints for route
function Checkpoints.SetCheckpoints(checkpointList)
    Checkpoints.Checkpoints = checkpointList or {}
    Checkpoints.CurrentCheckpoint = 0
    Checkpoints.ClearAck()

    if Checkpoints.ActiveHandle then DeleteCheckpoint(Checkpoints.ActiveHandle) end
    Checkpoints.ActiveHandle, Checkpoints.ActiveIndex = nil, nil

    if Checkpoints.RouteBlip and DoesBlipExist(Checkpoints.RouteBlip) then RemoveBlip(Checkpoints.RouteBlip) end
    Checkpoints.RouteBlip = nil

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

    CMLog('Route has ' .. #Checkpoints.Checkpoints .. ' checkpoints')
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
    Checkpoints.ResetLegDistance()
end

return Checkpoints
