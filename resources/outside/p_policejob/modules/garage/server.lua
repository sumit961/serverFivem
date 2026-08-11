if not Config?.Garage?.Enabled then return end

local isESX = GetResourceState('es_extended') == 'started'

CreateThread(function()
    while not MySQL?.ready do
        Citizen.Wait(100)
    end

    if isESX then
        local cols = MySQL.query.await("SHOW COLUMNS FROM `owned_vehicles` LIKE 'job'")
        if not cols or #cols == 0 then
            MySQL.query.await("ALTER TABLE `owned_vehicles` ADD COLUMN `job` VARCHAR(50) NULL DEFAULT NULL")
        end
    else
        local cols = MySQL.query.await("SHOW COLUMNS FROM `player_vehicles` LIKE 'job'")
        if not cols or #cols == 0 then
            MySQL.query.await("ALTER TABLE `player_vehicles` ADD COLUMN `job` VARCHAR(50) NULL DEFAULT NULL")
        end
    end
end)

local function getVehicleLabel(model)
    return model
end

lib.callback.register('p_policejob/garage/getVehicles', function(source, garageName)
    local _source = source
    local playerJob = Bridge.Framework.getPlayerJob(_source)
    if not playerJob then return {} end

    local garageData = Config.DepartmentData.garages[garageName]
    if not garageData then
        Bridge.Debug(('[Garage] getVehicles: unknown garage %s (player %s)'):format(tostring(garageName), _source))
        return {}
    end

    local minGrade = Config.Jobs[playerJob.name]
    if minGrade == nil then return {} end
    if playerJob.grade < minGrade then return {} end

    local identifier = Bridge.Framework.getUniqueId(_source)
    if not identifier then return {} end

    local vehicles = {}

    if not garageData.spawnerMode then
        local dbVehicles
        if isESX then
            dbVehicles = MySQL.query.await([[
                SELECT plate, vehicle, stored FROM owned_vehicles
                WHERE owner = ? AND job = ?
            ]], { identifier, playerJob.name })
        else
            local xPlayer = Bridge.Framework.getPlayerById(_source)
            if xPlayer then
                dbVehicles = MySQL.query.await([[
                    SELECT plate, vehicle, mods, state as stored FROM player_vehicles
                    WHERE citizenid = ? AND job = ?
                ]], { xPlayer.PlayerData.citizenid or identifier, playerJob.name })
            end
        end

        if dbVehicles then
            for _, row in ipairs(dbVehicles) do
                local mods = {}
                local vehicleField = isESX and row.vehicle or row.mods
                if vehicleField and type(vehicleField) == 'string' then
                    mods = json.decode(vehicleField) or {}
                elseif type(vehicleField) == 'table' then
                    mods = vehicleField
                end

                local modelName = ''
                if mods.model then
                    modelName = type(mods.model) == 'number' and tostring(mods.model) or mods.model
                elseif not isESX and row.vehicle then
                    modelName = row.vehicle
                end

                vehicles[#vehicles + 1] = {
                    plate = row.plate,
                    model = modelName,
                    label = getVehicleLabel(modelName),
                    stored = row.stored == 1,
                    isJobVehicle = false,
                    fuel = mods.fuelLevel or 100,
                    engine = mods.engineHealth or 1000,
                    body = mods.bodyHealth or 1000,
                }
            end
        end
    end

    if garageData.vehicles then
        local jobVehicles = garageData.vehicles[playerJob.name]
        if jobVehicles then
            local addedModels = {}
            for grade, gradeVehicles in pairs(jobVehicles) do
                if playerJob.grade >= grade then
                    for model, label in pairs(gradeVehicles) do
                        if not addedModels[model] then
                            addedModels[model] = true
                            local properties = Config.Garage.GetVehicleProperties and Config.Garage.GetVehicleProperties(model)
                            local entry = {
                                plate = properties and properties.plate or '',
                                model = model,
                                label = label,
                                stored = true,
                                isJobVehicle = true,
                                fuel = properties and properties.fuelLevel or 100,
                                engine = properties and properties.engineHealth or 1000,
                                body = properties and properties.bodyHealth or 1000,
                            }
                            if properties then
                                entry.preconfigured = true
                                entry.properties = properties
                            end
                            vehicles[#vehicles + 1] = entry
                        end
                    end
                end
            end
        end
    end

    if garageData.preconfiguredVehicles then
        local jobVehicles = garageData.preconfiguredVehicles[playerJob.name]
        if jobVehicles then
            for grade, gradeVehicles in pairs(jobVehicles) do
                if playerJob.grade >= grade then
                    for _, vehDef in ipairs(gradeVehicles) do
                        if vehDef.model then
                            local props = vehDef.properties or {}
                            vehicles[#vehicles + 1] = {
                                plate = props.plate or '',
                                model = vehDef.model,
                                label = vehDef.label or getVehicleLabel(vehDef.model),
                                stored = true,
                                isJobVehicle = true,
                                preconfigured = true,
                                properties = props,
                                fuel = props.fuelLevel or 100,
                                engine = props.engineHealth or 1000,
                                body = props.bodyHealth or 1000,
                            }
                        end
                    end
                end
            end
        end
    end

    return vehicles
end)

lib.callback.register('p_policejob/garage/takeOutVehicle', function(source, vehicleData)
    local _source = source
    local playerJob = Bridge.Framework.getPlayerJob(_source)
    if not playerJob then return nil end

    local identifier = Bridge.Framework.getUniqueId(_source)
    if not identifier then return nil end

    Bridge.Debug(('[Garage] Player %s taking out vehicle plate=%s'):format(_source, tostring(vehicleData and vehicleData.plate)))

    local result
    if isESX then
        MySQL.update.await([[
            UPDATE owned_vehicles SET stored = 0
            WHERE owner = ? AND plate = ? AND job = ?
        ]], { identifier, vehicleData.plate, playerJob.name })

        result = MySQL.single.await([[
            SELECT vehicle FROM owned_vehicles
            WHERE owner = ? AND plate = ? AND job = ?
        ]], { identifier, vehicleData.plate, playerJob.name })

        if result and result.vehicle then
            local decoded = json.decode(result.vehicle)
            return decoded
        end
    else
        local xPlayer = Bridge.Framework.getPlayerById(_source)
        if xPlayer then
            local cid = xPlayer.PlayerData.citizenid or identifier
            MySQL.update.await([[
                UPDATE player_vehicles SET state = 0
                WHERE citizenid = ? AND plate = ? AND job = ?
            ]], { cid, vehicleData.plate, playerJob.name })

            result = MySQL.single.await([[
                SELECT mods FROM player_vehicles
                WHERE citizenid = ? AND plate = ? AND job = ?
            ]], { cid, vehicleData.plate, playerJob.name })

            if result and result.mods then
                local decoded = json.decode(result.mods)
                return decoded
            end
        end
    end

    return nil
end)

RegisterNetEvent('p_policejob/garage/storeVehicle', function(data)
    local _source = source
    local playerJob = Bridge.Framework.getPlayerJob(_source)
    if not playerJob then return end

    if not data or not data.plate then return end

    Bridge.Debug(('[Garage] Player %s storing vehicle plate=%s garage=%s'):format(_source, data.plate, tostring(data.garageName)))

    local garageData = Config.DepartmentData.garages[data.garageName]
    if garageData and garageData.spawnerMode then
        local netId = data.netId
        if netId then
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if vehicle and vehicle ~= 0 then
                DeleteEntity(vehicle)
            end
        end
        TriggerClientEvent('p_policejob/garage/vehicleStored', _source)
        return
    end

    local netId = data.netId
    if netId then
        local vehicle = NetworkGetEntityFromNetworkId(netId)
        if vehicle and vehicle ~= 0 then
            DeleteEntity(vehicle)
        end
    end

    local identifier = Bridge.Framework.getUniqueId(_source)
    if not identifier then return end

    local properties = data.properties
    local encodedProps = properties and json.encode(properties) or nil

    if isESX then
        local exists = MySQL.single.await([[
            SELECT plate FROM owned_vehicles WHERE plate = ? AND job = ?
        ]], { data.plate, playerJob.name })

        if exists then
            if encodedProps then
                MySQL.update.await([[
                    UPDATE owned_vehicles SET stored = 1, vehicle = ?
                    WHERE plate = ? AND job = ?
                ]], { encodedProps, data.plate, playerJob.name })
            else
                MySQL.update.await([[
                    UPDATE owned_vehicles SET stored = 1
                    WHERE plate = ? AND job = ?
                ]], { data.plate, playerJob.name })
            end
        end
    else
        local xPlayer = Bridge.Framework.getPlayerById(_source)
        if xPlayer then
            local cid = xPlayer.PlayerData.citizenid or identifier
            local exists = MySQL.single.await([[
                SELECT plate FROM player_vehicles WHERE plate = ? AND job = ?
            ]], { data.plate, playerJob.name })

            if exists then
                if encodedProps then
                    MySQL.update.await([[
                        UPDATE player_vehicles SET state = 1, mods = ?
                        WHERE plate = ? AND job = ?
                    ]], { encodedProps, data.plate, playerJob.name })
                else
                    MySQL.update.await([[
                        UPDATE player_vehicles SET state = 1
                        WHERE plate = ? AND job = ?
                    ]], { data.plate, playerJob.name })
                end
            end
        end
    end

    TriggerClientEvent('p_policejob/garage/vehicleStored', _source)
end)