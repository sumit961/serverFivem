while not Config or not Config.VehicleRadar do
    Citizen.Wait(500)
end

if not Config.VehicleRadar.enabled then
    return
end

local radarModes = { "BOTH", "SAME", "OPP" }

VehicleRadar = {
    active = false,
    editing = false,
    previewing = false,
    mode = Config.VehicleRadar.DefaultMode or "BOTH",
    locked = { front = nil, rear = nil },
    targets = { front = nil, rear = nil, patrol = 0 },
    lastDist = { front = nil, rear = nil },
    peaks = { front = nil, rear = nil },
}

function cycleRadarMode(currentMode)
    for index, mode in ipairs(radarModes) do
        if mode == currentMode then
            return radarModes[(index % #radarModes) + 1]
        end
    end
    return "BOTH"
end

function playRadarSound(soundName)
    if not soundName or soundName == "" then
        return
    end
    SendNUIMessage({
        action = "playRadarSound",
        data = soundName,
    })
end

function hasRadarAccess()
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

function isAllowedRadarVehicle(vehicle)
    if not Config.VehicleRadar.restrictToAllowedVehicles then
        return true
    end
    if not next(Config.VehicleRadar.AllowedVehicles) then
        return true
    end
    local archetype = GetEntityArchetypeName(vehicle)
    if not archetype then
        local modelHash = GetEntityModel(vehicle)
        for modelName in pairs(Config.VehicleRadar.AllowedVehicles) do
            if GetHashKey(modelName) == modelHash then
                return true
            end
        end
        return false
    end
    return Config.VehicleRadar.AllowedVehicles[string.lower(archetype)] == true
end

function toDisplaySpeed(rawSpeed)
    if Config.VehicleRadar.Unit == "kmh" then
        return rawSpeed * 3.6
    end
    return rawSpeed * 2.236936
end

function trimPlate(plate)
    if not plate then
        return ""
    end
    return plate:gsub("%s+$", ""):gsub("^%s+", "")
end

function scanDirection(patrolVehicle, isFront, mode)
    local patrolCoords = GetEntityCoords(patrolVehicle)
    local forward = GetEntityForwardVector(patrolVehicle)
    local dirX, dirY = forward.x, forward.y
    if not isFront then
        dirX, dirY = -dirX, -dirY
    end
    local maxDistance = Config.VehicleRadar.MaxDistance
    local coneDot = Config.VehicleRadar.ConeDot
    local minFastSpeed = Config.VehicleRadar.MinFastSpeed or 0
    local nearestVehicle, nearestDist, fastestVehicle, fastestDist = nil, nil, nil, nil
    local fastestSpeed = nil
    for _, vehicle in ipairs(GetGamePool("CVehicle")) do
        if vehicle ~= patrolVehicle and DoesEntityExist(vehicle) then
            local vehicleCoords = GetEntityCoords(vehicle)
            local deltaX = vehicleCoords.x - patrolCoords.x
            local deltaY = vehicleCoords.y - patrolCoords.y
            local deltaZ = vehicleCoords.z - patrolCoords.z
            local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)
            if distance > 0.1 and distance <= maxDistance then
                local normX = deltaX / distance
                local normY = deltaY / distance
                local dot = normX * dirX + normY * dirY
                if dot >= coneDot then
                    local directionMatch = true
                    if mode == "SAME" or mode == "OPP" then
                        local targetForward = GetEntityForwardVector(vehicle)
                        local headingDot = targetForward.x * forward.x + targetForward.y * forward.y
                        if mode == "SAME" and headingDot <= 0 then
                            directionMatch = false
                        end
                        if mode == "OPP" and headingDot >= 0 then
                            directionMatch = false
                        end
                    end
                    if directionMatch then
                        if not nearestDist or distance < nearestDist then
                            nearestVehicle = vehicle
                            nearestDist = distance
                        end
                        local speed = toDisplaySpeed(GetEntitySpeed(vehicle))
                        if speed >= minFastSpeed and (not fastestSpeed or speed > fastestSpeed) then
                            fastestVehicle = vehicle
                            fastestDist = distance
                            fastestSpeed = speed
                        end
                    end
                end
            end
        end
    end
    return nearestVehicle, nearestDist, fastestVehicle, fastestDist
end

function buildTargetInfo(vehicle, distance)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end
    local speed = toDisplaySpeed(GetEntitySpeed(vehicle))
    if speed < Config.VehicleRadar.MinTargetSpeed then
        return nil
    end
    return {
        plate = trimPlate(GetVehicleNumberPlateText(vehicle)),
        speed = math.floor(speed + 0.5),
        distance = math.floor((distance or 0) + 0.5),
    }
end

function VehicleRadar.buildSide(self, side, targetVehicle, targetDist, fastVehicle, fastDist)
    local target = buildTargetInfo(targetVehicle, targetDist)
    if not target then
        self.lastDist[side] = nil
        self.peaks[side] = nil
    else
        local peak = self.peaks[side]
        if not peak or peak.plate ~= target.plate then
            peak = { plate = target.plate, speed = target.speed }
        elseif target.speed > peak.speed then
            peak.speed = target.speed
        end
        self.peaks[side] = peak
        target.peak = peak.speed
        local closing = "steady"
        local lastDist = self.lastDist[side]
        if lastDist and targetDist then
            local delta = targetDist - lastDist
            if delta < -0.4 then
                closing = "closing"
            elseif delta > 0.4 then
                closing = "receding"
            end
        end
        target.closing = closing
        self.lastDist[side] = targetDist
    end
    local fast = nil
    local fastTarget = buildTargetInfo(fastVehicle, fastDist)
    if fastTarget then
        local minFastSpeed = Config.VehicleRadar.MinFastSpeed or 0
        if fastTarget.speed >= minFastSpeed then
            if not target or fastTarget.plate ~= target.plate or fastTarget.speed > target.speed then
                fast = fastTarget
            end
        end
    end
    if not target and not fast then
        return nil
    end
    return { tgt = target, fast = fast }
end

function VehicleRadar.sendPreview(self)
    SendNUIMessage({
        action = "setVehicleRadarData",
        data = {
            unit = Config.VehicleRadar.Unit,
            maxDistance = Config.VehicleRadar.MaxDistance,
            mode = self.mode,
            patrol = 38,
            front = {
                tgt = { plate = "ABC1234", speed = 67, distance = 22, closing = "closing", peak = 71 },
                fast = { plate = "ZRX9911", speed = 88, distance = 64 },
            },
            rear = {
                tgt = { plate = "XYZ9876", speed = 31, distance = 48, closing = "receding", peak = 44 },
                fast = nil,
            },
            locked = {
                front = {
                    tgt = { plate = "ABC1234", speed = 67 },
                    fast = { plate = "ZRX9911", speed = 88 },
                },
                rear = nil,
            },
        },
    })
end

function VehicleRadar.sendState(self)
    SendNUIMessage({
        action = "setVehicleRadarData",
        data = {
            unit = Config.VehicleRadar.Unit,
            maxDistance = Config.VehicleRadar.MaxDistance,
            mode = self.mode,
            patrol = self.targets.patrol,
            front = self.targets.front,
            rear = self.targets.rear,
            locked = self.locked,
        },
    })
end

function VehicleRadar.open(self)
    self.active = true
    self.locked = { front = nil, rear = nil }
    self.targets = { front = nil, rear = nil, patrol = 0 }
    self.lastDist = { front = nil, rear = nil }
    self.peaks = { front = nil, rear = nil }
    SendNUIMessage({
        action = "setVisibleVehicleRadar",
        data = true,
    })
    self:sendState()
    playRadarSound(Config.VehicleRadar.Sounds and Config.VehicleRadar.Sounds.powerOn)
    Config.VehicleRadar.onToggleOn()
    self:startThread()
end

function VehicleRadar.close(self)
    if not self.active then
        return
    end
    self.active = false
    self.previewing = false
    self.locked = { front = nil, rear = nil }
    self.targets = { front = nil, rear = nil, patrol = 0 }
    self.lastDist = { front = nil, rear = nil }
    self.peaks = { front = nil, rear = nil }
    SendNUIMessage({
        action = "setVisibleVehicleRadar",
        data = false,
    })
    Config.VehicleRadar.onToggleOff()
end

function VehicleRadar.enterEdit(self)
    if self.editing then
        return
    end
    self.editing = true
    if not self.active then
        self.active = true
        self.previewing = true
        SendNUIMessage({
            action = "setVisibleVehicleRadar",
            data = true,
        })
        self:sendPreview()
    end
    SendNUIMessage({
        action = "setVehicleRadarEdit",
        data = true,
    })
    SetNuiFocus(true, true)
end

function VehicleRadar.exitEdit(self)
    if not self.editing then
        return
    end
    self.editing = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "setVehicleRadarEdit",
        data = false,
    })
    if self.previewing then
        self:close()
    end
end

function VehicleRadar.toggleEdit(self)
    if self.editing then
        self:exitEdit()
    else
        self:enterEdit()
    end
end

function VehicleRadar.toggle(self)
    if self.editing then
        return
    end
    if self.active then
        self:close()
        return
    end
    if not hasRadarAccess() then
        Bridge.Notify.showNotify(locale("no_access"), "error")
        return
    end
    local vehicle = GetVehiclePedIsIn(cache.ped, false)
    if not vehicle or vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= cache.ped then
        Bridge.Notify.showNotify(locale("vehicle_radar_not_in_vehicle"), "error")
        return
    end
    if not isAllowedRadarVehicle(vehicle) then
        Bridge.Notify.showNotify(locale("vehicle_radar_not_in_vehicle"), "error")
        return
    end
    self:open()
end

function VehicleRadar.lock(self, side)
    if self.editing or not self.active then
        return
    end
    if side ~= "front" and side ~= "rear" then
        return
    end
    if self.locked[side] then
        self.locked[side] = nil
        Config.VehicleRadar.onUnlock(side)
        self:sendState()
        return
    end
    local sideData = self.targets[side]
    if not sideData then
        return
    end
    local lockData = {}
    if sideData.tgt then
        lockData.tgt = {
            plate = sideData.tgt.plate,
            speed = sideData.tgt.speed,
        }
    end
    if sideData.fast then
        lockData.fast = {
            plate = sideData.fast.plate,
            speed = sideData.fast.speed,
        }
    end
    if not lockData.tgt and not lockData.fast then
        return
    end
    self.locked[side] = lockData
    playRadarSound(Config.VehicleRadar.Sounds and Config.VehicleRadar.Sounds.lock)
    Config.VehicleRadar.onLock(side, lockData)
    self:sendState()
end

function VehicleRadar.cycleMode(self)
    if not self.active then
        return
    end
    self.mode = cycleRadarMode(self.mode)
    playRadarSound(Config.VehicleRadar.Sounds and Config.VehicleRadar.Sounds.mode)
    self:sendState()
end

function VehicleRadar.startThread(self)
    CreateThread(function()
        while self.active do
            Wait(Config.VehicleRadar.UpdateInterval)
            if not self.previewing then
                local vehicle = GetVehiclePedIsIn(cache.ped, false)
                local isDriver = vehicle
                    and vehicle ~= 0
                    and GetPedInVehicleSeat(vehicle, -1) == cache.ped
                    and isAllowedRadarVehicle(vehicle)
                if not isDriver then
                    if not self.editing then
                        self:close()
                        break
                    end
                else
                    self.targets.patrol = math.floor(toDisplaySpeed(GetEntitySpeed(vehicle)) + 0.5)
                    local frontVehicle, frontDist, frontFastVehicle, frontFastDist = scanDirection(vehicle, true, self.mode)
                    local rearVehicle, rearDist, rearFastVehicle, rearFastDist = scanDirection(vehicle, false, self.mode)
                    self.targets.front = self:buildSide("front", frontVehicle, frontDist, frontFastVehicle, frontFastDist)
                    self.targets.rear = self:buildSide("rear", rearVehicle, rearDist, rearFastVehicle, rearFastDist)
                    self:sendState()
                end
            end
        end
    end)
end

function showVehicleRadarWanted(data)
    if type(data) ~= "table" or not data.plate or data.plate == "" then
        return
    end
    SendNUIMessage({
        action = "setVehicleRadarWanted",
        data = {
            plate = tostring(data.plate),
            reason = tostring(data.reason or ""),
            severity = data.severity or "danger",
            title = data.title,
            duration = data.duration,
        },
    })
end

function hideVehicleRadarWanted()
    SendNUIMessage({
        action = "setVehicleRadarWanted",
        data = nil,
    })
end

exports("isVehicleRadarActive", function()
    return VehicleRadar.active
end)

exports("toggleVehicleRadar", function()
    VehicleRadar:toggle()
end)

exports("lockVehicleRadar", function(side)
    VehicleRadar:lock(side)
end)

exports("cycleVehicleRadarMode", function()
    VehicleRadar:cycleMode()
end)

exports("openVehicleRadarConfig", function()
    VehicleRadar:toggleEdit()
end)

exports("showVehicleRadarWanted", showVehicleRadarWanted)
exports("hideVehicleRadarWanted", hideVehicleRadarWanted)

RegisterCommand("test_wanted", function()
    showVehicleRadarWanted({
        plate = "TEST123",
        reason = "Test wanted alert",
        severity = "warning",
        title = "TEST ALERT",
        duration = 10000,
    })
end)

RegisterNetEvent("p_policejob:vehicle_radar:wanted", showVehicleRadarWanted)
RegisterNetEvent("p_policejob:vehicle_radar:wanted:clear", hideVehicleRadarWanted)

lib.addKeybind({
    name = "vehicle_radar_toggle",
    description = locale("toggle_police_radar"),
    defaultKey = Config.VehicleRadar.Keys.toggle,
    onPressed = function()
        VehicleRadar:toggle()
    end,
})

lib.addKeybind({
    name = "vehicle_radar_lock_front",
    description = locale("lock_front_radar"),
    defaultKey = Config.VehicleRadar.Keys.lockFront,
    onPressed = function()
        VehicleRadar:lock("front")
    end,
})

lib.addKeybind({
    name = "vehicle_radar_lock_rear",
    description = locale("lock_rear_radar"),
    defaultKey = Config.VehicleRadar.Keys.lockRear,
    onPressed = function()
        VehicleRadar:lock("rear")
    end,
})

lib.addKeybind({
    name = "vehicle_radar_cycle_mode",
    description = locale("cycle_radar_mode"),
    defaultKey = Config.VehicleRadar.Keys.cycleMode,
    onPressed = function()
        VehicleRadar:cycleMode()
    end,
})

if Config.VehicleRadar.EditCommand and Config.VehicleRadar.EditCommand ~= "" then
    RegisterCommand(Config.VehicleRadar.EditCommand, function()
        VehicleRadar:toggleEdit()
    end, false)
end

RegisterNUICallback("VehicleRadarExitEdit", function(_, cb)
    VehicleRadar:exitEdit()
    cb("ok")
end)

AddEventHandler("baseevents:leftVehicle", function()
    if VehicleRadar.active and not VehicleRadar.editing then
        VehicleRadar:close()
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end
    if VehicleRadar.editing then
        SetNuiFocus(false, false)
    end
    if VehicleRadar.active then
        SendNUIMessage({
            action = "setVisibleVehicleRadar",
            data = false,
        })
    end
end)
