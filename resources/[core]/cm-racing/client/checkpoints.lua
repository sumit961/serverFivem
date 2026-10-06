CMRacing = CMRacing or {}
CMRacing.Client = CMRacing.Client or {}
CMRacing.Client.Checkpoints = {}

local CP = CMRacing.Client.Checkpoints
local Config = CMRacing.Config

local activeCheckpoints = {}
local currentCpIndex = 0
local activeHandle = nil
local routeBlip = nil
local nextBlip = nil
local isMonitoring = false
local awaitingAck = false
local currentSessionToken = nil

function CP.Start(token, checkpoints)
    CP.Clear()
    activeCheckpoints = checkpoints or {}
    currentCpIndex = 0
    currentSessionToken = token
    isMonitoring = true
    awaitingAck = false

    CP.UpdateVisuals(1)

    CreateThread(function()
        while isMonitoring do
            Wait(100)
            CP.CheckProximity()
        end
    end)
end

function CP.Clear()
    isMonitoring = false
    awaitingAck = false
    currentSessionToken = nil

    if activeHandle then
        DeleteCheckpoint(activeHandle)
        activeHandle = nil
    end

    if routeBlip and DoesBlipExist(routeBlip) then
        RemoveBlip(routeBlip)
        routeBlip = nil
    end

    if nextBlip and DoesBlipExist(nextBlip) then
        RemoveBlip(nextBlip)
        nextBlip = nil
    end
end

function CP.UpdateVisuals(index)
    local target = activeCheckpoints[index]
    if not target then
        if activeHandle then
            DeleteCheckpoint(activeHandle)
            activeHandle = nil
        end
        return
    end

    local following = activeCheckpoints[index + 1] or target
    local isFinish = (index == #activeCheckpoints) or (target.isFinish == true)
    local visual = Config.CheckpointVisual

    if activeHandle then
        DeleteCheckpoint(activeHandle)
        activeHandle = nil
    end

    local cpType = isFinish and visual.finishType or visual.normalType
    local color = isFinish and visual.finishColor or visual.color

    activeHandle = CreateCheckpoint(
        cpType,
        target.x + 0.0, target.y + 0.0, target.z + visual.zOffset,
        following.x + 0.0, following.y + 0.0, following.z + visual.zOffset,
        visual.diameter,
        color.r, color.g, color.b, color.a,
        0
    )
    SetCheckpointCylinderHeight(activeHandle, visual.cylinderHeight, visual.cylinderHeight, visual.diameter * 0.5)

    -- Update GPS Blips
    if routeBlip and DoesBlipExist(routeBlip) then
        RemoveBlip(routeBlip)
    end
    if nextBlip and DoesBlipExist(nextBlip) then
        RemoveBlip(nextBlip)
    end

    routeBlip = AddBlipForCoord(target.x, target.y, target.z)
    SetBlipSprite(routeBlip, isFinish and 38 or 1)
    SetBlipColour(routeBlip, isFinish and 5 or 3)
    SetBlipScale(routeBlip, 0.9)
    SetBlipRoute(routeBlip, true)
    SetBlipRouteColour(routeBlip, 3)

    if following and following ~= target then
        nextBlip = AddBlipForCoord(following.x, following.y, following.z)
        SetBlipSprite(nextBlip, 1)
        SetBlipColour(nextBlip, 3)
        SetBlipScale(nextBlip, 0.6)
        SetBlipAlpha(nextBlip, 150)
    end
end

function CP.CheckProximity()
    if not isMonitoring or awaitingAck then return end

    local nextIndex = currentCpIndex + 1
    local target = activeCheckpoints[nextIndex]
    if not target then return end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end

    local vehCoords = GetEntityCoords(veh)
    local targetCoords = vector3(target.x, target.y, target.z)
    local dist = #(vehCoords - targetCoords)
    local touchRadius = Config.Validation.DefaultCheckpointRadius or 12.0

    if dist <= touchRadius then
        awaitingAck = true
        TriggerServerEvent('cm-racing:server:reachCheckpoint', currentSessionToken, nextIndex)
    end
end

function CP.OnAck(checkpointIndex, totalCheckpoints)
    awaitingAck = false
    currentCpIndex = checkpointIndex
    PlaySoundFrontend(-1, 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', true)

    if checkpointIndex < totalCheckpoints then
        CP.UpdateVisuals(checkpointIndex + 1)
    else
        CP.Clear()
    end
end

function CP.OnRejected(expectedIndex)
    awaitingAck = false
    if expectedIndex then
        currentCpIndex = expectedIndex - 1
        CP.UpdateVisuals(expectedIndex)
    end
end
