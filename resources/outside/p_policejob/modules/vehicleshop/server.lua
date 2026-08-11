if not Config?.VehicleShop?.Enabled then return end

local function generatePlate()
    local chars = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789'
    local plate = ''

    for _ = 1, 100 do
        plate = ''
        for _ = 1, 8 do
            local idx = math.random(1, #chars)
            plate = plate .. chars:sub(idx, idx)
        end

        local query = 'SELECT plate FROM owned_vehicles WHERE plate = ?'
        if GetResourceState('es_extended') ~= 'started' then
            query = 'SELECT plate FROM player_vehicles WHERE plate = ?'
        end

        local exists = MySQL.single.await(query, { plate })
        if not exists then
            return plate
        end
    end

    return ('P%s'):format(os.time() % 10000000)
end

local function getVehicleById(vehicleId)
    for category, vehicles in pairs(Config.VehicleShop.Vehicles) do
        for _, vehicle in ipairs(vehicles) do
            if vehicle.id == vehicleId then
                return vehicle, category
            end
        end
    end
    return nil
end

local function validatePurchase(source, shopName, vehicleId)
    local playerJob = Bridge.Framework.getPlayerJob(source)
    if not playerJob then
        return false, locale('vehicle_shop_no_job')
    end

    local shopData = Config.DepartmentData.vehicleShops[shopName]
    if not shopData then
        return false, locale('vehicle_shop_invalid_shop')
    end

    local minGrade = Config.Jobs[playerJob.name]
    if minGrade == nil then
        return false, locale('vehicle_shop_no_access')
    end

    if playerJob.grade < minGrade then
        return false, locale('vehicle_shop_rank_too_low')
    end

    local vehicleData = getVehicleById(vehicleId)
    if not vehicleData then
        return false, locale('vehicle_shop_vehicle_not_found')
    end

    local jobAllowed = false
    for _, allowedJob in ipairs(vehicleData.allowedJobs) do
        if allowedJob == playerJob.name then
            jobAllowed = true
            break
        end
    end

    if not jobAllowed then
        return false, locale('vehicle_shop_job_no_access')
    end

    local requiredGrade = vehicleData.allowedGrades[playerJob.name]
    if requiredGrade and playerJob.grade < requiredGrade then
        return false, locale('vehicle_shop_rank_too_low_vehicle')
    end

    return true, vehicleData, playerJob
end

RegisterNetEvent('p_policejob/vehicleshop/setBucket', function(state)
    local _source = source
    if state then
        SetPlayerRoutingBucket(_source, _source + 1000)
    else
        SetPlayerRoutingBucket(_source, 0)
    end
end)

RegisterNetEvent('p_policejob/vehicleshop/purchase', function(data)
    local _source = source

    local valid, vehicleData, playerJob = validatePurchase(_source, data.shopName, data.vehicleId)
    if not valid then
        Bridge.Debug(('[VehicleShop] Player %s purchase rejected: %s'):format(_source, tostring(vehicleData)))
        TriggerClientEvent('p_policejob/vehicleshop/purchaseFailed', _source, vehicleData)
        return
    end

    local price = vehicleData.price
    local paymentMethod = data.paymentMethod or 'bank'
    local playerMoney = Bridge.Framework.getMoney(_source)

    if playerMoney[paymentMethod] < price then
        TriggerClientEvent('p_policejob/vehicleshop/purchaseFailed', _source, locale('not_enough_money'))
        return
    end

    if price > 0 then
        Bridge.Framework.removeMoney(_source, paymentMethod, price)
    end

    local plate = generatePlate()
    local identifier = Bridge.Framework.getUniqueId(_source)
    local armorMod = nil
    if vehicleData.armor then
        armorMod = math.max(0, math.min(4, math.floor(vehicleData.armor)))
    end
    local vehicleMods = {
        model = joaat(vehicleData.model),
        plate = plate,
        fuelLevel = 100.0,
        engineHealth = 1000.0,
        bodyHealth = 1000.0,
        modArmor = armorMod,
    }

    local defaultProps = Config.Garage.GetVehicleProperties and Config.Garage.GetVehicleProperties(vehicleData.model)
    if defaultProps then
        for key, value in pairs(defaultProps) do
            if key ~= 'plate' then
                vehicleMods[key] = value
            end
        end
    end

    local insertSuccess = false

    if GetResourceState('es_extended') == 'started' then
        local id = MySQL.insert.await([[
            INSERT INTO owned_vehicles (owner, plate, vehicle, stored, type, job)
            VALUES (?, ?, ?, ?, ?, ?)
        ]], {
            identifier,
            plate,
            json.encode(vehicleMods),
            1,
            'car',
            playerJob.name
        })
        insertSuccess = id ~= nil
    else
        local xPlayer = Bridge.Framework.getPlayerById(_source)
        if xPlayer then
            local id = MySQL.insert.await([[
                INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, fuelLevel, engineHealth, bodyHealth, state, job)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]], {
                xPlayer.PlayerData.license,
                xPlayer.PlayerData.citizenid or identifier,
                vehicleData.model,
                joaat(vehicleData.model),
                json.encode(vehicleMods),
                plate,
                100.0,
                1000.0,
                1000.0,
                1,
                playerJob.name
            })
            insertSuccess = id ~= nil
        end
    end

    if not insertSuccess then
        if price > 0 then
            Bridge.Framework.addMoney(_source, paymentMethod, price)
        end
        Bridge.Debug(('[VehicleShop] Player %s purchase DB insert failed (model=%s plate=%s)'):format(_source, vehicleData.model, plate))
        TriggerClientEvent('p_policejob/vehicleshop/purchaseFailed', _source, locale('vehicle_shop_database_error'))
        return
    end

    TriggerClientEvent('p_policejob/vehicleshop/purchaseSuccess', _source, {
        shopName = data.shopName,
        model = vehicleData.model,
        plate = plate,
        price = price,
        mods = vehicleMods
    })

    Bridge.Debug(('[VehicleShop] Player %s bought %s (plate=%s, $%s)'):format(_source, vehicleData.model, plate, price))
    Bridge.Notify.showNotify(_source, locale('vehicle_bought', price), 'success')
end)

exports('GetVehicleShopVehicles', function()
    return Config.VehicleShop.Vehicles
end)

exports('GetVehicleShopShops', function()
    return Config.DepartmentData.vehicleShops
end)
