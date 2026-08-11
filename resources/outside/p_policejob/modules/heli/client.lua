while not Config or not Config.Helicam do
    Citizen.Wait(500)
end

if not Config.Helicam.Enabled then
    return
end

local heliConfig = Config.Helicam
local VISION_NORMAL = 0
local VISION_NIGHT = 1
local VISION_THERMAL = 2

Helicam = {
    active = false,
    cam = nil,
    fov = heliConfig.FovDefault,
    vision = VISION_NORMAL,
    spotlight = false,
    spotlightRadius = heliConfig.Spotlight and heliConfig.Spotlight.Radius or 13.0,
    lockedEntity = nil,
    heli = nil,
}

local spotlightConfig = heliConfig.Spotlight or {}
local spotlightColor = spotlightConfig.Color or { 245, 245, 220 }
local spotlightDistance = spotlightConfig.Distance or 250.0
local spotlightBrightness = spotlightConfig.Brightness or 25.0
local spotlightHardness = spotlightConfig.Hardness or 0.0
local spotlightDefaultRadius = spotlightConfig.Radius or 13.0
local spotlightFalloff = spotlightConfig.Falloff or 28.0
local spotlightRadiusMin = spotlightConfig.RadiusMin or 4.0
local spotlightRadiusMax = spotlightConfig.RadiusMax or 40.0
local spotlightRadiusStep = spotlightConfig.RadiusStep or 1.5
local spotlightSmoothing = spotlightConfig.Smoothing or 12.0

remoteSpotlights = {}
spotlightRenderActive = false

local visionLabels = {
    [VISION_NORMAL] = "normal",
    [VISION_NIGHT] = "night",
    [VISION_THERMAL] = "thermal",
}

function hasHelicamJobAccess()
    local job = Bridge.Framework.fetchPlayerJob()
    if not job or not job.name then
        return false
    end
    local minGrade = Config.Jobs[job.name]
    if minGrade == nil then
        return false
    end
    return minGrade <= (job.grade or 0)
end

function getCurrentHeli()
    local vehicle = GetVehiclePedIsIn(cache.ped, false)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end
    if heliConfig.RestrictToHelicopter and GetVehicleClass(vehicle) ~= 15 then
        return nil
    end
    if not heliConfig.AllowPilot then
        local driver = GetPedInVehicleSeat(vehicle, -1)
        if driver == cache.ped then
            return nil
        end
    end
    return vehicle
end

function applyVisionMode(visionMode)
    if visionMode == VISION_NIGHT then
        SetSeethrough(false)
        SetNightvision(true)
    elseif visionMode == VISION_THERMAL then
        SetNightvision(false)
        SetSeethrough(true)
    else
        SetNightvision(false)
        SetSeethrough(false)
    end
end

function getCamDirection(cam)
    if not cam then
        return { x = 0.0, y = 0.0, z = -1.0 }
    end
    local rotation = GetCamRot(cam, 2)
    local pitchCos = math.cos(math.rad(rotation.x))
    return {
        x = -math.sin(math.rad(rotation.z)) * pitchCos,
        y = math.cos(math.rad(rotation.z)) * pitchCos,
        z = math.sin(math.rad(rotation.x)),
    }
end

function ensureSpotlightRenderLoop()
    if spotlightRenderActive then
        return
    end
    spotlightRenderActive = true
    CreateThread(function()
        while next(remoteSpotlights) do
            local blend = math.min(1.0, GetFrameTime() * spotlightSmoothing)
            for netId, spotlight in pairs(remoteSpotlights) do
                if NetworkDoesNetworkIdExist(netId) then
                    local heliEntity = NetworkGetEntityFromNetworkId(netId)
                    if heliEntity and heliEntity ~= 0 and DoesEntityExist(heliEntity) then
                        local heliCoords = GetEntityCoords(heliEntity)
                        local direction
                        if Helicam.active and Helicam.spotlight and Helicam.heli == heliEntity then
                            direction = getCamDirection(Helicam.cam)
                            spotlight.cur = direction
                        else
                            if not spotlight.cur then
                                spotlight.cur = {
                                    x = spotlight.dir.x,
                                    y = spotlight.dir.y,
                                    z = spotlight.dir.z,
                                }
                            end
                            local current = spotlight.cur
                            current.x = current.x + (spotlight.dir.x - current.x) * blend
                            current.y = current.y + (spotlight.dir.y - current.y) * blend
                            current.z = current.z + (spotlight.dir.z - current.z) * blend
                            local length = math.sqrt(current.x * current.x + current.y * current.y + current.z * current.z)
                            if length > 0.0001 then
                                current.x = current.x / length
                                current.y = current.y / length
                                current.z = current.z / length
                            end
                            direction = current
                        end
                        DrawSpotLight(
                            heliCoords.x, heliCoords.y, heliCoords.z,
                            direction.x, direction.y, direction.z,
                            spotlightColor[1], spotlightColor[2], spotlightColor[3],
                            spotlightDistance,
                            spotlightBrightness,
                            spotlightHardness,
                            spotlight.radius or spotlightDefaultRadius,
                            spotlightFalloff
                        )
                    end
                end
            end
            Wait(0)
        end
        spotlightRenderActive = false
    end)
end

RegisterNetEvent("p_policejob:heli:syncSpotlight", function(netId, enabled, direction, radius)
    if enabled then
        remoteSpotlights[netId] = {
            dir = direction or { x = 0.0, y = 0.0, z = -1.0 },
            radius = radius or spotlightDefaultRadius,
        }
        ensureSpotlightRenderLoop()
    else
        remoteSpotlights[netId] = nil
    end
end)

RegisterNetEvent("p_policejob:heli:syncSpotlightDir", function(netId, direction)
    if remoteSpotlights[netId] and direction then
        remoteSpotlights[netId].dir = direction
    end
end)

RegisterNetEvent("p_policejob:heli:syncSpotlightRadius", function(netId, radius)
    if remoteSpotlights[netId] and radius then
        remoteSpotlights[netId].radius = radius
    end
end)

function setSpotlightState(enabled)
    if not heliConfig.EnableSpotlight then
        return
    end
    if not Helicam.heli or not DoesEntityExist(Helicam.heli) then
        return
    end
    Helicam.spotlight = enabled
    local netId = NetworkGetNetworkIdFromEntity(Helicam.heli)
    if netId and netId ~= 0 then
        TriggerServerEvent(
            "p_policejob:heli:setSpotlight",
            netId,
            enabled,
            enabled and getCamDirection(Helicam.cam) or nil,
            enabled and Helicam.spotlightRadius or nil
        )
    end
end

function setSpotlightRadius(radius)
    radius = math.max(spotlightRadiusMin, math.min(spotlightRadiusMax, radius))
    if radius == Helicam.spotlightRadius then
        return
    end
    Helicam.spotlightRadius = radius
    if not Helicam.spotlight then
        return
    end
    if not Helicam.heli or not DoesEntityExist(Helicam.heli) then
        return
    end
    local netId = NetworkGetNetworkIdFromEntity(Helicam.heli)
    if netId and netId ~= 0 then
        TriggerServerEvent("p_policejob:heli:updateSpotlightRadius", netId, radius)
    end
end

function findLockTarget(cam)
    local camCoords = GetCamCoord(cam)
    local camDirection = getCamDirection(cam)
    local bestEntity = nil
    local bestDot = nil
    local bestDistance = nil
    function considerEntity(entity)
        if not DoesEntityExist(entity) then
            return
        end
        if entity == Helicam.heli or entity == cache.ped then
            return
        end
        local entityCoords = GetEntityCoords(entity)
        local offset = entityCoords - camCoords
        local distance = #offset
        if distance < 5.0 or distance > 350.0 then
            return
        end
        local direction = offset / distance
        local dot = direction.x * camDirection.x + direction.y * camDirection.y + direction.z * camDirection.z
        if dot < 0.985 then
            return
        end
        if not bestDot or dot > bestDot then
            bestEntity = entity
            bestDot = dot
            bestDistance = distance
        end
    end
    for _, ped in ipairs(GetGamePool("CPed")) do
        considerEntity(ped)
    end
    for _, vehicle in ipairs(GetGamePool("CVehicle")) do
        considerEntity(vehicle)
    end
    return bestEntity, bestDistance
end

function getTargetInfo(entity)
    if not entity or not DoesEntityExist(entity) then
        return nil
    end
    if IsEntityAVehicle(entity) then
        local plate = GetVehicleNumberPlateText(entity) or ""
        plate = plate:gsub("%s+$", ""):gsub("^%s+", "")
        return {
            type = "vehicle",
            label = plate ~= "" and plate or "----",
        }
    end
    if IsEntityAPed(entity) then
        if IsPedAPlayer(entity) then
            local playerIndex = NetworkGetPlayerIndexFromPed(entity)
            local playerName = playerIndex ~= -1 and GetPlayerName(playerIndex) or "PLAYER"
            return {
                type = "player",
                label = playerName or "PLAYER",
            }
        end
        return { type = "ped", label = "NPC" }
    end
    return nil
end

function updateHelicamHud()
    if not Helicam.heli or not DoesEntityExist(Helicam.heli) then
        return
    end
    local zoom = math.floor(
        ((heliConfig.FovMax - Helicam.fov) / (heliConfig.FovMax - heliConfig.FovMin)) * 100 + 0.5
    )
    local altitude = GetEntityHeightAboveGround(Helicam.heli)
    local speed = GetEntitySpeed(Helicam.heli)
    local altValue
    local altUnit
    if heliConfig.AltitudeUnit == "ft" then
        altValue = math.floor(altitude * 3.28084 + 0.5)
        altUnit = "ft"
    else
        altValue = math.floor(altitude + 0.5)
        altUnit = "m"
    end
    local speedValue
    local speedUnit
    if heliConfig.SpeedUnit == "mph" then
        speedValue = math.floor(speed * 2.236936 + 0.5)
        speedUnit = "mph"
    else
        speedValue = math.floor(speed * 3.6 + 0.5)
        speedUnit = "km/h"
    end
    SendNUIMessage({
        action = "setHelicamData",
        data = {
            vision = visionLabels[Helicam.vision],
            zoom = zoom,
            alt = altValue,
            altUnit = altUnit,
            spd = speedValue,
            spdUnit = speedUnit,
            fov = Helicam.fov,
            spotlight = Helicam.spotlight,
            spotlightRadius = math.floor(Helicam.spotlightRadius + 0.5),
            target = getTargetInfo(Helicam.lockedEntity) or false,
        },
    })
end

function Helicam.start(self)
    if self.active then
        return
    end
    if not cache.vehicle or cache.vehicle == 0 then
        return
    end
    if not hasHelicamJobAccess() then
        Bridge.Notify.showNotify(locale("no_access"), "error")
        return
    end
    local heli = getCurrentHeli()
    if not heli then
        Bridge.Notify.showNotify(locale("helicam_must_be_in_heli"), "error")
        return
    end
    self.active = true
    self.heli = heli
    self.fov = heliConfig.FovDefault
    self.vision = VISION_NORMAL
    self.spotlight = false
    self.spotlightRadius = spotlightDefaultRadius
    self.lockedEntity = nil
    local cam = CreateCam("DEFAULT_SCRIPTED_FLY_CAMERA", true)
    AttachCamToEntity(cam, heli, 0.0, 0.0, -1.5, true)
    SetCamRot(cam, -45.0, 0.0, GetEntityHeading(heli), 2)
    SetCamFov(cam, self.fov)
    RenderScriptCams(true, false, 0, true, false)
    self.cam = cam
    applyVisionMode(self.vision)
    heliConfig.onStart()
    SendNUIMessage({ action = "setVisibleHelicam", data = true })
    updateHelicamHud()
    CreateThread(function()
        local lastHudUpdate = 0
        local lastSpotlightSync = 0
        local lastSpotlightDirection = nil
        while self.active do
            Wait(0)
            local currentHeli = getCurrentHeli()
            if not currentHeli or currentHeli ~= self.heli or not DoesEntityExist(self.heli) then
                self:stop()
                break
            end
            HideHudAndRadarThisFrame()
            for _, control in ipairs({ 1, 2, 14, 15, 16, 17, 24, 25, 257, 263, 36 }) do
                DisableControlAction(0, control, true)
            end
            local rotateX = GetDisabledControlNormal(0, 1) * heliConfig.RotateSpeed
            local rotateY = GetDisabledControlNormal(0, 2) * heliConfig.RotateSpeed
            if self.lockedEntity and DoesEntityExist(self.lockedEntity) then
                local targetCoords = GetEntityCoords(self.lockedEntity)
                PointCamAtCoord(self.cam, targetCoords.x, targetCoords.y, targetCoords.z)
                if #(GetCamCoord(self.cam) - targetCoords) > 600.0 then
                    self.lockedEntity = nil
                    StopCamPointing(self.cam)
                end
            else
                local rotation = GetCamRot(self.cam, 2)
                local pitch = math.max(
                    heliConfig.PitchMin,
                    math.min(heliConfig.PitchMax, rotation.x - rotateY)
                )
                SetCamRot(self.cam, pitch, 0.0, rotation.z - rotateX, 2)
            end
            if self.spotlight then
                if IsDisabledControlPressed(0, 36) then
                    if IsDisabledControlPressed(0, 14) then
                        setSpotlightRadius(self.spotlightRadius - spotlightRadiusStep)
                    elseif IsDisabledControlPressed(0, 15) then
                        setSpotlightRadius(self.spotlightRadius + spotlightRadiusStep)
                    end
                end
            else
                if IsDisabledControlPressed(0, 14) then
                    self.fov = math.min(heliConfig.FovMax, self.fov + heliConfig.FovStep)
                    SetCamFov(self.cam, self.fov)
                elseif IsDisabledControlPressed(0, 15) then
                    self.fov = math.max(heliConfig.FovMin, self.fov - heliConfig.FovStep)
                    SetCamFov(self.cam, self.fov)
                end
            end
            local now = GetGameTimer()
            if self.spotlight then
                local direction = getCamDirection(self.cam)
                if not lastSpotlightDirection and now - lastSpotlightSync >= 120 then
                    lastSpotlightSync = now
                    lastSpotlightDirection = direction
                    local netId = NetworkGetNetworkIdFromEntity(self.heli)
                    if netId and netId ~= 0 then
                        TriggerServerEvent("p_policejob:heli:updateSpotlightDir", netId, direction)
                    end
                end
            end
            if now - lastHudUpdate >= 100 then
                lastHudUpdate = now
                updateHelicamHud()
            end
        end
    end)
end

function Helicam.stop(self)
    if not self.active then
        return
    end
    self.active = false
    if self.cam then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(self.cam, false)
        self.cam = nil
    end
    applyVisionMode(VISION_NORMAL)
    setSpotlightState(false)
    self.lockedEntity = nil
    self.heli = nil
    SendNUIMessage({ action = "setVisibleHelicam", data = false })
    heliConfig.onStop()
end

function Helicam.toggle(self)
    if self.active then
        self:stop()
    else
        self:start()
    end
end

function Helicam.cycleVision(self)
    if not self.active then
        return
    end
    self.vision = (self.vision + 1) % 3
    applyVisionMode(self.vision)
    updateHelicamHud()
end

function Helicam.toggleSpotlight(self)
    if not self.active then
        return
    end
    setSpotlightState(not self.spotlight)
    updateHelicamHud()
end

function Helicam.tryLock(self)
    if not self.active or not self.cam then
        return
    end
    if self.lockedEntity and DoesEntityExist(self.lockedEntity) then
        self.lockedEntity = nil
        StopCamPointing(self.cam)
        updateHelicamHud()
        return
    end
    local target = findLockTarget(self.cam)
    if target then
        self.lockedEntity = target
        updateHelicamHud()
    end
end

exports("isHelicamActive", function()
    return Helicam.active
end)

exports("toggleHelicam", function()
    Helicam:toggle()
end)

lib.addKeybind({
    name = "helicam_toggle",
    description = locale("helicam_toggle"),
    defaultKey = heliConfig.Keys.toggle,
    onPressed = function()
        Helicam:toggle()
    end,
})

lib.addKeybind({
    name = "helicam_vision",
    description = locale("helicam_cycle_vision"),
    defaultKey = heliConfig.Keys.cycleVision,
    onPressed = function()
        Helicam:cycleVision()
    end,
})

lib.addKeybind({
    name = "helicam_light",
    description = locale("helicam_toggle_light"),
    defaultKey = heliConfig.Keys.toggleLight,
    onPressed = function()
        Helicam:toggleSpotlight()
    end,
})

lib.addKeybind({
    name = "helicam_lock",
    description = locale("helicam_lock_target"),
    defaultKey = heliConfig.Keys.lockTarget,
    onPressed = function()
        Helicam:tryLock()
    end,
})

AddEventHandler("baseevents:leftVehicle", function()
    if Helicam.active then
        Helicam:stop()
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() and Helicam.active then
        Helicam:stop()
    end
end)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent("p_policejob:heli:requestSpotlights")
end)
