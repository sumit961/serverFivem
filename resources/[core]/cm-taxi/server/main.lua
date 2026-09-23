local Config = CMTaxi.Config
CMTaxi.Server = CMTaxi.Server or {}

local fares = {}
local drivers = {} -- [src] = { activeFare = false|id }
local nextFareId = 0
local lastActions = {}
local routeHistory = {}
local routeHistoryReady = false
local completedFareResults = {}
local completedFareOrder = {}

local function validFareId(value)
    if type(value) ~= 'number' and type(value) ~= 'string' then return nil end
    local id = tonumber(value)
    if not id or id ~= id or id < 1 or id > nextFareId or id % 1 ~= 0 then return nil end
    return id
end

local function sendRequestResult(src, eventName, reqId, data)
    if type(reqId) ~= 'string' or #reqId > 80 or not reqId:match('^[%w%-]+$') then return end
    TriggerClientEvent(eventName, src, reqId, data)
end

GlobalState.cmTaxiFares = {}
GlobalState.cmTaxiDrivers = { count = 0 }

math.randomseed(os.time())

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `cm_taxi_route_history` (
        `route_key` VARCHAR(128) NOT NULL PRIMARY KEY,
        `available_after` BIGINT NOT NULL
    )]])
    local rows = MySQL.query.await(
        'SELECT route_key, available_after FROM cm_taxi_route_history WHERE available_after > ?',
        { os.time() }
    ) or {}
    for _, row in ipairs(rows) do
        routeHistory[row.route_key] = tonumber(row.available_after) or 0
    end
    routeHistoryReady = true
end)

local function dbg(...)
    if Config.Debug then print('[CM-TAXI]', ...) end
end

local function notify(src, message, kind)
    TriggerClientEvent('cm-taxi:client:notify', src, message, kind or 'info')
end

local function notifyTaxiRequester(fare, status, data)
    local requester = tonumber(fare and fare.requestedBy)
    if fare and fare.playerRequested and requester and GetPlayerName(requester) then
        data = type(data) == 'table' and data or {}
        data.fareId = data.fareId or fare.id
        TriggerClientEvent('cm-taxi:client:taxiRequestStatus', requester, status, data)
    end
end

local function farePassengerPed(fare)
    local passenger = tonumber(fare and fare.requestedBy)
    if not passenger or not GetPlayerName(passenger) then return nil end
    local ped = GetPlayerPed(passenger)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

local function fareTaxiVehicle(fare)
    local netId = math.floor(tonumber(fare and fare.taxiNetId) or 0)
    if netId <= 0 then return nil end
    local ok, vehicle = pcall(function() return NetworkGetEntityFromNetworkId(netId) end)
    if not ok or not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    if GetEntityType(vehicle) ~= 2 or not Config.Vehicles[GetEntityModel(vehicle)] then return nil end
    return vehicle
end

local function sameFareRoutingBucket(fare, driverSrc, vehicle)
    local passenger = tonumber(fare and fare.requestedBy)
    if not passenger or not driverSrc then return false end
    local passengerOk, passengerBucket = pcall(GetPlayerRoutingBucket, passenger)
    local driverOk, driverBucket = pcall(GetPlayerRoutingBucket, tonumber(driverSrc))
    local vehicleOk, vehicleBucket = pcall(GetEntityRoutingBucket, vehicle)
    return passengerOk and driverOk and vehicleOk
        and passengerBucket == driverBucket and passengerBucket == vehicleBucket
end

local function fareCustomerEntity(fare, src)
    local netId = math.floor(tonumber(fare and fare.customerNetId) or 0)
    if netId <= 0 then return nil end

    local ok, entity = pcall(function() return NetworkGetEntityFromNetworkId(netId) end)
    if not ok or not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    if GetEntityType(entity) ~= 1 or GetEntityModel(entity) ~= GetHashKey(fare.model) then return nil end

    if src then
        local playerBucketOk, playerBucket = pcall(GetPlayerRoutingBucket, tonumber(src))
        local entityBucketOk, entityBucket = pcall(GetEntityRoutingBucket, entity)
        if playerBucketOk and entityBucketOk and playerBucket ~= entityBucket then return nil end
    end

    return entity
end

local function deleteFareCustomer(fare, src)
    local entity = fareCustomerEntity(fare, src)
    if entity then DeleteEntity(entity) end
    if fare then fare.customerNetId = nil end
end

local function releaseFareAssignment(id, fare, driverSrc)
    if not fare or fare.finishing then return false end
    local assignedDriver = tonumber(driverSrc or fare.driver)
    deleteFareCustomer(fare, assignedDriver)
    fare.driver = nil
    fare.phase = nil
    fare.assignedAt = nil
    fare.boardedAt = nil
    fare.vehicleBodyHealthAtBoard = nil
    fare.taxiNetId = nil
    fare.finishing = nil

    local driver = assignedDriver and drivers[assignedDriver]
    if driver and tostring(driver.activeFare) == tostring(id) then
        driver.activeFare = false
    end
    notifyTaxiRequester(fare, 'searching')
    return true
end

local function rememberCompletedFare(id, src)
    completedFareResults[id] = { source = src, completedAt = GetGameTimer() }
    completedFareOrder[#completedFareOrder + 1] = id
    if #completedFareOrder > 256 then
        local oldest = table.remove(completedFareOrder, 1)
        completedFareResults[oldest] = nil
    end
end

local function taxiEtaMinutes(src, pickup)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return 1 end
    local distance = #(GetEntityCoords(ped) - pickup)
    local speed = math.max(1.0, tonumber(Config.TaxiEtaSpeedMps) or 8.0)
    return math.max(1, math.ceil(distance / speed / 60.0))
end

local function rateLimited(src, action, cooldownMs)
    src = tonumber(src) or 0
    local now = GetGameTimer()
    lastActions[src] = lastActions[src] or {}
    local last = lastActions[src][action] or 0
    if now - last < (tonumber(cooldownMs) or 500) then return true end
    lastActions[src][action] = now
    return false
end

local function tableCount(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function publishDriverState()
    GlobalState.cmTaxiDrivers = { count = tableCount(drivers) }
end

local function publishFareState()
    local public = {}
    for id, fare in pairs(fares) do
        if not fare.playerRequested then
            public[id] = {
                start = fare.start,
                finish = fare.finish,
                fare = fare.fare,
                xp = fare.xp,
                name = fare.name,
                model = fare.model,
                driver = fare.driver ~= nil and true or nil,
                expiresAt = fare.expiresAt,
            }
        end
    end
    GlobalState.cmTaxiFares = public

    for driverSrc in pairs(drivers) do
        local driverPed = GetPlayerPed(driverSrc)
        local driverBucketOk, driverBucket = pcall(GetPlayerRoutingBucket, tonumber(driverSrc))
        local offers = {}
        if driverPed and driverPed ~= 0 and DoesEntityExist(driverPed) and driverBucketOk then
            local driverCoords = GetEntityCoords(driverPed)
            for id, fare in pairs(fares) do
                if fare.playerRequested and fare.driver == nil then
                    local passenger = tonumber(fare.requestedBy)
                    local passengerBucketOk, passengerBucket = pcall(GetPlayerRoutingBucket, passenger)
                    if passenger and GetPlayerName(passenger) and passengerBucketOk
                        and passengerBucket == driverBucket then
                        local pickupDistance = #(fare.start - driverCoords)
                        offers[tostring(id)] = {
                            name = 'Passenger',
                            start = fare.start,
                            fare = fare.fare,
                            distance = math.floor(pickupDistance + 0.5),
                            tripDistance = math.floor(#(fare.finish - fare.start) + 0.5),
                            nearby = pickupDistance <= (tonumber(Config.NearbyFareDistance) or 500.0),
                            playerRequested = true,
                            expiresAt = fare.expiresAt,
                        }
                    end
                end
            end
        end
        TriggerClientEvent('cm-taxi:client:playerFareOffers', driverSrc, offers)
    end
end

local function endDutySilently(src)
    src = tonumber(src)
    if not src then return end

    local driver = drivers[src]
    if driver and driver.activeFare and driver.activeFare ~= false then
        local fare = fares[driver.activeFare]
        if fare and fare.playerRequested and fare.phase == 'boarded' then return false end
        if fare and fare.driver == src then
            releaseFareAssignment(driver.activeFare, fare, src)
        end
    end

    drivers[src] = nil
    local player = Player(src)
    if player then player.state:set('cmTaxiDuty', false, true) end
    CMTaxi.Server.Progression.Clear(src)

    TriggerClientEvent('cm-taxi:client:dutyResult', src, false)
    TriggerClientEvent('cm-taxi:client:progression', src, { xp = 0, level = 1 })
    TriggerClientEvent('cm-taxi:client:rentalState', src, nil)
    TriggerClientEvent('cm-taxi:client:rentalIdleTimer', src, nil)
    TriggerClientEvent('cm-taxi:client:rentalExpired', src)
    publishDriverState()
    publishFareState()
    return true
end

-- Internal handoff used by server/rental.lua when an idle rental expires.
CMTaxi.Server.EndDutySilently = endDutySilently
CMTaxi.Server.CanExpireRental = function(src)
    local driver = drivers[tonumber(src)]
    local fare = driver and driver.activeFare and fares[driver.activeFare]
    return not (fare and fare.playerRequested and fare.phase == 'boarded')
end

-- Manual rental return is blocked while a fare is assigned. Drivers can
-- cancel a pre-pickup fare first; a boarded passenger must be delivered.
CMTaxi.Server.CanReturnRental = function(src)
    local driver = drivers[tonumber(src)]
    local fare = driver and driver.activeFare and fares[driver.activeFare]
    return not (fare and fare.driver == tonumber(src))
end

local function round(value, decimals)
    local power = 10 ^ (decimals or 0)
    return math.floor((value * power) + 0.5) / power
end

-- Fare earnings bank into cm-payday's hourly payout when it's running
-- (salary paid at the top of every hour instead of per fare); falls back to
-- the old instant pay if cm-payday isn't started.
local function addMoney(src, amount, reason)
    if GetResourceState('cm-payday') == 'started' then
        local ok, result = pcall(function() return exports['cm-payday']:AddPendingCash(src, 'taxi', amount, reason) end)
        if ok and result == true then return true end
    end
    if GetResourceState('cm-playerdata') ~= 'started' then return false end
    local ok, result = pcall(function() return exports['cm-playerdata']:AddCash(src, amount, reason) end)
    return ok and result == true
end

local function getCharacterLabel(src)
    return 'Passenger'
end

local function routeKey(pickup, dropoff)
    local function pointKey(coords)
        return ('%d:%d'):format(math.floor(coords.x / 100), math.floor(coords.y / 100))
    end
    return ('%s>%s'):format(pointKey(pickup), pointKey(dropoff))
end

local function routeIsRecent(key)
    local expiresAt = routeHistory[key]
    if not expiresAt then return false end
    if expiresAt <= os.time() then
        routeHistory[key] = nil
        return false
    end
    return true
end

local function reserveRoute(key)
    if not routeHistoryReady or routeIsRecent(key) then return false end
    local availableAfter = os.time() + math.floor(Config.FareRepeatCooldownMs / 1000)
    local ok = pcall(function()
        MySQL.update.await([[INSERT INTO cm_taxi_route_history (route_key, available_after)
            VALUES (?, ?) ON DUPLICATE KEY UPDATE available_after = VALUES(available_after)]],
            { key, availableAfter }
        )
    end)
    if not ok then return false end
    routeHistory[key] = availableAfter
    return true
end

local function nearestDriverDistance(coords)
    local nearest
    for src in pairs(drivers) do
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local distance = #(coords - GetEntityCoords(ped))
            if not nearest or distance < nearest then nearest = distance end
        end
    end
    return nearest
end

local function chooseClosePickup()
    local candidates = {}
    for _, location in ipairs(CMTaxi.Locations) do
        local distance = nearestDriverDistance(location)
        if distance and distance <= Config.FarePickupMaxDistance then
            candidates[#candidates + 1] = { coords = location, distance = distance }
        end
    end
    if #candidates == 0 then return nil end

    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    local choiceCount = math.min(5, #candidates)
    return candidates[math.random(choiceCount)].coords
end

local function generateFare(forcedPickup)
    if not routeHistoryReady or type(CMTaxi.Locations) ~= 'table' or #CMTaxi.Locations < 2 then return nil end
    local pickup = forcedPickup or chooseClosePickup()
    if not pickup then return nil end

    local dropoff
    local signature
    for _ = 1, 40 do
        local candidate = CMTaxi.Locations[math.random(#CMTaxi.Locations)]
        local candidateKey = routeKey(pickup, candidate)
        if #(candidate - pickup) >= Config.MinRouteDistance and not routeIsRecent(candidateKey) then
            dropoff = candidate
            signature = candidateKey
            break
        end
    end
    if not dropoff then return nil end

    local gender = math.random(1, 2)
    local distance = #(dropoff - pickup)

    return {
        pickup = pickup,
        dropoff = dropoff,
        signature = signature,
        fare = round((math.random(Config.FareMin, Config.FareMax) / 10) * distance / 10),
        xp = round(math.random(Config.XpMin, Config.XpMax) * distance / 1000, 1),
        name = CMTaxi.Names[gender][math.random(1, #CMTaxi.Names[gender])],
        model = CMTaxi.Peds[gender][math.random(1, #CMTaxi.Peds[gender])],
    }
end

local function broadcastToDrivers(message, kind)
    for src in pairs(drivers) do
        notify(src, message, kind)
    end
end

-- ============================================================
-- Duty
-- ============================================================

RegisterNetEvent('cm-taxi:server:toggleDuty', function(state, officeKey)
    local src = source
    if rateLimited(src, 'toggleDuty', 750) then return end
    state = state == true

    if state then
        local isNearOffice = CMTaxi.Server.Rental and CMTaxi.Server.Rental.IsNearOffice
        if not isNearOffice or not isNearOffice(src, officeKey, Config.OfficeServerDistance) then
            TriggerClientEvent('cm-taxi:client:dutyResult', src, false)
            return notify(src, 'You must be at a taxi office to go on duty.', 'error')
        end
    else
        local driver = drivers[src]
        local activeFare = driver and driver.activeFare and fares[driver.activeFare] or nil
        if activeFare and (activeFare.finishing or (activeFare.playerRequested and activeFare.phase == 'boarded')) then
            TriggerClientEvent('cm-taxi:client:dutyResult', src, true)
            local message = activeFare.finishing and CMTaxi.Locale('fare_finishing')
                or CMTaxi.Locale('player_fare_cannot_cancel')
            return notify(src, message, 'info')
        end
    end

    Player(src).state:set('cmTaxiDuty', state, true)
    TriggerClientEvent('cm-taxi:client:dutyResult', src, state)

    if state then
        if drivers[src] then return end
        local progression = CMTaxi.Server.Progression.Load(src)
        drivers[src] = {
            activeFare = false,
            progression = progression,
            shiftStats = { completed = 0, earnings = 0, tips = 0 },
        }
        TriggerClientEvent('cm-taxi:client:progression', src, progression or { xp = 0, level = 1 })
        TriggerClientEvent('cm-taxi:client:shiftStats', src, drivers[src].shiftStats)
        notify(src, CMTaxi.Locale('signin'), 'success')
    else
        if drivers[src] and drivers[src].activeFare then
            local id = drivers[src].activeFare
            if fares[id] then releaseFareAssignment(id, fares[id], src) end
        end
        local rentalCleaned = CMTaxi.Server.Rental.Cleanup(src, true)
        CMTaxi.Server.Progression.Clear(src)
        drivers[src] = nil
        TriggerClientEvent('cm-taxi:client:progression', src, { xp = 0, level = 1 })
        TriggerClientEvent('cm-taxi:client:rentalIdleTimer', src, nil)
        if rentalCleaned then
            TriggerClientEvent('cm-taxi:client:rentalState', src, nil)
        end
        notify(src, CMTaxi.Locale('signout'), 'info')
        publishFareState()
    end

    publishDriverState()
    publishFareState()
end)

-- ============================================================
-- Fares
-- ============================================================

RegisterNetEvent('cm-taxi:server:takeJob', function(reqId, id)
    local src = source
    local function respond(success)
        sendRequestResult(src, 'cm-taxi:client:takeJobResult', reqId, { success = success })
    end

    if rateLimited(src, 'takeJob', 500) then return respond(false) end
    id = validFareId(id)
    if not id then return respond(false) end
    if not Player(src).state.cmTaxiDuty then
        notify(src, CMTaxi.Locale('offduty'), 'error')
        return respond(false)
    end
    local playerPed = GetPlayerPed(src)
    local playerVehicle = playerPed and playerPed ~= 0 and GetVehiclePedIsIn(playerPed, false) or 0
    if playerVehicle == 0 or GetPedInVehicleSeat(playerVehicle, -1) ~= playerPed
        or not Config.Vehicles[GetEntityModel(playerVehicle)] then
        notify(src, 'You must be driving a taxi to accept a fare.', 'error')
        return respond(false)
    end

    local fare = fares[id]
    if not fare then return respond(false) end
    if fare.playerRequested and fare.requestedBy == src then
        notify(src, CMTaxi.Locale('taxi_request_self_accept'), 'warning')
        return respond(false)
    end
    if fare.driver == nil and fare.createdAt and GetGameTimer() - fare.createdAt >= Config.FareExpiryMs then
        fares[id] = nil
        notifyTaxiRequester(fare, 'expired')
        publishFareState()
        return respond(false)
    end
    if fare.driver ~= nil then
        notify(src, CMTaxi.Locale('fare_taken'), 'error')
        return respond(false)
    end

    local driver = drivers[src]
    if not driver or driver.activeFare ~= false then
        notify(src, CMTaxi.Locale('fare_active'), 'error')
        return respond(false)
    end
    if not driver.progression then
        notify(src, 'Your taxi profile is not ready. Please go off duty and sign in again.', 'error')
        return respond(false)
    end

    local playerFarePayload
    if fare.playerRequested then
        local passengerPed = farePassengerPed(fare)
        if not passengerPed then
            fares[id] = nil
            notifyTaxiRequester(fare, 'cancelled')
            publishFareState()
            return respond(false)
        end
        if not sameFareRoutingBucket(fare, src, playerVehicle) then
            notify(src, 'That passenger is not in the same routing instance.', 'error')
            return respond(false)
        end

        local taxiNetId = NetworkGetNetworkIdFromEntity(playerVehicle)
        if not taxiNetId or taxiNetId <= 0 then
            notify(src, 'Your taxi is not networked. Please use another taxi.', 'error')
            return respond(false)
        end

        fare.taxiNetId = taxiNetId
        fare.taxiModel = GetEntityModel(playerVehicle)
        playerFarePayload = {
            playerRequested = true,
            name = 'Passenger',
            start = fare.start,
            finish = fare.finish,
            fare = fare.fare,
            xp = fare.xp,
            taxiNetId = taxiNetId,
        }
    end

    fare.driver = src
    driver.activeFare = id
    fare.phase = 'assigned'
    fare.assignedAt = GetGameTimer()
    fare.finishing = false
    publishDriverState()
    publishFareState()

    if fare.playerRequested then
        notifyTaxiRequester(fare, 'accepted', {
            etaMinutes = taxiEtaMinutes(src, fare.start),
            taxiNetId = fare.taxiNetId,
            finish = fare.finish,
            driverCoords = GetEntityCoords(playerPed),
        })
    end

    TriggerClientEvent('cm-taxi:client:startJob', src, id, playerFarePayload)
    notify(src, CMTaxi.Locale('fare_started', fare.name), 'success')
    respond(true)
end)

RegisterNetEvent('cm-taxi:server:cancelJob', function(reqId, offduty)
    local src = source
    local function respond(success)
        if reqId then
            TriggerClientEvent('cm-taxi:client:cancelJobResult', src, reqId, { success = success })
        end
    end

    if rateLimited(src, 'cancelJob', 500) then return respond(false) end
    if offduty ~= true and not Player(src).state.cmTaxiDuty then
        notify(src, CMTaxi.Locale('offduty'), 'error')
        return respond(false)
    end

    local driver = drivers[src]
    if not driver or driver.activeFare == false then return respond(false) end

    local id = driver.activeFare
    local fare = fares[id]
    if fare and fare.finishing then return respond(false) end
    if fare and fare.playerRequested and fare.phase == 'boarded' then
        notify(src, CMTaxi.Locale('player_fare_cannot_cancel'), 'warning')
        return respond(false)
    end
    if fare then releaseFareAssignment(id, fare, src) else driver.activeFare = false end
    publishDriverState()
    publishFareState()

    notify(src, CMTaxi.Locale('fare_cancelled'), 'info')

    respond(true)
end)

RegisterNetEvent('cm-taxi:server:boardPassenger', function(reqId, id)
    local src = source
    local function respond(success, data)
        sendRequestResult(src, 'cm-taxi:client:boardPassengerResult', reqId, data or { success = success })
    end

    if rateLimited(src, 'boardPassenger', 1000) then return respond(false) end
    id = validFareId(id)
    if not id then return respond(false) end

    local fare = fares[id]
    if not fare or not fare.playerRequested or tonumber(fare.requestedBy) ~= tonumber(src)
        or fare.phase ~= 'assigned' or not fare.driver then
        return respond(false)
    end

    local driverSrc = tonumber(fare.driver)
    local driver = driverSrc and drivers[driverSrc]
    local passengerPed = farePassengerPed(fare)
    local driverPed = driverSrc and GetPlayerPed(driverSrc) or 0
    local vehicle = fareTaxiVehicle(fare)
    if not driver or driver.activeFare ~= id or not passengerPed or not driverPed or driverPed == 0
        or not vehicle or GetEntityHealth(passengerPed) <= 0 then
        return respond(false)
    end
    if not sameFareRoutingBucket(fare, driverSrc, vehicle) then return respond(false) end
    if GetPedInVehicleSeat(vehicle, -1) ~= driverPed
        or GetVehiclePedIsIn(passengerPed, false) ~= vehicle
        or GetPedInVehicleSeat(vehicle, -1) == passengerPed
        or #(GetEntityCoords(vehicle) - fare.start) > (Config.PlayerPickupValidationDistance or 60.0) then
        return respond(false)
    end

    fare.phase = 'boarded'
    fare.boardedAt = GetGameTimer()
    local healthOk, health = pcall(GetVehicleBodyHealth, vehicle)
    fare.vehicleBodyHealthAtBoard = healthOk and tonumber(health) or nil
    publishFareState()

    TriggerClientEvent('cm-taxi:client:playerFareBoarded', driverSrc, id, fare.finish)
    respond(true, { success = true, finish = fare.finish })
end)

RegisterNetEvent('cm-taxi:server:passengerAbandoned', function(id)
    local src = source
    if rateLimited(src, 'passengerAbandoned', 1500) then return end
    id = validFareId(id)
    if not id then return end

    local fare = fares[id]
    if not fare or not fare.playerRequested or tonumber(fare.requestedBy) ~= tonumber(src)
        or fare.phase ~= 'boarded' then return end
    local passengerPed = farePassengerPed(fare)
    if not passengerPed then return end

    local vehicle = fareTaxiVehicle(fare)
    local passengerDead = GetEntityHealth(passengerPed) <= 0
    local passengerInTaxi = vehicle and GetVehiclePedIsIn(passengerPed, false) == vehicle
    local nearDestination = #(GetEntityCoords(passengerPed) - fare.finish) <= Config.FareDropoffValidationDistance
    if not passengerDead and vehicle and (passengerInTaxi or nearDestination) then return end

    local driverSrc = tonumber(fare.driver)
    local driver = driverSrc and drivers[driverSrc]
    if driver and tostring(driver.activeFare) == tostring(id) then driver.activeFare = false end
    if driverSrc then
        TriggerClientEvent('cm-taxi:client:jobCancelled', driverSrc,
            CMTaxi.Locale('player_fare_passenger_left'))
    end
    fares[id] = nil
    notifyTaxiRequester(fare, 'cancelled')
    publishDriverState()
    publishFareState()
end)

RegisterNetEvent('cm-taxi:server:boardJob', function(reqId, id)
    local src = source
    local function respond(success)
        sendRequestResult(src, 'cm-taxi:client:boardJobResult', reqId, { success = success })
    end
    if rateLimited(src, 'boardJob', 750) then return respond(false) end
    id = validFareId(id)
    if not id then return respond(false) end

    local deadline = GetGameTimer() + 5000
    repeat
        local driver = drivers[src]
        local fare = driver and driver.activeFare and fares[driver.activeFare] or nil
        local ped = GetPlayerPed(src)
        local vehicle = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
        local correctDriver = fare and tostring(driver.activeFare) == tostring(id) and fare.driver == src
        local validTaxi = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
            and Config.Vehicles[GetEntityModel(vehicle)] == true
        local nearPickup = correctDriver and validTaxi
            and #(fare.start - GetEntityCoords(ped)) <= (Config.CustomerNearbyDistance + 20.0)
        local customer = correctDriver and fareCustomerEntity(fare, src) or nil

        if correctDriver and fare.phase == 'assigned' and nearPickup and customer
            and GetVehiclePedIsIn(customer, false) == vehicle then
            fare.phase = 'boarded'
            fare.boardedAt = GetGameTimer()
            local healthOk, health = pcall(GetVehicleBodyHealth, vehicle)
            fare.vehicleBodyHealthAtBoard = healthOk and tonumber(health) or nil
            return respond(true)
        end

        if GetGameTimer() >= deadline then break end
        Wait(100)
    until false

    respond(false)
end)

RegisterNetEvent('cm-taxi:server:registerCustomer', function(id, customerNetId)
    local src = source
    if rateLimited(src, 'registerCustomer', 500) then return end
    id = validFareId(id)
    if not id then return end
    local driver = drivers[src]
    local fare = driver and driver.activeFare and fares[driver.activeFare] or nil
    if not fare or tostring(driver.activeFare) ~= tostring(id) or fare.driver ~= src
        or fare.phase ~= 'assigned' or fare.customerNetId then return end

    if type(customerNetId) ~= 'number' or customerNetId ~= customerNetId
        or customerNetId < 1 or customerNetId > 65535 or customerNetId % 1 ~= 0 then return end
    local netId = customerNetId
    local ok, entity = pcall(function() return NetworkGetEntityFromNetworkId(netId) end)
    if not ok or not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 1 then return end
    if GetEntityModel(entity) ~= GetHashKey(fare.model) then return end
    if #(GetEntityCoords(entity) - fare.start) > 20.0 then return end
    local ownerOk, owner = pcall(function() return NetworkGetEntityOwner(entity) end)
    if not ownerOk or tonumber(owner) ~= tonumber(src) then return end

    fare.customerNetId = netId
end)

RegisterNetEvent('cm-taxi:server:customerDead', function(id)
    local src = source
    if rateLimited(src, 'customerDead', 1000) then return end
    id = validFareId(id)
    if not id then return end
    local driver = drivers[src]
    local fare = driver and driver.activeFare and fares[driver.activeFare] or nil
    if not fare or tostring(driver.activeFare) ~= tostring(id) or fare.driver ~= src then return end

    local entity = fareCustomerEntity(fare, src)
    if not entity or GetEntityHealth(entity) > 0 then return end
    DeleteEntity(entity)

    fares[driver.activeFare] = nil
    driver.activeFare = false
    notifyTaxiRequester(fare, 'cancelled')
    publishDriverState()
    publishFareState()
    notify(src, CMTaxi.Locale('fare_cancelled'), 'info')
end)

RegisterNetEvent('cm-taxi:server:finishJob', function(reqId, id)
    local src = source
    local ped = GetPlayerPed(src)
    local function respond(success, error)
        sendRequestResult(src, 'cm-taxi:client:finishJobResult', reqId, { success = success, error = error })
    end

    if rateLimited(src, 'finishJob', 750) then return respond(false, 'Please wait before trying again.') end
    id = validFareId(id)
    if not id then return respond(false, 'This fare is no longer active.') end
    local completed = completedFareResults[id]
    if completed and completed.source == src and GetGameTimer() - completed.completedAt <= 120000 then
        return respond(true)
    end
    if not Player(src).state.cmTaxiDuty then return respond(false, CMTaxi.Locale('offduty')) end
    local driver = drivers[src]
    if not driver or tostring(driver.activeFare) ~= tostring(id) then return respond(false, 'This is not your active fare.') end

    local fare = fares[id]
    if not fare or fare.driver ~= src then return respond(false, 'This fare is no longer active.') end
    if fare.finishing then return respond(false, 'This fare is already being completed.') end
    if fare.phase ~= 'boarded' then return respond(false, 'The passenger has not boarded yet.') end
    local vehicle = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped or not Config.Vehicles[GetEntityModel(vehicle)] then
        return respond(false, 'You must be driving a taxi to complete the fare.')
    end
    if fare.playerRequested then
        local assignedTaxi = fareTaxiVehicle(fare)
        if not assignedTaxi or assignedTaxi ~= vehicle
            or not sameFareRoutingBucket(fare, src, vehicle) then
            return respond(false, 'You must finish this trip in the assigned taxi.')
        end
    end
    if #(fare.finish - GetEntityCoords(ped)) > 25.0 then return respond(false, 'Move closer to the destination.') end

    local customer = fare.playerRequested and farePassengerPed(fare) or fareCustomerEntity(fare, src)
    if not customer or GetEntityHealth(customer) <= 0 then
        return respond(false, 'The passenger is no longer available.')
    end
    if GetVehiclePedIsIn(customer, false) ~= 0 then
        return respond(false, 'The passenger must exit the taxi before the fare can finish.')
    end
    if #(fare.finish - GetEntityCoords(customer)) > Config.FareDropoffValidationDistance then
        return respond(false, 'The passenger must be dropped off at the destination.')
    end

    local tip = 0
    local pickupDuration = tonumber(fare.boardedAt) and tonumber(fare.assignedAt)
        and fare.boardedAt - fare.assignedAt or math.huge
    local healthOk, currentBodyHealth = pcall(GetVehicleBodyHealth, vehicle)
    if fare.vehicleBodyHealthAtBoard and healthOk and pickupDuration <= Config.ServiceTipPickupDeadlineMs then
        local bodyDamage = math.max(0, fare.vehicleBodyHealthAtBoard - (tonumber(currentBodyHealth) or 0))
        if bodyDamage <= Config.ServiceTipMaxBodyDamage then
            tip = math.min(Config.ServiceTipMax, math.floor(fare.fare * Config.ServiceTipPercent))
        end
    end

    local payout = round(fare.fare + Config.FuelBonus + tip)
    fare.finishing = true
    if not addMoney(src, payout, ('Taxi fare: %s'):format(fare.name)) then
        fare.finishing = false
        if not GetPlayerName(src) then
            releaseFareAssignment(id, fare, src)
            publishDriverState()
            publishFareState()
        end
        return respond(false, 'Payment could not be processed. The fare is still active.')
    end

    driver.shiftStats = driver.shiftStats or { completed = 0, earnings = 0, tips = 0 }
    driver.shiftStats.completed = driver.shiftStats.completed + 1
    driver.shiftStats.earnings = driver.shiftStats.earnings + payout
    driver.shiftStats.tips = driver.shiftStats.tips + tip
    if not fare.playerRequested then deleteFareCustomer(fare, src) end
    local xpOk, xpError
    if GetResourceState('cm-payday') == 'started' then
        xpOk, xpError = pcall(function() exports['cm-payday']:AddPendingXp(src, 'taxi', fare.xp) end)
    else
        xpOk, xpError = pcall(CMTaxi.Server.Progression.AddXp, src, fare.xp)
    end
    if not xpOk then
        print(('[cm-taxi] fare XP award failed for fare %s: %s'):format(id, tostring(xpError)))
    end

    driver.activeFare = false
    fares[id] = nil
    rememberCompletedFare(id, src)
    notifyTaxiRequester(fare, 'completed')
    TriggerClientEvent('cm-taxi:client:shiftStats', src, driver.shiftStats)
    publishDriverState()
    publishFareState()
    notify(src, CMTaxi.Locale('fare_completed', payout, tip, fare.xp,
        driver.shiftStats.completed, driver.shiftStats.earnings), 'success')
    respond(true)
end)

RegisterNetEvent('cm-taxi:server:ping', function(sentAt)
    if rateLimited(source, 'ping', 1000) then return end
    TriggerClientEvent('cm-taxi:client:pong', source, sentAt)
end)

-- Any player can flag down a taxi from wherever they are standing.
local function requestTaxi(src)
    if src == 0 then return end
    if rateLimited(src, 'taxiCall', Config.TaxiCallCooldownMs) then
        return notify(src, 'Please wait before requesting another taxi.', 'error')
    end
    local requestBucketOk, requestBucket = pcall(GetPlayerRoutingBucket, tonumber(src))
    if not requestBucketOk then
        return notify(src, 'Taxi dispatch is temporarily unavailable.', 'error')
    end
    local hasOtherDriver = false
    for driverSrc in pairs(drivers) do
        if driverSrc ~= src then
            local driverBucketOk, driverBucket = pcall(GetPlayerRoutingBucket, tonumber(driverSrc))
            if driverBucketOk and driverBucket == requestBucket then
                hasOtherDriver = true
                break
            end
        end
    end
    if not hasOtherDriver then
        notify(src, 'No taxi drivers are currently on duty.', 'error')
        return
    end

    for _, fare in pairs(fares) do
        if fare.playerRequested and fare.requestedBy == src then
            if fare.driver ~= nil then
                notify(src, CMTaxi.Locale('taxi_request_on_way'), 'info')
            else
                notify(src, CMTaxi.Locale('taxi_request_pending'), 'info')
            end
            return
        end
    end

    if tableCount(fares) >= Config.MaxFares then
        return notify(src, 'Taxi dispatch is busy right now. Please try again shortly.', 'warning')
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) or GetEntityHealth(ped) <= 0 then
        return notify(src, 'You must be alive to request a taxi.', 'error')
    end
    local pickup = GetEntityCoords(ped)
    local route = generateFare(pickup)
    if not route then
        return notify(src, 'Taxi routes are temporarily unavailable.', 'error')
    end
    if not reserveRoute(route.signature) then
        return notify(src, 'That taxi route was used recently. Please try again shortly.', 'error')
    end
    nextFareId = nextFareId + 1
    local id = nextFareId
    local distance = #(route.dropoff - pickup)
    fares[id] = {
        id = id,
        start = pickup,
        finish = route.dropoff,
        fare = round((math.random(Config.FareMin, Config.FareMax) / 10) * distance / 10),
        xp = round(math.random(Config.XpMin, Config.XpMax) * distance / 1000, 1),
        name = 'Passenger',
        driver = nil,
        playerRequested = true,
        requestedBy = src,
        createdAt = GetGameTimer(),
        expiresAt = os.time() + math.ceil(Config.FareExpiryMs / 1000),
    }
    publishFareState()

    for driverSrc in pairs(drivers) do
        local driverBucketOk, driverBucket = pcall(GetPlayerRoutingBucket, tonumber(driverSrc))
        if driverBucketOk and driverBucket == requestBucket then
            notify(driverSrc, CMTaxi.Locale('fare_new'), 'info')
        end
    end
    notifyTaxiRequester(fares[id], 'queued')
end

RegisterCommand('taxi', requestTaxi, false)
RegisterCommand('texi', requestTaxi, false)

RegisterNetEvent('cm-taxi:server:cancelTaxiRequest', function()
    local src = source
    if rateLimited(src, 'cancelTaxiRequest', 1000) then return end

    for id, fare in pairs(fares) do
        if fare.playerRequested and fare.requestedBy == src then
            if fare.driver ~= nil then
                if fare.phase == 'boarded' then
                    return notify(src, CMTaxi.Locale('player_fare_cannot_cancel'), 'warning')
                end
                local driverSrc = tonumber(fare.driver)
                local driver = driverSrc and drivers[driverSrc]
                if driver and tostring(driver.activeFare) == tostring(id) then driver.activeFare = false end
                if driverSrc then
                    TriggerClientEvent('cm-taxi:client:jobCancelled', driverSrc,
                        CMTaxi.Locale('taxi_request_cancelled_by_passenger'))
                end
            end
            fares[id] = nil
            publishFareState()
            notifyTaxiRequester(fare, 'cancelled')
            return
        end
    end

    notify(src, CMTaxi.Locale('taxi_request_none'), 'info')
end)

-- ============================================================
-- Cleanup / fare generation
-- ============================================================

AddEventHandler('playerDropped', function()
    local src = source
    if drivers[src] and drivers[src].activeFare and drivers[src].activeFare ~= false then
        local id = drivers[src].activeFare
        local fare = fares[id]
        -- Let the player-fare cleanup below cancel boarded trips. Releasing it
        -- here would erase the assignment before that branch can notify the
        -- passenger, leaving their live ride stranded.
        if fare and not (fare.playerRequested and fare.phase == 'boarded') then
            releaseFareAssignment(id, fare, src)
        end
    end
    for id, fare in pairs(fares) do
        if fare.requestedBy == src then
            if fare.finishing then
                fare.requestedBy = nil
                fare.playerRequested = false
            else
                local assignedDriver = tonumber(fare.driver)
                if assignedDriver and assignedDriver ~= src then
                    local driver = drivers[assignedDriver]
                    if driver and tostring(driver.activeFare) == tostring(id) then driver.activeFare = false end
                    TriggerClientEvent('cm-taxi:client:jobCancelled', assignedDriver, CMTaxi.Locale('taxi_requester_left'))
                    releaseFareAssignment(id, fare, assignedDriver)
                end
                fares[id] = nil
            end
        elseif fare.driver == src then
            if fare.playerRequested and fare.phase == 'boarded' and not fare.finishing then
                local passenger = tonumber(fare.requestedBy)
                fares[id] = nil
                notifyTaxiRequester(fare, 'cancelled')
                if passenger and GetPlayerName(passenger) then
                    notify(passenger, CMTaxi.Locale('player_fare_driver_left'), 'warning')
                end
            else
                releaseFareAssignment(id, fare, src)
            end
        end
    end
    CMTaxi.Server.Rental.Cleanup(src, false)
    CMTaxi.Server.Progression.Clear(src)
    drivers[src] = nil
    lastActions[src] = nil
    publishDriverState()
    publishFareState()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, fare in pairs(fares) do
        deleteFareCustomer(fare, fare.driver)
    end
    for src in pairs(drivers) do
        Player(src).state:set('cmTaxiDuty', false, true)
        CMTaxi.Server.Rental.Cleanup(src, false)
        CMTaxi.Server.Progression.Clear(src)
    end
    drivers = {}
    publishDriverState()
    publishFareState()
end)

CreateThread(function()
    while true do
        local sleep = 500
        if tableCount(drivers) >= 1 then
            sleep = Config.NewFareIntervalMs
            if tableCount(fares) < Config.MaxFares then
                local fare = generateFare()
                if fare and reserveRoute(fare.signature) then
                    nextFareId = nextFareId + 1
                    fares[nextFareId] = {
                        id = nextFareId,
                        start = fare.pickup,
                        finish = fare.dropoff,
                        fare = fare.fare,
                        name = fare.name,
                        model = fare.model,
                        xp = fare.xp,
                        driver = nil,
                        createdAt = GetGameTimer(),
                        expiresAt = os.time() + math.ceil(Config.FareExpiryMs / 1000),
                    }
                    publishFareState()
                    broadcastToDrivers(CMTaxi.Locale('fare_new'), 'info')
                end
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    local lastRouteCleanup = 0
    while true do
        Wait(30000)
        local now = GetGameTimer()
        local changed = false
        for id, fare in pairs(fares) do
            if fare.driver ~= nil and fare.assignedAt and not fare.finishing then
                local assignedDriver = tonumber(fare.driver)
                local timerStart = fare.phase == 'boarded' and fare.boardedAt or fare.assignedAt
                local timeout = fare.phase == 'boarded'
                    and Config.FareTripTimeoutMs or Config.FarePickupAssignmentTimeoutMs
                if timerStart and now - timerStart >= timeout then
                    local driver = assignedDriver and drivers[assignedDriver]
                    if driver and tostring(driver.activeFare) == tostring(id) then
                        driver.activeFare = false
                        TriggerClientEvent('cm-taxi:client:jobCancelled', assignedDriver, CMTaxi.Locale('fare_timeout'))
                    end
                    if fare.playerRequested and fare.phase == 'boarded' then
                        fares[id] = nil
                        notifyTaxiRequester(fare, 'cancelled')
                    else
                        releaseFareAssignment(id, fare, assignedDriver)
                    end
                    changed = true
                end
            end

            if fare.driver == nil and fare.createdAt and now - fare.createdAt >= Config.FareExpiryMs then
                fares[id] = nil
                notifyTaxiRequester(fare, 'expired')
                changed = true
            end
        end
        if changed then publishFareState() end

        if routeHistoryReady and os.time() - lastRouteCleanup >= 300 then
            lastRouteCleanup = os.time()
            for key, expiresAt in pairs(routeHistory) do
                if expiresAt <= lastRouteCleanup then routeHistory[key] = nil end
            end
            pcall(function()
                MySQL.update.await('DELETE FROM cm_taxi_route_history WHERE available_after <= ?', { lastRouteCleanup })
            end)
        end
    end
end)
