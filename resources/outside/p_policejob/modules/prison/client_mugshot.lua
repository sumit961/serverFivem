if not Config or not Config.Prison or not Config.Prison.Enabled then
    return
end

if not Config.Prison.Mugshot.enabled then
    return
end

local mugshotCamera = nil
local mugshotActive = false
local mugshotBoardProp = nil
local mugshotTextProp = nil
local mugshotBoardRendering = false
local mugshotScenePeds = {}

function spawnMugshotScenePeds(pedConfigs)
    if not pedConfigs or #pedConfigs == 0 then
        return
    end

    for _, pedConfig in ipairs(pedConfigs) do
        local modelHash = type(pedConfig.model) == "string" and joaat(pedConfig.model) or pedConfig.model
        lib.requestModel(modelHash)

        local coords = pedConfig.coords
        local ped = CreatePed(
            4, modelHash,
            coords.x, coords.y, coords.z - 1.0, coords.w or 0.0,
            false, false
        )

        SetEntityAsMissionEntity(ped, true, true)
        SetPedFleeAttributes(ped, 0, false)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedCanRagdoll(ped, false)
        SetPedConfigFlag(ped, 32, true)
        FreezeEntityPosition(ped, true)

        if pedConfig.anim and pedConfig.anim.dict and pedConfig.anim.clip then
            lib.requestAnimDict(pedConfig.anim.dict)
            TaskPlayAnim(
                ped, pedConfig.anim.dict, pedConfig.anim.clip,
                8.0, -8.0, -1, pedConfig.anim.flag or 1,
                0, false, false, false
            )
        end

        SetModelAsNoLongerNeeded(modelHash)
        mugshotScenePeds[#mugshotScenePeds + 1] = ped
    end
end

function cleanupMugshotScenePeds()
    for _, ped in ipairs(mugshotScenePeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
    mugshotScenePeds = {}
end

function loadScaleformMovie(scaleformName)
    local handle = RequestScaleformMovie(scaleformName)
    while not HasScaleformMovieLoaded(handle) do
        Wait(0)
    end
    return handle
end

function getNamedRenderTarget(renderTargetName, modelHash)
    if not IsNamedRendertargetRegistered(renderTargetName) then
        RegisterNamedRendertarget(renderTargetName, 0)
    end
    if not IsNamedRendertargetLinked(modelHash) then
        LinkNamedRendertarget(modelHash)
    end
    if IsNamedRendertargetRegistered(renderTargetName) then
        return GetNamedRendertargetRenderId(renderTargetName)
    end
    return 0
end

function startMugshotBoardRender()
    mugshotBoardRendering = true
    local scaleform = loadScaleformMovie("mugshot_board_01")
    local renderId = getNamedRenderTarget("ID_Text", -955488312)

    CreateThread(function()
        while mugshotBoardRendering do
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

function setMugshotBoardText(scaleform, boardData)
    BeginScaleformMovieMethod(scaleform, "SET_BOARD")
    PushScaleformMovieMethodParameterString(boardData.title or "")
    PushScaleformMovieMethodParameterString(boardData.text or "")
    PushScaleformMovieMethodParameterString(boardData.subtitle or "")
    PushScaleformMovieMethodParameterString(boardData.footer or "")
    PushScaleformMovieFunctionParameterInt(0)
    PushScaleformMovieMethodParameterString(boardData.level or "")
    PushScaleformMovieFunctionParameterInt(116)
    EndScaleformMovieMethod()
end

function attachMugshotProps(ped)
    lib.requestModel(-1623189257)
    lib.requestModel(-955488312)

    local pedCoords = GetEntityCoords(ped)
    local boardProp = CreateObject(-1623189257, pedCoords, true, true, false)
    local textProp = CreateObject(-955488312, pedCoords, true, true, false)

    AttachEntityToEntity(textProp, boardProp, -1, 4103, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
    SetCurrentPedWeapon(ped, -1569615261, 1)
    ClearPedWetness(ped)
    ClearPedBloodDamage(ped)
    AttachEntityToEntity(
        boardProp, ped, GetPedBoneIndex(ped, 28422),
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0, 0, 0, 0, 2, 1
    )

    SetModelAsNoLongerNeeded(-1623189257)
    SetModelAsNoLongerNeeded(-955488312)
    return boardProp, textProp
end

function cleanupMugshotProps()
    mugshotBoardRendering = false

    if mugshotBoardProp and DoesEntityExist(mugshotBoardProp) then
        DeleteEntity(mugshotBoardProp)
    end
    if mugshotTextProp and DoesEntityExist(mugshotTextProp) then
        DeleteEntity(mugshotTextProp)
    end

    mugshotBoardProp = nil
    mugshotTextProp = nil
end

function playMugshotCameraFlash()
    PlaySoundFrontend(-1, "Camera_Shoot", "Phone_SoundSet_Default", true)
end

function playMugshotFlashEffect(duration)
    AnimpostfxStop("SuccessNeutral")
    AnimpostfxPlay("SuccessNeutral", duration or 250, false)
end

function updateMugshotBoard(scaleform, sentenceData, profileLabel)
    local minutes = math.ceil((sentenceData.sentenceTime or 0) / 60)
    local levelText = sentenceData.isLife and "LIFE" or (tostring(minutes) .. " MO")
    local mugshotId = string.format("%05d", math.random(10000, 99999))

    setMugshotBoardText(scaleform, {
        title = "BOLINGBROKE PENITENTIARY",
        text = string.upper(sentenceData.playerName or "Unknown"),
        subtitle = "ID #" .. mugshotId .. "  -  " .. profileLabel,
        footer = string.upper(sentenceData.reason or ""),
        level = levelText,
    })
end

function waitForPedHeading(ped, targetHeading, timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 2500)
    while GetGameTimer() < deadline do
        local headingDiff = math.abs(((GetEntityHeading(ped) - targetHeading + 540.0) % 360.0) - 180.0)
        if headingDiff < 3.0 then
            return
        end
        Wait(0)
    end
end

function runMugshotSequence(sentenceData)
    if mugshotActive then
        return
    end
    mugshotActive = true

    if not Prison.Map or not Prison.Map.mugshot then
        if Prison.playCellArrival then
            pcall(Prison.playCellArrival, sentenceData)
        end
        Prison:enter(sentenceData)
        mugshotActive = false
        return
    end

    local mugshotConfig = Prison.Map.mugshot
    local cameraConfig = mugshotConfig.camera
    local ped = cache.ped
    local pedHeading = mugshotConfig.pedCoords.w or 0.0
    local scaleform = startMugshotBoardRender()

    Wait(200)
    DoScreenFadeOut(500)
    Wait(600)

    SetEntityCoords(
        ped,
        mugshotConfig.pedCoords.x,
        mugshotConfig.pedCoords.y,
        mugshotConfig.pedCoords.z,
        false, false, false, true
    )
    SetEntityHeading(ped, pedHeading)

    spawnMugshotScenePeds(mugshotConfig.peds)
    mugshotBoardProp, mugshotTextProp = attachMugshotProps(ped)

    mugshotCamera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(mugshotCamera, cameraConfig.coords.x, cameraConfig.coords.y, cameraConfig.coords.z)
    SetCamRot(mugshotCamera, cameraConfig.rotation.x, cameraConfig.rotation.y, cameraConfig.rotation.z, 2)
    SetCamFov(mugshotCamera, cameraConfig.fov or 40.0)
    RenderScriptCams(true, false, 0, true, true)

    updateMugshotBoard(scaleform, sentenceData, "FRONT")

    lib.requestAnimDict("mp_character_creation@customise@male_a")
    TaskPlayAnim(ped, "mp_character_creation@customise@male_a", "loop", 4.0, -4.0, -1, 49, 0, false, false, false)

    Wait(1000)
    DoScreenFadeIn(700)
    Wait(500)

    local shotDuration = math.max(700, math.floor((Config.Prison.Mugshot.duration or 5000) / 3))
    local profiles = {
        { heading = pedHeading, label = "FRONT" },
        { heading = pedHeading + 90.0, label = "RIGHT PROFILE" },
        { heading = pedHeading - 90.0, label = "LEFT PROFILE" },
    }

    for index, profile in ipairs(profiles) do
        updateMugshotBoard(scaleform, sentenceData, profile.label)

        if index > 1 then
            ClearPedSecondaryTask(ped)
            if index == 3 then
                TaskAchieveHeading(ped, pedHeading, 1200)
                waitForPedHeading(ped, pedHeading, 1400)
            end
            TaskAchieveHeading(ped, profile.heading, 1500)
            waitForPedHeading(ped, profile.heading, 1800)
            TaskPlayAnim(ped, "mp_character_creation@customise@male_a", "loop", 4.0, -4.0, -1, 49, 0, false, false, false)
        end

        Wait(shotDuration)
        playMugshotCameraFlash()
        playMugshotFlashEffect(200)
        Wait(350)
    end

    ClearPedSecondaryTask(ped)
    TaskAchieveHeading(ped, pedHeading, 1200)
    waitForPedHeading(ped, pedHeading, 1400)
    TaskPlayAnim(ped, "mp_character_creation@customise@male_a", "loop", 4.0, -4.0, -1, 49, 0, false, false, false)

    Wait(250)
    DoScreenFadeOut(500)
    Wait(600)

    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(mugshotCamera, false)
    mugshotCamera = nil

    cleanupMugshotProps()
    cleanupMugshotScenePeds()
    ClearPedTasks(ped)
    SetEntityHeading(ped, pedHeading)

    mugshotActive = false

    if Prison.playCellArrival then
        pcall(Prison.playCellArrival, sentenceData)
    end
    Prison:enter(sentenceData)
end

RegisterNetEvent("p_policejob/client/prison/mugshot", function(sentenceData)
    if not sentenceData or type(sentenceData) ~= "table" then
        return
    end
    runMugshotSequence(sentenceData)
end)

RegisterCommand("mugshot", function()
    runMugshotSequence({
        playerName = GetPlayerName(cache.serverId),
        reason = "Testing Mugshot",
        sentenceTime = 900,
    })
end, false)
