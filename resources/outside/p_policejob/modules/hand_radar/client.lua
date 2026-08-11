while not Config or not Config.HandRadar do
    Citizen.Wait(500)
end

if not Config.HandRadar.enabled then
    return
end

HandRadar = {
    active = false,
    dui = nil,
    scaleform = nil,
    target = nil,
    locked = false,
    snapshot = nil,
    calmedPed = nil,
}

function HandRadar.hasJobAccess(self)
    if not Config.Jobs then
        return true
    end
    local job = Bridge.Framework.fetchPlayerJob and Bridge.Framework.fetchPlayerJob()
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

function HandRadar.convertSpeed(self, speed)
    if Config.HandRadar.Unit == "kmh" then
        return speed * 3.6
    end
    return speed * 2.236936
end

function HandRadar.getUnitLabel(self)
    if Config.HandRadar.Unit == "kmh" then
        return "KMH"
    end
    return "MPH"
end

function HandRadar.formatPlate(self, vehicle)
    local plate = vehicle and GetVehicleNumberPlateText(vehicle) or ""
    plate = (plate or ""):gsub("%s+$", "")
    if plate == "" or not plate then
        return "--------"
    end
    return plate
end

function HandRadar.buildUpdatePayload(self)
    local unit = self:getUnitLabel()
    if self.locked and self.snapshot then
        return {
            action = "update",
            target = true,
            locked = true,
            speed = self.snapshot.speed,
            plate = self.snapshot.plate,
            unit = unit,
        }
    end
    local target = self.target
    if not target or not DoesEntityExist(target) then
        return {
            action = "update",
            target = false,
            locked = false,
            unit = unit,
        }
    end
    return {
        action = "update",
        target = true,
        locked = false,
        speed = math.floor(self:convertSpeed(GetEntitySpeed(target)) + 0.5),
        plate = self:formatPlate(target),
        unit = unit,
    }
end

function HandRadar.sendDuiUpdate(self)
    if self.dui then
        self.dui:sendMessage(self:buildUpdatePayload())
    end
end

function HandRadar.setupDui(self)
    if self.dui then
        return
    end
    self.dui = lib.dui.new({
        url = ("nui://%s/web/handradar.html"):format(GetCurrentResourceName()),
        width = 512,
        height = 256,
    })
    local scaleform = RequestScaleformMovie("hand_radar_texture")
    while not HasScaleformMovieLoaded(scaleform) do
        Wait(0)
    end
    BeginScaleformMovieMethod(scaleform, "SET_TEXTURE")
    ScaleformMovieMethodAddParamTextureNameString(self.dui.dictName)
    ScaleformMovieMethodAddParamTextureNameString(self.dui.txtName)
    ScaleformMovieMethodAddParamInt(0)
    ScaleformMovieMethodAddParamInt(0)
    ScaleformMovieMethodAddParamInt(512)
    ScaleformMovieMethodAddParamInt(256)
    EndScaleformMovieMethod()
    self.scaleform = scaleform
end

function HandRadar.getWeaponDuiPosition(self)
    local weaponEntity = GetCurrentPedWeaponEntityIndex(cache.ped)
    if not weaponEntity or weaponEntity == 0 or not DoesEntityExist(weaponEntity) then
        return nil
    end
    local offset = Config.HandRadar.Dui.offset
    return GetOffsetFromEntityInWorldCoords(weaponEntity, 0.0, offset.forward, offset.up)
end

function HandRadar.toggleLock(self)
    if not self.active then
        return
    end
    if self.locked then
        self.locked = false
        self.snapshot = nil
    elseif self.target and DoesEntityExist(self.target) then
        self.snapshot = {
            speed = math.floor(self:convertSpeed(GetEntitySpeed(self.target)) + 0.5),
            plate = self:formatPlate(self.target),
        }
        self.locked = true
    end
    self:sendDuiUpdate()
end

function HandRadar.startDrawLoop(self)
    local duiConfig = Config.HandRadar.Dui
    CreateThread(function()
        while self.active do
            Wait(0)
            if self.scaleform and IsPlayerFreeAiming(PlayerId()) then
                local position = self:getWeaponDuiPosition()
                if position then
                    local camCoord = GetFinalRenderedCamCoord()
                    if #(position - camCoord) <= duiConfig.maxDistance then
                        local rotation
                        if duiConfig.faceCam then
                            rotation = GetGameplayCamRot(2) or vector3(0.0, 0.0, GetEntityHeading(cache.ped))
                        else
                            rotation = vector3(0.0, 0.0, GetEntityHeading(cache.ped))
                        end
                        DrawScaleformMovie_3dNonAdditive(
                            self.scaleform,
                            position.x, position.y, position.z,
                            rotation.x, rotation.y, rotation.z,
                            1.0, 1.0, 1.0,
                            duiConfig.scale.x, duiConfig.scale.y, duiConfig.scale.z,
                            0
                        )
                    end
                end
            end
        end
    end)
end

function HandRadar.updateCalmedPed(self, vehicle)
    local driver = 0
    if vehicle and DoesEntityExist(vehicle) then
        driver = GetPedInVehicleSeat(vehicle, -1) or 0
    end
    if driver == self.calmedPed then
        return
    end
    if self.calmedPed and DoesEntityExist(self.calmedPed) then
        SetBlockingOfNonTemporaryEvents(self.calmedPed, false)
    end
    self.calmedPed = nil
    if driver ~= 0 and DoesEntityExist(driver) and not IsPedAPlayer(driver) then
        SetBlockingOfNonTemporaryEvents(driver, true)
        self.calmedPed = driver
    end
end

function HandRadar.getCameraForwardVector(self)
    local camRot = GetFinalRenderedCamRot(2)
    local pitch = math.rad(camRot.x)
    local yaw = math.rad(camRot.z)
    local cosPitch = math.abs(math.cos(pitch))
    return vector3(-math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch))
end

function HandRadar.findTargetVehicle(self)
    local camCoord = GetFinalRenderedCamCoord()
    local forward = self:getCameraForwardVector()
    local maxDistance = Config.HandRadar.AimDistance
    local coneThreshold = math.cos(math.rad(Config.HandRadar.AimCone or 5.0))
    local bestVehicle, bestDot
    for _, vehicle in ipairs(GetGamePool("CVehicle")) do
        local offset = GetEntityCoords(vehicle) - camCoord
        local distance = #offset
        if distance > 1.0 and distance <= maxDistance then
            local dot = (offset.x * forward.x + offset.y * forward.y + offset.z * forward.z) / distance
            if dot >= coneThreshold and (not bestDot or bestDot < dot) then
                bestVehicle = vehicle
                bestDot = dot
            end
        end
    end
    return bestVehicle
end

function HandRadar.startTargetLoop(self)
    CreateThread(function()
        while self.active do
            local waitTime = 250
            if not self.locked then
                if IsPlayerFreeAiming(PlayerId()) then
                    waitTime = 0
                    self.target = self:findTargetVehicle()
                else
                    self.target = nil
                end
                self:updateCalmedPed(self.target)
                self:sendDuiUpdate()
            end
            Wait(waitTime)
        end
    end)
end

function HandRadar.startControlLoop(self)
    CreateThread(function()
        while self.active do
            Wait(0)
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 69, true)
            DisableControlAction(0, 70, true)
            DisableControlAction(0, 92, true)
            DisableControlAction(0, 114, true)
            DisableControlAction(0, 331, true)
            if IsDisabledControlJustPressed(0, 24) then
                self:toggleLock()
            end
        end
    end)
end

function HandRadar.activate(self)
    if self.active then
        return
    end
    if not self:hasJobAccess() then
        Bridge.Notify.showNotify(locale("no_access"), "error")
        return
    end
    self.active = true
    self.target = nil
    self.locked = false
    self.snapshot = nil
    SetEveryoneIgnorePlayer(PlayerId(), true)
    self:setupDui()
    self:sendDuiUpdate()
    self:startControlLoop()
    self:startDrawLoop()
    self:startTargetLoop()
end

function HandRadar.deactivate(self)
    if not self.active then
        return
    end
    self.active = false
    self.target = nil
    self.locked = false
    self.snapshot = nil
    self:updateCalmedPed(nil)
    SetEveryoneIgnorePlayer(PlayerId(), false)
    self:sendDuiUpdate()
end

lib.onCache("weapon", function(weapon)
    if weapon == Config.HandRadar.Weapon then
        HandRadar:activate()
    else
        HandRadar:deactivate()
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    if HandRadar.scaleform then
        SetScaleformMovieAsNoLongerNeeded(HandRadar.scaleform)
        HandRadar.scaleform = nil
    end
    if HandRadar.dui then
        HandRadar.dui:remove()
        HandRadar.dui = nil
    end
end)
