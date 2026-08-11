if not Config.Mugshot.enabled then
    return
end

Mugshot = {
    isActive = false,
    boardRendering = false,
}

exports("isMugshotActive", function()
    return Mugshot.isActive
end)

exports("openMugshotMenu", function(targetId)
    Mugshot:openMenu(targetId)
end)

exports("openMugshotGallery", function()
    Mugshot:openGallery()
end)

function Mugshot.loadScaleform(self, scaleformName)
    local scaleform = RequestScaleformMovie(scaleformName)
    while not HasScaleformMovieLoaded(scaleform) do
        Wait(0)
    end
    return scaleform
end

function Mugshot.createNamedRenderTarget(self, targetName, modelHash)
    if not IsNamedRendertargetRegistered(targetName) then
        RegisterNamedRendertarget(targetName, 0)
    end
    if not IsNamedRendertargetLinked(modelHash) then
        LinkNamedRendertarget(modelHash)
    end
    if IsNamedRendertargetRegistered(targetName) then
        return GetNamedRendertargetRenderId(targetName)
    end
    return 0
end

function Mugshot.prepareMugshotBoard(self)
    self.boardRendering = true
    local scaleform = self:loadScaleform("mugshot_board_01")
    local renderId = self:createNamedRenderTarget("ID_Text", -955488312)
    CreateThread(function()
        while self.boardRendering do
            HideHudAndRadarThisFrame()
            SetTextRenderId(renderId)
            Set_2dLayer(4)
            SetScriptGfxDrawBehindPausemenu(1)
            DrawScaleformMovie(scaleform, 0.405, 0.37, 0.81, 0.74, 255, 255, 255, 255, 0)
            SetScriptGfxDrawBehindPausemenu(0)
            SetTextRenderId(GetDefaultScriptRendertargetRenderId())
            Wait(0)
        end
    end)
    return scaleform
end

function Mugshot.drawBoard(self, scaleform, boardData)
    BeginScaleformMovieMethod(scaleform, "SET_BOARD")
    PushScaleformMovieMethodParameterString(boardData.title)
    PushScaleformMovieMethodParameterString(boardData.text)
    PushScaleformMovieMethodParameterString(boardData.subtitle)
    PushScaleformMovieMethodParameterString(boardData.footer)
    PushScaleformMovieFunctionParameterInt(0)
    PushScaleformMovieMethodParameterString(boardData.level or "")
    PushScaleformMovieFunctionParameterInt(116)
    EndScaleformMovieMethod()
end

function Mugshot.createPlayerBoard(self)
    local ped = cache.ped
    local boardModel = lib.requestModel("prop_police_id_board")
    local textModel = lib.requestModel("prop_police_id_text")
    local coords = GetEntityCoords(ped)
    local board = CreateObject(-1623189257, coords, true, true, false)
    local textProp = CreateObject(-955488312, coords, true, true, false)
    AttachEntityToEntity(
        textProp, board, -1, 4103,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        false, false, false, false, 2, true
    )
    SetCurrentPedWeapon(ped, -1569615261, 1)
    ClearPedWetness(ped)
    ClearPedBloodDamage(ped)
    AttachEntityToEntity(
        board, ped, GetPedBoneIndex(ped, 28422),
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0, 0, 0, 0, 2, 1
    )
    SetModelAsNoLongerNeeded(boardModel)
    SetModelAsNoLongerNeeded(textModel)
    return board, textProp
end

CreateThread(function()
    for locationId, location in pairs(Config.DepartmentData.mugshots or {}) do
        Bridge.Target.addSphereZone({
            coords = location.coords,
            radius = 0.5,
            drawSprite = true,
            debug = Config.Debug,
            options = {
                {
                    name = "p_policejob:mugshot:take_" .. locationId,
                    label = locale("take_mugshot"),
                    icon = "fa-solid fa-camera",
                    distance = 2,
                    groups = Config.Jobs,
                    onSelect = function()
                        Mugshot:takeMugshot(locationId, location)
                    end,
                },
                {
                    name = "p_policejob:mugshot:check_" .. locationId,
                    label = locale("check_mugshots"),
                    icon = "fa-solid fa-images",
                    distance = 2,
                    groups = Config.Jobs,
                    onSelect = function()
                        Mugshot:openGallery()
                    end,
                },
            },
        })
    end
end)

function Mugshot.takeMugshot(self, locationId, location)
    local input = lib.inputDialog(locale("take_mugshot"), {
        {
            type = "textarea",
            label = locale("mugshot_info"),
            required = true,
        },
    })
    if not input then
        return
    end
    local closestPlayer = lib.getClosestPlayer(location.photoCoords, 1.5, false)
    if not closestPlayer then
        return Bridge.Notify.showNotify(locale("no_player_to_mugshot"), "error")
    end
    TriggerServerEvent("p_policejob/server/mugshot/takePhoto", {
        playerId = GetPlayerServerId(closestPlayer),
        name = locationId,
        info = {
            description = input[1],
        },
    })
end

lib.callback.register("p_policejob/client/mugshot/takePhoto", function(photoData)
    local location = Config.DepartmentData.mugshots[photoData.name]
    local scaleform = Mugshot:prepareMugshotBoard()
    Wait(350)
    Mugshot:drawBoard(scaleform, {
        title = Config.Mugshot.boardTitle,
        subtitle = Config.Mugshot.boardSubtitle,
        text = Bridge.Framework.getPlayerName(),
        footer = photoData.info.dob,
        level = "",
    })
    local board, textProp = Mugshot:createPlayerBoard()
    local animDict = lib.requestAnimDict("mp_character_creation@customise@male_a")
    local previousWeapon = GetSelectedPedWeapon(cache.ped)
    TaskPlayAnim(cache.ped, animDict, "loop", -8.0, 8.0, -1, 1, true, false, false, false)
    local camera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    local pedCoords = GetEntityCoords(cache.ped)
    SetCamCoord(camera, location.cameraCoords.x, location.cameraCoords.y, location.cameraCoords.z)
    PointCamAtCoord(camera, pedCoords.x, pedCoords.y, location.cameraCoords.z)
    SetCamFov(camera, location.cameraFov or 50.0)
    RenderScriptCams(true, false, 0, true, true)
    Wait(2000)
    local photoUrl = PolicePhotoCapture()
    Wait(2000)
    Mugshot.boardRendering = false
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(camera)
    DeleteObject(board)
    DeleteObject(textProp)
    StopAnimTask(cache.ped, "mp_character_creation@customise@male_a", "loop", 1.0)
    SetCurrentPedWeapon(cache.ped, previousWeapon, true)
    if photoUrl then
        Config.Mugshot.onPhotoTaken(photoUrl)
    end
    return photoUrl
end)

function Mugshot.openGallery(self, searchQuery)
    local mugshots = lib.callback.await("p_policejob/server/mugshot/getMugshots", false, searchQuery)
    if not mugshots then
        return
    end
    SendNUIMessage({
        action = "setMugshotData",
        data = mugshots,
    })
    SendNUIMessage({
        action = "setVisibleMugshot",
        data = true,
    })
    SetNuiFocus(true, true)
end

function Mugshot.closeGallery(self)
    SendNUIMessage({
        action = "setVisibleMugshot",
        data = false,
    })
    SetNuiFocus(false, false)
end

RegisterNUICallback("hideFrame", function(data, cb)
    if data.name == "setVisibleMugshot" then
        Mugshot:closeGallery()
    end
    cb("ok")
end)

RegisterNUICallback("mugshot:remove", function(data, cb)
    if data.id then
        TriggerServerEvent("p_policejob/server/mugshot/remove", data.id)
    end
    cb("ok")
end)

RegisterNUICallback("mugshot:copyUrl", function(data, cb)
    if data.url then
        lib.setClipboard(data.url)
        Bridge.Notify.showNotify(locale("mugshot_url_copied"), "success")
    end
    cb("ok")
end)
