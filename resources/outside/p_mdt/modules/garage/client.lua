Garages = {
    currentPoint = nil,
    spawnedVehicles = {},
    antiSpam = GetGameTimer(),
}

function Garages.ensureData(self)
    if not self.points then
        self.points = lib.load("data.garages")
        self.vehiclesData = lib.load("data.vehicles")
    end
end

function Garages.getModelLabel(self, model)
    local displayName = GetDisplayNameFromVehicleModel(model)
    local label = GetLabelText(displayName)
    if label == "NULL" then
        label = displayName
    end
    return label
end

function Garages.sortVehicles(self, vehicles)
    local sorted = {}
    local job = Bridge.Framework.fetchPlayerJob()

    for index, entry in ipairs(vehicles) do
        local vehicle = entry.vehicle
        local modelKey = string.lower(GetDisplayNameFromVehicleModel(vehicle.model))

        if Bridge and Bridge.Config and Bridge.Config.Debug then
            print(modelKey, vehicle.model, self.vehiclesData[job and job.name or nil] and self.vehiclesData[job.name][modelKey] and self.vehiclesData[job.name][modelKey].image)
        end

        local item = {
            id = entry.id,
            model = modelKey,
            label = entry.label or self:getModelLabel(vehicle.model),
            vehicle = vehicle,
            plate = vehicle.plate,
            status = entry.status,
            officer = entry.officer or nil,
            imageUrl = (self.vehiclesData[job and job.name or nil] and self.vehiclesData[job.name][modelKey] and self.vehiclesData[job.name][modelKey].image)
                or ("https://docs.fivem.net/vehicles/%s.webp"):format(vehicle.model),
            info = {
                engine = math.floor(vehicle.engineHealth / 10),
                body = math.floor(vehicle.bodyHealth / 10),
                fuel = math.floor(vehicle.fuelLevel),
                impoundPrice = (self.vehiclesData[job and job.name or nil] and self.vehiclesData[job.name][modelKey] and self.vehiclesData[job.name][modelKey].impoundPrice) or 0,
            },
            grades = entry.grades or {},
            officers = entry.officers or {},
        }

        sorted[index] = item
    end

    return sorted
end

RegisterNUICallback("mdt/garage/fetch", function(data, cb)
    local result = lib.callback.await("p_mdt/server/garage/fetch", false)
    if result.vehicles then
        result.vehicles = Garages:sortVehicles(result.vehicles)
    end
    cb(result)
end)

RegisterNUICallback("mdt/garage/buyVehicle", function(data, cb)
    cb(lib.callback.await("p_mdt/server/garage/buyVehicle", false, data))
end)

RegisterNUICallback("mdt/garage/edit", function(data, cb)
    cb(lib.callback.await("p_mdt/server/garage/editVehiclePermissions", false, data))
end)

RegisterNUICallback("mdt/garage/impound", function(data, cb)
    cb(lib.callback.await("p_mdt/server/garage/impound", false, data))
end)

RegisterNUICallback("mdt/garage/mark", function(data, cb)
    local coords = lib.callback.await("p_mdt/server/garage/getVehicleLocation", false, data)
    if coords then
        SetNewWaypoint(coords.x, coords.y)
        Bridge.Notify.showNotify(locale("gps_set_to_vehicle"), "success")
    else
        Bridge.Notify.showNotify(locale("cannot_find_vehicle"), "error")
    end
    cb(1)
end)

function Garages.getFreeSpawnPoint(self, spawnPoints)
    for _, point in pairs(spawnPoints) do
        local nearby = lib.getNearbyVehicles(vec3(point.x, point.y, point.z), 1.5, false)
        if #nearby == 0 then
            return point
        end
    end
    return nil
end

function Garages.init(self)
    self:ensureData()
    for jobName, jobPoints in pairs(self.points) do
        for pointIndex, point in pairs(jobPoints) do
            local pointRef = lib.points.new({
                coords = vec3(point.ped.coords.x, point.ped.coords.y, point.ped.coords.z),
                distance = 30.0,
            })

            pointRef.onEnter = function(zone)
                local model = lib.requestModel(point.ped.model)
                zone.ped = CreatePed(
                    4, model,
                    point.ped.coords.x, point.ped.coords.y, point.ped.coords.z - 1.0,
                    point.ped.coords.w,
                    false, true
                )
                SetEntityInvincible(zone.ped, true)
                SetBlockingOfNonTemporaryEvents(zone.ped, true)
                FreezeEntityPosition(zone.ped, true)

                if point.ped.anim then
                    if point.ped.anim.dict then
                        lib.requestAnimDict(point.ped.anim.dict)
                        TaskPlayAnim(
                            zone.ped, point.ped.anim.dict, point.ped.anim.clip,
                            8.0, -8.0, -1, 1, 0, false, false, false
                        )
                    elseif point.ped.anim.scenario then
                        TaskStartScenarioInPlace(zone.ped, point.ped.anim.scenario, 0, true)
                    end
                end

                SetModelAsNoLongerNeeded(model)
            end

            pointRef.onExit = function(zone)
                if zone.ped and DoesEntityExist(zone.ped) then
                    DeleteEntity(zone.ped)
                end
                zone.ped = nil
            end

            Bridge.Target.addSphereZone({
                coords = vec3(point.ped.coords.x, point.ped.coords.y, point.ped.coords.z),
                radius = 1.5,
                options = {
                    {
                        name = "p_mdt_garage_" .. jobName,
                        label = locale("open_garage"),
                        icon = "fa-solid fa-car",
                        distance = 2.0,
                        groups = { [jobName] = 0 },
                        onSelect = function()
                            if self.antiSpam > GetGameTimer() then
                                return
                            end
                            self.currentPoint = point
                            self:open()
                        end,
                    },
                },
            })
        end
    end
end

function Garages.open(self)
    local vehicles = lib.callback.await("p_mdt/server/garage/fetchGarageData", false)
    if not vehicles then
        return
    end

    local job = Bridge.Framework.fetchPlayerJob()
    vehicles = self:sortVehicles(vehicles)

    local menuVehicles = {}
    for index, vehicle in pairs(vehicles) do
        local image = (self.vehiclesData[job and job.name or nil] and self.vehiclesData[job.name][vehicle.model] and self.vehiclesData[job.name][vehicle.model].image)
            or ("https://docs.fivem.net/vehicles/%s.webp"):format(vehicle.model)

        menuVehicles[index] = {
            id = vehicle.id,
            model = vehicle.model,
            label = vehicle.label,
            plate = vehicle.plate,
            status = vehicle.status,
            fuel = vehicle.info.fuel,
            body = vehicle.info.body,
            engine = vehicle.info.engine,
            image = image,
            grades = vehicle.grades or {},
            officers = vehicle.officers or {},
        }
    end

    if Bridge and Bridge.Config and Bridge.Config.Debug then
        lib.print.info(vehicles, "Fetched Garage Data")
    end

    SetNuiFocus(true, true)
    SendNUIMessage({ action = "setVisibleGarageMenu", data = true })
    SendNUIMessage({ action = "loadGarageVehicles", data = menuVehicles })
end

RegisterNUICallback("mdt/garage/takeOut", function(data, cb)
    if not Garages.currentPoint then
        cb(false)
        return
    end
    Garages:spawn(data.vehicle, Garages.currentPoint)
    cb(true)
end)

function Garages.spawn(self, vehicleData, garagePoint)
    if self.currentVehicle and DoesEntityExist(self.currentVehicle) then
        Bridge.Notify.showNotify(locale("vehicle_already_out"), "error")
        return
    end

    local spawnPoint = self:getFreeSpawnPoint(garagePoint.spawnPoints)
    if not spawnPoint then
        Bridge.Notify.showNotify(locale("no_free_spawn_point"), "error")
        return
    end

    local vehicleProps = lib.callback.await("p_mdt/server/garage/spawnVehicle", false, vehicleData.id)
    if not vehicleProps then
        Bridge.Notify.showNotify(locale("cannot_spawn_vehicle"), "error")
        return
    end

    local job = Bridge.Framework.fetchPlayerJob()
    local entity = Editable:spawnVehicle(vehicleProps, spawnPoint)
    self.spawnedVehicles[vehicleData.id] = entity

    Entity(entity).state:set("mdt:vehicleId", {
        id = vehicleData.id,
        job = job.name,
    }, true)

    self:closeGarageMenu()
end

RegisterNUICallback("mdt/garage/parkIn", function(data, cb)
    if not Garages.currentPoint then
        cb(false)
        return
    end
    Garages:park(data.vehicle)
    cb(true)
end)

function Garages.park(self, vehicleData)
    local entity = self.spawnedVehicles[vehicleData.id]
    if not entity or not DoesEntityExist(entity) then
        Bridge.Notify.showNotify(locale("no_vehicle_to_store"), "error")
        return
    end

    if Config.Garage.maxParkDistance then
        local vehicleCoords = GetEntityCoords(entity)
        local playerCoords = GetEntityCoords(cache.ped)
        if #(vehicleCoords - playerCoords) > Config.Garage.maxParkDistance then
            Bridge.Notify.showNotify(locale("too_far_from_vehicle"), "error")
            return
        end
    end

    local stateData = Entity(entity).state["mdt:vehicleId"]
    if Bridge and Bridge.CarKeys and Bridge.CarKeys.RemoveKeys then
        Bridge.CarKeys.RemoveKeys(GetVehicleNumberPlateText(entity), entity)
    end

    local mods = lib.getVehicleProperties(entity)
    mods.plate = GetVehicleNumberPlateText(entity)

    local stored = lib.callback.await("p_mdt/server/garage/storeVehicle", false, {
        id = stateData and stateData.id or nil,
        netId = NetworkGetNetworkIdFromEntity(entity),
        mods = mods,
    })

    if not stored then
        Bridge.Notify.showNotify(locale("cannot_store_vehicle"), "error")
        return
    end

    self.spawnedVehicles[vehicleData.id] = nil
    Bridge.Notify.showNotify(locale("vehicle_stored"), "success")
    self:closeGarageMenu()
end

CreateThread(function()
    while not lib do
        Wait(0)
    end

    lib.callback.register("p_mdt/client/garage/getProperties", function(netId)
        local entity = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(entity) then
            local props = lib.getVehicleProperties(entity)
            props.plate = GetVehicleNumberPlateText(entity)
            return props
        end
        return nil
    end)
end)

function Garages.closeGarageMenu(self)
    self.antiSpam = GetGameTimer() + 1000
    self.currentPoint = nil
    SendNUIMessage({ action = "setVisibleGarageMenu", data = false })
    SetNuiFocus(false, false)
end

CreateThread(function()
    while not lib do
        Wait(0)
    end

    Garages:init()
end)

RegisterNUICallback("hideFrame", function(data, cb)
    if data.name == "setVisibleGarageMenu" then
        Garages:closeGarageMenu()
    end
    cb(1)
end)
