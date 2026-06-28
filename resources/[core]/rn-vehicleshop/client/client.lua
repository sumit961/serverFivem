local pedSpawned = false
local GalleryPed = nil
local inShop = false
local newVehicle = nil
local spawnVehicle = false
local loadVeh = true
local cam = nil
local previewMode = 'store'
local lastPreviewDetails = nil
local testDriveActive = false
local testDriveVehicle = nil
local returnCoords = nil
local interactionVisible = false
local hudHidden = false
local purchaseNotifyAfterExit = nil
local interactionSuppressUntil = 0

local function sendUiToast(message)
    if message and message ~= '' then
        SendNUIMessage({ action = 'toast', message = tostring(message) })
    end
end

local function tryHudNotify(message, kind)
    message = tostring(message or '')
    kind = tostring(kind or 'info')
    if message == '' then return end
    local hud = (Config.HUD and Config.HUD.resource) or 'cm-hud'
    local ok = false
    for _, eventName in ipairs({
        'cm-hud:client:notify',
        'cm-hud:client:Notify',
        'cm-hud:notify',
        'cm-hud:Notify'
    }) do
        local status = pcall(function() TriggerEvent(eventName, message, kind) end)
        ok = ok or status
    end
    if GetResourceState(hud) == 'started' then
        for _, exportName in ipairs({ 'Notify', 'notify', 'SendNotification', 'ShowNotification' }) do
            pcall(function()
                if exports[hud] and exports[hud][exportName] then
                    exports[hud][exportName](message, kind)
                end
            end)
        end
    end
end

local function notify(message, kind)
    -- No GTA native notification is used in production. HUD gets the message when visible;
    -- NUI toast is kept for admin/store feedback while HUD is hidden.
    sendUiToast(message)
    if not hudHidden then tryHudNotify(message, kind) end
end

RegisterNetEvent('rn-vehicleshop:client:notify', function(message, kind)
    notify(message, kind)
end)

local function callHudExport(resourceName, exportName, ...)
    if GetResourceState(resourceName) ~= 'started' then return end
    pcall(function()
        local fn = exports[resourceName] and exports[resourceName][exportName]
        if fn then fn(...) end
    end)
end

local function emitHudVisibility(visible)
    local hud = (Config.HUD and Config.HUD.resource) or 'cm-hud'

    -- IMPORTANT: do not call generic ToggleHud/toggleHud APIs here.
    -- Some HUD resources treat toggle as "flip current state", not "set to this bool".
    -- Calling toggle on close was leaving cm-hud permanently hidden for some players.
    local setEvents = {
        'cm-hud:client:setVisible',
        'cm-hud:client:SetVisible',
        'cm-hud:client:setHudVisible',
        'cm-hud:client:SetHudVisible',
        'cm-hud:setVisible',
        'cm-hud:SetVisible'
    }
    for _, eventName in ipairs(setEvents) do
        pcall(function() TriggerEvent(eventName, visible) end)
    end

    if visible then
        for _, eventName in ipairs({
            'cm-hud:client:showHud',
            'cm-hud:client:ShowHud',
            'cm-hud:showHud',
            'cm-hud:ShowHud'
        }) do
            pcall(function() TriggerEvent(eventName) end)
        end
        callHudExport(hud, 'SetVisible', true)
        callHudExport(hud, 'SetHudVisible', true)
        callHudExport(hud, 'ShowHud')
        callHudExport(hud, 'showHud')
        callHudExport(hud, 'DisplayHud', true)
        callHudExport(hud, 'displayHud', true)
    else
        for _, eventName in ipairs({
            'cm-hud:client:hideHud',
            'cm-hud:client:HideHud',
            'cm-hud:hideHud',
            'cm-hud:HideHud'
        }) do
            pcall(function() TriggerEvent(eventName) end)
        end
        callHudExport(hud, 'SetVisible', false)
        callHudExport(hud, 'SetHudVisible', false)
        callHudExport(hud, 'HideHud')
        callHudExport(hud, 'hideHud')
        callHudExport(hud, 'DisplayHud', false)
        callHudExport(hud, 'displayHud', false)
    end
end

local function setHudVisible(visible, reason, force)
    visible = visible == true
    if (not force) and hudHidden == (not visible) then return end
    hudHidden = not visible
    emitHudVisibility(visible)
    pcall(function() LocalPlayer.state:set('cmHudHiddenByVehicleShop', not visible and (reason or true) or false, true) end)
    pcall(function() LocalPlayer.state:set('cmHudVisible', visible, true) end)
end

local function forceRestoreHud(reason)
    setHudVisible(true, reason or 'vehicle_shop_restore', true)
    CreateThread(function()
        -- Some HUD resources initialize UI one frame later after NUI/camera resets.
        -- Re-assert visible a few times without using toggle APIs.
        for _, delay in ipairs({ 150, 500, 1200 }) do
            Wait(delay)
            setHudVisible(true, reason or 'vehicle_shop_restore', true)
        end
    end)
end

function SetVehicleShopHudVisible(visible, reason)
    setHudVisible(visible == true, reason)
end

local function setInteractionVisible(show, payload)
    show = show == true
    if interactionVisible == show then return end
    interactionVisible = show
    payload = payload or {}
    payload.action = 'interaction'
    payload.show = show
    SendNUIMessage(payload)
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

-- Teleport the player to coords, waiting for collision so they never spawn in the
-- sky or fall through the map, then settle onto the real ground height.
local function safeTeleport(x, y, z, heading)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    if heading then SetEntityHeading(ped, heading) end
    local settleEnd = GetGameTimer() + 2000
    while GetGameTimer() < settleEnd do
        RequestCollisionAtCoord(x, y, z)
        if HasCollisionLoadedAroundEntity(ped) then break end
        Wait(0)
    end
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
    if found then SetEntityCoordsNoOffset(ped, x, y, groundZ, false, false, false) end
    if heading then SetEntityHeading(ped, heading) end
end

local function setShopState(active, mode)
    -- cm-spawn/cm-playerdata style resources can use this to skip saving airport/showroom coords.
    pcall(function() LocalPlayer.state:set('cmSkipPositionSave', active == true, true) end)
    pcall(function() LocalPlayer.state:set('ignorePositionSave', active == true, true) end)
    pcall(function() LocalPlayer.state:set('cmVehicleShop', active == true and (mode or previewMode or 'store') or false, true) end)
end

local function getPreviewStudio(mode)
    mode = mode or previewMode or 'store'
    if mode == 'admin' and Config.VehicleAdminStudio and Config.VehicleAdminStudio.enabled ~= false then
        return Config.VehicleAdminStudio
    end
    return Config.Showroom or {}
end

local function applyStudioEnvironment(mode)
    local studio = getPreviewStudio(mode)
    local env = studio.Environment
    if not env then return end
    NetworkOverrideClockTime(tonumber(env.hour) or 12, tonumber(env.minute) or 0, tonumber(env.second) or 0)
    if env.weather and env.weather ~= '' then
        ClearOverrideWeather()
        ClearWeatherTypePersist()
        SetWeatherTypeNowPersist(env.weather)
        SetWeatherTypeNow(env.weather)
        SetWeatherTypePersist(env.weather)
    end
    if env.timecycle and env.timecycle ~= '' then
        SetTimecycleModifier(env.timecycle)
        SetTimecycleModifierStrength(tonumber(env.timecycleStrength) or 0.0)
    end
end

local function restoreWorldEnvironment()
    ClearTimecycleModifier()
    ClearOverrideWeather()
end

function GetVehicleShopCaptureStudio()
    return getPreviewStudio('admin')
end

function GetVehicleShopPreviewMode()
    return previewMode
end

local function drawText3D(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    SetTextScale(0.34, 0.34)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(245, 245, 245, 235)
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(sx, sy)
end

local dealerSpeechText = nil
local dealerSpeechUntil = 0
local dealerNextGreetingAt = 0
local dealerWasNear = false
local dealerDialogOpen = false

local function spawnDealerPed()
    if pedSpawned then return end
    if Config.Ped and Config.Ped.enabled == false then return end
    local dealer = Config.Dealer or {}
    local hash = loadModel(dealer.ped or 'a_m_m_business_01')
    if not hash then return end
    local c = dealer.coords or vector4(Config.Location.x, Config.Location.y, Config.Location.z, 0.0)
    local pedConfig = Config.Ped or {}

    -- Spawn at the exact configured Z. Inside an MLO, GetGroundZFor_3dCoord often
    -- returns the natural terrain UNDER the building, which would sink the ped, so we
    -- trust the Z you captured while standing on the MLO floor instead.
    GalleryPed = CreatePed(4, hash, c.x, c.y, c.z, c.w or 0.0, false, true)
    SetEntityHeading(GalleryPed, c.w or 0.0)

    CreateThread(function()
        local deadline = GetGameTimer() + 4000
        RequestCollisionAtCoord(c.x, c.y, c.z)
        while not HasCollisionLoadedAroundEntity(GalleryPed) and GetGameTimer() < deadline do
            RequestCollisionAtCoord(c.x, c.y, c.z)
            Wait(0)
        end
        -- Re-assert the exact position once collision is present (prevents drift/sink).
        SetEntityCoordsNoOffset(GalleryPed, c.x, c.y, c.z, false, false, false)
        SetEntityHeading(GalleryPed, c.w or 0.0)
        FreezeEntityPosition(GalleryPed, true)
        if pedConfig.scenario and pedConfig.scenario ~= '' then
            TaskStartScenarioInPlace(GalleryPed, pedConfig.scenario, 0, true)
        end
    end)

    if pedConfig.invincible ~= false then SetEntityInvincible(GalleryPed, true) end
    SetBlockingOfNonTemporaryEvents(GalleryPed, pedConfig.blockEvents ~= false)
    SetPedCanRagdoll(GalleryPed, false)
    SetPedDiesWhenInjured(GalleryPed, false)
    SetModelAsNoLongerNeeded(hash)
    pedSpawned = true
end

local function randomFrom(list, fallback)
    if type(list) ~= 'table' or #list == 0 then return fallback end
    return list[math.random(1, #list)] or fallback
end

local function playDealerVoice(kind)
    local pedConfig = Config.Ped or {}
    if pedConfig.voiceEnabled == false then return end
    if not GalleryPed or not DoesEntityExist(GalleryPed) then return end
    local voices = kind == 'farewell' and pedConfig.farewellVoices or pedConfig.greetingVoices
    local speech = randomFrom(voices, kind == 'farewell' and 'GENERIC_BYE' or 'GENERIC_HI')
    pcall(function()
        StopCurrentPlayingAmbientSpeech(GalleryPed)
        PlayPedAmbientSpeechNative(GalleryPed, speech, 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR')
    end)
end

local function setDealerSpeech(text, duration)
    local pedConfig = Config.Ped or {}
    dealerSpeechText = text or ''
    dealerSpeechUntil = GetGameTimer() + (tonumber(duration or pedConfig.speechDuration) or 5000)
end

local function clearDealerSpeech()
    dealerSpeechText = nil
    dealerSpeechUntil = 0
end

local function playDealerGreetingIfNeeded()
    local pedConfig = Config.Ped or {}
    local now = GetGameTimer()
    if now < (dealerNextGreetingAt or 0) then return end
    setDealerSpeech(randomFrom(pedConfig.greetings, 'Welcome to the showroom.'), pedConfig.speechDuration)
    playDealerVoice('greeting')
    dealerNextGreetingAt = now + (tonumber(pedConfig.speechCooldown) or 15000)
end

local function playDealerFarewell()
    local pedConfig = Config.Ped or {}
    setDealerSpeech(randomFrom(pedConfig.farewells, 'See you around.'), pedConfig.speechDuration)
    playDealerVoice('farewell')
end

local function whenStarted()
    if Config.Blip and Config.Blip.showBlip then
        local blip = AddBlipForCoord(Config.Location)
        SetBlipSprite(blip, Config.Blip.id)
        SetBlipColour(blip, Config.Blip.color)
        SetBlipScale(blip, Config.Blip.scale)
        SetBlipDisplay(blip, 4)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Config.Blip.label)
        EndTextCommandSetBlipName(blip)
    end
    spawnDealerPed()
end

local function deletePreviewVehicle()
    if newVehicle and DoesEntityExist(newVehicle) then DeleteEntity(newVehicle) end
    newVehicle = nil
    spawnVehicle = false
    if SetCapturedPreviewVehicle then SetCapturedPreviewVehicle(nil) end
end

-- Spawn (or respawn) the showroom preview vehicle for a model. Returns the hash
-- on success so callers can push stats. Shared by the NUI spawn callback and the
-- admin image-capture flow.
local function spawnPreviewVehicle(model)
    model = tostring(model or '')
    if model == '' then return nil end
    deletePreviewVehicle()
    local hash = loadModel(model)
    if not hash then return nil end
    local studio = getPreviewStudio(previewMode)
    local c = studio.vehicle or vector4(Config.Location.x + 5.0, Config.Location.y + 5.0, Config.Location.z, 0.0)
    newVehicle = CreateVehicle(hash, c.x, c.y, c.z, c.w or 0.0, false, false)
    SetEntityAsMissionEntity(newVehicle, true, true)
    FreezeEntityPosition(newVehicle, true)
    SetEntityCollision(newVehicle, false, false)
    SetVehicleOnGroundProperly(newVehicle)
    SetVehicleDirtLevel(newVehicle, 0.0)
    SetVehicleCustomPrimaryColour(newVehicle, 255, 255, 255)
    SetVehicleCustomSecondaryColour(newVehicle, 255, 255, 255)
    SetModelAsNoLongerNeeded(hash)
    spawnVehicle = true
    if SetCapturedPreviewVehicle then SetCapturedPreviewVehicle(newVehicle) end
    return hash
end

function changeCam(mode)
    mode = mode or 'store'
    previewMode = mode
    DoScreenFadeOut(500)
    Wait(700)
    inShop = true
    setHudVisible(false, mode == 'admin' and 'vehicle_admin' or 'vehicle_store')
    setShopState(true, mode)
    setInteractionVisible(false)
    local shop = getPreviewStudio(mode)
    local p = shop.player or vector4(Config.Location.x, Config.Location.y, Config.Location.z, 0.0)
    local ped = PlayerPedId()
    if not returnCoords then
        local cur = GetEntityCoords(ped)
        returnCoords = vector4(cur.x, cur.y, cur.z, GetEntityHeading(ped))
    end

    SetEntityCoordsNoOffset(ped, p.x, p.y, p.z, false, false, false)
    SetEntityHeading(ped, p.w or 0.0)
    FreezeEntityPosition(ped, false)

    local settleEnd = GetGameTimer() + 2500
    while GetGameTimer() < settleEnd do
        RequestCollisionAtCoord(p.x, p.y, p.z)
        if HasCollisionLoadedAroundEntity(ped) then break end
        Wait(0)
    end

    local foundGround, groundZ = GetGroundZFor_3dCoord(p.x, p.y, p.z + 2.0, false)
    if foundGround and mode ~= 'admin' then
        SetEntityCoordsNoOffset(ped, p.x, p.y, groundZ, false, false, false)
    else
        -- Admin studio uses exact Z because the green floor/stage can be above native ground.
        SetEntityCoordsNoOffset(ped, p.x, p.y, p.z, false, false, false)
    end
    SetEntityHeading(ped, p.w or 0.0)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetLocalPlayerInvisibleLocally(true)
    SetEntityCollision(ped, false, false)

    applyStudioEnvironment(mode)

    if not DoesCamExist(cam) then cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true) end
    SetCamActive(cam, true)
    SetCamFov(cam, shop.cameraFov or 42.0)

    local cc = shop.camera or vector3(p.x - 4.0, p.y - 6.0, p.z + 2.2)
    SetCamCoord(cam, cc.x, cc.y, cc.z)

    local look = shop.cameraLookAt or shop.vehicle or p
    PointCamAtCoord(cam, look.x, look.y, (look.z or p.z))

    RenderScriptCams(true, false, 800, true, true)
    DoScreenFadeIn(700)
end

local function closeShopBase()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'forceClose' })
    SendNUIMessage({ action = 'prepareVehicleCapture', value = false })
    SendNUIMessage({ action = 'adminFocus', value = false })
    deletePreviewVehicle()
    DoScreenFadeOut(350)
    Wait(500)
    FreezeEntityPosition(PlayerPedId(), false)
    SetEntityVisible(PlayerPedId(), true, false)
    SetLocalPlayerInvisibleLocally(false)
    SetEntityCollision(PlayerPedId(), true, true)
    local e = (previewMode == 'admin' and returnCoords) or Config.ExitLocation or vector4(-2264.3823, 392.3130, 174.6739, 263.2466)
    safeTeleport(e.x, e.y, e.z, e.w or 0.0)
    returnCoords = nil
    TriggerEvent('change:time', false)
    restoreWorldEnvironment()
    RenderScriptCams(false, false, 1, true, true)
    DestroyAllCams(true)
    cam = nil
    interactionSuppressUntil = GetGameTimer() + 900
    inShop = false
    previewMode = 'store'
    setShopState(false)
    forceRestoreHud('vehicle_shop_closed')
    SendNUIMessage({ action = 'closeAdmin' })
    TriggerServerEvent('rn-vehicleshop:server:leaveShop')
    DoScreenFadeIn(500)
    if purchaseNotifyAfterExit then
        local msg = purchaseNotifyAfterExit
        purchaseNotifyAfterExit = nil
        SetTimeout(450, function() notify(msg, 'success') end)
    end
end

function closeVehicleShop()
    closeShopBase()
end

function closeVehicleShopAfterBuy(message)
    purchaseNotifyAfterExit = message or 'Vehicle purchased and stored.'
    closeShopBase()
end

local function deleteTestDriveVehicle()
    if testDriveVehicle and DoesEntityExist(testDriveVehicle) then
        SetEntityAsMissionEntity(testDriveVehicle, true, true)
        DeleteVehicle(testDriveVehicle)
        if DoesEntityExist(testDriveVehicle) then DeleteEntity(testDriveVehicle) end
    end
    testDriveVehicle = nil
    pcall(function() LocalPlayer.state:set('cmVehicleShopTestDrive', false, true) end)
    pcall(function() LocalPlayer.state:set('cmTestDrivePlate', false, true) end)
end

local function returnFromTestDrive(reason)
    if not testDriveActive then return end
    testDriveActive = false
    SendNUIMessage({ action = 'hideTimer' })
    DoScreenFadeOut(450)
    Wait(650)
    deleteTestDriveVehicle()
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    SetEntityVisible(ped, false, false)
    SetLocalPlayerInvisibleLocally(true)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)
    changeCam('store')
    if lastPreviewDetails and lastPreviewDetails.model then
        spawnPreviewVehicle(lastPreviewDetails.model)
        SendNUIMessage({ action = 'testDriveReturned', details = lastPreviewDetails, reason = reason or 'finished' })
    else
        SendNUIMessage({ action = 'open', vehicles = (data and data.vehicles) or {}, buttons = {}, daily = {}, colors = Config.Colors, buyer = (data and data.buyer) or 'Customer', testDrive = Config.TestDrive })
    end
    SetNuiFocus(true, true)
    DoScreenFadeIn(500)
end


RegisterNetEvent('rn-vehicleshop:target', function()
    if inShop then return end
    setInteractionVisible(false)
    SendNUIMessage({ action = 'undraw' })
    interactionSuppressUntil = GetGameTimer() + 2500
    -- Ask the server first while the player is still beside the dealer.
    -- If validation fails, the prompt can return after the short suppression window.
    TriggerServerEvent('rn-vehicleshop:server:openUI')
end)

RegisterNetEvent('vehicles:client:openUI', function(vehicles, daily, buyer)
    dealerDialogOpen = false
    if inShop then return end
    setInteractionVisible(false)
    SendNUIMessage({ action = 'dealerDialog', close = true })
    changeCam('store')
    TriggerEvent('change:time', true)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        vehicles = vehicles or {},
        buttons = {},
        daily = daily or {},
        colors = Config.Colors,
        buyer = buyer or 'Customer',
        testDrive = Config.TestDrive
    })
end)

RegisterNUICallback('spawnVehicle', function(data, cb)
    if not loadVeh then cb('busy') return end
    data = type(data) == 'table' and data or {}
    local model = tostring(data.model or '')
    if model == '' then cb('bad_model') return end
    loadVeh = false
    local hash = spawnPreviewVehicle(model)
    if not hash then loadVeh = true cb('bad_model') return end
    loadVeh = true

    local vehicleInfo = {
        speed = string.format('%.0f', GetVehicleMaxSpeed(newVehicle) * 3.6),
        acceleration = string.format('%.1f', GetVehicleModelAcceleration(hash) * 10),
        braking = string.format('%.1f', GetVehicleModelMaxBraking(hash) * 10),
        traction = string.format('%.1f', GetVehicleModelMaxTraction(hash) * 10)
    }
    SendNUIMessage({ action = 'updateInfo', vehicleInfo = vehicleInfo })
    cb('ok')
end)

-- Admin image capture: spawn the requested model in the showroom if the admin has
-- not already previewed it, so capture.lua has a live car to photograph.
RegisterNetEvent('rn-vehicleshop:client:spawnPreviewForCapture', function(model)
    spawnPreviewVehicle(model)
end)

RegisterNUICallback('buyVehicle', function(data, cb)
    data = type(data) == 'table' and data or {}
    if data.details then TriggerServerEvent('rn-vehicleshop:server:buyVehicle', data.details) end
    cb('ok')
end)

RegisterNetEvent('rn-vehicleshop:client:purchaseResult', function(success, message, vehicleData)
    if success then
        SendNUIMessage({ action = 'buyvehicle' })
        closeVehicleShopAfterBuy(message or 'Vehicle purchased and stored.')
        -- Vehicle is registered to the player but NOT spawned. A parking/retrieve
        -- system will handle spawning later.
    else
        notify(message or 'Purchase failed.')
        SendNUIMessage({ action = 'purchaseFailed', message = message or 'Purchase failed.' })
    end
end)

RegisterNUICallback('testDrive', function(data, cb)
    data = type(data) == 'table' and data or {}
    if data.details then TriggerServerEvent('rn-vehicleshop:server:testDriveRequest', data.details) end
    cb('ok')
end)

RegisterNetEvent('rn-vehicleshop:client:startTestDrive', function(vehDetails, timer)
    vehDetails = type(vehDetails) == 'table' and vehDetails or {}
    local model = tostring(vehDetails.model or '')
    if model == '' then return notify('Invalid test-drive vehicle.') end

    lastPreviewDetails = vehDetails
    SendNUIMessage({ action = 'testdriver', duration = tonumber(timer) or (Config.TestDrive and Config.TestDrive.testDriveTimer) or 60 })
    SetNuiFocus(false, false)
    setHudVisible(true, 'test_drive')
    deletePreviewVehicle()

    DoScreenFadeOut(450)
    Wait(650)
    RenderScriptCams(false, false, 1, true, true)
    if cam and DoesCamExist(cam) then DestroyCam(cam, false) end
    cam = nil

    local modelHash = loadModel(model)
    if not modelHash then
        notify('Could not load test vehicle.', 'error')
        testDriveActive = true
        returnFromTestDrive('load_failed')
        return
    end

    local c = Config.TestVehicleSpawnLocation or { coords = vector3(-1047.42, -3023.59, 13.95), heading = 60.0 }
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetLocalPlayerInvisibleLocally(false)
    SetEntityCollision(ped, true, true)
    safeTeleport(c.coords.x, c.coords.y, c.coords.z, c.heading or 0.0)

    -- Test-drive vehicle must be networked so key/vehicle resources can identify it.
    -- Calling NetworkGetNetworkIdFromEntity on a local vehicle causes the "no net object" warning.
    testDriveVehicle = CreateVehicle(modelHash, c.coords.x, c.coords.y, c.coords.z, c.heading or 0.0, true, true)
    SetEntityAsMissionEntity(testDriveVehicle, true, true)
    SetVehicleOnGroundProperly(testDriveVehicle)
    local testPlate = ('TEST%04d'):format(GetPlayerServerId(PlayerId()) % 10000)
    SetVehicleNumberPlateText(testDriveVehicle, testPlate)
    SetVehicleHasBeenOwnedByPlayer(testDriveVehicle, true)
    SetVehicleDoorsLocked(testDriveVehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(testDriveVehicle, false)
    SetVehicleDoorsLockedForPlayer(testDriveVehicle, PlayerId(), false)
    local netId = 0
    local netDeadline = GetGameTimer() + 1500
    repeat
        netId = NetworkGetNetworkIdFromEntity(testDriveVehicle)
        if netId and netId ~= 0 then break end
        Wait(0)
    until GetGameTimer() > netDeadline
    if netId and netId ~= 0 then
        SetNetworkIdCanMigrate(netId, false)
        NetworkSetNetworkIdDynamic(netId, false)
    end
    pcall(function() Entity(testDriveVehicle).state:set('cmVehicleShopTestDrive', true, true) end)
    pcall(function() Entity(testDriveVehicle).state:set('cm_testdrive', true, true) end)
    pcall(function() Entity(testDriveVehicle).state:set('vehicleShopTestDrive', true, true) end)
    pcall(function() Entity(testDriveVehicle).state:set('temporaryKeys', true, true) end)
    pcall(function() Entity(testDriveVehicle).state:set('testDrivePlate', testPlate, true) end)
    pcall(function() LocalPlayer.state:set('cmVehicleShopTestDrive', true, true) end)
    pcall(function() LocalPlayer.state:set('cmTestDrivePlate', testPlate, true) end)
    for _, eventName in ipairs({
        'cm-vehicles:client:GiveKeys',
        'cm-vehicles:client:giveKeys',
        'cm_vehicle:client:GiveKeys',
        'cm_vehicle:client:giveKeys',
        'vehiclekeys:client:SetOwner'
    }) do
        pcall(function() TriggerEvent(eventName, testPlate, testDriveVehicle, netId) end)
        pcall(function() TriggerEvent(eventName, testPlate) end)
        pcall(function() TriggerEvent(eventName, testDriveVehicle) end)
    end
    if netId and netId ~= 0 then
        for _, serverEvent in ipairs({
            'cm-vehicles:server:GiveTempKeys',
            'cm_vehicle:server:GiveTempKeys',
            'vehiclekeys:server:GiveTempKeys'
        }) do
            TriggerServerEvent(serverEvent, testPlate, netId)
        end
    end
    SetVehicleColours(testDriveVehicle, tonumber(vehDetails.gtaColor) or 111, tonumber(vehDetails.gtaColor) or 111)
    if vehDetails.r and vehDetails.g and vehDetails.b then
        SetVehicleCustomPrimaryColour(testDriveVehicle, tonumber(vehDetails.r) or 255, tonumber(vehDetails.g) or 255, tonumber(vehDetails.b) or 255)
        SetVehicleCustomSecondaryColour(testDriveVehicle, tonumber(vehDetails.r) or 255, tonumber(vehDetails.g) or 255, tonumber(vehDetails.b) or 255)
    end
    SetVehicleDirtLevel(testDriveVehicle, 0.0)
    SetVehicleEngineOn(testDriveVehicle, true, true, false)
    SetVehicleNeedsToBeHotwired(testDriveVehicle, false)
    SetPedIntoVehicle(ped, testDriveVehicle, -1)
    SetModelAsNoLongerNeeded(modelHash)

    testDriveActive = true
    local duration = tonumber(timer) or (Config.TestDrive and Config.TestDrive.testDriveTimer) or 60
    local startedAt = GetGameTimer()
    local endAt = startedAt + (duration * 1000)
    notify('Test drive started. Press F after 2 seconds to return early.', 'info')
    DoScreenFadeIn(500)

    CreateThread(function()
        while testDriveActive do
            Wait(0)
            if hudHidden then setHudVisible(true, 'test_drive_loop', true) end
            local now = GetGameTimer()
            DisableControlAction(0, 75, true) -- block default F exit; use it as return key
            if testDriveVehicle and DoesEntityExist(testDriveVehicle) then
                SetVehicleEngineOn(testDriveVehicle, true, true, false)
                SetVehicleUndriveable(testDriveVehicle, false)
                SetVehicleNeedsToBeHotwired(testDriveVehicle, false)
                SetVehicleDoorsLocked(testDriveVehicle, 1)
                SetVehicleDoorsLockedForPlayer(testDriveVehicle, PlayerId(), false)
                if GetVehiclePedIsIn(PlayerPedId(), false) ~= testDriveVehicle and (now - startedAt) < 3500 then
                    SetPedIntoVehicle(PlayerPedId(), testDriveVehicle, -1)
                end
            end
            -- Ignore any old/held F key state from opening/entering the vehicle.
            if (now - startedAt) > 2000 and IsDisabledControlJustPressed(0, 75) then
                returnFromTestDrive('manual')
                break
            end
            if now >= endAt then
                returnFromTestDrive('timer')
                break
            end
            -- Some vehicle/key resources touch newly-created cars right after spawn.
            -- Do not cancel during the first few seconds unless the timer is done.
            if (now - startedAt) > 12000 and (not testDriveVehicle or not DoesEntityExist(testDriveVehicle)) then
                returnFromTestDrive('vehicle_missing')
                break
            end
        end
    end)
end)


RegisterNUICallback('changeColor', function(data, cb)
    if newVehicle and DoesEntityExist(newVehicle) then
        SetVehicleCustomPrimaryColour(newVehicle, tonumber(data.colorR) or 255, tonumber(data.colorG) or 255, tonumber(data.colorB) or 255)
        SetVehicleCustomSecondaryColour(newVehicle, tonumber(data.colorR) or 255, tonumber(data.colorG) or 255, tonumber(data.colorB) or 255)
    end
    cb('ok')
end)

RegisterNUICallback('changePos', function(data, cb)
    if newVehicle and DoesEntityExist(newVehicle) then SetEntityHeading(newVehicle, tonumber(data.data) or 0.0) end
    cb('ok')
end)

RegisterNUICallback('closeVehicleShop', function(_, cb)
    closeVehicleShop()
    cb('ok')
end)

RegisterNUICallback('deletevehicle', function(_, cb)
    isRotatingMouseDown = false
    deletePreviewVehicle()
    cb('ok')
end)

RegisterNetEvent('rn-vehicleshop:client:requestAdmin', function()
    TriggerServerEvent('rn-vehicleshop:server:openAdmin')
end)

RegisterNetEvent('rn-vehicleshop:client:openAdmin', function(sourceList, catalog)
    -- Put the admin into the showroom camera view so the Capture Image button
    -- always has a cleanly framed car against the backdrop, even when /vehicleadmin
    -- is run from elsewhere on the map.
    if not inShop or previewMode ~= 'admin' then changeCam('admin') end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'adminOpen', sourceVehicles = sourceList or {}, catalog = catalog or {} })
end)

RegisterNetEvent('rn-vehicleshop:client:adminData', function(sourceList, catalog)
    SendNUIMessage({ action = 'adminData', sourceVehicles = sourceList or {}, catalog = catalog or {} })
end)

-- Server told us this car must be photographed before it can be enabled.
-- The NUI will run a capture and then re-submit the save automatically.
RegisterNetEvent('rn-vehicleshop:client:adminNeedsImage', function(model, pendingSave)
    SendNUIMessage({ action = 'adminNeedsImage', model = model, pendingSave = pendingSave or {} })
end)

RegisterNUICallback('adminSaveVehicle', function(data, cb)
    TriggerServerEvent('rn-vehicleshop:server:saveAdminVehicle', data or {})
    cb('ok')
end)

RegisterNUICallback('adminPreviewVehicle', function(data, cb)
    data = type(data) == 'table' and data or {}
    local model = tostring(data.model or '')
    if model ~= '' then
        previewMode = 'admin'
        local hash = spawnPreviewVehicle(model)
        if hash then
            local vehicleInfo = {
                speed = string.format('%.0f', GetVehicleMaxSpeed(newVehicle) * 3.6),
                acceleration = string.format('%.1f', GetVehicleModelAcceleration(hash) * 10),
                braking = string.format('%.1f', GetVehicleModelMaxBraking(hash) * 10),
                traction = string.format('%.1f', GetVehicleModelMaxTraction(hash) * 10)
            }
            SendNUIMessage({ action = 'updateInfo', vehicleInfo = vehicleInfo })
        end
    end
    cb('ok')
end)

RegisterNUICallback('adminDisableVehicle', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('rn-vehicleshop:server:disableAdminVehicle', data.model)
    cb('ok')
end)

RegisterNUICallback('adminRefresh', function(_, cb)
    TriggerServerEvent('rn-vehicleshop:server:openAdmin')
    cb('ok')
end)

RegisterNUICallback('adminClose', function(_, cb)
    SendNUIMessage({ action = 'closeAdmin' })
    -- Leave the showroom view and restore the player if the admin panel put us there.
    if inShop then
        closeVehicleShop()
    else
        SetNuiFocus(false, false)
    end
    cb('ok')
end)

-- Camera inspection controls from original rn-vehicleshop.
RegisterNUICallback('returnCam', function(_, cb)
    if cam and DoesCamExist(cam) then SetCamFov(cam, 50.0) end
    cb('ok')
end)

RegisterNUICallback('zoomCam', function(_, cb)
    if cam and DoesCamExist(cam) then SetCamFov(cam, 25.0) end
    cb('ok')
end)

local lastX = nil
local isRotatingMouseDown = false
RegisterNUICallback('mousedown', function(_, cb)
    if spawnVehicle and newVehicle and DoesEntityExist(newVehicle) then
        isRotatingMouseDown = true
        local currentEntityHeading = GetEntityHeading(newVehicle)
        lastX = GetNuiCursorPosition()
        CreateThread(function()
            while isRotatingMouseDown and newVehicle and DoesEntityExist(newVehicle) do
                local currentX = GetNuiCursorPosition()
                local diff = (currentX - lastX) * 0.3
                local newheading = currentEntityHeading + diff
                SetEntityHeading(newVehicle, newheading + 0.0)
                currentEntityHeading = newheading
                lastX = currentX
                Wait(0)
            end
        end)
    end
    cb('ok')
end)

RegisterNUICallback('mouseup', function(_, cb)
    isRotatingMouseDown = false
    cb('ok')
end)

RegisterNUICallback('downscroll', function(_, cb)
    if cam and DoesCamExist(cam) then SetCamFov(cam, math.min(GetCamFov(cam) + 4.0, 80.0)) end
    cb('ok')
end)

RegisterNUICallback('upscroll', function(_, cb)
    if cam and DoesCamExist(cam) then SetCamFov(cam, math.max(GetCamFov(cam) - 4.0, 20.0)) end
    cb('ok')
end)

CreateThread(function()
    Wait(800)
    whenStarted()
end)

CreateThread(function()
    while true do
        local sleep = 700
        if not inShop and not dealerDialogOpen and pedSpawned and GetGameTimer() > interactionSuppressUntil then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local dealer = Config.Dealer or {}
            local pedConfig = Config.Ped or {}
            local interact = Config.Interact or {}
            local c4 = dealer.coords or vector4(Config.Location.x, Config.Location.y, Config.Location.z, 0.0)
            local c = vector3(c4.x, c4.y, c4.z)
            local dist = #(coords - c)
            local now = GetGameTimer()

            if dist <= (interact.markerDistance or 18.0) then
                sleep = 0

                -- Optional greeting (off by default). Only runs if Config.Ped.showGreeting = true.
                if pedConfig.showGreeting == true then
                    local speechDistance = tonumber(pedConfig.speechDistance) or 6.0
                    if dist <= speechDistance then
                        if not dealerWasNear then
                            dealerWasNear = true
                            dealerNextGreetingAt = 0
                        end
                        playDealerGreetingIfNeeded()
                    elseif dealerWasNear and dist > (speechDistance + 1.5) then
                        dealerWasNear = false
                        clearDealerSpeech()
                    end
                end

                -- Name above the dealer (the greeting text bubble is only drawn if enabled).
                if pedConfig.showName ~= false and dist <= (pedConfig.nameDistance or 8.0) then
                    drawText3D(c.x, c.y, c.z + (pedConfig.nameHeight or 1.30), dealer.npcName or 'Vehicle Dealer')
                end
                if pedConfig.showGreeting == true and dealerSpeechText and now < dealerSpeechUntil and dist <= (pedConfig.nameDistance or 8.0) then
                    drawText3D(c.x, c.y, c.z + (pedConfig.nameHeight or 1.30) + 0.26, dealerSpeechText)
                end

                -- On-screen interaction prompt + open on E.
                if dist <= (interact.distance or 2.6) then
                    setInteractionVisible(true, {
                        clerkName = dealer.npcName or 'Vehicle Dealer',
                        title = interact.title or 'Talk to Dealer',
                        subtitle = interact.subtitle or 'Browse and buy vehicles',
                        key = interact.keyLabel or 'E'
                    })
                    if IsControlJustPressed(0, interact.key or 38) then
                        setInteractionVisible(false)
                        TriggerEvent('rn-vehicleshop:openDialog')
                        Wait(300)
                    end
                else
                    setInteractionVisible(false)
                end
            else
                setInteractionVisible(false)
                if dealerWasNear then dealerWasNear = false clearDealerSpeech() end
            end
        end
        Wait(sleep)
    end
end)

-- RP "talk" step: show a short dealer dialog, then open the catalog on confirm.
RegisterNetEvent('rn-vehicleshop:openDialog', function()
    if inShop then return end
    dealerDialogOpen = true
    setInteractionVisible(false)
    local pedConfig = Config.Ped or {}
    local dialog = pedConfig.dialog or {}
    -- Dealer says the RP line out loud (bubble + voice) as the dialog opens.
    setDealerSpeech(dialog.line or 'Tell me what you are after.', pedConfig.speechDuration)
    playDealerVoice('greeting')
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'dealerDialog',
        clerkName = dialog.clerkName or (Config.Dealer and Config.Dealer.npcName) or 'Dealer',
        title = dialog.title or 'How can I help you today?',
        line = dialog.line or '',
        optionStore = dialog.optionStore or 'Show me the catalog',
        optionClose = dialog.optionClose or 'Maybe later'
    })
end)

-- NUI chose "Show me the catalog" -> proceed to open the shop.
RegisterNUICallback('dealerDialogStore', function(_, cb)
    dealerDialogOpen = false
    SendNUIMessage({ action = 'dealerDialog', close = true })
    setInteractionVisible(false)
    SetNuiFocus(false, false)
    TriggerEvent('rn-vehicleshop:target')
    cb('ok')
end)

-- NUI chose "Maybe later" -> close dialog, farewell.
RegisterNUICallback('dealerDialogClose', function(_, cb)
    dealerDialogOpen = false
    SendNUIMessage({ action = 'dealerDialog', close = true })
    SetNuiFocus(false, false)
    playDealerFarewell()
    cb('ok')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    deletePreviewVehicle()
    deleteTestDriveVehicle()
    if inShop then
        FreezeEntityPosition(PlayerPedId(), false)
        SetEntityVisible(PlayerPedId(), true, false)
        SetLocalPlayerInvisibleLocally(false)
        SetEntityCollision(PlayerPedId(), true, true)
        local e = returnCoords or Config.ExitLocation or vector4(Config.Location.x, Config.Location.y, Config.Location.z, 0.0)
        safeTeleport(e.x, e.y, e.z, e.w or 0.0)
        returnCoords = nil
        SetNuiFocus(false, false)
        RenderScriptCams(false, false, 1, true, true)
        DestroyAllCams(true)
        setShopState(false)
        forceRestoreHud('resource_stop')
    end
    if GalleryPed and DoesEntityExist(GalleryPed) then DeleteEntity(GalleryPed) end
    forceRestoreHud('resource_stop')
end)
