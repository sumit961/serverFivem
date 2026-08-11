while not Config or not Config.Grenades do
    Citizen.Wait(500)
end

if not Config.Grenades.Enabled then
    return
end

local flashbangConfig = Config.Grenades.Flashbang
local smokeConfig = Config.Grenades.SmokeGrenade

Grenades = {
    active = {},
    inFlight = {},
    flashbang = {
        affected = false,
    },
    smoke = {
        zones = {},
        inside = false,
        lastCough = 0,
        loopRunning = false,
    },
}

function Grenades.hasJobAccess(self)
    if not next(Config.Jobs) then
        return true
    end
    local job = Bridge.Framework.fetchPlayerJob()
    if not job or not job.name then
        return false
    end
    local requiredGrade = Config.Jobs[job.name]
    if requiredGrade == nil then
        return false
    end
    local grade = job.grade or 0
    return requiredGrade <= grade
end

function Grenades.disableAimControls(self)
    DisableControlAction(0, 1, true)
    DisableControlAction(0, 2, true)
    DisableControlAction(0, 220, true)
    DisableControlAction(0, 221, true)
end

function Grenades.startSlowAim(self, durationMs, scale)
    CreateThread(function()
        local startTime = GetGameTimer()
        local heading = GetGameplayCamRelativeHeading()
        local pitch = GetGameplayCamRelativePitch()
        while self.flashbang.affected and GetGameTimer() - startTime < durationMs do
            local lookX = GetDisabledControlNormal(0, 220)
            local lookY = GetDisabledControlNormal(0, 221)
            heading = heading - lookX * scale * 10.0
            pitch = math.max(-70.0, math.min(42.0, pitch - lookY * scale * 10.0))
            SetGameplayCamRelativeHeading(heading)
            SetGameplayCamRelativePitch(pitch, 1.0)
            Wait(0)
        end
    end)
end

function Grenades.drawWhiteFlash(self, durationMs)
    CreateThread(function()
        local whiteFlashMs = math.min(durationMs, flashbangConfig.WhiteFlashMs)
        local startTime = GetGameTimer()
        while GetGameTimer() - startTime < whiteFlashMs do
            local elapsed = GetGameTimer() - startTime
            local alpha = math.floor(255 * (1.0 - elapsed / whiteFlashMs))
            DrawRect(0.5, 0.5, 1.0, 1.0, 255, 255, 255, alpha)
            Wait(0)
        end
    end)
end

function Grenades.applyFlashEffect(self, intensity, durationMs, isStunned, facingFlash)
    if self.flashbang.affected then
        return
    end
    self.flashbang.affected = true
    local ped = cache.ped
    AnimpostfxStop("MP_flash")
    AnimpostfxPlay("MP_flash", 0, true)
    local showWhiteFlash = isStunned and facingFlash
    Sounds:playSound("flashbang", 0.4)
    if showWhiteFlash then
        self:drawWhiteFlash(durationMs)
    end
    local drunkMs = math.floor(flashbangConfig.DrunkMs * intensity)
    CreateThread(function()
        local animDict = lib.requestAnimDict(flashbangConfig.FaceAnimDict, 2000)
        if animDict then
            TaskPlayAnim(ped, flashbangConfig.FaceAnimDict, flashbangConfig.FaceAnimName, 4.0, -4.0, drunkMs, 49, 0, false, false, false)
        end
    end)
    CreateThread(function()
        ShakeGameplayCam("DRUNK_SHAKE", flashbangConfig.DrunkShakeAmp)
        local startTime = GetGameTimer()
        while GetGameTimer() - startTime < drunkMs do
            local progress = (GetGameTimer() - startTime) / drunkMs
            local amplitudeScale = progress < 0.75 and 1.0 or (1.0 - (progress - 0.75) / 0.25)
            SetGameplayCamShakeAmplitude(flashbangConfig.DrunkShakeAmp * amplitudeScale)
            Wait(0)
        end
        StopGameplayCamShaking(true)
        StopAnimTask(ped, flashbangConfig.FaceAnimDict, flashbangConfig.FaceAnimName, -4.0)
    end)
    if isStunned then
        if flashbangConfig.Disarm then
            SetCurrentPedWeapon(ped, -1569615261, true)
            if Bridge.Inventory.disarm then
                pcall(Bridge.Inventory.disarm, true)
            end
        end
        if flashbangConfig.RagdollEnabled and not IsPedInAnyVehicle(ped, false) then
            SetPedToRagdoll(ped, flashbangConfig.RagdollMs, flashbangConfig.RagdollMs, 0, false, false, false)
        end
        if flashbangConfig.SlowAim then
            self:startSlowAim(durationMs, flashbangConfig.SlowAimScale)
        end
        CreateThread(function()
            while self.flashbang.affected do
                self:disableAimControls()
                Wait(0)
            end
        end)
    end
    CreateThread(function()
        Wait(durationMs)
        AnimpostfxStop("MP_flash")
        SetPedMotionBlur(ped, false)
        self.flashbang.affected = false
    end)
end

RegisterNetEvent("p_policejob/client/grenades/flashbang", function(payload)
    if type(payload) ~= "table" or type(payload.pos) ~= "vector3" then
        return
    end
    if not flashbangConfig.Enabled then
        return
    end
    local ped = cache.ped
    if not DoesEntityExist(ped) or IsEntityDead(ped) then
        return
    end
    local playerCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - payload.pos)
    if distance > flashbangConfig.Radius then
        return
    end
    local isStunned = distance <= flashbangConfig.StunRadius
    if not isStunned and flashbangConfig.RequireLineOfSight then
        local rayHandle = StartShapeTestRay(
            playerCoords.x, playerCoords.y, playerCoords.z + 0.5,
            payload.pos.x, payload.pos.y, payload.pos.z,
            1, ped, 0
        )
        local _, hit = GetShapeTestResult(rayHandle)
        if hit == 1 then
            return
        end
    end
    local falloffRange = math.max(0.001, flashbangConfig.Radius - flashbangConfig.StunRadius)
    local intensity
    if isStunned then
        intensity = 1.0
    else
        intensity = math.max(0.0, math.min(1.0, (flashbangConfig.Radius - distance) / falloffRange))
    end
    local durationMs = math.floor(flashbangConfig.MinDurationMs + (flashbangConfig.MaxDurationMs - flashbangConfig.MinDurationMs) * intensity)
    if isStunned then
        local stunMultiplier = math.max(0.0, 1.0 - distance / flashbangConfig.StunRadius)
        durationMs = math.floor(durationMs * (1.0 + stunMultiplier))
    end
    local facingFlash = isStunned
    if not isStunned then
        local camRot = GetGameplayCamRot(2)
        local yaw = math.rad(-camRot.z)
        local forward = vector3(math.sin(yaw), math.cos(yaw), 0.0)
        local direction = vector3(payload.pos.x - playerCoords.x, payload.pos.y - playerCoords.y, 0.0)
        local directionLength = #direction
        if directionLength > 0.001 then
            direction = direction / directionLength
            facingFlash = (forward.x * direction.x + forward.y * direction.y) > 0.4
        end
    end
    Grenades:applyFlashEffect(intensity, durationMs, isStunned, facingFlash)
end)

function Grenades.ensureSmokeLoop(self)
    if self.smoke.loopRunning then
        return
    end
    self.smoke.loopRunning = true
    CreateThread(function()
        while next(self.smoke.zones) do
            local now = GetGameTimer()
            local ped = cache.ped
            local playerCoords = GetEntityCoords(ped)
            local maxIntensity = 0.0
            for zoneId, zone in pairs(self.smoke.zones) do
                if now >= zone.expiresAt then
                    self.smoke.zones[zoneId] = nil
                else
                    local distance = #(playerCoords - zone.pos)
                    if distance <= zone.radius then
                        local intensity = math.max(0.0, math.min(1.0, (zone.radius - distance) / zone.radius))
                        if intensity > maxIntensity then
                            maxIntensity = intensity
                        end
                    end
                end
            end
            if maxIntensity > 0.0 and not IsEntityDead(ped) then
                if not self.smoke.inside then
                    self.smoke.inside = true
                    SetTimecycleModifier("hud_def_blur_flash")
                end
                SetTimecycleModifierStrength(smokeConfig.BlurStrength * maxIntensity)
                if now - self.smoke.lastCough >= smokeConfig.CoughInterval and not IsPedInAnyVehicle(ped, false) then
                    self.smoke.lastCough = now
                    CreateThread(function()
                        local animDict = "random@arrests"
                        if lib.requestAnimDict(animDict, 1500) then
                            TaskPlayAnim(ped, animDict, "generic_radio_chatter", 4.0, -4.0, 1200, 49, 0, false, false, false)
                        end
                    end)
                end
            elseif self.smoke.inside then
                self.smoke.inside = false
                ClearTimecycleModifier()
            end
            Wait(smokeConfig.TickMs)
        end
        if self.smoke.inside then
            self.smoke.inside = false
            ClearTimecycleModifier()
        end
        self.smoke.loopRunning = false
    end)
end

RegisterNetEvent("p_policejob/client/grenades/smoke", function(payload)
    if type(payload) ~= "table" or type(payload.pos) ~= "vector3" then
        return
    end
    if not smokeConfig.Enabled then
        return
    end
    if smokeConfig.ImmuneAllowedJobs and Grenades:hasJobAccess() then
        return
    end
    local zoneId = ("%d_%d"):format(GetGameTimer(), math.random(1, 1000000))
    Grenades.smoke.zones[zoneId] = {
        pos = payload.pos,
        radius = smokeConfig.Radius,
        expiresAt = GetGameTimer() + smokeConfig.LingerMs,
    }
    Grenades:ensureSmokeLoop()
end)

function Grenades.trackProjectile(self, grenadeConfig, serverEvent, onDetonate)
    if self.inFlight[grenadeConfig.WeaponHash] then
        return
    end
    self.inFlight[grenadeConfig.WeaponHash] = true
    CreateThread(function()
        local projectile = 0
        local searchUntil = GetGameTimer() + 250
        while projectile == 0 and GetGameTimer() < searchUntil do
            projectile = GetClosestObjectOfType(
                GetEntityCoords(cache.ped), 8.0,
                grenadeConfig.ProjectileModel, false, false, false
            )
            if projectile == 0 then
                Wait(20)
            end
        end
        local detonateAt = GetGameTimer() + grenadeConfig.FuseMs
        local position = projectile ~= 0 and GetEntityCoords(projectile) or GetEntityCoords(cache.ped)
        while GetGameTimer() < detonateAt do
            if projectile ~= 0 and DoesEntityExist(projectile) then
                position = GetEntityCoords(projectile)
            end
            Wait(50)
        end
        TriggerServerEvent(serverEvent, position)
        if onDetonate then
            onDetonate(position)
        end
        self.inFlight[grenadeConfig.WeaponHash] = false
    end)
end

function Grenades.watchWeapon(self, grenadeConfig, serverEvent, onDetonate)
    if self.active[grenadeConfig.WeaponHash] then
        return
    end
    if not self:hasJobAccess() then
        return
    end
    self.active[grenadeConfig.WeaponHash] = true
    CreateThread(function()
        while self.active[grenadeConfig.WeaponHash] do
            if IsPedShooting(cache.ped) then
                self:trackProjectile(grenadeConfig, serverEvent, onDetonate)
            end
            Wait(0)
        end
    end)
end

function Grenades.stopWatching(self, grenadeConfig)
    self.active[grenadeConfig.WeaponHash] = nil
end

lib.onCache("weapon", function(weapon)
    if flashbangConfig.Enabled then
        if weapon == flashbangConfig.WeaponHash then
            Grenades:watchWeapon(flashbangConfig, "p_policejob/server/grenades/flashbangDetonate", function(position)
                AddExplosion(position.x, position.y, position.z, 25, 0.0, true, false, 0.6)
            end)
        else
            Grenades:stopWatching(flashbangConfig)
        end
    end
    if smokeConfig.Enabled then
        if weapon == smokeConfig.WeaponHash then
            Grenades:watchWeapon(smokeConfig, "p_policejob/server/grenades/smokeDetonate", nil)
        else
            Grenades:stopWatching(smokeConfig)
        end
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    AnimpostfxStop("MP_flash")
    ClearTimecycleModifier()
    SetPedMotionBlur(cache.ped, false)
    SetPedIsDrunk(cache.ped, false)
    ResetPedMovementClipset(cache.ped, 0.0)
    StopGameplayCamShaking(true)
end)
