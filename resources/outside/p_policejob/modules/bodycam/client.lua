if not Config.Bodycam.Enabled then
    return
end

Bodycam = {
    isActive = false,
    data = nil,
    watching = {
        camera = nil,
        targetPed = nil,
        targetId = nil,
        isActive = false,
        isRecording = false,
        cachedCoords = nil,
    },
}

exports("isBodycamActive", function()
    return Bodycam.isActive
end)

exports("ToggleBodyCam", function(player, state)
    Bodycam:toggle(player, state)
end)

exports("OpenBodyCamList", function()
    Bodycam:openList()
end)

exports("StartWatchBodyCam", function(targetId)
    Bodycam:startWatching(targetId)
end)

function Bodycam.open(self, data)
    self.isActive = true
    self.data = data
    SendNUIMessage({ action = "setVisibleBodycam", data = true })
    SendNUIMessage({ action = "setBodycamData", data = data })
end

function Bodycam.close(self)
    self.isActive = false
    self.data = nil
    SendNUIMessage({ action = "setVisibleBodycam", data = false })
end

function Bodycam.toggle(self, state, data)
    if state == nil then
        state = not self.isActive
    end
    if data then
        self.data = data
    end
    if state then
        self:open(data or self.data)
    else
        self:close()
    end
end

function Bodycam.setupWatchingPed(self, hidden)
    local ped = cache.ped
    FreezeEntityPosition(ped, hidden)
    SetEntityVisible(ped, not hidden)
    SetEntityCollision(ped, not hidden, not hidden)
    SetEntityInvincible(ped, hidden)
    NetworkSetEntityInvisibleToNetwork(ped, hidden)
end

function Bodycam.startWatching(self, targetId)
    local coords = lib.callback.await("p_policejob/server/bodycam/fetchPlayerCoords", false, targetId)
    if not coords then
        return Bridge.Notify.showNotify(locale("bodycam_not_active"), "error")
    end

    local ped = cache.ped
    local playerCoords = GetEntityCoords(ped)
    local playerHeading = GetEntityHeading(ped)

    self.watching.cachedCoords = vector4(playerCoords.x, playerCoords.y, playerCoords.z, playerHeading)
    self.watching.isActive = true
    self.watching.targetId = targetId
    self.watching.isRecording = false

    Config.Bodycam.onStartWatching()
    LocalPlayer.state:set("isInBodycam", targetId, true)

    Utils:fadeOutScreen(1000)
    self:setupWatchingPed(true)

    SetEntityCoords(ped, coords.x, coords.y, coords.z - 100.0)
    Wait(500)

    self.watching.targetPed = GetPlayerPed(GetPlayerFromServerId(targetId))
    self.watching.camera = CreateCam("DEFAULT_SCRIPTED_FLY_CAMERA", true)

    AttachCamToPedBone(
        self.watching.camera, self.watching.targetPed,
        46240, 0.1, 0.025, 0.1, true
    )
    SetCamFov(self.watching.camera, 100.0)
    SetCamRot(self.watching.camera, 0, 0, GetEntityHeading(self.watching.targetPed), 2)
    RenderScriptCams(true, false, 0, 1, 0)
    ShakeCam(self.watching.camera, "HAND_SHAKE", 1.0)
    SetCamShakeAmplitude(self.watching.camera, 2.0)
    SetTimecycleModifier("Island_CCTV_ChannelFuzz")
    SetTimecycleModifierStrength(0.45)

    self:startWatchingThreads()
    Utils:fadeInScreen(1000)
end

function Bodycam.stopWatching(self)
    if not self.watching.isActive then
        return
    end

    if self.watching.isRecording and self.watching.targetId then
        TriggerServerEvent("p_policejob/server/bodycam/stopRecording", self.watching.targetId)
        self.watching.isRecording = false
    end

    Utils:fadeOutScreen(1000)
    self:setupWatchingPed(false)

    if self.watching.cachedCoords then
        SetEntityCoords(
            cache.ped,
            self.watching.cachedCoords.x,
            self.watching.cachedCoords.y,
            self.watching.cachedCoords.z
        )
        SetEntityHeading(cache.ped, self.watching.cachedCoords.w)
    end

    RenderScriptCams(false, false, 0, 1, 0)
    SetTimecycleModifier("default")
    SetTimecycleModifierStrength(1.0)
    DoScreenFadeIn(1000)
    Wait(500)

    self.watching = {
        camera = nil,
        targetPed = nil,
        targetId = nil,
        isActive = false,
        isRecording = false,
        cachedCoords = nil,
    }

    LocalPlayer.state:set("isInBodycam", false, true)
    Config.Bodycam.onStopWatching()
end

function Bodycam.getTextUI(self)
    local recordingConfig = Config.Bodycam.Recording
    if not recordingConfig or not recordingConfig.Enabled then
        return locale("bodycam_textui")
    end
    if self.watching.isRecording then
        return locale("bodycam_textui_recording")
    end
    return locale("bodycam_textui_record")
end

function Bodycam.toggleRecording(self)
    local recordingConfig = Config.Bodycam.Recording
    if not recordingConfig or not recordingConfig.Enabled then
        return Bridge.Notify.showNotify(locale("bodycam_recording_disabled"), "error")
    end
    if not self.watching.isActive or not self.watching.targetId then
        return
    end

    if self.watching.isRecording then
        self.watching.isRecording = false
        lib.showTextUI(self:getTextUI(), { position = "bottom-center" })
        TriggerServerEvent("p_policejob/server/bodycam/stopRecording", self.watching.targetId)
        Bridge.Notify.showNotify(locale("bodycam_recording_stopped"), "inform")
    else
        local started = lib.callback.await(
            "p_policejob/server/bodycam/startRecording",
            false,
            self.watching.targetId
        )
        if not started then
            return Bridge.Notify.showNotify(locale("bodycam_recording_failed_start"), "error")
        end
        self.watching.isRecording = true
        lib.showTextUI(self:getTextUI(), { position = "bottom-center" })
        Bridge.Notify.showNotify(locale("bodycam_recording_started"), "inform")
    end
end

function Bodycam.startWatchingThreads(self)
    CreateThread(function()
        lib.showTextUI(Bodycam:getTextUI(), { position = "bottom-center" })

        local recordKey = Config.Bodycam.Recording and Config.Bodycam.Recording.Key or nil
        local recordingEnabled = Config.Bodycam.Recording and Config.Bodycam.Recording.Enabled or false
        local recordCooldown = 500
        local lastRecordPress = 0

        while Bodycam.watching.isActive do
            Wait(1)
            DisableAllControlActions(0)
            SetCamRot(
                Bodycam.watching.camera,
                0, 0,
                GetEntityHeading(Bodycam.watching.targetPed),
                2
            )

            if IsControlJustPressed(0, 73) or IsDisabledControlJustPressed(0, 73) then
                Bodycam:stopWatching()
                break
            end

            if recordingEnabled and recordKey then
                if IsControlJustPressed(0, recordKey) or IsDisabledControlJustPressed(0, recordKey) then
                    local now = GetGameTimer()
                    if now - lastRecordPress > recordCooldown then
                        lastRecordPress = now
                        Bodycam:toggleRecording()
                    end
                end
            end
        end

        lib.hideTextUI()
    end)

    CreateThread(function()
        while Bodycam.watching.isActive do
            Wait(2500)
            if not Bodycam.watching.isActive then
                break
            end

            local targetPed = Bodycam.watching.targetPed
            if targetPed ~= cache.ped and DoesEntityExist(targetPed) then
                local watcherCoords = GetEntityCoords(cache.ped)
                local targetCoords = GetEntityCoords(targetPed)
                if #(watcherCoords - targetCoords) > 150 then
                    SetEntityCoords(
                        cache.ped,
                        targetCoords.x, targetCoords.y, targetCoords.z - 100.0,
                        false, false, false, true
                    )
                end
            else
                Bodycam:stopWatching()
            end
        end
    end)
end

function Bodycam.openList(self)
    local bodycams = lib.callback.await("p_policejob/server/bodycam/fetchList", false)
    if not bodycams or not next(bodycams) then
        return Bridge.Notify.showNotify(locale("no_active_bodycams"), "error")
    end

    local options = {}
    for serverId, bodycamData in pairs(bodycams) do
        options[#options + 1] = {
            title = locale("watch_bodycam_title", bodycamData.name, bodycamData.badge),
            description = locale("watch_bodycam_info", bodycamData.name, bodycamData.badge),
            arrow = true,
            onSelect = function()
                Bodycam:startWatching(serverId)
            end,
        }
    end

    lib.registerContext({
        id = "bodycam_list_menu",
        title = locale("bodycam_list_menu"),
        options = options,
    })
    lib.showContext("bodycam_list_menu")
end

RegisterNetEvent("p_policejob/client/bodycam/toggle", function(state, data)
    Bodycam:toggle(state, data)
end)

RegisterNetEvent("p_policejob/client/bodycam/forceStopWatching", function()
    if Bodycam.watching.isActive then
        Bridge.Notify.showNotify(locale("bodycam_target_disconnected"), "error")
        Bodycam:stopWatching()
    end
end)

RegisterNetEvent("p_policejob/client/bodycam/recordingUploaded", function(url)
    Bridge.Notify.showNotify(locale("bodycam_recording_uploaded"), "success")
    if url then
        lib.setClipboard(url)
    end
end)

RegisterNetEvent("p_policejob/client/bodycam/recordingFailed", function()
    Bridge.Notify.showNotify(locale("bodycam_recording_failed_upload"), "error")
end)

RegisterNetEvent("p_policejob:pauseMenuState", function(isPaused)
    if not Bodycam.isActive then
        return
    end
    SendNUIMessage({
        action = "setVisibleBodycam",
        data = not isPaused,
    })
end)

AddEventHandler("ox_inventory:itemCount", function(itemName, count)
    if itemName == "body_cam" and count < 1 and Bodycam.isActive then
        Bodycam:close()
    end
end)

CreateThread(function()
    Citizen.Wait(2000)
    local bodycamLocations = Config.DepartmentData.bodycams or {}
    for index, location in pairs(bodycamLocations) do
        Bridge.Target.addSphereZone({
            coords = location.coords,
            radius = location.radius or 0.5,
            drawSprite = true,
            debug = Bridge and Bridge.Config and Bridge.Config.Debug,
            options = {
                {
                    name = "p_policejob:bodycam:watch_" .. index,
                    label = locale("check_bodycams"),
                    icon = "fa-solid fa-video",
                    distance = location.distance or 2,
                    groups = Config.Jobs,
                    onSelect = function()
                        Bodycam:openList()
                    end,
                },
            },
        })
    end
end)
