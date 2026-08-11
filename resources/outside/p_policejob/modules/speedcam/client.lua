while not Config or not Config.Speedcam do
    Citizen.Wait(500)
end

if not Config.Speedcam.enabled then
    return
end

Speedcam = {
    cameras = {},
    placing = false,
}

function Speedcam.checkAccess()
    local job = Bridge.Framework.fetchPlayerJob()
    local minGrade = Config.Jobs[job.name]
    if not minGrade or job.grade < minGrade then
        Bridge.Notify.showNotify(locale("no_access"), "error")
        return false
    end
    return true
end

function Speedcam.startCreator()
    if Speedcam.placing then
        return
    end
    if not Speedcam:checkAccess() then
        return
    end
    local modelOptions = {}
    for modelName, label in pairs(Config.Speedcam.Models) do
        modelOptions[#modelOptions + 1] = {
            value = modelName,
            label = label,
        }
    end
    local input = lib.inputDialog(locale("speed_cam_creator"), {
        { type = "select", label = "Camera Model", options = modelOptions, required = true },
        { type = "input", label = "Camera Name", required = true },
        { type = "number", label = "Speed Limit (KMH)", min = 1, default = 100, required = true },
        { type = "number", label = "Detection Distance", min = 1, default = 50, required = true },
        { type = "number", label = "Fine Amount", min = 0, default = 500, required = true },
        { type = "checkbox", label = "Fine Multiplier" },
        { type = "checkbox", label = "Show Blip" },
        { type = "checkbox", label = "Screen Flash" },
        { type = "checkbox", label = "Light Effect", checked = true },
    })
    if not input then
        return
    end
    local modelName = input[1]
    local camName = input[2]
    local speedLimit = input[3]
    local camDistance = input[4]
    local fine = input[5]
    local fineMultiplier = input[6]
    local blipEnabled = input[7]
    local screenEffect = input[8]
    local lightEffect = input[9]
    if GetResourceState("object_gizmo") ~= "started" then
        Bridge.Notify.showNotify("object_gizmo resource is not started", "error")
        return
    end
    local model = lib.requestModel(modelName)
    local spawnCoords = GetOffsetFromEntityInWorldCoords(cache.ped, 0, 2.0, 0)
    local previewObject = CreateObject(model, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false)
    SetEntityHeading(previewObject, GetEntityHeading(cache.ped))
    SetEntityCollision(previewObject, false, false)
    PlaceObjectOnGroundProperly(previewObject)
    SetModelAsNoLongerNeeded(model)
    Speedcam.placing = true
    local gizmoResult = exports.object_gizmo:useGizmo(previewObject)
    Speedcam.placing = false
    if not gizmoResult or not DoesEntityExist(previewObject) then
        if DoesEntityExist(previewObject) then
            DeleteEntity(previewObject)
        end
        return
    end
    local coords = GetEntityCoords(previewObject)
    local heading = GetEntityHeading(previewObject)
    DeleteEntity(previewObject)
    Citizen.Wait(500)
    local sensorInput = lib.inputDialog("Set Sensors", {
        { type = "number", label = "Number of Sensors", min = 1, default = 1, required = true },
    })
    if not sensorInput then
        return
    end
    local sensorCount = sensorInput[1]
    local sensors = {}
    Speedcam.placing = true
    while Speedcam.placing and sensorCount > #sensors do
        Citizen.Wait(0)
        local _, _, hitCoords = lib.raycast.fromCamera(511)
        if hitCoords then
            local pedCoords = GetEntityCoords(cache.ped)
            DrawLine(pedCoords, hitCoords, 255, 255, 255, 100)
            DrawMarker(
                28, hitCoords,
                0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                0.1, 0.1, 0.1,
                2, 255, 255, 255,
                false, true, 2, nil, nil, false
            )
            if IsControlJustPressed(0, 38) then
                sensors[#sensors + 1] = hitCoords
                Citizen.Wait(500)
                if sensorCount <= #sensors then
                    break
                end
            end
        end
        if IsControlJustPressed(0, 73) then
            Speedcam.placing = false
            return
        end
    end
    Speedcam.placing = false
    TriggerServerEvent("p_policejob/server/speedcam/createSpeedcam", {
        coords = coords,
        heading = heading,
        modelName = modelName,
        camName = camName,
        speedLimit = speedLimit,
        camDistance = camDistance,
        fine = fine,
        fineMultiplier = fineMultiplier,
        blipEnabled = blipEnabled,
        screenEffect = screenEffect,
        lightEffect = lightEffect,
        sensors = sensors,
    })
end

function Speedcam.spawnCamera(cameraData)
    local camObject = nil
    local blip = nil
    local sensorPoints = {}
    local caughtCooldown = false
    Citizen.Wait(100)
    local model = lib.requestModel(cameraData.modelName)
    camObject = CreateObject(
        model,
        cameraData.coords.x,
        cameraData.coords.y,
        cameraData.coords.z,
        false, true, true
    )
    FreezeEntityPosition(camObject, true)
    PlaceObjectOnGroundProperly(camObject)
    SetEntityHeading(camObject, cameraData.heading)
    SetModelAsNoLongerNeeded(model)
    if cameraData.blipEnabled then
        blip = AddBlipForCoord(cameraData.coords.x, cameraData.coords.y, cameraData.coords.z)
        SetBlipSprite(blip, Config.Speedcam.Blip.sprite)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, Config.Speedcam.Blip.scale)
        SetBlipColour(blip, Config.Speedcam.Blip.color)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(Config.Speedcam.Blip.label)
        EndTextCommandSetBlipName(blip)
    end
    for i = 1, #cameraData.sensors do
        local point = lib.points.new({
            coords = cameraData.sensors[i],
            distance = cameraData.camDistance,
        })
        point.onEnter = function()
            if caughtCooldown then
                return
            end
            if not cache.vehicle or cache.vehicle == 0 then
                return
            end
            if cache.seat ~= -1 then
                return
            end
            if Config.Speedcam.IgnoredJobs[Bridge.Framework.fetchPlayerJob().name] then
                return
            end
            local speedMultiplier = Config.Speedcam.Unit == "KMH" and 3.6 or 2.236936
            local speed = math.floor(GetEntitySpeed(cache.vehicle) * speedMultiplier)
            if speed < cameraData.speedLimit then
                return
            end
            caughtCooldown = true
            if cameraData.screenEffect then
                StartScreenEffect("DefaultFlash", 0, false)
                Citizen.Wait(500)
                StopScreenEffect("DefaultFlash")
            end
            if Config.Speedcam.Sound.enabled then
                Citizen.SetTimeout(500, function()
                    SendNUIMessage({
                        action = "PlayAudio",
                        audio = {
                            file = "speedcam",
                            vol = Config.Speedcam.Sound.volume,
                        },
                    })
                end)
            end
            TriggerServerEvent("p_policejob/server/speedcam/playerCaught", {
                cameraData = cameraData,
                speed = speed,
                playerCoords = GetEntityCoords(cache.ped),
            })
            SetTimeout(30000, function()
                caughtCooldown = false
            end)
        end
        sensorPoints[#sensorPoints + 1] = point
    end
    Speedcam.cameras[cameraData.camName] = {
        data = cameraData,
        camObject = camObject,
        blip = blip,
        sensorPoints = sensorPoints,
    }
end

function Speedcam.removeCamera(camName)
    local entry = Speedcam.cameras[camName]
    if not entry then
        return
    end
    if entry.camObject and DoesEntityExist(entry.camObject) then
        DeleteEntity(entry.camObject)
    end
    if entry.blip and DoesBlipExist(entry.blip) then
        RemoveBlip(entry.blip)
    end
    if entry.sensorPoints then
        for _, point in ipairs(entry.sensorPoints) do
            point:remove()
        end
    end
    Speedcam.cameras[camName] = nil
end

RegisterCommand("speedcam_creator", function()
    Speedcam:startCreator()
end)

RegisterCommand("speedcam_manager", function()
    if not Speedcam:checkAccess() then
        return
    end
    SendNUIMessage({
        action = "setVisibleSpeedcamManager",
        data = true,
    })
    SetNuiFocus(true, true)
end)

RegisterNetEvent("p_policejob/client/speedcam/loadCameras", function(cameraList)
    Speedcam.cameras = {}
    for _, cameraData in ipairs(cameraList) do
        Speedcam:spawnCamera(cameraData)
    end
end)

RegisterNetEvent("p_policejob/client/speedcam/newCamera", function(cameraData)
    Speedcam:spawnCamera(cameraData)
end)

RegisterNetEvent("p_policejob/client/speedcam/removeCamera", function(camName)
    Speedcam:removeCamera(camName)
end)

RegisterNetEvent("p_policejob/client/speedcam/syncLight", function(payload)
    Citizen.Wait(1)
    local cameraCoords = payload.cameraData.coords
    local direction = payload.playerCoords - cameraCoords
    local flashFrames = 0
    Citizen.CreateThread(function()
        while flashFrames < 50 do
            Citizen.Wait(1)
            DrawSpotLight(
                cameraCoords.x, cameraCoords.y, cameraCoords.z + 2.0,
                direction.x, direction.y, direction.z,
                221, 221, 221,
                70.0, 100.0, 4.3, 25.0, 28.6
            )
            flashFrames = flashFrames + 1
        end
        Citizen.Wait(10)
        local pulseFrames = 0
        Citizen.CreateThread(function()
            while pulseFrames < 10 do
                Citizen.Wait(1)
                DrawSpotLight(
                    cameraCoords.x, cameraCoords.y, cameraCoords.z + 2.0,
                    direction.x, direction.y, direction.z,
                    221, 221, 221,
                    70.0, 100.0, 4.3, 25.0, 28.6
                )
                pulseFrames = pulseFrames + 1
            end
        end)
    end)
end)

RegisterNUICallback("speedcam/close", function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "setVisibleSpeedcamManager",
        data = false,
    })
    cb("ok")
end)

RegisterNUICallback("speedcam/getAll", function(_, cb)
    local cameraList = {}
    for _, entry in pairs(Speedcam.cameras) do
        cameraList[#cameraList + 1] = entry.data
    end
    cb(cameraList)
end)

RegisterNUICallback("speedcam/remove", function(data, cb)
    TriggerServerEvent("p_policejob/server/speedcam/removeSpeedcam", data.camName)
    cb(true)
end)

RegisterNUICallback("speedcam/teleport", function(data, cb)
    local entry = Speedcam.cameras[data.camName]
    if entry then
        SetEntityCoords(
            cache.ped,
            entry.data.coords.x,
            entry.data.coords.y,
            entry.data.coords.z + 1.0
        )
        SetEntityHeading(cache.ped, 0.0)
    end
    cb(true)
end)

RegisterNUICallback("speedcam/updateSpeedcam", function(data, cb)
    TriggerServerEvent("p_policejob/server/speedcam/updateSpeedcam", data)
    cb(true)
end)

Citizen.CreateThread(function()
    TriggerServerEvent("p_policejob/server/speedcam/loadCameras")
end)
