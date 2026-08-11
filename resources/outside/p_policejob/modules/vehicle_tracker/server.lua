if not Config.VehicleTracker.Enabled then
    return
end

VehicleTracker = {
    trackedVehicles = {},
}

GlobalState.p_policejob_vehicleTrackers = VehicleTracker.trackedVehicles

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

function VehicleTracker.hasPoliceAccess(self, playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job then
        return false
    end
    local minGrade = Config.Jobs[job.name]
    if minGrade == nil then
        return false
    end
    local grade = tonumber(job.grade) or 0
    return minGrade <= grade
end

function VehicleTracker.getVehicleByPlate(self, plate)
    local vehicles = GetAllVehicles()
    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if normalizePlate(GetVehicleNumberPlateText(vehicle)) == plate then
            return vehicle
        end
    end
    return 0
end

function VehicleTracker.getVehicleEntity(self, netId, plate)
    local vehicle = 0
    if netId then
        vehicle = NetworkGetEntityFromNetworkId(netId)
    end
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        return vehicle
    end
    return self:getVehicleByPlate(plate)
end

function VehicleTracker.isPlayerNearVehicle(self, playerId, vehicle, maxDistance)
    if not vehicle or vehicle == 0 then
        return false
    end
    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 then
        return false
    end
    local playerCoords = GetEntityCoords(ped)
    local vehicleCoords = GetEntityCoords(vehicle)
    local distance = #(playerCoords - vehicleCoords)
    return distance <= (maxDistance or 4.0)
end

function VehicleTracker.updateGlobalState(self)
    GlobalState.p_policejob_vehicleTrackers = self.trackedVehicles
end

function VehicleTracker.install(self, playerId, data)
    if not self:hasPoliceAccess(playerId) then
        Bridge.Notify.showNotify(playerId, locale("no_access"), "error")
        return
    end
    local vehicle = self:getVehicleEntity(data.netId, data.plate)
    if vehicle == 0 then
        Bridge.Notify.showNotify(playerId, locale("vehicle_tracker_not_found"), "error")
        return
    end
    if not self:isPlayerNearVehicle(playerId, vehicle, Config.VehicleTracker.InstallDistance) then
        Bridge.Notify.showNotify(playerId, locale("you_cant_do_it"), "error")
        return
    end
    local plate = normalizePlate(GetVehicleNumberPlateText(vehicle))
    if not plate then
        Bridge.Notify.showNotify(playerId, locale("vehicle_tracker_not_found"), "error")
        return
    end
    if self.trackedVehicles[plate] then
        Bridge.Notify.showNotify(playerId, locale("vehicle_tracker_already_on_vehicle"), "error")
        return
    end
    Bridge.Inventory.removeItem(playerId, Config.VehicleTracker.ItemName, 1)
    local coords = GetEntityCoords(vehicle)
    local heading = nil
    if Config.VehicleTracker.Blip.heading then
        heading = GetEntityHeading(vehicle)
    end
    self.trackedVehicles[plate] = {
        plate = plate,
        netId = NetworkGetNetworkIdFromEntity(vehicle),
        coords = vector3(coords.x, coords.y, coords.z),
        heading = heading,
        exists = true,
    }
    Entity(vehicle).state:set("hasVehicleTracker", true, true)
    self:updateGlobalState()
    Bridge.Notify.showNotify(playerId, locale("vehicle_tracker_installed"), "success")
    Bridge.Logs.Send(playerId, "VehicleTracker", ("Installed vehicle tracker on %s"):format(plate), Config.Webhooks.interactions)
    Config.VehicleTracker.onInstall_Server(playerId, plate)
    Bridge.Debug(("[VehicleTracker] Player %s installed tracker on %s"):format(playerId, plate))
end

function VehicleTracker.remove(self, playerId, data)
    local reason = data.reason or "police"
    if reason == "police" and not self:hasPoliceAccess(playerId) then
        Bridge.Notify.showNotify(playerId, locale("no_access"), "error")
        return
    end
    local plate = normalizePlate(data.plate)
    if not plate or not self.trackedVehicles[plate] then
        Bridge.Notify.showNotify(playerId, locale("vehicle_tracker_not_found"), "error")
        return
    end
    local trackerData = self.trackedVehicles[plate]
    local vehicle = self:getVehicleEntity(data.netId or trackerData.netId, plate)
    if vehicle ~= 0 then
        if not self:isPlayerNearVehicle(playerId, vehicle, Config.VehicleTracker.RemoveDistance) then
            Bridge.Notify.showNotify(playerId, locale("you_cant_do_it"), "error")
            return
        end
    end
    if vehicle ~= 0 then
        Entity(vehicle).state:set("hasVehicleTracker", false, true)
    end
    self.trackedVehicles[plate] = nil
    self:updateGlobalState()
    if reason == "police" and Config.VehicleTracker.ReturnItemOnPoliceRemove then
        Bridge.Inventory.addItem(playerId, Config.VehicleTracker.ItemName, 1)
    end
    if reason == "hack" then
        Bridge.Notify.showNotify(playerId, locale("vehicle_tracker_removed"), "success")
        for _, player in ipairs(GetPlayers()) do
            local targetId = tonumber(player)
            if targetId and self:hasPoliceAccess(targetId) then
                Bridge.Notify.showNotify(
                    targetId,
                    ("%s (%s)"):format(locale("vehicle_tracker_hack_alert"), plate),
                    "error"
                )
            end
        end
    else
        Bridge.Notify.showNotify(playerId, locale("vehicle_tracker_removed"), "success")
    end
    TriggerClientEvent("p_policejob:vehicleTracker:removeBlip", -1, { plate = plate })
    Bridge.Logs.Send(
        playerId,
        "VehicleTracker",
        ("Removed vehicle tracker from %s (%s)"):format(plate, reason),
        Config.Webhooks.interactions
    )
    Config.VehicleTracker.onRemove_Server(playerId, plate, reason)
    Bridge.Debug(("[VehicleTracker] Player %s removed tracker from %s (%s)"):format(playerId, plate, reason))
end

function VehicleTracker.updateCoords(self)
    local changed = false
    for plate, trackerData in pairs(self.trackedVehicles) do
        local vehicle = self:getVehicleEntity(trackerData.netId, plate)
        if vehicle ~= 0 and DoesEntityExist(vehicle) then
            local coords = GetEntityCoords(vehicle)
            trackerData.coords = vector3(coords.x, coords.y, coords.z)
            trackerData.netId = NetworkGetNetworkIdFromEntity(vehicle)
            trackerData.exists = true
            if Config.VehicleTracker.Blip.heading then
                trackerData.heading = GetEntityHeading(vehicle)
            end
            Entity(vehicle).state:set("hasVehicleTracker", true, true)
            changed = true
        else
            trackerData.exists = false
            changed = true
        end
    end
    if changed then
        self:updateGlobalState()
    end
end

exports("SetVehicleTracker", function(playerId, netId, plate, state)
    if state then
        VehicleTracker:install(playerId, { netId = netId, plate = plate })
    else
        VehicleTracker:remove(playerId, { netId = netId, plate = plate, reason = "police" })
    end
end)

exports("HasVehicleTracker", function(plate)
    plate = normalizePlate(plate)
    if plate then
        return VehicleTracker.trackedVehicles[plate] ~= nil
    end
    return false
end)

exports("GetTrackedVehicles", function()
    return VehicleTracker.trackedVehicles
end)

exports("tracking_vehicle", function(event, item, inventory, slot, data)
    if event == "usingItem" then
        TriggerClientEvent("p_policejob:vehicleTracker:useItem", inventory.id)
    end
end)

RegisterNetEvent("p_policejob:vehicleTracker:install", function(data)
    VehicleTracker:install(source, data or {})
end)

RegisterNetEvent("p_policejob:vehicleTracker:remove", function(data)
    VehicleTracker:remove(source, data or {})
end)

CreateThread(function()
    Wait(1000)
    while not Bridge or not Bridge.Framework do
        Wait(500)
    end
end)

CreateThread(function()
    while true do
        Wait(Config.VehicleTracker.UpdateCoordsRate)
        VehicleTracker:updateCoords()
    end
end)
