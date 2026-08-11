while not Config or not Config.Extras do
    Citizen.Wait(1)
end

if not Config.Extras.enabled then
    return
end

Extras = {
    inZone = false,
    currentVehicle = nil,
    cameraUnlocked = false,
    antiSpam = GetGameTimer(),
}

function Extras.hasAccess(self)
    local job = Bridge.Framework.fetchPlayerJob()
    return job and Config.Jobs[job.name] ~= nil
end

function Extras.getVehicleExtras(self, vehicle)
    local extras = {}
    for extraId = 0, 20 do
        if DoesExtraExist(vehicle, extraId) then
            extras[#extras + 1] = {
                id = extraId,
                enabled = IsVehicleExtraTurnedOn(vehicle, extraId),
            }
        end
    end
    return extras
end

function Extras.getVehicleLiveries(self, vehicle)
    local liveries = {}
    local liveryCount = GetVehicleLiveryCount(vehicle)
    if liveryCount <= 0 then
        return liveries
    end
    local currentLivery = GetVehicleLivery(vehicle)
    for liveryId = 0, liveryCount - 1 do
        local label = GetLiveryName(vehicle, liveryId)
        if label and label ~= "" and label ~= "NULL" then
            local localized = GetLabelText(label)
            if localized and localized ~= "" and localized ~= "NULL" then
                label = localized
            else
                label = nil
            end
        else
            label = nil
        end
        liveries[#liveries + 1] = {
            id = liveryId,
            label = label or ("Livery #" .. (liveryId + 1)),
            active = currentLivery == liveryId,
        }
    end
    return liveries
end

function Extras.getVehicleModLiveries(self, vehicle)
    local liveries = {}
    local modCount = GetNumVehicleMods(vehicle, 48)
    if modCount <= 0 then
        return liveries
    end
    local currentMod = GetVehicleMod(vehicle, 48)
    for modId = 0, modCount - 1 do
        local label = GetModTextLabel(vehicle, 48, modId)
        if label and label ~= "" and label ~= "NULL" then
            local localized = GetLabelText(label)
            if localized and localized ~= "" and localized ~= "NULL" then
                label = localized
            else
                label = nil
            end
        else
            label = nil
        end
        liveries[#liveries + 1] = {
            id = modId,
            label = label or ("Livery #" .. (modId + 1)),
            active = currentMod == modId,
        }
    end
    return liveries
end

function Extras.getVehicleMods(self, vehicle)
    local mods = {}
    for _, modConfig in ipairs(Config.Extras.mods) do
        local modType = modConfig.modType
        local modCount = GetNumVehicleMods(vehicle, modType)
        if modCount > 0 then
            local currentMod = GetVehicleMod(vehicle, modType)
            local options = {
                {
                    index = -1,
                    label = "Stock",
                    active = currentMod == -1,
                },
            }
            for modIndex = 0, modCount - 1 do
                local label = GetModTextLabel(vehicle, modType, modIndex)
                if not label or label == "" or label == "NULL" then
                    label = modConfig.label .. " #" .. (modIndex + 1)
                end
                options[#options + 1] = {
                    index = modIndex,
                    label = label,
                    active = currentMod == modIndex,
                }
            end
            mods[#mods + 1] = {
                modType = modType,
                label = modConfig.label,
                current = currentMod,
                options = options,
            }
        end
    end
    return mods
end

function Extras.fetchVehicleData(self, vehicle)
    SetVehicleModKit(vehicle, 0)
    return {
        extras = self:getVehicleExtras(vehicle),
        liveries = self:getVehicleLiveries(vehicle),
        modLiveries = self:getVehicleModLiveries(vehicle),
        mods = self:getVehicleMods(vehicle),
    }
end

function Extras.openMenu(self)
    if self.antiSpam > GetGameTimer() then
        return
    end
    if not self:hasAccess() then
        return
    end
    local vehicle = cache.vehicle
    if not vehicle or not DoesEntityExist(vehicle) then
        Bridge.Notify.showNotify("No vehicle nearby", "error")
        return
    end
    self.currentVehicle = vehicle
    self.cameraUnlocked = false
    local vehicleData = self:fetchVehicleData(vehicle)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "setExtrasCameraKeybind",
        data = Config.Extras.CameraKeybind,
    })
    SendNUIMessage({ action = "setVisibleExtras", data = true })
    SendNUIMessage({ action = "setExtrasData", data = vehicleData })
end

function Extras.toggleCamera(self)
    if self.antiSpam > GetGameTimer() or not self.currentVehicle then
        return
    end
    self.antiSpam = GetGameTimer() + 100
    self.cameraUnlocked = not self.cameraUnlocked
    SetNuiFocus(not self.cameraUnlocked, not self.cameraUnlocked)
    SendNUIMessage({
        action = "setExtrasCameraState",
        data = self.cameraUnlocked,
    })
end

RegisterNUICallback("extras/toggleExtra", function(data, cb)
    if Extras.currentVehicle and DoesEntityExist(Extras.currentVehicle) then
        SetVehicleExtra(Extras.currentVehicle, data.id, not data.enabled)
        cb(Extras:fetchVehicleData(Extras.currentVehicle))
    else
        cb({})
    end
end)

RegisterNUICallback("extras/setLivery", function(data, cb)
    if Extras.currentVehicle and DoesEntityExist(Extras.currentVehicle) then
        SetVehicleLivery(Extras.currentVehicle, data.id)
        cb(Extras:fetchVehicleData(Extras.currentVehicle))
    else
        cb({})
    end
end)

RegisterNUICallback("extras/setModLivery", function(data, cb)
    if Extras.currentVehicle and DoesEntityExist(Extras.currentVehicle) then
        SetVehicleMod(Extras.currentVehicle, 48, data.id, false)
        cb(Extras:fetchVehicleData(Extras.currentVehicle))
    else
        cb({})
    end
end)

RegisterNUICallback("extras/setMod", function(data, cb)
    if Extras.currentVehicle and DoesEntityExist(Extras.currentVehicle) then
        SetVehicleMod(Extras.currentVehicle, data.modType, data.index, false)
        cb(Extras:fetchVehicleData(Extras.currentVehicle))
    else
        cb({})
    end
end)

RegisterNUICallback("hideFrame", function(data, cb)
    if data.name == "setVisibleExtras" then
        SendNUIMessage({ action = "setVisibleExtras", data = false })
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        Extras.cameraUnlocked = false
        Extras.currentVehicle = nil
        Extras.antiSpam = GetGameTimer() + 1000
    end
    cb("ok")
end)

for _, zoneConfig in ipairs(Config.DepartmentData.extras or {}) do
    local point = lib.points.new({
        coords = zoneConfig.coords,
        distance = zoneConfig.size,
    })
    point.textShown = false

    point.onEnter = function()
        Extras.inZone = true
    end

    point.onExit = function(pointRef)
        Extras.inZone = false
        if pointRef.textShown then
            lib.hideTextUI()
            pointRef.textShown = false
        end
    end

    point.nearby = function(pointRef)
        local canOpen = cache.vehicle and Extras:hasAccess()
        if canOpen then
            if not pointRef.textShown then
                lib.showTextUI("[E] " .. (zoneConfig.label or "Vehicle Extras"))
                pointRef.textShown = true
            end
        elseif pointRef.textShown then
            lib.hideTextUI()
            pointRef.textShown = false
        end
        if canOpen and IsControlJustPressed(0, 38) then
            Extras:openMenu()
        end
    end
end

lib.addKeybind({
    name = "extras_camera_toggle",
    description = "Toggle camera movement in extras menu",
    defaultKey = Config.Extras.CameraKeybind,
    defaultMapper = "keyboard",
    onPressed = function()
        Extras:toggleCamera()
    end,
})

RegisterNUICallback("extras/toggleCamera", function(_, cb)
    Extras:toggleCamera()
    cb("ok")
end)
