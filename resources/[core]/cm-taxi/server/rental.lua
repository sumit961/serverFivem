local Config = CMTaxi.Config
CMTaxi.Server = CMTaxi.Server or {}

-- [src] = { entity, netId, plate, cost, account, officeKey }
local rentals = {}
local lastRequests = {}
local rentalPlateCounter = 0

local function nextRentalPlate()
    if GetResourceState('cm-vehicles') ~= 'started' then return nil end

    for _ = 1, 10000 do
        rentalPlateCounter = (rentalPlateCounter % 10000) + 1
        local plate = ('TAXI%04d'):format(rentalPlateCounter)
        local alreadyRented = false
        for _, rental in pairs(rentals) do
            if rental.plate == plate then
                alreadyRented = true
                break
            end
        end

        local ok, alreadySpawned = pcall(function()
            return exports['cm-vehicles']:IsAdminVehicle(plate)
        end)
        if not ok then return nil end
        if not alreadyRented and alreadySpawned ~= true then return plate end
    end

    return nil
end

local function notify(src, message, kind)
    TriggerClientEvent('cm-taxi:client:notify', src, message, kind or 'info')
end

local function rateLimited(src, action, cooldownMs)
    local now = GetGameTimer()
    lastRequests[src] = lastRequests[src] or {}
    local last = lastRequests[src][action] or 0
    if now - last < cooldownMs then return true end
    lastRequests[src][action] = now
    return false
end

local function playerNearOffice(src, officeKey, maxDistance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local coords = GetEntityCoords(ped)
    local office = officeKey and Config.Offices[officeKey] or nil
    if office then
        -- Match the client interaction prompt, which is positioned at the
        -- office clerk rather than the separate map/blip coordinate.
        local interactionCoords = office.pedData and office.pedData.coords or office.coords
        return #(coords - interactionCoords) <= maxDistance, officeKey
    end

    for key, candidate in pairs(Config.Offices) do
        local interactionCoords = candidate.pedData and candidate.pedData.coords or candidate.coords
        if #(coords - interactionCoords) <= maxDistance then
            return true, key
        end
    end
    return false
end

local function payForRental(src, cost)
    if not Config.ChargeForRental or cost == nil or cost <= 0 then return true, nil end
    if GetResourceState('cm-playerdata') ~= 'started' then return false end

    for _, account in ipairs({ 'bank', 'cash' }) do
        local ok, removed = pcall(function()
            return exports['cm-playerdata']:RemoveMoney(src, account, cost, 'Taxi rental')
        end)
        if ok and removed == true then
            return true, account
        end
    end
    return false
end

local function refundRental(src, rental)
    if not rental or not rental.cost or rental.cost <= 0 then return true end
    if GetResourceState('cm-playerdata') ~= 'started' then return false end

    local account = rental.account or 'cash'
    local ok, refunded = pcall(function()
        return exports['cm-playerdata']:AddMoney(src, account, rental.cost, 'Taxi rental refund')
    end)
    return ok and refunded == true
end

local function checkUnlock(src, model)
    local progression = CMTaxi.Server.Progression.Get(src)
    if not progression then return false, nil, nil end
    for level, data in pairs(Config.Levels) do
        if progression.level >= level and data.vehicle == model and type(data.spawnModel) == 'string' then
            return true, data.vehicleRentCost or 0, data
        end
    end
    return false, nil, nil
end

local function spawnIsClear(spawn)
    local spawnCoords = vector3(spawn.x, spawn.y, spawn.z)
    for _, vehicle in ipairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) and #(spawnCoords - GetEntityCoords(vehicle)) <= Config.RentalSpawnClearRadius then
            return false
        end
    end
    return true
end

local function deleteRentalVehicle(rental)
    if not rental then return true end
    if GetResourceState('cm-vehicles') == 'started' and rental.plate then
        local ok, deleted = pcall(function()
            return exports['cm-vehicles']:DeleteAdminVehicle(rental.plate)
        end)
        if ok and deleted then return true end
    end
    if rental.entity and DoesEntityExist(rental.entity) then
        DeleteEntity(rental.entity)
    end
    return not rental.entity or not DoesEntityExist(rental.entity)
end

local function revokeRentalKey(src, rental)
    if not rental or not rental.plate or GetResourceState('cm-vehiclekeys') ~= 'started' then return end
    pcall(function() exports['cm-vehiclekeys']:RevokeTempKey(src, rental.plate) end)
end

local function cleanupRental(src, shouldRefund)
    local rental = rentals[src]
    if not rental then
        lastRequests[src] = nil
        return true
    end

    if shouldRefund and not refundRental(src, rental) then
        notify(src, 'The rental could not be refunded automatically. Please contact staff.', 'error')
        return false
    end

    revokeRentalKey(src, rental)
    deleteRentalVehicle(rental)
    rentals[src] = nil
    lastRequests[src] = nil
    return true
end

local function expireRental(src, rental)
    if rentals[src] ~= rental then return false end
    if CMTaxi.Server.CanExpireRental and not CMTaxi.Server.CanExpireRental(src) then
        rental.abandonedAt = GetGameTimer()
        TriggerClientEvent('cm-taxi:client:rentalIdleTimer', src, Config.RentalIdleGraceMs)
        return false
    end
    cleanupRental(src, false)
    if CMTaxi.Server.EndDutySilently then
        CMTaxi.Server.EndDutySilently(src)
    else
        TriggerClientEvent('cm-taxi:client:rentalState', src, nil)
        TriggerClientEvent('cm-taxi:client:rentalIdleTimer', src, nil)
        TriggerClientEvent('cm-taxi:client:rentalExpired', src)
    end
    return true
end

RegisterNetEvent('cm-taxi:server:requestRent', function(reqId, officeKey, model, spawnIndex)
    local src = source
    local function respond(data)
        TriggerClientEvent('cm-taxi:client:rentResult', src, reqId, data)
    end
    local function fail(message)
        notify(src, message, 'error')
        respond({ success = false })
    end

    if rateLimited(src, 'requestRent', 1500) then return fail('Please wait before requesting another rental.') end
    model = tonumber(model)
    spawnIndex = tonumber(spawnIndex)
    local office = Config.Offices[officeKey]
    local spawn = office and office.rentalSpawns and office.rentalSpawns[spawnIndex]

    if not office or not spawn then return fail('Invalid rental spawn point.') end
    if not Player(src).state.cmTaxiDuty then return fail(CMTaxi.Locale('offduty')) end
    if not playerNearOffice(src, officeKey, Config.OfficeServerDistance) then
        return fail('You must be at the taxi office to rent a vehicle.')
    end
    if rentals[src] then return fail(CMTaxi.Locale('has_rental')) end
    if not spawnIsClear(spawn) then return fail(CMTaxi.Locale('no_spawns')) end

    local unlocked, cost, levelConfig = checkUnlock(src, model)
    if not unlocked then return fail('You have not unlocked this vehicle yet.') end

    local paid, account = payForRental(src, cost)
    if not paid then return fail(CMTaxi.Locale('rent_pay_fail')) end

    if GetResourceState('cm-vehicles') ~= 'started' then
        refundRental(src, { cost = cost, account = account })
        return fail('The vehicle service is unavailable. You were refunded.')
    end

    local plate = nextRentalPlate()
    if not plate then
        refundRental(src, { cost = cost, account = account })
        return fail('A unique taxi plate could not be assigned. You were refunded.')
    end

    local ok, result = pcall(function()
        return exports['cm-vehicles']:SpawnAdminVehicle(src, levelConfig.spawnModel, {
            x = spawn.x,
            y = spawn.y,
            z = spawn.z,
            h = spawn.w,
        }, {
            placementKind = 'car',
            label = 'CM Taxi Rental',
            plate = plate,
            engineOn = true,
        })
    end)
    if not ok or type(result) ~= 'table' or result.ok ~= true or not result.plate then
        refundRental(src, { cost = cost, account = account })
        return fail('The rental vehicle failed to spawn. You were refunded.')
    end

    local rental = {
        entity = result.entity,
        netId = result.netId,
        plate = result.plate,
        cost = cost,
        account = account,
        officeKey = officeKey,
        hasBeenDriven = false,
        abandonedAt = nil,
    }

    local keyGranted = false
    if GetResourceState('cm-vehiclekeys') == 'started' then
        local keyOk, granted = pcall(function()
            return exports['cm-vehiclekeys']:GiveTempKey(0, src, result.plate, {})
        end)
        keyGranted = keyOk and granted == true
    end
    if not keyGranted then
        deleteRentalVehicle(rental)
        refundRental(src, rental)
        return fail('The rental key could not be issued. You were refunded.')
    end

    rentals[src] = rental
    TriggerClientEvent('cm-taxi:client:rentalIdleTimer', src, nil)
    TriggerClientEvent('cm-taxi:client:rentalState', src, {
        plate = rental.plate,
        cost = rental.cost,
        officeKey = rental.officeKey,
        netId = rental.netId,
    })
    respond({
        success = true,
        netId = rental.netId,
        rental = {
            plate = rental.plate,
            cost = rental.cost,
            officeKey = rental.officeKey,
            netId = rental.netId,
        },
    })
end)

RegisterNetEvent('cm-taxi:server:returnTaxi', function(reqId)
    local src = source
    local function respond(data)
        TriggerClientEvent('cm-taxi:client:returnResult', src, reqId, data)
    end
    if rateLimited(src, 'returnTaxi', 1500) then return respond({ success = false }) end

    local rental = rentals[src]
    if not rental then
        notify(src, CMTaxi.Locale('no_rental'), 'error')
        return respond({ success = false })
    end
    if CMTaxi.Server.CanReturnRental and not CMTaxi.Server.CanReturnRental(src) then
        notify(src, 'Finish or cancel your active fare before returning the taxi.', 'error')
        return respond({ success = false })
    end
    if not refundRental(src, rental) then
        notify(src, 'The rental could not be refunded yet. Please try again.', 'error')
        return respond({ success = false })
    end

    revokeRentalKey(src, rental)
    deleteRentalVehicle(rental)
    rentals[src] = nil
    lastRequests[src] = nil
    TriggerClientEvent('cm-taxi:client:rentalIdleTimer', src, nil)
    TriggerClientEvent('cm-taxi:client:rentalState', src, nil)
    notify(src, 'Rental returned and refunded.', 'success')
    respond({ success = true })
end)

CMTaxi.Server.Rental = {
    Cleanup = cleanupRental,
    IsNearOffice = playerNearOffice,
}

AddEventHandler('playerDropped', function()
    cleanupRental(source, false)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for src in pairs(rentals) do
        cleanupRental(src, false)
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local now = GetGameTimer()
        for src, rental in pairs(rentals) do
            if not rental.entity or not DoesEntityExist(rental.entity) then
                expireRental(src, rental)
            else
                local playerPed = GetPlayerPed(src)
                local driverVehicle = playerPed and playerPed ~= 0 and GetVehiclePedIsIn(playerPed, false) or 0
                local isDriver = driverVehicle ~= 0
                    and driverVehicle == rental.entity
                    and GetPedInVehicleSeat(rental.entity, -1) == playerPed

                if isDriver then
                    rental.hasBeenDriven = true
                    if rental.abandonedAt then
                        TriggerClientEvent('cm-taxi:client:rentalIdleTimer', src, nil)
                    end
                    rental.abandonedAt = nil
                elseif rental.hasBeenDriven then
                    if not rental.abandonedAt then
                        rental.abandonedAt = now
                        TriggerClientEvent('cm-taxi:client:rentalIdleTimer', src, Config.RentalIdleGraceMs)
                    end
                    if now - rental.abandonedAt >= Config.RentalIdleGraceMs then
                        expireRental(src, rental)
                    end
                end
            end
        end
    end
end)
