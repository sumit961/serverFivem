-- Production vehicle image capture for rn-vehicleshop.
-- Uses screenshot-basic + one real streamed prop_ld_greenscreen_01 backdrop.
-- Debug placement commands were intentionally removed for production.

local pendingCapture = nil
local currentPreviewVehicle = nil
local backdropProp = nil

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

local function applyEntityScale(entity, scale)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    scale = tonumber(scale) or 1.0
    if math.abs(scale - 1.0) < 0.001 then return end

    local forward = GetEntityForwardVector(entity)
    local right = vector3(forward.y, -forward.x, 0.0)
    local up = vector3(0.0, 0.0, 1.0)
    local pos = GetEntityCoords(entity)

    SetEntityMatrix(
        entity,
        forward.x * scale, forward.y * scale, forward.z * scale,
        right.x * scale, right.y * scale, right.z * scale,
        up.x * scale, up.y * scale, up.z * scale,
        pos.x, pos.y, pos.z
    )
end

local function setCaptureHudVisible(visible)
    if SetVehicleShopHudVisible then
        SetVehicleShopHudVisible(visible == true, 'capture')
    end
end

local function getCaptureStudio()
    if GetVehicleShopCaptureStudio then
        local studio = GetVehicleShopCaptureStudio()
        if studio then return studio end
    end
    return Config.VehicleAdminStudio or Config.Showroom or {}
end

local function applyCaptureEnvironment()
    local studio = getCaptureStudio()
    local env = studio.Environment or {}
    NetworkOverrideClockTime(tonumber(env.hour) or 12, tonumber(env.minute) or 0, tonumber(env.second) or 0)
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    SetWeatherTypeNowPersist(env.weather or 'EXTRASUNNY')
    SetWeatherTypeNow(env.weather or 'EXTRASUNNY')
    SetWeatherTypePersist(env.weather or 'EXTRASUNNY')
    if env.timecycle and env.timecycle ~= '' then
        SetTimecycleModifier(env.timecycle)
        SetTimecycleModifierStrength(tonumber(env.timecycleStrength) or 0.0)
    end
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

    if fixed and fixed.x and fixed.y and fixed.z then
        x, y, z = fixed.x, fixed.y, fixed.z
        heading = tonumber(fixed.w) or tonumber(cfg.heading) or 0.0
    else
        local v = (studio and studio.vehicle) or vector4(Config.Location.x, Config.Location.y, Config.Location.z, 0.0)
        x, y, z, heading = v.x, v.y, v.z + (tonumber(cfg.zLift) or 0.62), v.w or 0.0
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
    applyEntityScale(obj, tonumber(cfg.scale) or 1.0)
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
        local timeout = GetGameTimer() + 9000
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

    pendingCapture = {
        model = model,
        label = data.label,
        category = data.category,
        padding = Config.ImageCapture.padding or 12,
        background = Config.ImageCapture.background or 'green',
        crop = Config.ImageCapture.crop,
        chroma = Config.ImageCapture.chroma,
    }

    applyCaptureEnvironment()
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleLights(veh, 2)
    SetVehicleFullbeam(veh, true)
    FreezeEntityPosition(veh, true)

    if not spawnBackdrop() then
        pendingCapture = nil
        cb({ ok = false, error = 'backdrop_failed' })
        return
    end

    SendNUIMessage({ action = 'prepareVehicleCapture', value = true })
    SetNuiFocus(false, false)
    setCaptureHudVisible(false)
    Wait(850)

    exports['screenshot-basic']:requestScreenshot({ encoding = 'png' }, function(imageData)
        clearBackdrop()
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'prepareVehicleCapture', value = false })
        SendNUIMessage({ action = 'adminFocus', value = false })
        -- Keep HUD hidden while the crop preview/admin menu is open. It will be restored by closeShopBase().
        setCaptureHudVisible(false)

        if not imageData or imageData == '' then
            pendingCapture = nil
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

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearBackdrop()
end)
