while not Config or not Config.Camera do
    Citizen.Wait(500)
end

if not Config.Camera.Enabled then
    return
end

Camera = {
    isActive = false,
    cameraProp = nil,
    cameraState = false,
    antiSpam = 0,
}

exports("isCameraActive", function()
    return Camera.isActive
end)

function PolicePhotoCapture()
    local uploadTarget = lib.callback.await("p_policejob/server/screenshot/uploadTarget", false)
    if not uploadTarget or not uploadTarget.clientUpload then
        return lib.callback.await("p_policejob/server/screenshotCapture", false)
    end

    local capturePromise = promise.new()
    local resolved = false

    function resolveCapture(response)
        if resolved then
            return
        end
        resolved = true
        capturePromise:resolve(response)
    end

    exports["screenshot-basic"]:requestScreenshotUpload(
        uploadTarget.url,
        uploadTarget.field or "file",
        {
            encoding = uploadTarget.encoding or "jpg",
            quality = uploadTarget.quality or 0.85,
            headers = uploadTarget.headers or {},
        },
        function(response)
            resolveCapture(response)
        end
    )

    SetTimeout(30000, function()
        resolveCapture(nil)
    end)

    local response = Citizen.Await(capturePromise)
    if type(response) ~= "string" or response == "" then
        return nil
    end

    return lib.callback.await("p_policejob/server/screenshot/resolveUrl", false, response)
end

function setCameraPropVisible(visible)
    if visible then
        local model = lib.requestModel("ch_prop_ch_camera_01")
        local animDict = lib.requestAnimDict("amb@world_human_paparazzi@male@base")
        TaskPlayAnim(cache.ped, animDict, "base", -8.0, 8.0, -1, 49, 1)
        Camera.cameraProp = CreateObject(model, GetEntityCoords(cache.ped), true, true, true)
        SetEntityAsMissionEntity(Camera.cameraProp, true, true)
        AttachEntityToEntity(
            Camera.cameraProp, cache.ped,
            GetPedBoneIndex(cache.ped, 18905),
            0.03, -0.15, 0.13,
            24.8, 0.0, 132.0,
            true, true, false, false, 1, true
        )
        SetModelAsNoLongerNeeded(model)
        RemoveAnimDict(animDict)
    else
        ClearPedTasks(cache.ped)
        if Camera.cameraProp and DoesEntityExist(Camera.cameraProp) then
            while DoesEntityExist(Camera.cameraProp) do
                Citizen.Wait(1)
                NetworkRequestControlOfEntity(Camera.cameraProp)
                DeleteEntity(Camera.cameraProp)
                DeleteObject(Camera.cameraProp)
            end
        end
        Camera.cameraProp = nil
    end
end

function Camera.use(self)
    if self.antiSpam > GetGameTimer() then
        return
    end

    local job = Bridge.Framework.fetchPlayerJob()
    if Config.Jobs then
        local requiredGrade = Config.Jobs[job.name]
        if not requiredGrade or requiredGrade > job.grade then
            Bridge.Notify.showNotify(locale("camera_item_no_access"), "error")
            return
        end
    end

    self.antiSpam = GetGameTimer() + 1000
    self.cameraState = true
    self.isActive = true
    setCameraPropVisible(true)
    Citizen.Wait(1500)

    local waitAttempts = 0
    while (not self.cameraProp or not DoesEntityExist(self.cameraProp)) and waitAttempts < 100 do
        Citizen.Wait(100)
        waitAttempts = waitAttempts + 1
    end

    if not self.cameraProp or not DoesEntityExist(self.cameraProp) then
        self.cameraState = false
        self.isActive = false
        return
    end

    local scriptCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    AttachCamToEntity(scriptCam, self.cameraProp, 0.0, -0.4, 0.0, true)
    SetCamRot(scriptCam, GetEntityRotation(cache.ped, 2), 2)
    SetCamActive(scriptCam, true)
    RenderScriptCams(true, false, 0, true, true)
    Config.Camera.onCameraStart()

    CreateThread(function()
        while Camera.cameraState do
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 14, true)
            DisableControlAction(0, 15, true)
            DisableControlAction(0, 16, true)
            DisableControlAction(0, 17, true)
            DisableControlAction(0, 81, true)
            DisableControlAction(0, 82, true)

            local mouseX = GetDisabledControlNormal(0, 1)
            local mouseY = GetDisabledControlNormal(0, 2)
            local camRot = GetCamRot(scriptCam, 2)
            local pedHeading = GetEntityHeading(cache.ped)

            SetCamRot(scriptCam, camRot.x - mouseY * 3.0, 0.0, camRot.z - mouseX * 3.0, 2)
            SetEntityHeading(cache.ped, pedHeading - mouseX * 1.5)

            local zoomIn = IsDisabledControlPressed(0, 15)
                or IsDisabledControlPressed(0, 241)
                or IsControlPressed(0, 172)
                or IsDisabledControlPressed(0, 172)

            local zoomOut = IsDisabledControlPressed(0, 14)
                or IsDisabledControlPressed(0, 242)
                or IsControlPressed(0, 173)
                or IsDisabledControlPressed(0, 173)

            if zoomIn then
                SetCamFov(scriptCam, math.max(GetCamFov(scriptCam) - 2.0, 10.0))
            elseif zoomOut then
                SetCamFov(scriptCam, math.min(GetCamFov(scriptCam) + 2.0, 65.0))
            end

            if IsControlJustPressed(0, 73) or IsDisabledControlJustPressed(0, 73) then
                Camera.cameraState = false
                setCameraPropVisible(false)
                RenderScriptCams(false, false, 0, true, true)
                DestroyCam(scriptCam, false)
                Config.Camera.onCameraStop()
                Camera.isActive = false
            end

            if IsControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 191) then
                Camera.cameraState = false
                local photoUrl = PolicePhotoCapture()
                if photoUrl then
                    TriggerServerEvent("p_policejob/server/camera/TakePhoto", photoUrl)
                    Bridge.Notify.showNotify(locale("photo_taken"), "success")
                else
                    Bridge.Notify.showNotify(locale("photo_failed"), "error")
                end
                RenderScriptCams(false, false, 0, true, true)
                DestroyCam(scriptCam, false)
                setCameraPropVisible(false)
                Config.Camera.onCameraStop()
                Camera.isActive = false
            end

            Citizen.Wait(0)
        end
    end)
end

RegisterNetEvent("p_policejob/client/camera/ShowPhoto", function(photoData)
    SendNUIMessage({ action = "setPhotoData", data = photoData })
    SendNUIMessage({ action = "setVisiblePhoto", data = true })
    SetNuiFocus(true, true)
end)

RegisterNUICallback("hideFrame", function(data, cb)
    if data and data.name == "setVisiblePhoto" then
        SetNuiFocus(false, false)
        SendNUIMessage({ action = "setVisiblePhoto", data = false })
    end
    cb("ok")
end)

RegisterNUICallback("camera/copyPhoto", function(data, cb)
    if data and data.url then
        lib.setClipboard(data.url)
        Bridge.Notify.showNotify(locale("photo_copied"), "success")
    end
    cb("ok")
end)

RegisterNetEvent("p_policejob/client/camera/CopyPhoto", function(url)
    lib.setClipboard(url)
    Bridge.Notify.showNotify(locale("photo_copied"), "success")
end)

RegisterNetEvent("p_policejob/client/camera/use", function()
    Camera:use()
end)
