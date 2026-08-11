Garage = {
    vehicles = {},
    shopVehicles = lib.load("data.vehicles"),
    occupiedPlates = {},
}

CreateThread(function()
    while not MySQL or not MySQL.ready do
        Wait(100)
    end

    local rows = MySQL.query.await("SELECT * FROM p_mdt_garage")
    for _, row in ipairs(rows) do
        local job = row.job
        if not Garage.vehicles[job] then
            Garage.vehicles[job] = {}
        end

        if row.vehicle then
            local vehicle = json.decode(row.vehicle)
            if vehicle.plate then
                local model = vehicle.model

                if Config.Garage.retrieveOnRestart and row.status == "out" then
                    row.status = "in"
                end

                if Bridge and Bridge.Config and Bridge.Config.Debug then
                    print(job, model, Garage.shopVehicles[job] and Garage.shopVehicles[job][model] and Garage.shopVehicles[job][model].image)
                end

                local grades = {}
                if row.grades then
                    grades = json.decode(row.grades) or {}
                end

                local officers = {}
                if row.officers then
                    officers = json.decode(row.officers) or {}
                end

                local licences = {}
                if row.licences then
                    licences = json.decode(row.licences) or {}
                end

                table.insert(Garage.vehicles[job], {
                    id = row.id,
                    label = (Garage.shopVehicles[job] and Garage.shopVehicles[job][model] and Garage.shopVehicles[job][model].label) or nil,
                    vehicle = vehicle,
                    job = row.job,
                    status = row.status,
                    grades = grades,
                    officers = officers,
                    licences = licences,
                    imageUrl = (Garage.shopVehicles[job] and Garage.shopVehicles[job][model] and Garage.shopVehicles[job][model].image) or nil,
                })

                Garage.occupiedPlates[vehicle.plate] = row.id
            end
        end
    end
end)

lib.callback.register("p_mdt/server/garage/fetch", function(source)
    local job = Bridge.Framework.getPlayerJob(source)
    if not job then
        return nil
    end

    return {
        vehicles = Garage.vehicles[job.name] or {},
        shopData = Garage.shopVehicles[job.name] or {},
    }
end)

function Garage.generatePlate(self)
    local charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890"
    local plate

    repeat
        repeat
            Wait(1)
            plate = ""
            for _ = 1, 8 do
                local index = math.random(1, #charset)
                plate = plate .. charset:sub(index, index)
            end
        until not Bridge.Framework.getVehicleByPlate(plate)
    until not self.occupiedPlates[plate]

    return plate
end

function Garage.buyVehicle(self, source, data)
    local job = Bridge.Framework.getPlayerJob(source)
    if not job then
        return false
    end

    local shopData = Garage.shopVehicles[job.name]
    if not shopData then
        lib.print.error("Could not find shop data for job: " .. tostring(job.name))
        return false
    end

    local vehicleData = shopData[data.model]
    if not vehicleData then
        lib.print.error("Could not find vehicle data for model: " .. tostring(data.model))
        return false
    end

    if not Bridge.Society then
        lib.print.error("Could not find Society Module. Make sure you use a compatible society system.")
        return false
    end

    local price = vehicleData.price
    local societyAccount
    if GetResourceState("esx_addonaccount") == "started" then
        societyAccount = ("society_%s"):format(job.name)
    else
        societyAccount = job.name
    end

    if price > Bridge.Society.getMoney(source, societyAccount) then
        Bridge.Notify.showNotify(source, locale("not_enough_money"), "error")
        return false
    end

    Bridge.Society.removeMoney(source, societyAccount, price)
    Bridge.Notify.showNotify(source, locale("vehicle_purchased", vehicleData.label), "success")

    local payload = {
        vehicle = {
            plate = self:generatePlate(),
            model = data.model,
            fuelLevel = 100.0,
            engineHealth = 1000.0,
            bodyHealth = 1000.0,
        },
        job = job.name,
        status = "in",
    }

    local insertId = MySQL.insert.await(
        "INSERT INTO p_mdt_garage (vehicle, job, status) VALUES (?, ?, ?)",
        { json.encode(payload.vehicle), payload.job, payload.status }
    )

    if insertId then
        if not Garage.vehicles[job.name] then
            Garage.vehicles[job.name] = {}
        end

        table.insert(Garage.vehicles[job.name], {
            id = insertId,
            label = (Garage.shopVehicles[job.name] and Garage.shopVehicles[job.name][data.model] and Garage.shopVehicles[job.name][data.model].label) or nil,
            vehicle = payload.vehicle,
            job = payload.job,
            status = payload.status,
            grades = {},
            officers = {},
            licences = {},
            imageUrl = (Garage.shopVehicles[job.name] and Garage.shopVehicles[job.name][data.model] and Garage.shopVehicles[job.name][data.model].image) or nil,
        })

        Garage.occupiedPlates[payload.vehicle.plate] = insertId
    end

    Logs:new(source, {
        category = "garage",
        action = "buy",
        message = ("Purchased vehicle %s for $%s"):format(vehicleData.label, price),
    })

    return true
end

lib.callback.register("p_mdt/server/garage/buyVehicle", function(source, data)
    return Garage:buyVehicle(source, data)
end)

function Garage.editVehicle(self, source, data)
    local job = Bridge.Framework.getPlayerJob(source)

    for _, vehicle in ipairs(self.vehicles[job.name]) do
        if vehicle.id == data.id then
            vehicle.grades = data.grades
            vehicle.officers = data.officers
            vehicle.licences = data.licences

            MySQL.update(
                "UPDATE p_mdt_garage SET grades = ?, officers = ?, licences = ? WHERE id = ?",
                {
                    json.encode(vehicle.grades),
                    json.encode(vehicle.officers),
                    json.encode(vehicle.licences),
                    vehicle.id,
                }
            )

            Logs:new(source, {
                category = "garage",
                action = "edit",
                message = ("Edited vehicle permissions for vehicle ID %s"):format(data.id),
            })

            return true
        end
    end

    return false
end

lib.callback.register("p_mdt/server/garage/editVehiclePermissions", function(source, data)
    return Garage:editVehicle(source, data)
end)

function Garage.getGarageData(self, source)
    local job = Bridge.Framework.getPlayerJob(source)
    local uniqueId = Bridge.Framework.getUniqueId(source)
    local uniqueIdAlt = Bridge.Framework.getUniqueId(source, true)

    if not job then
        return nil
    end

    local accessible = {}
    local vehicles = self.vehicles[job.name] or {}
    local licences = Employees:getLicences(uniqueId)

    for _, vehicle in ipairs(vehicles) do
        local gradeAllowed = vehicle.grades[tostring(job.grade)]
        local officerAllowed = vehicle.officers[tostring(uniqueIdAlt)]

        if gradeAllowed or officerAllowed then
            accessible[#accessible + 1] = vehicle
        else
            for _, licence in pairs(vehicle.licences) do
                if licences[licence] then
                    accessible[#accessible + 1] = vehicle
                    break
                end
            end
        end
    end

    return accessible
end

lib.callback.register("p_mdt/server/garage/fetchGarageData", function(source)
    return Garage:getGarageData(source)
end)

lib.callback.register("p_mdt/server/garage/spawnVehicle", function(source, vehicleId)
    local job = Bridge.Framework.getPlayerJob(source)
    if not job then
        return false
    end

    local vehicles = Garage.vehicles[job.name] or {}
    for _, vehicle in ipairs(vehicles) do
        if vehicle.id == vehicleId then
            if vehicle.status == "out" then
                return false
            end

            vehicle.status = "out"
            vehicle.officer = Bridge.Framework.getPlayerName(source)

            MySQL.update(
                "UPDATE p_mdt_garage SET status = ? WHERE id = ?",
                { vehicle.status, vehicle.id }
            )

            Logs:new(source, {
                category = "garage",
                action = "spawn",
                message = ("Spawned vehicle with ID %s"):format(vehicleId),
            })

            return vehicle.vehicle
        end
    end
end)

function Garage.storeVehicle(self, source, data)
    local job = Bridge.Framework.getPlayerJob(source)
    if not job then
        return false
    end

    local vehicles = self.vehicles[job.name] or {}
    for _, vehicle in ipairs(vehicles) do
        if vehicle.id == data.id then
            if vehicle.status == "in" then
                return false
            end

            vehicle.status = "in"
            vehicle.officer = nil
            vehicle.vehicle = data.mods

            MySQL.update(
                "UPDATE p_mdt_garage SET vehicle = ?, status = ? WHERE id = ?",
                { json.encode(vehicle.vehicle), vehicle.status, vehicle.id }
            )

            if data.netId then
                local entity = NetworkGetEntityFromNetworkId(data.netId)
                if DoesEntityExist(entity) then
                    pcall(DeleteEntity, entity)
                end
            end

            Logs:new(source, {
                category = "garage",
                action = "store",
                message = ("Stored vehicle with ID %s"):format(data.id),
            })

            return true
        end
    end

    return false
end

lib.callback.register("p_mdt/server/garage/storeVehicle", function(source, data)
    return Garage:storeVehicle(source, data)
end)

function Garage.impound(self, source, data)
    local job = Bridge.Framework.getPlayerJob(source)
    if not job then
        return false
    end

    if not Permissions.hasPerm(source, "garage.impound") then
        Bridge.Notify.showNotify(source, locale("no_permission"), "error")
        return false
    end

    local vehicles = self.vehicles[job.name] or {}
    for _, vehicle in ipairs(vehicles) do
        if vehicle.id == data.id then
            local savedProps = nil

            if vehicle.netId then
                local entity = NetworkGetEntityFromNetworkId(vehicle.netId)
                if DoesEntityExist(entity) then
                    if not Config.Garage.canImpoundOccupied then
                        for seat = -1, 6, 1 do
                            local occupant = GetPedInVehicleSeat(entity, seat)
                            if occupant and occupant ~= 0 then
                                Bridge.Notify.showNotify(source, locale("cannot_impound_occupied"), "error")
                                return false
                            end
                        end
                    end

                    local owner = NetworkGetEntityOwner(entity)
                    if Config.Garage.savePropsOnImpound and owner then
                        savedProps = lib.callback.await("p_mdt/client/garage/getProperties", owner, vehicle.netId)
                        if savedProps then
                            vehicle.vehicle = savedProps
                        end
                    end

                    Wait(100)
                    pcall(DeleteEntity, entity)
                end
            end

            if savedProps then
                MySQL.update(
                    "UPDATE p_mdt_garage SET status = ?, vehicle = ? WHERE id = ?",
                    { "in", json.encode(savedProps), vehicle.id }
                )
            else
                MySQL.update(
                    "UPDATE p_mdt_garage SET status = ? WHERE id = ?",
                    { "in", vehicle.id }
                )
            end

            vehicle.netId = nil
            vehicle.status = "in"
            vehicle.officer = nil

            Logs:new(source, {
                category = "garage",
                action = "impound",
                message = ("Impounded vehicle with ID %s"):format(data.id),
            })

            return true
        end
    end

    return false
end

lib.callback.register("p_mdt/server/garage/impound", function(source, data)
    return Garage:impound(source, data)
end)

lib.callback.register("p_mdt/server/garage/getVehicleLocation", function(source, data)
    local job = Bridge.Framework.getPlayerJob(source)
    if not job then
        return nil
    end

    local vehicles = Garage.vehicles[job.name] or {}
    for _, vehicle in ipairs(vehicles) do
        if vehicle.id == data.id and vehicle.netId then
            local entity = NetworkGetEntityFromNetworkId(vehicle.netId)
            if DoesEntityExist(entity) then
                local coords = GetEntityCoords(entity)
                return { x = coords.x, y = coords.y, z = coords.z }
            end
        end
    end

    return nil
end)

AddStateBagChangeHandler("mdt:vehicleId", nil, function(bagName, _, value)
    local entity = GetEntityFromStateBagName(bagName)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(entity)
    local vehicles = Garage.vehicles[value.job] or {}

    for _, vehicle in ipairs(vehicles) do
        if vehicle.id == value.id then
            vehicle.netId = netId
            break
        end
    end
end)
