-- Production vehicle image capture for rn-vehicleshop.
-- Uses screenshot-basic + one real streamed prop_ld_greenscreen_01 backdrop.
-- Debug placement commands were intentionally removed for production.

local pendingCapture = nil
local captureSerial = 0
local currentPreviewVehicle = nil
local backdropProp = nil

function IsVehicleShopCaptureActive()
    return pendingCapture ~= nil
end

local function uiToast(message)
    if not message or message == '' then return end
    SendNUIMessage({ action = 'toast', message = tostring(message) })
end

local function loadPropModel(model, timeout)
    local hash = type(model) == 'number' and model or joaat(model)
    RequestModel(hash)
    local deadline = GetGameTimer() + (timeout or 5000)
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function clearBackdrop()
    if backdropProp and DoesEntityExist(backdropProp) then
        DeleteEntity(backdropProp)
    end
    backdropProp = nil
end

local function vectorComponent(v, key, index, default)
    if type(v) ~= 'vector3' and type(v) ~= 'vector4' and type(v) ~= 'table' then return default end
    return tonumber(v[key] or v[index]) or default
end

-- Scale an entity by rebuilding its matrix.
--
-- IMPORTANT: SetEntityMatrix OVERWRITES rotation, so it must be the LAST thing
-- applied and it must carry the rotation itself. The previous version called
-- SetEntityRotation and then SetEntityMatrix with a left-handed `right` vector
-- derived from the forward vector, which silently threw the heading away and
-- mirrored the prop.
--
-- We now build the basis from the entity's rotation (pitch/roll/yaw) directly and
-- scale each axis independently, so the backdrop can be made ARBITRARILY LARGE
-- (e.g. scale 8-12) and still face the camera correctly.
local function applyEntityScale(entity, scale, scaleX, scaleY, scaleZ)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    scale = tonumber(scale) or 1.0
    local sx = tonumber(scaleX) or scale
    local sy = tonumber(scaleY) or scale
    local sz = tonumber(scaleZ) or scale
    if math.abs(sx - 1.0) < 0.001 and math.abs(sy - 1.0) < 0.001 and math.abs(sz - 1.0) < 0.001 then
        return
    end

    local rot = GetEntityRotation(entity, 2)   -- ZXY, degrees
    local pos = GetEntityCoords(entity)

    local rx = math.rad(rot.x)   -- pitch
    local ry = math.rad(rot.y)   -- roll
    local rz = math.rad(rot.z)   -- yaw

    local cx, sxr = math.cos(rx), math.sin(rx)
    local cy, syr = math.cos(ry), math.sin(ry)
    local cz, szr = math.cos(rz), math.sin(rz)

    -- Standard ZXY rotation basis (right, forward, up), each axis scaled.
    local right   = vector3(
        (cy * cz + syr * sxr * szr),
        (cy * szr - syr * sxr * cz),
        (-syr * cx)
    )
    local forward = vector3(
        (-cx * szr),
        (cx * cz),
        sxr
    )
    local up      = vector3(
        (syr * cz - cy * sxr * szr),
        (syr * szr + cy * sxr * cz),
        (cy * cx)
    )

    SetEntityMatrix(
        entity,
        forward.x * sy, forward.y * sy, forward.z * sy,
        right.x   * sx, right.y   * sx, right.z   * sx,
        up.x      * sz, up.y      * sz, up.z      * sz,
        pos.x, pos.y, pos.z
    )
end

local function setCaptureHudVisible(visible)
    -- Keep capture.lua isolated from legacy global helper files. client.lua owns
    -- HUD state through local wrappers and exposes this internal event only.
    TriggerEvent('rn-vehicleshop:client:setHudVisible', visible == true, 'capture')
    DisplayRadar(visible == true)
end

local function getCaptureStudio()
    if GetVehicleShopCaptureStudio then
        local studio = GetVehicleShopCaptureStudio()
        if studio then return studio end
    end
    return Config.VehicleAdminStudio or Config.Showroom or {}
end

-- Force a bright, flat, shadowless stage for the capture.
--
-- Two bugs used to live here:
--   1. SetTimecycleModifierStrength was fed env.timecycleStrength, which the
--      config sets to 0.0 -- i.e. the modifier was applied and then immediately
--      nullified, so it did nothing at all.
--   2. Weather/time were set ONCE. GTA (and cm-climatime) then fight it back, so
--      by the time the screenshot fires the stage can be dim again. It has to be
--      re-asserted every frame while capturing.
--
-- A dim stage is exactly what breaks the chroma key: the upper half of the (now
-- very large) backdrop falls into shadow, those pixels drop below `minGreen`,
-- and the key skips them -- which is the dark-green band left in the image.
local captureEnvHold = false

local function pushCaptureEnvironment()
    local studio = getCaptureStudio()
    local env = studio.Environment or {}

    NetworkOverrideClockTime(tonumber(env.hour) or 12, tonumber(env.minute) or 0, tonumber(env.second) or 0)

    local weather = env.weather or 'EXTRASUNNY'
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    SetWeatherTypeNowPersist(weather)
    SetWeatherTypeNow(weather)
    SetWeatherTypePersist(weather)
    SetForceVehicleTrails(false)
    SetForcePedFootstepsTracks(false)

    -- Flat, even light. Strength must be > 0 or the modifier does nothing.
    local tc = env.timecycle
    if tc and tc ~= '' then
        SetTimecycleModifier(tc)
        SetTimecycleModifierStrength(tonumber(env.timecycleStrength) or 1.0)
    end

    -- Kill the things that darken the backdrop.
    SetArtificialLightsState(false)
    if env.noShadows ~= false then
        pcall(function() CascadeShadowsEnableEntityTracker(false) end)
        pcall(function() SetRainLevel(0.0) end)
    end
end

local function applyCaptureEnvironment()
    pushCaptureEnvironment()

    -- Hold it. Other resources (cm-climatime) will otherwise stomp the weather
    -- back mid-capture and the stage goes dim again.
    --
    -- Reassert interval MUST stay slow (the light visibly blinks/pulses on
    -- every single call to SetWeatherTypeNow/NetworkOverrideClockTime, even
    -- with identical values -- each call restarts GTA's internal weather
    -- blend). This is the exact same bug already fixed once for the general
    -- studio view (see Config.VehicleAdminStudio.Environment.reassertMs and
    -- its "old 350ms clear/set loop caused visible flicker" note) -- this
    -- capture-specific loop had been left on the old fast interval. A whole
    -- capture only takes ~1-1.5s, so a 5s reassert means it fires at most
    -- once during any single photo, and only actually kicks in if the studio
    -- stays open far longer than a capture takes.
    local studio = getCaptureStudio()
    local reassertMs = math.max(2000, tonumber((studio.Environment or {}).reassertMs) or 5000)
    if captureEnvHold then return end
    captureEnvHold = true
    CreateThread(function()
        while captureEnvHold do
            Wait(reassertMs)
            pushCaptureEnvironment()
        end
    end)
end

local function releaseCaptureEnvironment()
    captureEnvHold = false
    ClearTimecycleModifier()
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    pcall(function() NetworkClearClockTimeOverride() end)
    pcall(function() SetArtificialLightsState(false) end)
end

local function spawnBackdrop()
    clearBackdrop()
    local cfg = (Config.ImageCapture and Config.ImageCapture.Backdrop) or {}
    if cfg.enabled == false then return true end

    local hash = loadPropModel(cfg.model or 'prop_ld_greenscreen_01', 5000)
    if not hash then
        uiToast('Green-screen prop failed to load. Check stream/prop_ld_greenscreen_01.ydr.')
        return false
    end

    local studio = getCaptureStudio()
    local fixed = cfg.fixedCoords or cfg.coords or (studio and studio.backdrop)
    local x, y, z, heading

    -- zLift MUST apply in both branches. It used to be added only in the `else`
    -- branch, so any config with fixedCoords (which is the normal setup) silently
    -- ignored zLift: the prop always spawned at the raw fixed height and the
    -- tuned value was thrown away.
    local zLift = tonumber(cfg.zLift) or 0.0

    if fixed and fixed.x and fixed.y and fixed.z then
        x, y = fixed.x, fixed.y
        z = fixed.z + zLift
        heading = tonumber(fixed.w) or tonumber(cfg.heading) or 0.0
    else
        local v = (studio and studio.vehicle) or vector4(Config.Location.x, Config.Location.y, Config.Location.z, 0.0)
        x, y = v.x, v.y
        z = v.z + zLift
        heading = v.w or 0.0
    end

    local obj = CreateObjectNoOffset(hash, x, y, z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not obj or obj == 0 then
        uiToast('Could not create green-screen prop.')
        return false
    end

    backdropProp = obj
    SetEntityAsMissionEntity(obj, true, true)
    SetEntityCollision(obj, cfg.collision == true, cfg.collision == true)
    FreezeEntityPosition(obj, true)
    SetEntityAlpha(obj, 255, false)
    SetEntityLodDist(obj, 1000)
    SetEntityHeading(obj, (heading + (tonumber(cfg.headingOffset) or 0.0)) % 360.0)

    local rot = cfg.rotation or vector3(0.0, 0.0, 0.0)
    local rx = vectorComponent(rot, 'x', 1, 0.0)
    local ry = vectorComponent(rot, 'y', 2, 0.0)
    local rz = (heading + (tonumber(cfg.headingOffset) or 0.0) + vectorComponent(rot, 'z', 3, 0.0)) % 360.0
    SetEntityRotation(obj, rx, ry, rz, 2, true)

    -- Scale LAST (SetEntityMatrix overwrites rotation, so it must carry it).
    -- scale = uniform; scaleX/Y/Z override individual axes so the backdrop can be
    -- stretched wide + tall to completely fill the camera frame.
    applyEntityScale(
        obj,
        tonumber(cfg.scale) or 1.0,
        tonumber(cfg.scaleX),
        tonumber(cfg.scaleY),
        tonumber(cfg.scaleZ)
    )
    return true
end

function SetCapturedPreviewVehicle(veh)
    currentPreviewVehicle = veh
end

RegisterNUICallback('captureVehicleImage', function(data, cb)
    data = type(data) == 'table' and data or {}
    local model = tostring(data.model or ''):lower():gsub('%s+', '')
    if model == '' then cb({ ok = false, error = 'no_model' }) return end

    if GetVehicleShopPreviewMode and GetVehicleShopPreviewMode() ~= 'admin' then
        cb({ ok = false, error = 'not_in_vehicle_admin_studio' })
        SendNUIMessage({ action = 'vehicleImageResult', success = false, error = 'Open /vehicleadmin first.' })
        return
    end

    if not (Config.ImageCapture and Config.ImageCapture.enabled) then
        cb({ ok = false, error = 'capture_disabled' })
        return
    end

    if GetResourceState('screenshot-basic') ~= 'started' then
        SendNUIMessage({ action = 'vehicleImageResult', success = false, error = 'screenshot-basic is not started' })
        cb({ ok = false, error = 'screenshot-basic_not_started' })
        return
    end

    local veh = currentPreviewVehicle
    if not veh or not DoesEntityExist(veh) or GetEntityModel(veh) ~= joaat(model) then
        TriggerEvent('rn-vehicleshop:client:spawnPreviewForCapture', model)
        local timeout = GetGameTimer() + tonumber((Config.ImageCapture and Config.ImageCapture.spawnTimeoutMs) or 9000)
        repeat
            Wait(50)
            veh = currentPreviewVehicle
        until (veh and DoesEntityExist(veh) and GetEntityModel(veh) == joaat(model)) or GetGameTimer() > timeout
    end

    if not veh or not DoesEntityExist(veh) then
        SendNUIMessage({ action = 'vehicleImageResult', success = false, error = 'preview vehicle missing' })
        cb({ ok = false, error = 'no_vehicle' })
        return
    end

    captureSerial = captureSerial + 1
    local serial = captureSerial
    pendingCapture = {
        serial = serial,
        model = model,
        label = data.label,
        category = data.category,
        padding = Config.ImageCapture.padding or 12,
        background = Config.ImageCapture.background or 'green',
        crop = Config.ImageCapture.crop,
        chroma = Config.ImageCapture.chroma,
    }
    CreateThread(function()
        Wait(tonumber((Config.ImageCapture and Config.ImageCapture.pendingTimeoutMs) or 60000))
        if pendingCapture and pendingCapture.serial == serial then
            pendingCapture = nil
            clearBackdrop()
            releaseCaptureEnvironment()
            setCaptureHudVisible(false)
            SetNuiFocus(true, true)
            SendNUIMessage({ action = 'prepareVehicleCapture', value = false })
            SendNUIMessage({ action = 'adminFocus', value = true })
            SendNUIMessage({ action = 'vehicleImageResult', success = false, error = 'capture timed out' })
        end
    end)

    applyCaptureEnvironment()

    -- Make the admin thumbnail capture deterministic: clear liveries/modkits,
    -- remove dirt, ensure the vehicle is visible, and give streamed add-on
    -- textures/collision a short grace period before screenshot-basic fires.
    if ForceVehicleShopStockAppearancePasses then
        ForceVehicleShopStockAppearancePasses(veh, false, false, model)
    elseif ResetVehicleShopVehicleToDefaultStock then
        ResetVehicleShopVehicleToDefaultStock(veh, false, model)
    end
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleLights(veh, 2)
    SetVehicleFullbeam(veh, true)
    FreezeEntityPosition(veh, false)
    SetEntityCollision(veh, true, true)
    pcall(function() SetVehicleOnGroundProperly(veh) end)

    -- Lift the car slightly so the tyres sit ON TOP of the green floor. If the
    -- wheels sink into the backdrop plane they get keyed out with the green and
    -- the car is saved with its tyres cut off.
    local vLift = tonumber(Config.ImageCapture and Config.ImageCapture.vehicleZLift) or 0.0
    if vLift ~= 0.0 then
        local vc = GetEntityCoords(veh)
        SetEntityCoordsNoOffset(veh, vc.x, vc.y, vc.z + vLift, false, false, false)
    end

    FreezeEntityPosition(veh, true)
    SetEntityAlpha(veh, 255, false)
    SetEntityVisible(veh, true, false)

    if not spawnBackdrop() then
        pendingCapture = nil
        clearBackdrop()
        releaseCaptureEnvironment()
        SendNUIMessage({ action = 'prepareVehicleCapture', value = false })
        SendNUIMessage({ action = 'adminFocus', value = true })
        SetNuiFocus(true, true)
        setCaptureHudVisible(false)
        cb({ ok = false, error = 'backdrop_failed' })
        return
    end

    SendNUIMessage({ action = 'prepareVehicleCapture', value = true })
    SendNUIMessage({ action = 'adminFocus', value = false })
    SetNuiFocus(false, false)
    setCaptureHudVisible(false)

    local settleUntil = GetGameTimer() + tonumber((Config.ImageCapture and Config.ImageCapture.preShotDelayMs) or 1250)
    while GetGameTimer() < settleUntil do
        if not veh or not DoesEntityExist(veh) then
            pendingCapture = nil
            clearBackdrop()
            releaseCaptureEnvironment()
            SendNUIMessage({ action = 'prepareVehicleCapture', value = false })
            SendNUIMessage({ action = 'adminFocus', value = true })
            SetNuiFocus(true, true)
            SendNUIMessage({ action = 'vehicleImageResult', success = false, error = 'preview vehicle disappeared' })
            cb({ ok = false, error = 'vehicle_missing' })
            return
        end
        if ResetVehicleShopVehicleToDefaultStock then ResetVehicleShopVehicleToDefaultStock(veh, false, model) end
        SetEntityAlpha(veh, 255, false)
        SetEntityVisible(veh, true, false)
        Wait(100)
    end

    exports['screenshot-basic']:requestScreenshot({ encoding = 'png' }, function(imageData)
        clearBackdrop()
        releaseCaptureEnvironment()
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'prepareVehicleCapture', value = false })
        SendNUIMessage({ action = 'adminFocus', value = false })
        -- Keep HUD hidden while the crop preview/admin menu is open. It will be restored by closeShopBase().
        setCaptureHudVisible(false)

        if not imageData or imageData == '' then
            pendingCapture = nil
            SendNUIMessage({ action = 'adminFocus', value = true })
            SendNUIMessage({ action = 'vehicleImageResult', success = false, error = 'screenshot failed' })
            return
        end

        SendNUIMessage({ action = 'processVehicleImage', image = imageData, payload = pendingCapture })
    end)

    cb({ ok = true, pending = true })
end)

RegisterNUICallback('vehicleImageProcessed', function(data, cb)
    data = type(data) == 'table' and data or {}
    local payload = pendingCapture or {}

    if data.error or not data.imageBase64 or data.imageBase64 == '' then
        pendingCapture = nil
        SendNUIMessage({ action = 'adminFocus', value = true })
        if tostring(data.error or '') ~= 'cancelled' then
            SendNUIMessage({ action = 'vehicleImageResult', success = false, error = tostring(data.error or 'empty processed image') })
        end
        cb('ok')
        return
    end

    if not payload.model then
        pendingCapture = nil
        SendNUIMessage({ action = 'adminFocus', value = true })
        SendNUIMessage({ action = 'vehicleImageResult', success = false, error = 'capture payload expired' })
        cb('ok')
        return
    end

    TriggerLatentServerEvent('rn-vehicleshop:server:saveVehicleImage', 200000, {
        model = payload.model,
        label = payload.label,
        category = payload.category,
        imageBase64 = data.imageBase64,
        dataUrl = data.dataUrl,
        mime = data.mime,
        ext = data.ext,
    })
    pendingCapture = nil
    cb('ok')
end)

RegisterNUICallback('cancelVehicleImage', function(_, cb)
    pendingCapture = nil
    clearBackdrop()
    releaseCaptureEnvironment()
    setCaptureHudVisible(false)
    SendNUIMessage({ action = 'prepareVehicleCapture', value = false })
    SendNUIMessage({ action = 'adminFocus', value = true })
    cb('ok')
end)

RegisterNetEvent('rn-vehicleshop:client:vehicleImageSaved', function(success, pathOrErr, model)
    SendNUIMessage({ action = 'adminFocus', value = true })
    if success then
        SendNUIMessage({ action = 'vehicleImageResult', success = true, image = pathOrErr, model = model })
    else
        SendNUIMessage({ action = 'vehicleImageResult', success = false, error = tostring(pathOrErr or 'save failed') })
    end
end)

-- Runtime green-screen tuning commands were removed for production.
-- Capture cleanup still runs when the resource stops.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    captureSerial = captureSerial + 1
    pendingCapture = nil
    currentPreviewVehicle = nil
    clearBackdrop()
    releaseCaptureEnvironment()
    setCaptureHudVisible(true)
    SendNUIMessage({ action = 'prepareVehicleCapture', value = false })
    SendNUIMessage({ action = 'adminFocus', value = true })
end)
