local pedSpawned = false
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
local hudHidden = false
local hudStoreLock = false

-- EMS fleet vehicle appearance: accumulated locally and applied to the
-- (purely local, non-networked) admin preview vehicle via cm-vehicles'
-- ApplyVehicleMods export -- same reuse cm-ems's configurator uses, just
-- against this resource's own preview vehicle instead of a spawned one.
local currentAdminMods = {}
local hudLoopToken = 0
local testDriveHudTransition = false
local purchaseNotifyAfterExit = nil
local interactionSuppressUntil = 0
local openRequestPending = false
local lastShopPayload = nil
local testDriveChargeToken = nil
local testDriveSessionToken = nil
local testDriveReturnMode = 'store'
local testDriveProtection = nil
local isRotatingMouseDown = false
local appearanceCleanupToken = 0
local vehicleAdminClimatePauseRequested = false
local vehicleAdminClimatePauseReason = 'rn-vehicleshop:vehicleadmin'

local function setTestDriveProtection(active)
    local player = PlayerId()
    local ped = PlayerPedId()
    if active then
        if testDriveProtection then return end
        local playerWasInvincible = false
        local entityWasInvincible = false
        local okPlayer, playerValue = pcall(function() return GetPlayerInvincible(player) end)
        local okEntity, entityValue = pcall(function() return GetEntityInvincible(ped) end)
        if okPlayer then playerWasInvincible = playerValue == true end
        if okEntity then entityWasInvincible = entityValue == true end
        testDriveProtection = {
            ped = ped,
            playerWasInvincible = playerWasInvincible,
            entityWasInvincible = entityWasInvincible,
        }
        SetPlayerInvincible(player, true)
        SetEntityInvincible(ped, true)
        return
    end

    local previous = testDriveProtection
    testDriveProtection = nil
    if not previous then return end
    local restorePed = DoesEntityExist(previous.ped) and previous.ped or PlayerPedId()
    SetPlayerInvincible(player, previous.playerWasInvincible == true)
    SetEntityInvincible(restorePed, previous.entityWasInvincible == true)
end

local function reassertTestDriveProtection()
    if not testDriveProtection then return end
    SetPlayerInvincible(PlayerId(), true)
    SetEntityInvincible(PlayerPedId(), true)
end

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
    local args = { ... }
    pcall(function()
        local fn = exports[resourceName] and exports[resourceName][exportName]
        if fn then fn(table.unpack(args)) end
    end)
end

local function setNativeHudVisible(visible, thisFrame)
    visible = visible == true
    if thisFrame and not visible then
        pcall(function() HideHudAndRadarThisFrame() end)
    end
    pcall(function() DisplayHud(visible) end)
    pcall(function() DisplayRadar(visible) end)
end


local function emitHudVisibility(visible, reason)
    visible = visible == true
    reason = reason or 'vehicle_shop'

    -- Native GTA HUD/radar is separate from cm-hud/NUI bridge events.
    setNativeHudVisible(visible, false)

    local hud = (Config.HUD and Config.HUD.resource) or 'cm-hud'

    -- Use cm-hud's real bridge events instead of generic Toggle events.
    -- Toggle-style events can flip the HUD back off during close/test-drive races.
    if visible then
        pcall(function() TriggerEvent('cm-hud:client:setHudVisible', true, reason) end)
        pcall(function() TriggerEvent('cm-hud:client:showAfterUi', reason) end)
    else
        pcall(function() TriggerEvent('cm-hud:client:hideForUi', reason) end)
        pcall(function() TriggerEvent('cm-hud:client:setHudVisible', false, reason) end)
    end

    -- Export bridge for this cm-hud build and compatibility with similar HUDs.
    callHudExport(hud, 'SetHudVisible', visible)
    callHudExport(hud, 'SetVisible', visible)
    callHudExport(hud, 'DisplayHud', visible)
    callHudExport(hud, 'displayHud', visible)
    callHudExport(hud, 'SetDisplay', visible)
    callHudExport(hud, 'setDisplay', visible)

    -- Generic non-toggle compatibility events only. Do not call Toggle here.
    for _, eventName in ipairs({
        'hud:client:SetVisible', 'hud:client:setVisible',
        'hud:client:DisplayHud', 'hud:client:displayHud'
    }) do
        pcall(function() TriggerEvent(eventName, visible, reason) end)
    end
end

local function setHudVisible(visible, reason, force)
    visible = visible == true
    if (not force) and hudHidden == (not visible) then return end
    hudHidden = not visible
    emitHudVisibility(visible, reason or 'vehicle_shop')
    pcall(function() LocalPlayer.state:set('cmHudHiddenByVehicleShop', not visible and (reason or true) or false, true) end)
    pcall(function() LocalPlayer.state:set('cmHudVisible', visible, true) end)
end

local function shouldHideHudForMode(mode)
    local hudCfg = Config.HUD or {}
    -- Test drive is allowed to show HUD. Never let a stale store/admin lock hide it.
    if mode == 'test_drive' then return false end
    if mode == 'admin' then return hudCfg.hideWhileInAdmin ~= false end
    if mode == 'store' then return hudCfg.hideWhileInStore ~= false end
    if mode == 'capture' then return hudCfg.hideWhileCapturing ~= false end
    return false
end

local function runHudAssertion(visible, reason, durationMs, sessionBound)
    hudLoopToken = hudLoopToken + 1
    local token = hudLoopToken
    local untilTime = durationMs and (GetGameTimer() + math.max(tonumber(durationMs) or 0, 0)) or nil
    local hideMode = visible ~= true

    setHudVisible(visible, reason, true)
    setNativeHudVisible(visible, false)

    CreateThread(function()
        local nextBridgeAssert = 0
        while token == hudLoopToken do
            local now = GetGameTimer()
            if untilTime and now > untilTime then break end

            if sessionBound then
                local activeStoreHudLock = hudStoreLock and inShop and shouldHideHudForMode(previewMode) and not testDriveActive and not testDriveHudTransition
                if not activeStoreHudLock then break end
            end

            -- For store/admin hide, native HUD/radar must be suppressed every frame.
            -- cm-hud's NUI bridge is reasserted only a few times per second to avoid spam.
            if hideMode then
                setNativeHudVisible(false, true)
                if now >= nextBridgeAssert then
                    nextBridgeAssert = now + 150
                    setHudVisible(false, reason, true)
                end
                Wait(0)
            else
                -- Visible HUD loops should never force cm-hud/NUI bridge events.
                -- Forcing true here retriggers HUD fade/slide animations and causes blinking.
                -- setHudVisible(..., false) only fires if the state actually changed.
                setHudVisible(true, reason, false)
                setNativeHudVisible(true, false)
                Wait(250)
            end
        end
    end)
end

local function beginHudStoreLock(reason)
    reason = reason or 'vehicle_shop'
    hudStoreLock = true
    runHudAssertion(false, reason, nil, true)
end

local function endHudStoreLock()
    hudStoreLock = false
    hudLoopToken = hudLoopToken + 1
end

local function forceHideHud(reason, durationMs)
    reason = reason or 'vehicle_shop'
    if hudStoreLock then
        runHudAssertion(false, reason, nil, true)
    else
        runHudAssertion(false, reason, tonumber(durationMs) or 1500, false)
    end
end

local function forceRestoreHud(reason, durationMs)
    reason = reason or 'vehicle_shop_restore'
    hudStoreLock = false
    pcall(function() LocalPlayer.state:set('cmHudHiddenByVehicleShop', false, true) end)
    pcall(function() LocalPlayer.state:set('cmHudVisible', true, true) end)
    pcall(function() LocalPlayer.state:set('hudVisible', true, true) end)
    pcall(function() LocalPlayer.state:set('hudHidden', false, true) end)
    pcall(function() LocalPlayer.state:set('hideHud', false, true) end)
    runHudAssertion(true, reason, tonumber(durationMs) or 3500, false)
end

local function enterTestDriveHudMode(durationMs)
    -- Hard switch from showroom/admin hidden HUD into visible test-drive HUD.
    -- This clears the store lock before NUI/camera/teleport changes so no stale hide
    -- tick can win the transition and cause a HUD blink.
    testDriveHudTransition = true
    testDriveActive = true
    previewMode = 'test_drive'
    hudStoreLock = false
    hudLoopToken = hudLoopToken + 1

    pcall(function() LocalPlayer.state:set('cmHudHiddenByVehicleShop', false, true) end)
    pcall(function() LocalPlayer.state:set('cmHudVisible', true, true) end)
    pcall(function() LocalPlayer.state:set('cmVehicleShop', 'test_drive', true) end)
    pcall(function() LocalPlayer.state:set('cmVehicleShopTestDrive', true, true) end)
    pcall(function() LocalPlayer.state:set('hudVisible', true, true) end)
    pcall(function() LocalPlayer.state:set('hudHidden', false, true) end)
    pcall(function() LocalPlayer.state:set('hideHud', false, true) end)

    runHudAssertion(true, 'test_drive', tonumber(durationMs) or 7000, false)
end

RegisterNetEvent('rn-vehicleshop:client:setHudVisible', function(visible, reason)
    setHudVisible(visible == true, reason or 'external_request', true)
end)

-- Shared "Press E" prompt + cinematic NPC dialogue come from cm-ui (same
-- convention as cm-gunstore / nv_cloth / cm-store). Guarded at call time so the
-- shop still opens if cm-ui is stopped -- the dealer then skips straight to the
-- catalog instead of showing a conversation.
local function uiAvailable()
    return GetResourceState('cm-ui') == 'started'
end

local function uiShowInteract(payload)
    if not uiAvailable() then return end
    exports['cm-ui']:ShowInteract(payload)
end

local function uiHideInteract()
    if not uiAvailable() then return end
    exports['cm-ui']:HideInteract()
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    RequestModel(hash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function loadVehicleModel(model)
    local hash = type(model) == 'number' and model or joaat(tostring(model or ''))
    if hash == 0 or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(hash) or not IsModelAVehicle(hash) then return nil end
    return hash
end

local function clampInt(value, minValue, maxValue, fallback)
    value = math.floor(tonumber(value) or fallback)
    if value < minValue then value = minValue end
    if value > maxValue then value = maxValue end
    return value
end

local function vehicleDefaults(model)
    model = tostring(model or ''):lower():gsub('%s+', '')
    local defaults = Config.VehicleDefaults or {}
    return defaults[model] or defaults[tostring(joaat(model))] or {}
end

local function applyConfiguredVehicleDefaults(vehicle, model)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local cfg = vehicleDefaults(model)
    if cfg.livery ~= nil and cfg.livery ~= 'auto' then
        local livery = math.floor(tonumber(cfg.livery) or -1)
        pcall(function() SetVehicleLivery(vehicle, livery) end)
        pcall(function() SetVehicleMod(vehicle, 48, livery, false) end)
    end
    if type(cfg.extras) == 'table' then
        for extraId, enabled in pairs(cfg.extras) do
            extraId = tonumber(extraId)
            if extraId and DoesExtraExist(vehicle, extraId) then
                pcall(function() SetVehicleExtra(vehicle, extraId, enabled == true and 0 or 1) end)
            end
        end
    end
end

-- Teleport the player to coords, waiting for collision so they never spawn in the
-- sky or fall through the map, then settle onto the real ground height.
local function safeTeleport(x, y, z, heading)
    local ped = PlayerPedId()
    -- Keep the player frozen while collision streams in. If we unfreeze first,
    -- gravity can pull the ped below unloaded ground during long teleports.
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    if heading then SetEntityHeading(ped, heading) end

    local settleEnd = GetGameTimer() + 2000
    while GetGameTimer() < settleEnd do
        RequestCollisionAtCoord(x, y, z)
        if HasCollisionLoadedAroundEntity(ped) then break end
        Wait(0)
    end

    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
    if found then
        SetEntityCoordsNoOffset(ped, x, y, groundZ, false, false, false)
    else
        SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    end
    if heading then SetEntityHeading(ped, heading) end
    FreezeEntityPosition(ped, false)
end

local function setShopState(active, mode)
    -- cm-spawn/cm-playerdata style resources can use this to skip saving airport/showroom coords.
    pcall(function() LocalPlayer.state:set('cmSkipPositionSave', active == true, true) end)
    pcall(function() LocalPlayer.state:set('ignorePositionSave', active == true, true) end)
    pcall(function() LocalPlayer.state:set('cmVehicleShop', active == true and (mode or previewMode or 'store') or false, true) end)
end

local function shouldRefundTestDriveCharge(reason)
    reason = tostring(reason or '')
    return reason == 'load_failed'
        or reason == 'missing_spawn'
        or reason == 'spawn_failed'
        or reason == 'invalid_model'
end

local function reportTestDriveStartFailed(reason)
    if not testDriveChargeToken then return end
    local token = testDriveChargeToken
    testDriveChargeToken = nil
    TriggerServerEvent('rn-vehicleshop:server:testDriveStartFailed', token, tostring(reason or 'start_failed'))
end

local function getPreviewStudio(mode)
    mode = mode or previewMode or 'store'
    if mode == 'admin' and Config.VehicleAdminStudio and Config.VehicleAdminStudio.enabled ~= false then
        return Config.VehicleAdminStudio
    end
    if mode == 'boat' and Config.BoatShowroom then
        return Config.BoatShowroom
    end
    if mode == 'air' and Config.AirShowroom then
        return Config.AirShowroom
    end
    return Config.Showroom or {}
end

-- The admin photo studio deliberately uses fixed midday/clear conditions. Pause
-- cm-climatime while the studio owns those natives, then let it immediately
-- restore the player's live climate when the admin leaves or starts a test drive.
local function setVehicleAdminClimatePaused(paused)
    paused = paused == true
    vehicleAdminClimatePauseRequested = paused
    if GetResourceState('cm-climatime') ~= 'started' then return end

    pcall(function()
        exports['cm-climatime']:PauseSync(paused, vehicleAdminClimatePauseReason)
    end)
end

local function applyStudioEnvironment(mode, hardReset)
    local studio = getPreviewStudio(mode)
    local env = studio.Environment
    if not env then return end
    NetworkOverrideClockTime(tonumber(env.hour) or 12, tonumber(env.minute) or 0, tonumber(env.second) or 0)
    if env.weather and env.weather ~= '' then
        if hardReset ~= false then
            ClearOverrideWeather()
            ClearWeatherTypePersist()
            SetWeatherTypeNowPersist(env.weather)
            SetWeatherTypeNow(env.weather)
        else
            -- Soft persistence does not clear/reapply the weather every few frames,
            -- preventing the visible flash/blink caused by the old 350 ms loop.
            SetWeatherTypePersist(env.weather)
        end
    end
    if hardReset ~= false then
        if env.timecycle and env.timecycle ~= '' then
            SetTimecycleModifier(env.timecycle)
            SetTimecycleModifierStrength(tonumber(env.timecycleStrength) or 0.0)
        else
            ClearTimecycleModifier()
        end
    end
end

local function restoreWorldEnvironment()
    ClearTimecycleModifier()
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    pcall(function() NetworkClearClockTimeOverride() end)
end

-- Reassert only the persistent clock/weather state at a low frequency so GTA's
-- ambient systems cannot drift the photo studio while cm-climatime is paused.
CreateThread(function()
    while true do
        local captureActive = IsVehicleShopCaptureActive and IsVehicleShopCaptureActive()
        if inShop and previewMode == 'admin' and not captureActive then
            applyStudioEnvironment('admin', false)
            local env = (getPreviewStudio('admin') or {}).Environment or {}
            Wait(math.max(2500, tonumber(env.reassertMs) or 5000))
        else
            Wait(1000)
        end
    end
end)

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

local dealerDialogOpen = false
local activeDealerShop = nil

-- One dealer NPC per storefront (cars / boats / air). Each entry keeps its own
-- ped + speech state, mirroring cm-gunstore's per-shop `_ped` pattern.
local dealerShops = {
    { type = 'store', label = 'CAR DEALER',  dealerKey = 'Dealer',      showroomKey = 'Showroom',     blipKey = 'Blip' },
    { type = 'boat',  label = 'BOAT DEALER', dealerKey = 'BoatDealer',  showroomKey = 'BoatShowroom', blipKey = 'BoatBlip' },
    { type = 'air',   label = 'AIR DEALER',  dealerKey = 'AirDealer',   showroomKey = 'AirShowroom',  blipKey = 'AirBlip' },
}

local function shopDealer(shop)
    return Config[shop.dealerKey] or {}
end

local function spawnShopPed(shop)
    if shop._ped and DoesEntityExist(shop._ped) then return end
    if Config.Ped and Config.Ped.enabled == false then return end
    local dealer = shopDealer(shop)
    local c = dealer.coords
    if not c then return end
    local hash = loadModel(dealer.ped or 'a_m_m_business_01')
    if not hash then return end
    local pedConfig = Config.Ped or {}

    -- Spawn at the exact configured Z. Inside an MLO, GetGroundZFor_3dCoord often
    -- returns the natural terrain UNDER the building, which would sink the ped, so we
    -- trust the Z you captured while standing on the MLO floor instead.
    local ped = CreatePed(4, hash, c.x, c.y, c.z, c.w or 0.0, false, true)
    SetEntityHeading(ped, c.w or 0.0)

    CreateThread(function()
        local deadline = GetGameTimer() + 4000
        RequestCollisionAtCoord(c.x, c.y, c.z)
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
            RequestCollisionAtCoord(c.x, c.y, c.z)
            Wait(0)
        end
        -- Re-assert the exact position once collision is present (prevents drift/sink).
        SetEntityCoordsNoOffset(ped, c.x, c.y, c.z, false, false, false)
        SetEntityHeading(ped, c.w or 0.0)
        FreezeEntityPosition(ped, true)
        if pedConfig.scenario and pedConfig.scenario ~= '' then
            TaskStartScenarioInPlace(ped, pedConfig.scenario, 0, true)
        end
    end)

    if pedConfig.invincible ~= false then SetEntityInvincible(ped, true) end
    SetBlockingOfNonTemporaryEvents(ped, pedConfig.blockEvents ~= false)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetModelAsNoLongerNeeded(hash)
    shop._ped = ped
    shop._clerkName = dealer.npcName or shop.label
end

local function ensureShopPedVisible(shop)
    if not shop._ped or not DoesEntityExist(shop._ped) then
        spawnShopPed(shop)
        return
    end
    SetEntityVisible(shop._ped, true, false)
    SetEntityAlpha(shop._ped, 255, false)
    FreezeEntityPosition(shop._ped, true)
    SetBlockingOfNonTemporaryEvents(shop._ped, true)
end

local function randomFrom(list, fallback)
    if type(list) ~= 'table' or #list == 0 then return fallback end
    return list[math.random(1, #list)] or fallback
end

local function playShopVoice(shop, kind)
    local pedConfig = Config.Ped or {}
    if pedConfig.voiceEnabled == false then return end
    if not shop._ped or not DoesEntityExist(shop._ped) then return end
    local voices = kind == 'farewell' and pedConfig.farewellVoices or pedConfig.greetingVoices
    local speech = randomFrom(voices, kind == 'farewell' and 'GENERIC_BYE' or 'GENERIC_HI')
    pcall(function()
        StopCurrentPlayingAmbientSpeech(shop._ped)
        PlayPedAmbientSpeechNative(shop._ped, speech, 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR')
    end)
end

local function setShopSpeech(shop, text, duration)
    local pedConfig = Config.Ped or {}
    shop._speechText = text or ''
    shop._speechUntil = GetGameTimer() + (tonumber(duration or pedConfig.speechDuration) or 5000)
end

local function clearShopSpeech(shop)
    shop._speechText = nil
    shop._speechUntil = 0
end

local function playShopGreetingIfNeeded(shop)
    local pedConfig = Config.Ped or {}
    local now = GetGameTimer()
    if now < (shop._nextGreetingAt or 0) then return end
    -- Voice greeting only by default. Text bubble is shown only if explicitly enabled.
    if pedConfig.showGreeting == true then
        setShopSpeech(shop, randomFrom(pedConfig.greetings, 'Welcome to the showroom.'), pedConfig.speechDuration)
    else
        clearShopSpeech(shop)
    end
    playShopVoice(shop, 'greeting')
    shop._nextGreetingAt = now + (tonumber(pedConfig.speechCooldown) or 15000)
end

local function playShopFarewell(shop)
    if not shop then return end
    local pedConfig = Config.Ped or {}
    if pedConfig.showGreeting == true then
        setShopSpeech(shop, randomFrom(pedConfig.farewells, 'See you around.'), pedConfig.speechDuration)
    else
        clearShopSpeech(shop)
    end
    playShopVoice(shop, 'farewell')
end

local function addShopBlip(blipCfg, coords)
    if not blipCfg or blipCfg.showBlip == false then return end
    local pos = coords or (Config.Location and vector3(Config.Location.x, Config.Location.y, Config.Location.z))
    if not pos then return end
    local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
    SetBlipSprite(blip, blipCfg.id)
    SetBlipColour(blip, blipCfg.color)
    SetBlipScale(blip, blipCfg.scale)
    SetBlipDisplay(blip, 4)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(blipCfg.label)
    EndTextCommandSetBlipName(blip)
end

local function whenStarted()
    local pedEnabled = not (Config.Ped and Config.Ped.enabled == false)
    for _, shop in ipairs(dealerShops) do
        local dealer = shopDealer(shop)
        addShopBlip(Config[shop.blipKey], dealer.coords)
        if pedEnabled then spawnShopPed(shop) end
    end
    pedSpawned = pedEnabled
end


local function resetVehicleToDefaultStock(vehicle, keepColor, model)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    -- Keep dealership previews and test-drive cars stock/default.
    -- This is intentionally idempotent and runs several times because many
    -- add-on vehicles apply modkits / liveries after CreateVehicle returns.
    pcall(function() SetVehicleModKit(vehicle, 0) end)

    -- Slot 48 is the mod-livery slot on many vehicles. Clear it before handling
    -- native liveries so add-on packs cannot re-apply a decal layer.
    pcall(function() SetVehicleMod(vehicle, 48, -1, false) end)
    pcall(function() RemoveVehicleMod(vehicle, 48) end)

    -- Remove all tuning mods.
    for modType = 0, 49 do
        if modType ~= 48 then
            pcall(function() SetVehicleMod(vehicle, modType, -1, false) end)
            pcall(function() RemoveVehicleMod(vehicle, modType) end)
        end
    end

    -- Disable toggle upgrades and visual effects.
    for _, toggleMod in ipairs({ 18, 20, 22 }) do
        pcall(function() ToggleVehicleMod(vehicle, toggleMod, false) end)
    end
    for i = 0, 3 do
        pcall(function() SetVehicleNeonLightEnabled(vehicle, i, false) end)
    end

    -- Native livery handling:
    -- Base GTA vehicles usually use -1 for "no livery"; many custom addon cars
    -- use livery index 0 as the plain / unpainted template and randomize when -1.
    pcall(function()
        local liveryCount = tonumber(GetVehicleLiveryCount(vehicle)) or -1
        if liveryCount > 0 then
            SetVehicleLivery(vehicle, 0)
        else
            SetVehicleLivery(vehicle, -1)
        end
    end)

    -- Re-clear slot 48 after native livery because some modkits re-enable it.
    pcall(function() SetVehicleMod(vehicle, 48, -1, false) end)
    pcall(function() RemoveVehicleMod(vehicle, 48) end)

    -- Do not globally disable extras. Add-on vehicles often use extras for essential
    -- body panels. Only Config.VehicleDefaults[model].extras is applied below.

    pcall(function() SetVehicleWindowTint(vehicle, 0) end)
    pcall(function() SetVehicleWheelType(vehicle, 0) end)
    pcall(function() SetVehicleTyresCanBurst(vehicle, true) end)
    pcall(function() SetVehicleXenonLightsColor(vehicle, 255) end)
    pcall(function() SetVehicleTyreSmokeColor(vehicle, 255, 255, 255) end)
    pcall(function() SetVehicleExtraColours(vehicle, 0, 0) end)
    pcall(function() SetVehicleDirtLevel(vehicle, 0.0) end)

    if keepColor ~= true then
        pcall(function() ClearVehicleCustomPrimaryColour(vehicle) end)
        pcall(function() ClearVehicleCustomSecondaryColour(vehicle) end)
        pcall(function() SetVehicleColours(vehicle, 111, 111) end)
        pcall(function() SetVehicleCustomPrimaryColour(vehicle, 255, 255, 255) end)
        pcall(function() SetVehicleCustomSecondaryColour(vehicle, 255, 255, 255) end)
    end
    applyConfiguredVehicleDefaults(vehicle, model)
end

local function forceStockAppearancePasses(vehicle, keepColor, makeVisibleAfter, model)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    -- Cancel older delayed passes for the current showroom preview. This prevents a
    -- previous cleanup from overwriting a colour the player just chose.
    appearanceCleanupToken = appearanceCleanupToken + 1
    local token = appearanceCleanupToken

    -- First pass now, then absolute-timed delayed passes. High-poly add-on
    -- streams can apply modkits / texture dictionaries after 1 second, so this
    -- catches late-loading liveries without blocking the client thread.
    resetVehicleToDefaultStock(vehicle, keepColor, model)

    CreateThread(function()
        local delays = { 0, 75, 175, 350, 700, 1000, 1500, 2000 }
        local lastDelay = 0
        local madeVisible = false

        for index, delay in ipairs(delays) do
            Wait(math.max(0, delay - lastDelay))
            lastDelay = delay

            if token ~= appearanceCleanupToken then return end
            if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

            resetVehicleToDefaultStock(vehicle, keepColor, model)

            -- Keep the car hidden through the early modkit/livery reset frames so
            -- players do not see the "random colour/livery then white" flicker.
            if makeVisibleAfter == true and not madeVisible and delay >= 350 then
                SetEntityAlpha(vehicle, 255, false)
                SetEntityVisible(vehicle, true, false)
                madeVisible = true
            end
        end

        if token ~= appearanceCleanupToken then return end
        if makeVisibleAfter == true and not madeVisible and vehicle and DoesEntityExist(vehicle) then
            SetEntityAlpha(vehicle, 255, false)
            SetEntityVisible(vehicle, true, false)
        end
    end)
end

function ResetVehicleShopVehicleToDefaultStock(vehicle, keepColor, model)
    resetVehicleToDefaultStock(vehicle, keepColor == true, model)
end

function ForceVehicleShopStockAppearancePasses(vehicle, keepColor, makeVisibleAfter, model)
    forceStockAppearancePasses(vehicle, keepColor == true, makeVisibleAfter == true, model)
end

local function settleVehicleOnGround(vehicle, x, y, z, heading, freezeAfter, collisionAfter)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    x = tonumber(x) or 0.0
    y = tonumber(y) or 0.0
    z = tonumber(z) or 0.0
    heading = tonumber(heading) or 0.0

    -- SetVehicleOnGroundProperly works best when collision is enabled and the
    -- entity is not frozen. This fixes the preview/test-drive car floating above
    -- the floor after returning from a test drive.
    FreezeEntityPosition(vehicle, false)
    SetEntityCollision(vehicle, true, true)
    SetEntityHeading(vehicle, heading)
    SetEntityCoordsNoOffset(vehicle, x, y, z + 0.75, false, false, false)

    local deadline = GetGameTimer() + 2200
    while GetGameTimer() < deadline do
        RequestCollisionAtCoord(x, y, z)
        pcall(function() SetVehicleOnGroundProperly(vehicle) end)
        if HasCollisionLoadedAroundEntity(vehicle) then break end
        Wait(0)
    end

    -- One more short settle pass after collision is available.
    for _ = 1, 8 do
        pcall(function() SetVehicleOnGroundProperly(vehicle) end)
        Wait(0)
    end

    -- Fallback: if native ground data is available, nudge near it then let the
    -- native place the wheels again. The 0.08 lift avoids clipping into the floor.
    local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, z + 8.0, false)
    if foundGround and math.abs((tonumber(groundZ) or z) - z) < 6.0 then
        SetEntityCoordsNoOffset(vehicle, x, y, groundZ + 0.08, false, false, false)
        for _ = 1, 4 do
            pcall(function() SetVehicleOnGroundProperly(vehicle) end)
            Wait(0)
        end
    end

    SetEntityHeading(vehicle, heading)
    FreezeEntityPosition(vehicle, freezeAfter == true)
    SetEntityCollision(vehicle, collisionAfter == true, collisionAfter == true)
end

local function deletePreviewVehicle()
    appearanceCleanupToken = appearanceCleanupToken + 1
    if newVehicle and DoesEntityExist(newVehicle) then DeleteEntity(newVehicle) end
    newVehicle = nil
    spawnVehicle = false
    if SetCapturedPreviewVehicle then SetCapturedPreviewVehicle(nil) end
end

-- Base-game model used as a temporary stand-in when a requested preview model
-- cannot be streamed (not in CD image, not a vehicle, or its files never load).
local PREVIEW_FALLBACK_MODEL = 'komoda'
local PREVIEW_FALLBACK_NOTICE = 'This vehicle model is temporarily unavailable. Showing a Komoda until it can be streamed.'

-- Spawn (or respawn) the showroom preview vehicle for a model. Returns the hash
-- on success so callers can push stats. Shared by the NUI spawn callback and the
-- admin image-capture flow.
--
-- When `allowFallback` is true (default) and the requested model cannot be
-- streamed, a base-game Komoda is spawned as a temporary stand-in and a notice
-- is shown. Image capture passes false so the photo studio never photographs
-- the stand-in instead of the real car.
local function spawnPreviewVehicle(model, allowFallback)
    model = tostring(model or '')
    if model == '' then return nil end
    deletePreviewVehicle()
    local hash = loadVehicleModel(model)
    local spawnModel = model
    local usingFallback = false
    if not hash then
        if allowFallback == false or tostring(model):lower():gsub('%s+', '') == PREVIEW_FALLBACK_MODEL then
            notify(('Invalid or unavailable vehicle model: %s'):format(model), 'error')
            return nil
        end
        hash = loadVehicleModel(PREVIEW_FALLBACK_MODEL)
        if not hash then
            notify(('Invalid or unavailable vehicle model: %s'):format(model), 'error')
            return nil
        end
        spawnModel = PREVIEW_FALLBACK_MODEL
        usingFallback = true
    end
    local studio = getPreviewStudio(previewMode)
    local c = studio.vehicle or vector4(Config.Location.x + 5.0, Config.Location.y + 5.0, Config.Location.z, 0.0)
    newVehicle = CreateVehicle(hash, c.x, c.y, c.z + 0.75, c.w or 0.0, false, false)
    SetEntityAsMissionEntity(newVehicle, true, true)

    -- Hide while the car is being reset/settled so players do not see random
    -- spawn colour, tuning or livery for a split second.
    SetEntityAlpha(newVehicle, 0, false)
    SetEntityVisible(newVehicle, false, false)

    if previewMode == 'boat' then
        -- Boats spawn on water: place at the configured water coords and skip
        -- ground-settling (GetGroundZFor_3dCoord would pull it to the sea floor).
        SetEntityCoordsNoOffset(newVehicle, c.x, c.y, c.z + 0.2, false, false, false)
        SetEntityHeading(newVehicle, c.w or 0.0)
    else
        settleVehicleOnGround(newVehicle, c.x, c.y, c.z, c.w or 0.0, true, false)
    end
    forceStockAppearancePasses(newVehicle, false, true, spawnModel)
    SetModelAsNoLongerNeeded(hash)
    spawnVehicle = true
    if SetCapturedPreviewVehicle then SetCapturedPreviewVehicle(newVehicle) end
    if usingFallback then notify(PREVIEW_FALLBACK_NOTICE, 'info') end
    return hash
end

local function sendPreviewStats(hash)
    if not hash or not newVehicle or not DoesEntityExist(newVehicle) then return end
    local vehicleInfo = {
        speed = string.format('%.0f', GetVehicleMaxSpeed(newVehicle) * 3.6),
        acceleration = string.format('%.1f', GetVehicleModelAcceleration(hash) * 10),
        braking = string.format('%.1f', GetVehicleModelMaxBraking(hash) * 10),
        traction = string.format('%.1f', GetVehicleModelMaxTraction(hash) * 10)
    }
    SendNUIMessage({ action = 'updateInfo', vehicleInfo = vehicleInfo })
end

local function firstShopModel(groups)
    if type(groups) ~= 'table' then return nil end
    for _, group in ipairs(groups) do
        if type(group) == 'table' and type(group.buttons) == 'table' then
            for _, vehicle in ipairs(group.buttons) do
                if type(vehicle) == 'table' and vehicle.model and tostring(vehicle.model) ~= '' then
                    return tostring(vehicle.model)
                end
            end
        end
    end
    return nil
end

local function changeCam(mode)
    mode = mode or 'store'
    if mode == 'admin' then
        setVehicleAdminClimatePaused(true)
    elseif vehicleAdminClimatePauseRequested then
        setVehicleAdminClimatePaused(false)
    end
    previewMode = mode
    DoScreenFadeOut(500)
    Wait(700)
    inShop = true
    local hudReason = mode == 'admin' and 'vehicle_admin' or 'vehicle_store'
    if shouldHideHudForMode(mode) then
        beginHudStoreLock(hudReason)
        forceHideHud(hudReason, 4500)
    else
        endHudStoreLock()
        forceRestoreHud(hudReason .. '_hud_allowed', 1500)
    end
    setShopState(true, mode)
    uiHideInteract()
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

    applyStudioEnvironment(mode, true)

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
    openRequestPending = false
    SetNuiFocus(false, false)
    -- Fire leaveShop early so the server restores routing bucket 0 BEFORE forceRestoreHud
    -- runs its ticks. Any cm-playerdata unload/reload triggered by the bucket change will
    -- have settled by the time we reassert HUD visibility below.
    TriggerServerEvent('rn-vehicleshop:server:leaveShop')
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
    -- Match nv_cloth behaviour: return the player to the exact place they pressed E / opened admin.
    -- Config.ReturnToOriginalPosition can be set false to fall back to Config.ExitLocation.
    local preferOriginal = Config.ReturnToOriginalPosition ~= false
    local e = (preferOriginal and returnCoords) or Config.ExitLocation or returnCoords or vector4(Config.Location.x, Config.Location.y, Config.Location.z, 0.0)
    safeTeleport(e.x, e.y, e.z, e.w or 0.0)
    returnCoords = nil
    TriggerEvent('change:time', false)
    restoreWorldEnvironment()
    setVehicleAdminClimatePaused(false)
    RenderScriptCams(false, false, 1, true, true)
    if cam and DoesCamExist(cam) then DestroyCam(cam, true) end
    cam = nil
    interactionSuppressUntil = GetGameTimer() + 900
    inShop = false
    previewMode = 'store'
    setShopState(false)
    endHudStoreLock()
    forceRestoreHud('vehicle_shop_closed')
    pcall(function() DisplayHud(true) end)
    pcall(function() DisplayRadar(true) end)
    SendNUIMessage({ action = 'closeAdmin' })
    DoScreenFadeIn(500)
    -- Late restore: fires after the screen is visible and any routing-bucket-driven
    -- playerdata events have had time to settle (leaveShop was sent at the top).
    CreateThread(function()
        Wait(1200)
        if not inShop then
            TriggerEvent('cm-hud:client:showAfterUi')
        end
    end)
    if purchaseNotifyAfterExit then
        local msg = purchaseNotifyAfterExit
        purchaseNotifyAfterExit = nil
        SetTimeout(450, function() notify(msg, 'success') end)
    end
end

local function closeVehicleShop()
    closeShopBase()
end

local function closeVehicleShopAfterBuy(message)
    purchaseNotifyAfterExit = message or 'Vehicle purchased and stored.'
    closeShopBase()
end

local function deleteTestDriveVehicle()
    if testDriveVehicle and DoesEntityExist(testDriveVehicle) then
        local ped = PlayerPedId()

        -- Never delete a vehicle while the local player is still seated in it.
        -- FiveM/GTA can leave a ghost entity if the occupied vehicle is deleted.
        if ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) == testDriveVehicle then
            ClearPedTasksImmediately(ped)
            Wait(0)
            if GetVehiclePedIsIn(ped, false) == testDriveVehicle then
                TaskLeaveVehicle(ped, testDriveVehicle, 16)
                Wait(250)
                ClearPedTasksImmediately(ped)
                Wait(0)
            end
        end

        SetEntityAsMissionEntity(testDriveVehicle, true, true)
        DeleteVehicle(testDriveVehicle)
        Wait(0)
        if DoesEntityExist(testDriveVehicle) then DeleteEntity(testDriveVehicle) end
    end
    testDriveVehicle = nil
    testDriveHudTransition = false
    pcall(function() LocalPlayer.state:set('cmVehicleShopTestDrive', false, true) end)
    pcall(function() LocalPlayer.state:set('cmTestDrivePlate', false, true) end)
end

local function returnFromTestDrive(reason)
    if not testDriveActive then return end
    testDriveActive = false
    testDriveHudTransition = false
    setTestDriveProtection(false)
    local startFailureReported = false
    if shouldRefundTestDriveCharge(reason) then
        reportTestDriveStartFailed(reason)
        startFailureReported = true
    else
        testDriveChargeToken = nil
    end
    SendNUIMessage({ action = 'hideTimer' })
    DoScreenFadeOut(450)
    Wait(650)

    local ped = PlayerPedId()
    if ped and ped ~= 0 then
        -- Unseat before deleting the test vehicle to avoid abandoned ghost cars.
        ClearPedTasksImmediately(ped)
        if testDriveVehicle and DoesEntityExist(testDriveVehicle) and GetVehiclePedIsIn(ped, false) == testDriveVehicle then
            TaskLeaveVehicle(ped, testDriveVehicle, 16)
            Wait(250)
            ClearPedTasksImmediately(ped)
        end
        Wait(0)
    end
    deleteTestDriveVehicle()

    SetEntityVisible(ped, false, false)
    SetLocalPlayerInvisibleLocally(true)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)
    local returnMode = testDriveReturnMode
    if not startFailureReported then
        TriggerServerEvent('rn-vehicleshop:server:testDriveEnded', reason or 'finished', returnMode, testDriveSessionToken)
    end
    testDriveSessionToken = nil
    if returnMode == 'admin' then
        changeCam('admin')
        if lastPreviewDetails and lastPreviewDetails.model then spawnPreviewVehicle(lastPreviewDetails.model) end
        SendNUIMessage({ action = 'adminReturned', details = lastPreviewDetails or {}, reason = reason or 'finished' })
    else
        changeCam(returnMode)
        if lastPreviewDetails and lastPreviewDetails.model then
            spawnPreviewVehicle(lastPreviewDetails.model)
            SendNUIMessage({ action = 'testDriveReturned', details = lastPreviewDetails, reason = reason or 'finished' })
        else
            local payload = lastShopPayload or {}
            SendNUIMessage({ action = 'open', vehicles = payload.vehicles or {}, buttons = {}, daily = payload.daily or {}, balance = payload.daily and payload.daily.balance or nil, colors = Config.Colors, buyer = payload.buyer or 'Customer', testDrive = Config.TestDrive })
        end
    end
    testDriveReturnMode = 'store'
    SetNuiFocus(true, true)
    DoScreenFadeIn(500)
end


RegisterNetEvent('rn-vehicleshop:target', function(shopType)
    if inShop or openRequestPending then return end
    shopType = shopType or (activeDealerShop and activeDealerShop.type) or 'store'
    openRequestPending = true
    uiHideInteract()
    SendNUIMessage({ action = 'undraw' })
    SendNUIMessage({ action = 'dealerDialog', close = true })
    interactionSuppressUntil = GetGameTimer() + 2500
    -- Ask the server first while the player is still beside the dealer.
    TriggerServerEvent('rn-vehicleshop:server:openUI', shopType)
    CreateThread(function()
        Wait(5000)
        if openRequestPending and not inShop then
            openRequestPending = false
            dealerDialogOpen = false
            SetNuiFocus(false, false)
            forceRestoreHud('vehicle_shop_open_failed')
            interactionSuppressUntil = GetGameTimer() + 400
            SendNUIMessage({ action = 'forceClose' })
        end
    end)
end)


RegisterNetEvent('rn-vehicleshop:client:openFailed', function(message)
    openRequestPending = false
    dealerDialogOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'forceClose' })
    forceRestoreHud('vehicle_shop_open_failed')
    interactionSuppressUntil = GetGameTimer() + 400
    if message and message ~= '' then notify(message, 'error') end
end)

RegisterNetEvent('vehicles:client:openUI', function(vehicles, daily, buyer, shopType)
    shopType = shopType or 'store'
    openRequestPending = false
    dealerDialogOpen = false
    lastShopPayload = { vehicles = vehicles or {}, daily = daily or {}, buyer = buyer or 'Customer' }
    if inShop then return end
    uiHideInteract()
    SendNUIMessage({ action = 'dealerDialog', close = true })
    changeCam(shopType)
    TriggerEvent('change:time', true)
    SetNuiFocus(true, true)
    beginHudStoreLock('vehicle_store')
    SendNUIMessage({
        action = 'open',
        vehicles = lastShopPayload.vehicles or {},
        buttons = {},
        daily = lastShopPayload.daily or {},
        balance = (lastShopPayload.daily and lastShopPayload.daily.balance) or nil,
        colors = Config.Colors,
        buyer = lastShopPayload.buyer or 'Customer',
        testDrive = Config.TestDrive
    })

    -- Fallback: always spawn the first catalog vehicle from Lua too. This keeps
    -- the showroom from being empty if the NUI selection event is delayed or blocked.
    local firstModel = firstShopModel(lastShopPayload.vehicles or {})
    if firstModel and firstModel ~= '' then
        CreateThread(function()
            Wait(350)
            if inShop and not (newVehicle and DoesEntityExist(newVehicle)) then
                local hash = spawnPreviewVehicle(firstModel)
                sendPreviewStats(hash)
            end
        end)
    end
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

    sendPreviewStats(hash)
    cb('ok')
end)

RegisterNUICallback('selectVehicle', function(data, cb)
    if not loadVeh then cb('busy') return end
    data = type(data) == 'table' and data or {}
    local model = tostring(data.model or '')
    if model == '' then cb('bad_model') return end
    loadVeh = false
    local hash = spawnPreviewVehicle(model)
    if not hash then loadVeh = true cb('bad_model') return end
    loadVeh = true
    sendPreviewStats(hash)
    cb('ok')
end)

-- Admin image capture: spawn the requested model in the showroom if the admin has
-- not already previewed it, so capture.lua has a live car to photograph.
RegisterNetEvent('rn-vehicleshop:client:spawnPreviewForCapture', function(model)
    -- Capture must photograph the real model, never the Komoda stand-in.
    spawnPreviewVehicle(model, false)
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

RegisterNetEvent('rn-vehicleshop:client:balanceUpdate', function(balance, reason)
    SendNUIMessage({ action = 'balanceUpdate', balance = balance or { cash = 0, bank = 0 }, reason = reason or 'update' })
end)

RegisterNetEvent('rn-vehicleshop:client:testDriveResult', function(success, code, message, extra)
    SendNUIMessage({ action = 'testDriveResult', success = success == true, code = code, message = message, extra = extra or {} })
end)

local function getTestDriveSpawn(vehicleType)
    vehicleType = tostring(vehicleType or ''):lower()
    if vehicleType == 'boat' and Config.BoatTestVehicleSpawnLocation then
        return Config.BoatTestVehicleSpawnLocation
    end
    if vehicleType == 'air' and Config.AirTestVehicleSpawnLocation then
        return Config.AirTestVehicleSpawnLocation
    end
    return Config.TestVehicleSpawnLocation
end

RegisterNetEvent('rn-vehicleshop:client:startTestDrive', function(vehDetails, timer, chargeToken, returnMode)
    vehDetails = type(vehDetails) == 'table' and vehDetails or {}
    if returnMode == 'admin' or returnMode == 'boat' or returnMode == 'air' then
        testDriveReturnMode = returnMode
    else
        testDriveReturnMode = 'store'
    end
    testDriveChargeToken = chargeToken
    testDriveSessionToken = chargeToken
    local model = tostring(vehDetails.model or ''):lower():gsub('%s+', '')
    if model == '' then
        testDriveActive = true
        returnFromTestDrive('invalid_model')
        notify('Invalid test-drive vehicle.', 'error')
        return
    end

    lastPreviewDetails = vehDetails
    local duration = math.floor(tonumber(timer) or (Config.TestDrive and Config.TestDrive.testDriveTimer) or 300)
    if duration < 10 then duration = 10 end

    -- The server controls the duration, but the client also protects the
    -- player during the transition so a test drive cannot begin in a lethal
    -- state while the showroom camera/teleport is being cleared.
    setTestDriveProtection(true)

    -- Test drive is a sub-mode of the shop. First switch HUD/session state to
    -- visible test-drive mode, then close NUI focus/camera. This order prevents
    -- a stale store/admin hide assertion from blinking the HUD during transition.
    enterTestDriveHudMode((duration * 1000) + 5000)
    setShopState(true, 'test_drive')
    SendNUIMessage({ action = 'testdriver', duration = duration })
    SetNuiFocus(false, false)
    deletePreviewVehicle()

    DoScreenFadeOut(350)
    Wait(450)
    RenderScriptCams(false, false, 1, true, true)
    if cam and DoesCamExist(cam) then DestroyCam(cam, false) end
    cam = nil

    if vehicleAdminClimatePauseRequested then
        restoreWorldEnvironment()
        setVehicleAdminClimatePaused(false)
    end

    local modelHash = loadVehicleModel(model)
    if not modelHash then
        notify('Could not load test vehicle.', 'error')
        testDriveActive = true
        returnFromTestDrive('load_failed')
        return
    end

    local vehicleType = tostring(vehDetails.vehicleType or ''):lower()
    local spawn = getTestDriveSpawn(vehicleType)
    if not spawn or not spawn.coords then
        notify('Test-drive spawn is not configured.', 'error')
        SetModelAsNoLongerNeeded(modelHash)
        testDriveActive = true
        returnFromTestDrive('missing_spawn')
        return
    end

    local coords = spawn.coords
    local heading = tonumber(spawn.heading) or 0.0
    local ped = PlayerPedId()

    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetLocalPlayerInvisibleLocally(false)
    SetEntityCollision(ped, true, true)
    safeTeleport(coords.x, coords.y, coords.z, heading)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    ClearAreaOfVehicles(coords.x, coords.y, coords.z, 8.0, false, false, false, false, false)
    Wait(250)

    -- IMPORTANT: local-only vehicle. Networked test-drive entities inside private
    -- OneSync buckets can be removed by server ownership cleanup before the client
    -- is warped in. Local mission entities are enough because only this player sees
    -- and drives the test car.
    testDriveVehicle = CreateVehicle(modelHash, coords.x, coords.y, coords.z, heading, false, false)
    if not testDriveVehicle or testDriveVehicle == 0 or not DoesEntityExist(testDriveVehicle) then
        SetModelAsNoLongerNeeded(modelHash)
        notify('Test drive vehicle could not spawn.', 'error')
        testDriveActive = true
        returnFromTestDrive('spawn_failed')
        return
    end

    SetEntityAsMissionEntity(testDriveVehicle, true, true)
    SetEntityVisible(testDriveVehicle, true, false)
    SetEntityCollision(testDriveVehicle, true, true)
    SetEntityHeading(testDriveVehicle, heading)
    if vehicleType ~= 'boat' then
        settleVehicleOnGround(testDriveVehicle, coords.x, coords.y, coords.z, heading, false, true)
    end
    resetVehicleToDefaultStock(testDriveVehicle, false, model)

    local testPlate = ('TEST%04d'):format(GetPlayerServerId(PlayerId()) % 10000)
    -- Keep the temporary identity private for key/cleanup compatibility; never
    -- show a TEST/CM plate to the player.
    SetVehicleNumberPlateText(testDriveVehicle, '        ')
    SetVehicleHasBeenOwnedByPlayer(testDriveVehicle, true)
    SetVehicleDoorsLocked(testDriveVehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(testDriveVehicle, false)
    SetVehicleDoorsLockedForPlayer(testDriveVehicle, PlayerId(), false)
    SetVehicleNeedsToBeHotwired(testDriveVehicle, false)
    SetVehicleEngineOn(testDriveVehicle, true, true, false)
    SetVehicleUndriveable(testDriveVehicle, false)
    SetVehicleDirtLevel(testDriveVehicle, 0.0)
    SetVehicleFuelLevel(testDriveVehicle, 100.0)

    -- Local state/events for key/ownership resources that support temporary keys.
    -- No NetworkGetNetworkIdFromEntity call is used here because this vehicle is local.
    pcall(function() Entity(testDriveVehicle).state:set('cmVehicleShopTestDrive', true, false) end)
    pcall(function() Entity(testDriveVehicle).state:set('cm_testdrive', true, false) end)
    pcall(function() Entity(testDriveVehicle).state:set('vehicleShopTestDrive', true, false) end)
    pcall(function() Entity(testDriveVehicle).state:set('temporaryKeys', true, false) end)
    pcall(function() Entity(testDriveVehicle).state:set('testDrivePlate', testPlate, false) end)
    pcall(function() LocalPlayer.state:set('cmVehicleShopTestDrive', true, true) end)
    pcall(function() LocalPlayer.state:set('cmTestDrivePlate', testPlate, true) end)

    for _, eventName in ipairs({
        'cm-vehicles:client:GiveKeys',
        'cm-vehicles:client:giveKeys',
        'cm_vehicle:client:GiveKeys',
        'cm_vehicle:client:giveKeys',
        'vehiclekeys:client:SetOwner'
    }) do
        pcall(function() TriggerEvent(eventName, testPlate, testDriveVehicle) end)
        pcall(function() TriggerEvent(eventName, testPlate) end)
        pcall(function() TriggerEvent(eventName, testDriveVehicle) end)
    end

    local gtaColor = clampInt(vehDetails.gtaColor, 0, 160, 111)
    local r = clampInt(vehDetails.r, 0, 255, 255)
    local g = clampInt(vehDetails.g, 0, 255, 255)
    local b = clampInt(vehDetails.b, 0, 255, 255)
    SetVehicleColours(testDriveVehicle, gtaColor, gtaColor)
    SetVehicleCustomPrimaryColour(testDriveVehicle, r, g, b)
    SetVehicleCustomSecondaryColour(testDriveVehicle, r, g, b)
    forceStockAppearancePasses(testDriveVehicle, true, false, model)

    local warpUntil = GetGameTimer() + 3500
    repeat
        SetPedIntoVehicle(ped, testDriveVehicle, -1)
        Wait(50)
    until GetVehiclePedIsIn(ped, false) == testDriveVehicle or GetGameTimer() > warpUntil

    if GetVehiclePedIsIn(ped, false) ~= testDriveVehicle then
        ClearPedTasksImmediately(ped)
        SetPedIntoVehicle(ped, testDriveVehicle, -1)
        Wait(150)
    end

    SetModelAsNoLongerNeeded(modelHash)
    TriggerServerEvent('rn-vehicleshop:server:testDriveStarted', testDriveChargeToken)
    testDriveChargeToken = nil
    testDriveActive = true
    local startedAt = GetGameTimer()
    local endAt = startedAt + (duration * 1000)
    DoScreenFadeIn(500)
    SendNUIMessage({ action = 'testDriveTick', remaining = duration, duration = duration })

    CreateThread(function()
        local nextHudAssert = 0
        while testDriveActive do
            Wait(0)
            local now = GetGameTimer()
            reassertTestDriveProtection()
            if now >= nextHudAssert then
                nextHudAssert = now + 1000
                -- Keep native HUD/radar visible while driving, but do not force cm-hud/NUI
                -- show events every second. Re-forcing those events restarts HUD animations.
                setHudVisible(true, 'test_drive_loop', false)
                setNativeHudVisible(true, false)
                SendNUIMessage({
                    action = 'testDriveTick',
                    remaining = math.max(0, math.ceil((endAt - now) / 1000)),
                    duration = duration
                })
            end
            DisableControlAction(0, 75, true) -- F returns early after grace period.

            local playerPed = PlayerPedId()
            if IsEntityDead(playerPed) or IsPlayerDead(PlayerId()) then
                -- Invincibility should prevent this, but recover locally if a
                -- game/native edge case marks the ped dead during the trial.
                local recovery = GetEntityCoords(playerPed)
                NetworkResurrectLocalPlayer(recovery.x, recovery.y, recovery.z, GetEntityHeading(playerPed), true, false)
                ClearPedTasksImmediately(playerPed)
                SetEntityHealth(playerPed, 200)
                reassertTestDriveProtection()
            end

            if testDriveVehicle and DoesEntityExist(testDriveVehicle) then
                SetVehicleEngineOn(testDriveVehicle, true, true, false)
                SetVehicleUndriveable(testDriveVehicle, false)
                SetVehicleNeedsToBeHotwired(testDriveVehicle, false)
                SetVehicleDoorsLocked(testDriveVehicle, 1)
                SetVehicleDoorsLockedForPlayer(testDriveVehicle, PlayerId(), false)
                if GetVehiclePedIsIn(playerPed, false) ~= testDriveVehicle and (now - startedAt) < 3500 then
                    SetPedIntoVehicle(playerPed, testDriveVehicle, -1)
                end
            elseif (now - startedAt) > 6000 then
                returnFromTestDrive('vehicle_missing')
                break
            end

            if (now - startedAt) > 2500 and IsDisabledControlJustPressed(0, 75) then
                returnFromTestDrive('manual')
                break
            end
            if now >= endAt then
                returnFromTestDrive('timer')
                break
            end
        end
    end)
end)

RegisterNUICallback('changeColor', function(data, cb)
    data = type(data) == 'table' and data or {}
    if newVehicle and DoesEntityExist(newVehicle) then
        local r = tonumber(data.colorR) or 255
        local g = tonumber(data.colorG) or 255
        local b = tonumber(data.colorB) or 255
        forceStockAppearancePasses(newVehicle, true, false, lastPreviewDetails and lastPreviewDetails.model)
        SetVehicleCustomPrimaryColour(newVehicle, r, g, b)
        SetVehicleCustomSecondaryColour(newVehicle, r, g, b)
        CreateThread(function()
            Wait(250)
            if newVehicle and DoesEntityExist(newVehicle) then
                SetVehicleCustomPrimaryColour(newVehicle, r, g, b)
                SetVehicleCustomSecondaryColour(newVehicle, r, g, b)
            end
        end)
    end
    cb('ok')
end)

RegisterNUICallback('changePos', function(data, cb)
    data = type(data) == 'table' and data or {}
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

local activeAdminMode = 'manage'

RegisterNetEvent('rn-vehicleshop:client:requestAdmin', function(mode)
    activeAdminMode = mode == 'capture' and 'capture' or 'manage'
    TriggerServerEvent('rn-vehicleshop:server:openAdmin', activeAdminMode)
end)

local vehicleClassLabels = {
    [0] = 'Compacts', [1] = 'Sedans', [2] = 'SUV', [3] = 'Coupes', [4] = 'Muscle',
    [5] = 'Sports Classics', [6] = 'Sports', [7] = 'Super', [8] = 'Motorcycles',
    [9] = 'Off Road', [10] = 'Industrial', [11] = 'Utility', [12] = 'Vans',
    [13] = 'Bicycles', [14] = 'Boats', [15] = 'Helicopters', [16] = 'Planes',
    [17] = 'Service', [18] = 'Emergency', [19] = 'Military', [20] = 'Commercial', [21] = 'Rail'
}

local function enrichAdminSourceVehicles(sourceList)
    local out = {}
    for _, row in ipairs(type(sourceList) == 'table' and sourceList or {}) do
        if type(row) == 'table' then
            local model = tostring(row.model or ''):lower():gsub('%s+', '')
            local hash = model ~= '' and joaat(model) or 0
            row.clientValid = hash ~= 0 and IsModelInCdimage(hash) and IsModelAVehicle(hash)
            if row.clientValid and row.autoDiscovered == true then
                local displayCode = GetDisplayNameFromVehicleModel(hash)
                local translated = displayCode and GetLabelText(displayCode) or nil
                if translated and translated ~= '' and translated ~= 'NULL' and translated ~= 'CARNOTFOUND' then
                    row.label = translated
                elseif row.gameName and row.gameName ~= '' then
                    local gameTranslated = GetLabelText(tostring(row.gameName))
                    if gameTranslated and gameTranslated ~= '' and gameTranslated ~= 'NULL' then row.label = gameTranslated end
                end
                local classId = GetVehicleClassFromName(hash)
                if vehicleClassLabels[classId] then row.category = vehicleClassLabels[classId] end
            end
            out[#out + 1] = row
        end
    end
    return out
end

local runtimeModelsSent = false
local function sendRuntimeVehicleModels()
    if runtimeModelsSent or not Config.RuntimeCatalogSeed or Config.RuntimeCatalogSeed.enabled ~= true then return end
    runtimeModelsSent = true
    CreateThread(function()
        local models = GetAllVehicleModels()
        local batch = {}
        for _, model in ipairs(type(models) == 'table' and models or {}) do
            model = tostring(model or ''):lower()
            local hash = joaat(model)
            if model ~= '' and IsModelInCdimage(hash) and IsModelAVehicle(hash) then
                local code = GetDisplayNameFromVehicleModel(hash)
                local label = code and GetLabelText(code) or nil
                if not label or label == '' or label == 'NULL' or label == 'CARNOTFOUND' then label = model end
                batch[#batch + 1] = {
                    model = model, label = label, classId = GetVehicleClassFromName(hash),
                    speedKph = math.floor((GetVehicleModelEstimatedMaxSpeed(hash) or 0.0) * 3.6 + 0.5)
                }
                if #batch >= 150 then
                    TriggerServerEvent('rn-vehicleshop:server:runtimeVehicleModels', batch, false)
                    batch = {}
                    Wait(0)
                end
            end
        end
        TriggerServerEvent('rn-vehicleshop:server:runtimeVehicleModels', batch, true)
    end)
end

RegisterNetEvent('rn-vehicleshop:client:openAdmin', function(sourceList, catalog, discoveryInfo, mode)
    -- Put the admin into the showroom camera view so the Capture Image button
    -- always has a cleanly framed car against the backdrop, even when /vehicleadmin
    -- is run from elsewhere on the map.
    if not inShop or previewMode ~= 'admin' then changeCam('admin') end
    SetNuiFocus(true, true)
    beginHudStoreLock('vehicle_admin')
    activeAdminMode = mode == 'capture' and 'capture' or 'manage'
    SendNUIMessage({ action = 'adminOpen', sourceVehicles = enrichAdminSourceVehicles(sourceList), catalog = catalog or {}, discovery = discoveryInfo or {}, mode = activeAdminMode })
    sendRuntimeVehicleModels()
end)

RegisterNetEvent('rn-vehicleshop:client:adminData', function(sourceList, catalog, discoveryInfo)
    SendNUIMessage({ action = 'adminData', sourceVehicles = enrichAdminSourceVehicles(sourceList), catalog = catalog or {}, discovery = discoveryInfo or {} })
end)

-- Server told us this car must be photographed before it can be enabled.
-- The NUI will run a capture and then re-submit the save automatically.
RegisterNetEvent('rn-vehicleshop:client:adminNeedsImage', function(model, pendingSave)
    SendNUIMessage({ action = 'adminNeedsImage', model = model, pendingSave = pendingSave or {} })
end)

-- Shallow-merge a patch into the accumulated EMS mods table. `extras`/`mods`/
-- `neons` merge key-by-key instead of replacing the whole sub-table, so one
-- extra toggle does not wipe every other extra already chosen. Same approach
-- as cm-ems's fleet configurator (client/vehicles.lua mergeMods).
local function mergeAdminMods(base, patch)
    if type(patch) ~= 'table' then return base end
    for key, value in pairs(patch) do
        if (key == 'extras' or key == 'mods') and type(value) == 'table' then
            base[key] = base[key] or {}
            for k, v in pairs(value) do base[key][k] = v end
        elseif key == 'neons' and type(value) == 'table' then
            base.neons = base.neons or {}
            for i, v in pairs(value) do base.neons[i] = v end
        else
            base[key] = value
        end
    end
    return base
end

local function applyAdminPreviewMods()
    if not newVehicle or not DoesEntityExist(newVehicle) then return end
    pcall(function() exports['cm-vehicles']:ApplyVehicleMods(newVehicle, currentAdminMods) end)
end

-- How many liveries/wheel-visual-indices/body-part options THIS SPECIFIC
-- vehicle actually supports, so the NUI never offers an index GTA will just
-- ignore. Same live-introspection approach as cm-ems's configurator
-- (client/vehicles.lua introspectVehicle) and what cm-tuning's own shop does
-- instead of a static ceiling.
local ADMIN_MOD_SLOT_TYPES = {
    { type = 0,  key = 'spoiler' },     { type = 1,  key = 'frontBumper' },
    { type = 2,  key = 'rearBumper' },  { type = 3,  key = 'skirts' },
    { type = 4,  key = 'exhaust' },     { type = 5,  key = 'rollcage' },
    { type = 6,  key = 'grille' },      { type = 7,  key = 'hood' },
    { type = 8,  key = 'fender' },      { type = 10, key = 'roof' },
    { type = 14, key = 'horn' },        { type = 23, key = 'wheels' },
}

local function introspectAdminVehicle()
    local out = { liveries = 0, slots = {}, extras = {} }
    if not newVehicle or not DoesEntityExist(newVehicle) then return out end
    local ok, num = pcall(GetNumVehicleLiveries, newVehicle)
    out.liveries = (ok and tonumber(num)) or 0
    for _, entry in ipairs(ADMIN_MOD_SLOT_TYPES) do
        local sok, count = pcall(GetNumVehicleMods, newVehicle, entry.type)
        out.slots[entry.key] = { modType = entry.type, count = (sok and tonumber(count)) or 0 }
    end
    for id = 1, 14 do
        local eok, exists = pcall(DoesExtraExist, newVehicle, id)
        out.extras[tostring(id)] = eok and exists == true
    end
    return out
end

RegisterNUICallback('adminSaveVehicle', function(data, cb)
    data = type(data) == 'table' and data or {}
    data.mods = currentAdminMods
    data.vehicleType = GetVehicleShopVehicleType(newVehicle)
    TriggerServerEvent('rn-vehicleshop:server:saveAdminVehicle', data)
    cb({ accepted = true, pending = true, requestId = data.requestId })
end)

RegisterNUICallback('adminModPatch', function(data, cb)
    data = type(data) == 'table' and data or {}
    currentAdminMods = mergeAdminMods(currentAdminMods, data.patch)
    applyAdminPreviewMods()
    cb('ok')
end)

RegisterNUICallback('adminModIntrospect', function(_, cb)
    cb({ ok = true, introspect = introspectAdminVehicle() })
end)

RegisterNUICallback('adminPreviewVehicle', function(data, cb)
    data = type(data) == 'table' and data or {}
    local model = tostring(data.model or '')
    if model == '' then cb({ ok = true }); return end

    previewMode = 'admin'
    local requestedHash = joaat(model)
    local hash
    local reused = newVehicle and DoesEntityExist(newVehicle) and GetEntityModel(newVehicle) == requestedHash
    if reused then
        hash = requestedHash
    else
        hash = spawnPreviewVehicle(model)
        -- A different vehicle now exists (or none) -- do not carry the
        -- previous vehicle's EMS appearance over onto this one.
        currentAdminMods = {}
    end
    if hash then sendPreviewStats(hash) end
    -- Re-apply this catalog row's saved EMS mods (if any) so switching
    -- between vehicles in the admin list shows each one's own paint/livery
    -- instead of stock or a leftover appearance from the last selection.
    if type(data.mods) == 'table' and next(data.mods) ~= nil then
        currentAdminMods = data.mods
        applyAdminPreviewMods()
    end
    cb({ ok = true, introspect = introspectAdminVehicle() })
end)

RegisterNUICallback('adminTestVehicle', function(data, cb)
    data = type(data) == 'table' and data or {}
    local model = tostring(data.model or ''):lower():gsub('%s+', '')
    local hash = joaat(model)
    if model == '' or hash == 0 or not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        notify('Invalid or unavailable vehicle model.', 'error')
        cb('invalid_model')
        return
    end
    TriggerServerEvent('rn-vehicleshop:server:adminTestDriveRequest', data)
    cb('ok')
end)

RegisterNUICallback('adminDisableVehicle', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('rn-vehicleshop:server:disableAdminVehicle', data.model)
    cb('ok')
end)

RegisterNUICallback('adminEnableVehicle', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('rn-vehicleshop:server:enableAdminVehicle', data.model)
    cb('ok')
end)

RegisterNUICallback('adminReplaceVehicle', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('rn-vehicleshop:server:replaceAdminVehicle', data)
    cb({ accepted = true, pending = true, requestId = data.requestId })
end)

RegisterNUICallback('adminUpdateReplacementNotice', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('rn-vehicleshop:server:updateReplacementNotice', data)
    cb({ accepted = true, pending = true, requestId = data.requestId })
end)

RegisterNUICallback('adminGrantOrganizationVehicle', function(data, cb)
    data = type(data) == 'table' and data or {}
    TriggerServerEvent('rn-vehicleshop:server:grantOrganizationVehicle', data.model, data.organization, data.minimumTier, data.trunkMinimumTier, data.requestId)
    cb({ accepted = true, pending = true, requestId = data.requestId })
end)

RegisterNetEvent('rn-vehicleshop:client:adminActionResult', function(result)
    SendNUIMessage({ action = 'adminActionResult', result = type(result) == 'table' and result or {} })
end)

RegisterNetEvent('rn-vehicleshop:client:organizationGrantResult', function(result)
    SendNUIMessage({ action = 'organizationGrantResult', result = type(result) == 'table' and result or {} })
end)

RegisterNUICallback('adminRescanVehicles', function(_, cb)
    TriggerServerEvent('rn-vehicleshop:server:rescanVehicles')
    cb('ok')
end)

RegisterNUICallback('adminRefresh', function(_, cb)
    TriggerServerEvent('rn-vehicleshop:server:openAdmin', activeAdminMode)
    cb('ok')
end)

RegisterNUICallback('adminClose', function(_, cb)
    TriggerServerEvent('rn-vehicleshop:server:adminClosed')
    SendNUIMessage({ action = 'closeAdmin' })
    -- Leave the showroom view and restore the player if the admin panel put us there.
    if inShop then
        closeVehicleShop()
    else
        SetNuiFocus(false, false)
        endHudStoreLock()
        forceRestoreHud('vehicle_admin_closed')
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
                Wait(5)
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
            local pedConfig = Config.Ped or {}
            local interact = Config.Interact or {}
            local now = GetGameTimer()
            local nearShop = nil
            local nearDist = nil

            for _, shop in ipairs(dealerShops) do
                local dealer = shopDealer(shop)
                local c4 = dealer.coords or vector4(Config.Location.x, Config.Location.y, Config.Location.z, 0.0)
                local c = vector3(c4.x, c4.y, c4.z)
                local dist = #(coords - c)

                if dist <= (interact.markerDistance or 18.0) then
                    sleep = 0
                    ensureShopPedVisible(shop)

                    -- Voice greeting when the player first walks near the NPC.
                    local speechDistance = tonumber(pedConfig.speechDistance) or 6.0
                    if dist <= speechDistance then
                        if not shop._wasNear then
                            shop._wasNear = true
                            shop._nextGreetingAt = 0
                        end
                        playShopGreetingIfNeeded(shop)
                    elseif shop._wasNear and dist > (speechDistance + 1.5) then
                        shop._wasNear = false
                        clearShopSpeech(shop)
                    end

                    -- Name above the dealer.
                    if pedConfig.showName ~= false and dist <= (pedConfig.nameDistance or 8.0) then
                        drawText3D(c.x, c.y, c.z + (pedConfig.nameHeight or 1.30), dealer.npcName or shop.label)
                    end
                    if pedConfig.showGreeting == true and shop._speechText and now < (shop._speechUntil or 0) and dist <= (pedConfig.nameDistance or 8.0) then
                        drawText3D(c.x, c.y, c.z + (pedConfig.nameHeight or 1.30) + 0.26, shop._speechText)
                    end

                    -- Track the nearest shop within interact range for the E prompt.
                    if dist <= (interact.distance or 2.6) and (not nearShop or dist < nearDist) then
                        nearShop = shop
                        nearDist = dist
                    end
                elseif shop._wasNear then
                    shop._wasNear = false
                    clearShopSpeech(shop)
                end
            end

            -- On-screen interaction prompt + open on E (cm-ui shared prompt).
            if nearShop then
                local dealer = shopDealer(nearShop)
                uiShowInteract({
                    key = interact.keyLabel or 'E',
                    label = 'TALK TO DEALER',
                    name = dealer.npcName or nearShop.label,
                    role = nearShop.label
                })
                if IsControlJustPressed(0, interact.key or 38) then
                    uiHideInteract()
                    activeDealerShop = nearShop
                    TriggerEvent('rn-vehicleshop:openDialog')
                    Wait(300)
                end
            else
                uiHideInteract()
            end
        end
        Wait(sleep)
    end
end)

-- RP "talk" step: cm-ui's cinematic NPC dialogue, then open the catalog on confirm.
RegisterNetEvent('rn-vehicleshop:openDialog', function()
    if inShop or dealerDialogOpen then return end
    local shop = activeDealerShop
    if not shop or not shop._ped or not DoesEntityExist(shop._ped) then return end
    if not uiAvailable() then
        -- cm-ui is stopped: skip the conversation and go straight to the catalog.
        TriggerEvent('rn-vehicleshop:target', shop.type)
        return
    end
    dealerDialogOpen = true
    uiHideInteract()
    local pedConfig = Config.Ped or {}
    local dialog = pedConfig.dialog or {}
    local dealer = shopDealer(shop)
    exports['cm-ui']:OpenNpcDialogue(shop._ped, {
        name = dialog.clerkName or dealer.npcName or shop.label,
        role = shop.label,
        quote = dialog.line or dialog.title or 'How can I help you today?',
        choices = {
            {
                id = 'store',
                label = dialog.optionStore or 'Show me the catalog',
                description = 'Browse the showroom and buy a vehicle',
                event = 'rn-vehicleshop:client:dialogueChoiceStore',
            },
            {
                id = 'close',
                label = dialog.optionClose or 'Just browsing, thanks',
                description = 'Maybe another time',
                event = 'rn-vehicleshop:client:dialogueChoiceClose',
            },
        },
        closeEvent = 'rn-vehicleshop:client:dialogueDismissed',
    })
end)

-- cm-ui dialogue choice: "Show me the catalog" -> open the shop.
AddEventHandler('rn-vehicleshop:client:dialogueChoiceStore', function()
    local shop = activeDealerShop
    dealerDialogOpen = false
    uiHideInteract()
    TriggerEvent('rn-vehicleshop:target', shop and shop.type or 'store')
end)

-- cm-ui dialogue choice: "Just browsing" -> farewell and close.
AddEventHandler('rn-vehicleshop:client:dialogueChoiceClose', function()
    dealerDialogOpen = false
    playShopFarewell(activeDealerShop)
end)

-- cm-ui dialogue dismissed (Esc / "I'm not interested right now") -> cleanup.
AddEventHandler('rn-vehicleshop:client:dialogueDismissed', function()
    dealerDialogOpen = false
    playShopFarewell(activeDealerShop)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    setTestDriveProtection(false)
    restoreWorldEnvironment()
    setVehicleAdminClimatePaused(false)
    deletePreviewVehicle()
    deleteTestDriveVehicle()
    uiHideInteract()
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
        if cam and DoesCamExist(cam) then DestroyCam(cam, true) end
        cam = nil
        setShopState(false)
        endHudStoreLock()
        forceRestoreHud('resource_stop')
    end
    for _, shop in ipairs(dealerShops) do
        if shop._ped and DoesEntityExist(shop._ped) then DeleteEntity(shop._ped) end
    end
    endHudStoreLock()
    forceRestoreHud('resource_stop')
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == 'cm-climatime' and vehicleAdminClimatePauseRequested then
        setVehicleAdminClimatePaused(true)
    end
end)
