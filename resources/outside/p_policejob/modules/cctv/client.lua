while not Config or not Config.CCTV do
    Citizen.Wait(1)
end

if not Config.CCTV.enabled then
    return
end

CCTV = {
    cameras = {},
    points = {},
    objects = {},
    watching = false,
    curCam = nil,
    rotX = 0.0,
    rotZ = 0.0,
}

function hasCctvJob(jobs)
    local job = Bridge.Framework.fetchPlayerJob()
    if not job then
        return false
    end
    for _, allowedJob in ipairs(jobs) do
        if job.name == allowedJob then
            return true
        end
    end
    return false
end

function getStreetNameAtCoords(coords)
    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    return GetStreetNameFromHashKey(streetHash)
end

function rotationToDirection(rotation)
    local pitch = math.rad(rotation.x)
    local yaw = math.rad(rotation.z)
    local cosPitch = math.cos(pitch)
    return vector3(-math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch))
end

function CCTV.spawnCameraObject(self, cameraData)
    local existingObject = self.objects[cameraData.id]
    if existingObject and DoesEntityExist(existingObject) then
        DeleteEntity(existingObject)
    end

    local model = lib.requestModel(cameraData.model, 5000)
    if not model then
        return nil
    end

    local object = CreateObject(
        cameraData.model,
        cameraData.coords.x, cameraData.coords.y, cameraData.coords.z,
        false, false, false
    )
    SetEntityRotation(object, cameraData.rotation.x, cameraData.rotation.y, cameraData.rotation.z, 2, true)
    FreezeEntityPosition(object, true)
    SetEntityCollision(object, true, false)
    SetModelAsNoLongerNeeded(cameraData.model)
    self.objects[cameraData.id] = object
    return object
end

function CCTV.despawnCameraObject(self, cameraId)
    local object = self.objects[cameraId]
    if object and DoesEntityExist(object) then
        DeleteEntity(object)
        self.objects[cameraId] = nil
    end
end

function CCTV.createCameraPoint(self, cameraData)
    local existingPoint = self.points[cameraData.id]
    if existingPoint then
        existingPoint:remove()
    end

    local point = lib.points.new({
        coords = vector3(cameraData.coords.x, cameraData.coords.y, cameraData.coords.z),
        distance = Config.CCTV.loadDistance,
        camData = cameraData,
    })

    function point.onEnter(pointData)
        CCTV:spawnCameraObject(pointData.camData)
    end

    function point.onExit(pointData)
        CCTV:despawnCameraObject(pointData.camData.id)
    end

    self.points[cameraData.id] = point
end

function CCTV.removeCameraPoint(self, cameraId)
    local point = self.points[cameraId]
    if point then
        point:remove()
        self.points[cameraId] = nil
    end
    self:despawnCameraObject(cameraId)
end

function CCTV.LoadCameras(self, cameras)
    for _, cameraData in pairs(cameras) do
        self.cameras[cameraData.id] = cameraData
        self:createCameraPoint(cameraData)
    end
end

function CCTV.AddCamera(self, cameraData)
    self.cameras[cameraData.id] = cameraData
    self:createCameraPoint(cameraData)
end

function CCTV.RemoveCamera(self, cameraId)
    self.cameras[cameraId] = nil
    self:removeCameraPoint(cameraId)
end

function CCTV.UpdateCamera(self, cameraData)
    self.cameras[cameraData.id] = cameraData
    local point = self.points[cameraData.id]
    if point then
        point.camData = cameraData
    end
end

function CCTV.Creator(self)
    if not hasCctvJob(Config.CCTV.creatorAccess) then
        return lib.notify({ title = locale("camera_no_access"), type = "error" })
    end

    local modelOptions = {}
    for _, modelEntry in ipairs(Config.CCTV.models) do
        modelOptions[#modelOptions + 1] = {
            value = modelEntry.model,
            label = modelEntry.label,
        }
    end

    local jobOptions = {}
    for _, jobName in ipairs(Config.CCTV.defaultJobs) do
        jobOptions[#jobOptions + 1] = {
            value = jobName,
            label = jobName:upper(),
        }
    end

    local input = lib.inputDialog(locale("camera_creator"), {
        {
            type = "input",
            label = locale("camera_name"),
            placeholder = locale("camera_name_info"),
            required = true,
        },
        {
            type = "select",
            label = locale("camera_model"),
            options = modelOptions,
            required = true,
        },
        {
            type = "multi-select",
            label = locale("camera_job"),
            options = jobOptions,
            required = true,
        },
    })

    if not input then
        return
    end

    local name, selectedModel, selectedJobs = input[1], input[2], input[3]
    local ped = cache.ped
    local pedCoords = GetEntityCoords(ped)
    local pedHeading = GetEntityHeading(ped)
    local previewCoords = pedCoords + GetEntityForwardVector(ped) * 3.0
    previewCoords = vector3(previewCoords.x, previewCoords.y, previewCoords.z + 2.0)

    local model = lib.requestModel(selectedModel, 5000)
    if not model then
        return lib.notify({ title = locale("camera_model_info"), type = "error" })
    end

    local previewObject = CreateObject(selectedModel, previewCoords.x, previewCoords.y, previewCoords.z, false, false, false)
    SetEntityHeading(previewObject, pedHeading)
    SetEntityCollision(previewObject, false, false)
    FreezeEntityPosition(previewObject, true)
    SetModelAsNoLongerNeeded(selectedModel)

    local gizmoResult = exports.object_gizmo:useGizmo(previewObject)
    if not gizmoResult then
        if DoesEntityExist(previewObject) then
            DeleteEntity(previewObject)
        end
        return
    end

    local finalCoords = GetEntityCoords(previewObject)
    local finalRotation = GetEntityRotation(previewObject, 2)
    if DoesEntityExist(previewObject) then
        DeleteEntity(previewObject)
    end

    TriggerServerEvent("p_policejob/server/cctv/create", {
        name = name,
        model = selectedModel,
        coords = { x = finalCoords.x, y = finalCoords.y, z = finalCoords.z },
        rotation = { x = finalRotation.x, y = finalRotation.y, z = finalRotation.z },
        jobs = selectedJobs,
    })
end

function CCTV.WatchCamera(self, cameraRef)
    if not cameraRef or not cameraRef.id then
        return
    end

    local cameraData = self.cameras[cameraRef.id]
    if not cameraData then
        return lib.notify({ title = locale("cctv_not_found"), type = "error" })
    end
    if not hasCctvJob(cameraData.jobs) then
        return lib.notify({ title = locale("camera_no_access"), type = "error" })
    end
    if cameraData.broken then
        return lib.notify({ title = locale("cctv_no_signal"), type = "error" })
    end

    self.watching = true
    self.curCam = cameraData
    self.rotX = 0.0
    self.rotZ = 0.0

    local forward = rotationToDirection(vector3(cameraData.rotation.x, cameraData.rotation.y, cameraData.rotation.z))
    local cameraOffset = Config.CCTV.cameraOffset or 0.5

    local modelHash = type(cameraData.model) == "number" and cameraData.model or GetHashKey(cameraData.model)
    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local waited = 0
        while not HasModelLoaded(modelHash) and waited < 2000 do
            Wait(50)
            waited = waited + 50
        end
    end

    if HasModelLoaded(modelHash) then
        local _, maxDimensions = GetModelDimensions(modelHash)
        cameraOffset = maxDimensions.y - 0.5
    end

    local camCoords = vec3(cameraData.coords.x, cameraData.coords.y, cameraData.coords.z) + forward * cameraOffset
    local ped = cache.ped
    local originalCoords = GetEntityCoords(ped)
    local distanceToCamera = #(originalCoords - vector3(cameraData.coords.x, cameraData.coords.y, cameraData.coords.z))
    local teleportDistance = Config.CCTV.teleportDistance or 100.0
    local teleported = false

    DoScreenFadeOut(500)
    Wait(500)

    if distanceToCamera > teleportDistance then
        teleported = true
        FreezeEntityPosition(ped, true)
        SetEntityVisible(ped, false, false)
        SetLocalPlayerInvisibleLocally(true)
        SetPlayerInvincible(cache.playerId, true)
        NetworkSetEntityInvisibleToNetwork(ped, true)
        SetEntityCoords(ped, cameraData.coords.x, cameraData.coords.y, cameraData.coords.z - 1.0, false, false, false, false)
        RequestCollisionAtCoord(cameraData.coords.x, cameraData.coords.y, cameraData.coords.z)

        local collisionWait = 0
        while not HasCollisionLoadedAroundEntity(ped) and collisionWait < 5000 do
            Wait(50)
            collisionWait = collisionWait + 50
        end
    end

    local scriptCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(scriptCam, camCoords.x, camCoords.y, camCoords.z)
    SetCamRot(scriptCam, cameraData.rotation.x, cameraData.rotation.y, cameraData.rotation.z - 180.0, 2)
    SetCamFov(scriptCam, 70.0)
    RenderScriptCams(true, false, 0, true, true)
    StartScreenEffect(
        Config.CCTV.screenEffect.name,
        0,
        Config.CCTV.screenEffect.looped
    )

    SendNUIMessage({
        action = "setCCTVData",
        data = {
            name = cameraData.name,
            street = getStreetNameAtCoords(vector3(cameraData.coords.x, cameraData.coords.y, cameraData.coords.z)),
            locales = {
                rec = locale("cctv_rec"),
                cam = locale("cctv_cam"),
                loc = locale("cctv_loc"),
                signal = locale("cctv_signal"),
                live = locale("cctv_live"),
                up = locale("cctv_up"),
                down = locale("cctv_down"),
                left = locale("cctv_left"),
                right = locale("cctv_right"),
                exit = locale("cctv_exit"),
            },
        },
    })
    SendNUIMessage({ action = "setVisibleCCTV", data = true })
    DoScreenFadeIn(500)

    local basePitch = cameraData.rotation.x
    local baseYaw = cameraData.rotation.z - 180.0
    local rotationConfig = Config.CCTV.cameraRotation

    while self.watching do
        Wait(0)
        HideHudAndRadarThisFrame()
        DisableAllControlActions(0)

        if IsDisabledControlPressed(0, 172) then
            self.rotX = math.min(self.rotX + rotationConfig.speed, rotationConfig.maxPitch)
            SetCamRot(scriptCam, basePitch + self.rotX, cameraData.rotation.y, baseYaw + self.rotZ, 2)
        end

        if IsDisabledControlPressed(0, 173) then
            self.rotX = math.max(self.rotX - rotationConfig.speed, rotationConfig.minPitch)
            SetCamRot(scriptCam, basePitch + self.rotX, cameraData.rotation.y, baseYaw + self.rotZ, 2)
        end

        if IsDisabledControlPressed(0, 174) then
            self.rotZ = self.rotZ + rotationConfig.speed
            if self.rotZ > 180.0 then
                self.rotZ = self.rotZ - 360.0
            end
            SetCamRot(scriptCam, basePitch + self.rotX, cameraData.rotation.y, baseYaw + self.rotZ, 2)
        end

        if IsDisabledControlPressed(0, 175) then
            self.rotZ = self.rotZ - rotationConfig.speed
            if self.rotZ < -180.0 then
                self.rotZ = self.rotZ + 360.0
            end
            SetCamRot(scriptCam, basePitch + self.rotX, cameraData.rotation.y, baseYaw + self.rotZ, 2)
        end

        if IsDisabledControlJustPressed(0, 73) then
            self.watching = false
        end
    end

    SendNUIMessage({ action = "setVisibleCCTV", data = false })
    StopScreenEffect(Config.CCTV.screenEffect.name)
    DoScreenFadeOut(500)
    Wait(1100)
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(scriptCam, false)

    if teleported then
        SetEntityCoords(ped, originalCoords.x, originalCoords.y, originalCoords.z, false, false, false, false)
        FreezeEntityPosition(ped, false)
        SetEntityVisible(ped, true, false)
        SetLocalPlayerInvisibleLocally(false)
        SetPlayerInvincible(cache.playerId, false)
        NetworkSetEntityInvisibleToNetwork(ped, false)
    end

    DoScreenFadeIn(500)
    self.curCam = nil
end

function CCTV.OpenMenu(self)
    if not hasCctvJob(Config.CCTV.defaultJobs) then
        return lib.notify({ title = locale("camera_no_access"), type = "error" })
    end

    local options = {}
    for cameraId, cameraData in pairs(self.cameras) do
        if hasCctvJob(cameraData.jobs) then
            local street = getStreetNameAtCoords(vector3(cameraData.coords.x, cameraData.coords.y, cameraData.coords.z))
            local prefix = cameraData.broken and ("~r~[" .. locale("cctv_broken") .. "]~s~ ") or ""
            options[#options + 1] = {
                title = prefix .. cameraData.name,
                description = locale("watch_camera", cameraData.name, street),
                icon = cameraData.broken and "video-slash" or "video",
                onSelect = function()
                    CCTV:WatchCamera({ id = cameraId })
                end,
            }
        end
    end

    if #options == 0 then
        return lib.notify({ title = locale("cctv_no_cameras"), type = "error" })
    end

    lib.registerContext({
        id = "cctv_menu",
        title = locale("cameras_menu"),
        options = options,
    })
    lib.showContext("cctv_menu")
end

function CCTV.DeleteCamera(self, cameraId)
    if not hasCctvJob(Config.CCTV.creatorAccess) then
        return lib.notify({ title = locale("camera_no_access"), type = "error" })
    end

    local confirmed = lib.alertDialog({
        header = locale("cctv_delete_confirm"),
        content = locale("cctv_delete_confirm_desc"),
        centered = true,
        cancel = true,
    })

    if confirmed == "confirm" then
        TriggerServerEvent("p_policejob/server/cctv/delete", cameraId)
    end
end

RegisterNetEvent("p_policejob/client/cctv/load", function(cameras)
    CCTV:LoadCameras(cameras)
end)

RegisterNetEvent("p_policejob/client/cctv/add", function(cameraData)
    CCTV:AddCamera(cameraData)
end)

RegisterNetEvent("p_policejob/client/cctv/remove", function(cameraId)
    CCTV:RemoveCamera(cameraId)
end)

RegisterNetEvent("p_policejob/client/cctv/update", function(cameraData)
    CCTV:UpdateCamera(cameraData)
end)

RegisterNetEvent("p_policejob/client/cctv/creator", function()
    CCTV:Creator()
end)

RegisterNetEvent("p_policejob/client/cctv/menu", function()
    CCTV:OpenMenu()
end)

RegisterNetEvent("p_policejob/client/cctv/broken", function(cameraId, isBroken)
    local cameraData = CCTV.cameras[cameraId]
    if cameraData then
        cameraData.broken = isBroken
    end

    if CCTV.watching and CCTV.curCam and CCTV.curCam.id == cameraId and isBroken then
        CCTV.watching = false
        lib.notify({ title = locale("cctv_no_signal"), type = "error" })
    end
end)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent("p_policejob/server/cctv/request")
end)

lib.onCache("weapon", function(weaponHash)
    if not weaponHash or not Config.CCTV.damage.enabled then
        return
    end

    CreateThread(function()
        while cache.weapon == weaponHash do
            Wait(0)
            if IsPedShooting(cache.ped) then
                local _, aimedEntity = GetEntityPlayerIsFreeAimingAt(cache.playerId)
                if aimedEntity and DoesEntityExist(aimedEntity) then
                    for cameraId, cameraObject in pairs(CCTV.objects) do
                        if cameraObject == aimedEntity then
                            local cameraData = CCTV.cameras[cameraId]
                            if cameraData and not cameraData.broken then
                                TriggerServerEvent("p_policejob/server/cctv/damage", cameraId)
                            end
                            break
                        end
                    end
                end
            end
            Wait(100)
        end
    end)
end)

exports("cctvCreator", function()
    CCTV:Creator()
end)

exports("cctvMenu", function()
    CCTV:OpenMenu()
end)

exports("cctvWatch", function(cameraRef)
    CCTV:WatchCamera(cameraRef)
end)

RegisterCommand("cctv_creator", function()
    CCTV:Creator()
end, false)
