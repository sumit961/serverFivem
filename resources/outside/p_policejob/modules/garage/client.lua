if not Config or not Config.Garage or not Config.Garage.Enabled then
    return
end

Garage = {
    currentGarage = nil,
}

function Garage.enrichVehicleList(vehicles)
    for _, vehicleEntry in ipairs(vehicles or {}) do
        local modelHash = type(vehicleEntry.model) == "number" and vehicleEntry.model or tonumber(vehicleEntry.model)
        if modelHash then
            local displayName = GetDisplayNameFromVehicleModel(modelHash)
            if displayName and displayName ~= "" and displayName ~= "CARNOTFOUND" then
                vehicleEntry.model = displayName:lower()
                local label = GetLabelText(displayName)
                if label and label ~= "" and label ~= "NULL" then
                    vehicleEntry.label = label
                end
            end
        end
    end
    return vehicles
end

function Garage.spawnPed(pedConfig)
    local model = lib.requestModel(pedConfig.model)
    if not model then
        return nil
    end
    local ped = CreatePed(
        4, model,
        pedConfig.coords.x, pedConfig.coords.y, pedConfig.coords.z - 1.0,
        pedConfig.coords.w,
        false, true
    )
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    if pedConfig.scenario then
        TaskStartScenarioInPlace(ped, pedConfig.scenario, 0, true)
    elseif pedConfig.anim then
        local animDict = lib.requestAnimDict(pedConfig.anim.dict)
        TaskPlayAnim(ped, animDict, pedConfig.anim.clip, 8.0, -8.0, -1, 1, 0, false, false, false)
        RemoveAnimDict(animDict)
    end
    if pedConfig.onCreate then
        pedConfig.onCreate(ped)
    end
    SetModelAsNoLongerNeeded(model)
    return ped
end

function Garage.findFreeSpawnPoint(garageConfig)
    for _, spawnPoint in ipairs(garageConfig.spawnPoints) do
        local nearby = lib.getNearbyVehicles(vector3(spawnPoint.x, spawnPoint.y, spawnPoint.z), 2.5, false)
        if #nearby == 0 then
            return spawnPoint
        end
    end
    return nil
end

function Garage.open(self, garageName)
    local garageConfig = Config.DepartmentData.garages[garageName]
    if not garageConfig then
        return
    end
    self.currentGarage = garageName
    local vehicles = lib.callback.await("p_policejob/garage/getVehicles", false, garageName) or {}
    Garage.enrichVehicleList(vehicles)
    SendNUIMessage({
        action = "setGarageData",
        data = {
            garageName = garageName,
            garageLabel = garageConfig.label or garageName,
            vehicles = vehicles,
            inVehicle = cache.vehicle ~= nil,
        },
    })
    SendNUIMessage({ action = "setVisibleGarage", data = true })
    SetNuiFocus(true, true)
end

function Garage.close(self)
    self.currentGarage = nil
    SendNUIMessage({ action = "setVisibleGarage", data = false })
    SetNuiFocus(false, false)
end

function Garage.takeOutVehicle(self, vehicleData, isJobVehicle)
    local garageConfig = Config.DepartmentData.garages[self.currentGarage]
    if not garageConfig then
        return
    end
    local spawnPoint = Garage.findFreeSpawnPoint(garageConfig)
    if not spawnPoint then
        Bridge.Notify.showNotify(locale("garage_no_free_spawn"), "error")
        return false
    end
    local properties
    if not isJobVehicle then
        properties = lib.callback.await("p_policejob/garage/takeOutVehicle", false, vehicleData)
        if not properties then
            Bridge.Notify.showNotify(locale("garage_cant_get_vehicle"), "error")
            return false
        end
    elseif vehicleData.preconfigured and vehicleData.properties then
        properties = vehicleData.properties
    end
    local model = lib.requestModel(vehicleData.model)
    if not model then
        return false
    end
    local vehicle = CreateVehicle(model, spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnPoint.w, true, false)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    SetNetworkIdCanMigrate(netId, true)
    SetNetworkIdExistsOnAllMachines(netId, true)
    SetVehicleHasBeenOwnedByPlayer(vehicle, true)
    if properties and type(properties) == "table" then
        lib.setVehicleProperties(vehicle, properties)
    else
        if vehicleData.plate then
            SetVehicleNumberPlateText(vehicle, vehicleData.plate)
        end
        local defaultProps = Config.Garage.GetVehicleProperties and Config.Garage.GetVehicleProperties(vehicleData.model)
        if defaultProps then
            lib.setVehicleProperties(vehicle, defaultProps)
        end
        Entity(vehicle).state:set("isPoliceVehicle", true, true)
    end
    local plate = GetVehicleNumberPlateText(vehicle)
    Bridge.CarKeys.CreateKeys(plate, vehicle)
    TaskWarpPedIntoVehicle(cache.ped, vehicle, -1)
    SetModelAsNoLongerNeeded(model)
    return true
end

function Garage.storeVehicle(self)
    local garageConfig = Config.DepartmentData.garages[self.currentGarage]
    if not garageConfig then
        return
    end
    local vehicle = GetVehiclePedIsIn(cache.ped, true)
    if not vehicle or vehicle == 0 or not NetworkGetEntityIsNetworked(vehicle) then
        Bridge.Notify.showNotify(locale("no_vehicle_to_store"), "error")
        return
    end
    if #(GetEntityCoords(vehicle) - GetEntityCoords(cache.ped)) > Config.Garage.maxDistance then
        Bridge.Notify.showNotify(locale("vehicle_too_far"), "error")
        return
    end
    local plate = GetVehicleNumberPlateText(vehicle)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    Bridge.CarKeys.RemoveKeys(plate)
    TriggerServerEvent("p_policejob/garage/storeVehicle", {
        plate = plate,
        model = GetEntityModel(vehicle),
        netId = netId,
        properties = lib.getVehicleProperties(vehicle),
        garageName = self.currentGarage,
    })
end

RegisterNUICallback("hideFrame", function(data, cb)
    if data.name == "setVisibleGarage" then
        Garage:close()
    end
    cb("ok")
end)

RegisterNUICallback("garage:takeOut", function(data, cb)
    if not Garage.currentGarage or not data.vehicle then
        cb({ success = false })
        return
    end
    Garage:close()
    local success = Garage:takeOutVehicle(data.vehicle, data.vehicle.isJobVehicle)
    cb({ success = success or false })
end)

RegisterNUICallback("garage:store", function(_, cb)
    if not Garage.currentGarage then
        cb({ success = false })
        return
    end
    Garage:storeVehicle()
    Garage:close()
    cb({ success = true })
end)

RegisterNUICallback("garage:refresh", function(_, cb)
    if not Garage.currentGarage then
        cb({})
        return
    end
    local vehicles = lib.callback.await("p_policejob/garage/getVehicles", false, Garage.currentGarage)
    cb(Garage.enrichVehicleList(vehicles or {}))
end)

RegisterNetEvent("p_policejob/garage/vehicleStored", function()
    Bridge.Notify.showNotify(locale("vehicle_stored"), "success")
end)

CreateThread(function()
    for garageName, garageConfig in pairs(Config.DepartmentData.garages or {}) do
        if garageConfig.blip and garageConfig.blip.enabled then
            local blip = AddBlipForCoord(garageConfig.blip.coords.x, garageConfig.blip.coords.y, garageConfig.blip.coords.z)
            SetBlipSprite(blip, garageConfig.blip.sprite)
            SetBlipColour(blip, garageConfig.blip.color)
            SetBlipScale(blip, garageConfig.blip.scale)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(garageConfig.blip.label)
            EndTextCommandSetBlipName(blip)
        end
        local point = lib.points.new({
            coords = vector3(garageConfig.ped.coords.x, garageConfig.ped.coords.y, garageConfig.ped.coords.z),
            distance = 50,
        })
        point.onEnter = function(pointRef)
            pointRef.ped = Garage.spawnPed(garageConfig.ped)
            if not pointRef.ped then
                return
            end
            local targets = {
                {
                    name = "garage_open_" .. garageName,
                    label = locale("open_police_garage"),
                    icon = "fa-solid fa-warehouse",
                    distance = 2.5,
                    groups = Config.Jobs,
                    onSelect = function()
                        Garage:open(garageName)
                    end,
                },
            }
            if not garageConfig.spawnerMode then
                targets[#targets + 1] = {
                    name = "garage_store_" .. garageName,
                    label = locale("store_vehicle"),
                    icon = "fa-solid fa-square-parking",
                    distance = 2.5,
                    groups = Config.Jobs,
                    onSelect = function()
                        Garage.currentGarage = garageName
                        Garage:storeVehicle()
                    end,
                }
            end
            Bridge.Target.addLocalEntity(pointRef.ped, targets)
        end
        point.onExit = function(pointRef)
            if pointRef.ped then
                Bridge.Target.removeLocalEntity(pointRef.ped, {
                    "garage_open_" .. garageName,
                    "garage_store_" .. garageName,
                })
                DeleteEntity(pointRef.ped)
                pointRef.ped = nil
            end
        end
    end
end)
