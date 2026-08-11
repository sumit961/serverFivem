if not Config.VehicleTracker.Enabled then
    return
end

VehicleTracker = {
    blips = {},
    isTracking = false,
}

function normalizePlate(plate)
    if not plate then
        return nil
    end
    plate = tostring(plate):gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", ""):upper()
    if plate == "" then
        return nil
    end
    return plate
end

function VehicleTracker.hasPoliceAccess(self)
    if not Bridge.Framework.isPlayerLoaded() then
        return false
    end
    local job = Bridge.Framework.fetchPlayerJob()
    if not job then
        return false
    end
    return Config.Jobs[job.name] ~= nil
end

function VehicleTracker.isTrackedVehicle(self, vehicle)
    if not vehicle or vehicle == 0 then
        return false
    end
    local plate = normalizePlate(GetVehicleNumberPlateText(vehicle))
    if not plate then
        return false
    end
    local trackers = GlobalState.p_policejob_vehicleTrackers
    return trackers and trackers[plate] ~= nil
end

function VehicleTracker.getVehicleData(self, vehicle)
    if not vehicle or vehicle == 0 then
        return nil
    end
    local plate = normalizePlate(GetVehicleNumberPlateText(vehicle))
    if not plate then
        return nil
    end
    local trackers = GlobalState.p_policejob_vehicleTrackers
    local trackerData = trackers and trackers[plate] or nil
    return plate, trackerData
end

function VehicleTracker.createBlip(self, plate, trackerData)
    if not trackerData.coords then
        return
    end
    self:removeBlip(plate)
    self.blips[plate] = {}
    local blipConfig = Config.VehicleTracker.Blip
    local coords = trackerData.coords
    local blipEntry = self.blips[plate]
    blipEntry.first = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipScale(blipEntry.first, blipConfig.scale or 0.9)
    SetBlipSprite(blipEntry.first, blipConfig.sprite or 225)
    SetBlipCategory(blipEntry.first, blipConfig.category or 3)
    SetBlipShrink(blipEntry.first, blipConfig.shrink ~= false)
    SetBlipPriority(blipEntry.first, blipConfig.priority or 3)
    ShowHeightOnBlip(blipEntry.first, blipConfig.height or false)
    SetBlipColour(blipEntry.first, blipConfig.color or 5)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString((blipConfig.namePrefix or "Tracker | ") .. (trackerData.plate or plate))
    EndTextCommandSetBlipName(blipEntry.first)
    if blipConfig.pulse then
        blipEntry.second = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blipEntry.second, 161)
        SetBlipScale(blipEntry.second, 1.0)
        SetBlipColour(blipEntry.second, blipConfig.color or 5)
        PulseBlip(blipEntry.second)
    end
    if blipConfig.heading and trackerData.heading then
        ShowHeadingIndicatorOnBlip(blipEntry.first, true)
        SetBlipRotation(blipEntry.first, trackerData.heading)
    end
end

function VehicleTracker.removeBlip(self, plate)
    local blipEntry = self.blips[plate]
    if not blipEntry then
        return
    end
    if blipEntry.first then
        RemoveBlip(blipEntry.first)
    end
    if blipEntry.second then
        RemoveBlip(blipEntry.second)
    end
    self.blips[plate] = nil
end

function VehicleTracker.removeAllBlips(self)
    for plate in pairs(self.blips) do
        self:removeBlip(plate)
    end
end

function VehicleTracker.updateBlips(self)
    local trackers = GlobalState.p_policejob_vehicleTrackers or {}
    local activePlates = {}
    for plate, trackerData in pairs(trackers) do
        if trackerData and trackerData.coords and trackerData.exists ~= false then
            self:createBlip(plate, trackerData)
            activePlates[plate] = true
        end
    end
    for plate in pairs(self.blips) do
        if not activePlates[plate] then
            self:removeBlip(plate)
        end
    end
end

function VehicleTracker.startTracking(self)
    if self.isTracking then
        return
    end
    self.isTracking = true
    CreateThread(function()
        while self.isTracking do
            self:updateBlips()
            Wait(Config.VehicleTracker.LoopRate)
        end
    end)
end

function VehicleTracker.stopTracking(self)
    if not self.isTracking then
        return
    end
    self.isTracking = false
    self:removeAllBlips()
end

function VehicleTracker.useItem(self)
    if not self:hasPoliceAccess() then
        Bridge.Notify.showNotify(locale("no_access"), "error")
        return
    end
    local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), Config.VehicleTracker.InstallDistance, false)
    self:installOnVehicle(vehicle)
end

function VehicleTracker.installOnVehicle(self, vehicle)
    if not vehicle or vehicle == 0 then
        Bridge.Notify.showNotify(locale("vehicle_tracker_not_found"), "error")
        return
    end
    if not NetworkGetEntityIsNetworked(vehicle) then
        Bridge.Notify.showNotify(locale("you_cant_do_it"), "error")
        return
    end
    if self:isTrackedVehicle(vehicle) then
        Bridge.Notify.showNotify(locale("vehicle_tracker_already_on_vehicle"), "error")
        return
    end
    local installConfig = Config.VehicleTracker.Install
    local completed = Bridge.Progress.Start({
        duration = installConfig.duration,
        label = locale("setting_vehicle_tracker"),
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = {
            dict = installConfig.animation.dict,
            clip = installConfig.animation.clip,
        },
    })
    if not completed then
        return
    end
    local plate = normalizePlate(GetVehicleNumberPlateText(vehicle))
    if not plate then
        Bridge.Notify.showNotify(locale("vehicle_tracker_not_found"), "error")
        return
    end
    TriggerServerEvent("p_policejob:vehicleTracker:install", {
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        plate = plate,
    })
    Config.VehicleTracker.onInstall(vehicle, plate)
end

function VehicleTracker.removeByPolice(self, vehicle)
    if not self:hasPoliceAccess() then
        Bridge.Notify.showNotify(locale("no_access"), "error")
        return
    end
    local plate = self:getVehicleData(vehicle)
    if not plate then
        Bridge.Notify.showNotify(locale("vehicle_tracker_not_found"), "error")
        return
    end
    local removeConfig = Config.VehicleTracker.Remove
    local completed = Bridge.Progress.Start({
        duration = removeConfig.duration,
        label = locale("removing_vehicle_tracker"),
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = {
            dict = removeConfig.animation.dict,
            clip = removeConfig.animation.clip,
        },
    })
    if not completed then
        return
    end
    TriggerServerEvent("p_policejob:vehicleTracker:remove", {
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        plate = plate,
        reason = "police",
    })
    Config.VehicleTracker.onRemove(vehicle, plate, "police")
end

function VehicleTracker.removeByHack(self, vehicle)
    if self:hasPoliceAccess() then
        Bridge.Notify.showNotify(locale("you_cant_do_it"), "error")
        return
    end
    if not Config.VehicleTracker.Hack.enabled then
        Bridge.Notify.showNotify(locale("you_cant_do_it"), "error")
        return
    end
    local plate = self:getVehicleData(vehicle)
    if not plate then
        Bridge.Notify.showNotify(locale("vehicle_tracker_not_found"), "error")
        return
    end
    local hackConfig = Config.VehicleTracker.Hack
    local completed = Bridge.Progress.Start({
        duration = hackConfig.duration,
        label = locale("hacking_vehicle_tracker"),
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = {
            dict = hackConfig.animation.dict,
            clip = hackConfig.animation.clip,
        },
    })
    if not completed then
        return
    end
    if not hackConfig.miniGame() then
        Bridge.Notify.showNotify(locale("vehicle_tracker_hack_failed"), "error")
        return
    end
    TriggerServerEvent("p_policejob:vehicleTracker:remove", {
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        plate = plate,
        reason = "hack",
    })
    Config.VehicleTracker.onRemove(vehicle, plate, "hack")
end

function resolveTargetVehicle(target)
    if type(target) == "number" then
        return target
    end
    return target.entity
end

CreateThread(function()
    Bridge.Target.addVehicle({
        {
            name = "vehicle_tracker_install",
            label = locale("install_vehicle_tracker"),
            icon = "fa-solid fa-satellite-dish",
            distance = Config.VehicleTracker.InstallDistance,
            canInteract = function(vehicle)
                if not VehicleTracker:hasPoliceAccess() then
                    return false
                end
                if not vehicle or vehicle == 0 then
                    return false
                end
                if not NetworkGetEntityIsNetworked(vehicle) then
                    return false
                end
                if VehicleTracker:isTrackedVehicle(vehicle) then
                    return false
                end
                return Bridge.Inventory.getItemCount(Config.VehicleTracker.ItemName) >= 1
            end,
            onSelect = function(target)
                VehicleTracker:installOnVehicle(resolveTargetVehicle(target))
            end,
        },
        {
            name = "vehicle_tracker_remove",
            label = locale("remove_vehicle_tracker"),
            icon = "fa-solid fa-circle-minus",
            distance = Config.VehicleTracker.RemoveDistance,
            canInteract = function(vehicle)
                if not VehicleTracker:hasPoliceAccess() then
                    return false
                end
                if not vehicle or vehicle == 0 then
                    return false
                end
                return VehicleTracker:isTrackedVehicle(vehicle)
            end,
            onSelect = function(target)
                VehicleTracker:removeByPolice(resolveTargetVehicle(target))
            end,
        },
        {
            name = "vehicle_tracker_hack_remove",
            label = locale("hack_vehicle_tracker"),
            icon = "fa-solid fa-laptop-code",
            distance = Config.VehicleTracker.RemoveDistance,
            canInteract = function(vehicle)
                if VehicleTracker:hasPoliceAccess() then
                    return false
                end
                if not Config.VehicleTracker.Hack.enabled then
                    return false
                end
                if not vehicle or vehicle == 0 then
                    return false
                end
                return VehicleTracker:isTrackedVehicle(vehicle)
            end,
            onSelect = function(target)
                VehicleTracker:removeByHack(resolveTargetVehicle(target))
            end,
        },
    })
end)

CreateThread(function()
    while true do
        Wait(2500)
        if VehicleTracker:hasPoliceAccess() then
            if not VehicleTracker.isTracking then
                VehicleTracker:startTracking()
            end
        elseif VehicleTracker.isTracking then
            VehicleTracker:stopTracking()
        end
    end
end)

RegisterNetEvent("p_policejob:vehicleTracker:useItem", function()
    VehicleTracker:useItem()
end)

RegisterNetEvent("p_policejob:vehicleTracker:removeBlip", function(data)
    local plate = data and data.plate and normalizePlate(data.plate) or nil
    if plate then
        VehicleTracker:removeBlip(plate)
    end
end)
