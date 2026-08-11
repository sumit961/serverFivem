Vehicles = {}

local vehicleClassKeys = {
    [0] = "compacts",
    [1] = "sedans",
    [2] = "suvs",
    [3] = "coupes",
    [4] = "muscle",
    [5] = "sports_classics",
    [6] = "sports",
    [7] = "super",
    [8] = "motorcycles",
    [9] = "off_road",
    [10] = "industrial",
    [11] = "utility",
    [12] = "vans",
    [13] = "cycles",
    [14] = "boats",
    [15] = "helicopters",
    [16] = "planes",
    [17] = "service",
    [18] = "emergency",
    [19] = "military",
    [20] = "commercial",
    [21] = "trains",
}

function Vehicles.ensureClasses(self)
    if self.classes then
        return
    end
    self.classes = {}
    for classId, localeKey in pairs(vehicleClassKeys) do
        self.classes[classId] = locale(localeKey)
    end
end

function Vehicles.sort(self, vehicleList)
    self:ensureClasses()
    local sortedVehicles = {}

    for index, vehicle in ipairs(vehicleList) do
        local displayName = GetDisplayNameFromVehicleModel(vehicle.model)
        local labelText = GetLabelText(displayName)
        vehicle.label = (labelText ~= "NULL" and labelText) or displayName
        vehicle.class = self.classes[GetVehicleClassFromName(vehicle.model)] or locale("no_data")
        sortedVehicles[index] = vehicle
    end

    return sortedVehicles
end

RegisterNUICallback("mdt/vehicles/search", function(data, cb)
    if data.query:len() < 1 then
        cb({})
        return
    end

    local vehicles = lib.callback.await("p_mdt/server/vehicles/search", false, data)
    cb(Vehicles:sort(vehicles))
end)

RegisterNUICallback("mdt/vehicles/getProfile", function(data, cb)
    local profile = lib.callback.await("p_mdt/server/vehicles/getProfile", false, data)

    for _, metadata in pairs(profile.metadata or {}) do
        if metadata.isModel then
            local displayName = GetDisplayNameFromVehicleModel(metadata.value)
            local labelText = GetLabelText(displayName)
            metadata.value = (labelText ~= "NULL" and labelText) or displayName
        end
    end

    cb(profile)
end)

RegisterNUICallback("mdt/vehicle/createNote", function(data, cb)
    TriggerServerEvent("p_mdt/server/vehicle/createNote", data)
    cb(1)
end)

RegisterNUICallback("mdt/vehicle/changeAvatar", function(data, cb)
    TriggerServerEvent("p_mdt/server/vehicle/changeAvatar", data)
    cb(1)
end)

RegisterNUICallback("mdt/vehicle/addPhoto", function(data, cb)
    TriggerServerEvent("p_mdt/server/vehicle/addPhoto", data)
    cb(1)
end)

RegisterNUICallback("mdt/vehicles/deletePhoto", function(data, cb)
    TriggerServerEvent("p_mdt/server/vehicle/deletePhoto", data)
    cb(1)
end)

RegisterNUICallback("mdt/vehicle/deleteNote", function(data, cb)
    TriggerServerEvent("p_mdt/server/vehicle/deleteNote", data)
    cb(1)
end)
