local guiEnabled = false
local focustablet = false
local taxiDuty = false
local isEntering = false
local nearCustomer = false
local enteredVehicle = false
local customer = nil
local customerBlip = nil
local oldBlip = nil
local dropoffBlip = nil
local currentJob = nil
local currentZone = nil
local keybind = nil
local npc = nil
local vehThread = false
local camThread = false
local ped = cache.ped
local vehicle = cache.vehicle

local function SendReactMessage(action, data)
    SendNUIMessage({
        action = action,
        data = data
    })
end

local function toggleNuiFrame(shouldShow)
    SendReactMessage('setVisible', shouldShow)
    isdisplayed = shouldShow
end

local function isPointClear(entities, isPlayerEntities, coords, maxDistance)
    local nearbyEntities = {}
    if coords then
        coords = vector3(coords.x, coords.y, coords.z)
    else
        coords = GetEntityCoords(ped)
    end

    for k, entity in pairs(entities) do
        if #(coords - GetEntityCoords(entity)) <= maxDistance then
            nearbyEntities[#nearbyEntities + 1] = isPlayerEntities and k or entity
        end
    end
    return nearbyEntities
end

local function inTaxi()
    if vehicle ~= false then
        local model = GetEntityModel(vehicle)
        if Config.Vehicles[model] then
            return true
        end
        return false
    end
    return false
end

local function openUI()
    guiEnabled = true
    toggleNuiFrame(true)
end

local function closeUI()
    if guiEnabled then
        toggleNuiFrame(false)
        guiEnabled = false
        SetPlayerControl(cache.playerId, true, 0)
    end
end

local function updateMeter()
    local data = {}
    data.keybind = GetControlInstructionalButton(0, joaat('+' .. keybind.name) | 0x80000000, true):sub(3)
    data.speed = { velocity = math.floor(GetEntitySpeed(vehicle) * 2.236936) }
    data.fares = GlobalState.taxiFares
    if currentJob == nil then
        data.currentfareinfo = { customer = '-', destination = '-', currentfare = '0.00', perminute = '0.00', basefare = '0.00'}
        SendReactMessage('setData', data)
        return
    end
    local fare = GlobalState.taxiFares[currentJob]
    local zoneNameFull = zones[GetNameOfZone(fare.finish.x, fare.finish.y, fare.finish.z)]
    local streetName = zoneNameFull ~= nil and string.format('%s, %s', GetStreetNameFromHashKey(GetStreetNameAtCoord(fare.finish.x, fare.finish.y, fare.finish.z)), zoneNameFull) or GetStreetNameFromHashKey(GetStreetNameAtCoord(fare.finish.x, fare.finish.y, fare.finish.z))
    data.currentfareinfo = { customer = fare.name, destination = streetName, currentfare = round(fare.fare + (fare.fuelconsumption * Config.fuelPay), 1), perminute = '2.00', basefare = round(fare.fare, 1) }
    SendReactMessage('setData', data)
end

local function resetFare(offduty)
    TriggerServerEvent('OT_taxijob:cancelJob', offduty)
    if DoesBlipExist(customerBlip) then RemoveBlip(customerBlip) end
    if DoesBlipExist(oldBlip) then RemoveBlip(oldBlip) end
    if DoesBlipExist(dropoffBlip) then RemoveBlip(dropoffBlip) end
    customer, customerBlip, oldBlip, dropoffBlip, dropoffCoords, nearCustomer, isEntering, enteredVehicle, currentJob = nil, nil, nil, nil, nil, false, false, false, nil
    return {success = true}
end

local function CustomerBlip(x, y, z, name)
    customerBlip = AddBlipForCoord(x, y, z)
    SetBlipScale(customerBlip, 1.0)
    SetBlipColour(customerBlip, 5)
    SetBlipAsShortRange(customerBlip, false)
    SetBlipRoute(customerBlip, true)
    SetBlipRouteColour(customerBlip, 5)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(_U('customer_blip_name', name))
    EndTextCommandSetBlipName(customerBlip)
end

local function manageFare(id)
    local timer = GetGameTimer()
    while not IsPedInVehicle(customer, vehicle, false) do
        Wait(200)
        if GetGameTimer() - timer > 60000 then
            customer = nil
            currentJob = nil
            break
        end
    end
    while customer ~= nil do
        local playerCoords = GetEntityCoords(ped)
        local dropoffCoords = GlobalState.taxiFares[id].finish
        if isEntering then
            if enteredVehicle then
                local targetDistance = #(playerCoords - dropoffCoords)

                if targetDistance <= 10.0 then
                    TaskLeaveVehicle(customer, vehicle, 0)
                    while IsPedInVehicle(customer, vehicle, false) do
                        Wait(13)
                    end
                    notification({style = { backgroundColor = '#282c34', color = '#909296'}, icon = 'taxi', iconColor = '#29c785', position = 'top', duration = 4000, title = _U('notification_title'), description = _U('fare_dropoff') })
                    TaskGoStraightToCoord(customer, dropoffCoords.x, dropoffCoords.y, dropoffCoords.z, 1.0, -1, 0.0, 0.0)
                    SetEntityAsMissionEntity(customer, false, true)
                    TriggerServerEvent('OT_taxijob:finishJob', id)
                    RemoveBlip(dropoffBlip)
                    customer, customerBlip, oldBlip, dropoffBlip, dropoffCoords, nearCustomer, isEntering, enteredVehicle, currentJob = nil, nil, nil, nil, nil, false, false, false, nil
                end
            else
                RemoveBlip(customerBlip)
                customerBlip = nil
                local zoneNameFull = zones[GetNameOfZone(dropoffCoords.x, dropoffCoords.y, dropoffCoords.z)]
                local streetName = zoneNameFull ~= nil and string.format('%s, %s', GetStreetNameFromHashKey(GetStreetNameAtCoord(dropoffCoords.x, dropoffCoords.y, dropoffCoords.z)), zoneNameFull) or GetStreetNameFromHashKey(GetStreetNameAtCoord(dropoffCoords.x, dropoffCoords.y, dropoffCoords.z))
                notification({style = {backgroundColor = '#282c34', color = '#909296'}, icon = 'taxi', iconColor = '#29c785', position = 'top', duration = 4000, title = _U('notification_title'), description = _U('fare_goto', streetName) })

                dropoffBlip = AddBlipForCoord(dropoffCoords.x, dropoffCoords.y, dropoffCoords.z)

                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName('Destination')
                EndTextCommandSetBlipName(dropoffBlip)
                SetBlipRoute(dropoffBlip, true)
                enteredVehicle = true
            end
        end
        Wait(200)
    end
end

local function pickupFare(target, id, oldBlip)
    while not isEntering do
        local playerCoords = GetEntityCoords(ped)
        local customerCoords = GetEntityCoords(customer)
        if customer == target then
            local customerDist = #(playerCoords - customerCoords)
            if customerDist <= 40.0 then
                if not nearCustomer then
                    TaskTurnPedToFaceCoord(customer, playerCoords, 1000)
                    RemoveBlip(oldBlip)
                    notification({style = {backgroundColor = '#282c34', color = '#909296'}, icon = 'circle-info', iconColor = '#eed202', position = 'top', duration = 4000, title = _U('notification_title'), description = _U('fare_nearby') })
                    nearCustomer = true
                end
            end

            if customerDist <= 20.0 then
                lib.requestAnimDict('taxi_hail', 500)
                TaskPlayAnim(customer, 'taxi_hail', 'hail_taxi', 8.0, -8.0, -1, 1, 0, false, false, false)
                Wait(3000)
                if not isEntering then
                    ClearPedTasksImmediately(customer)
                    local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(vehicle)

                    for i = maxSeats - 1, 0, -1 do
                        if IsVehicleSeatFree(vehicle, i) then
                            freeSeat = i
                            break
                        end
                    end
                    if freeSeat then
                        TaskEnterVehicle(customer, vehicle, -1, freeSeat, 1.0, 0)
                        isEntering = true
                        manageFare(id)
                    end
                end
            end
        end
        Wait(0)
    end
end

local function startFare(id)
    local location = GlobalState.taxiFares[id].start
    local name = GlobalState.taxiFares[id].name
    local model = GlobalState.taxiFares[id].model
    CustomerBlip(location.x, location.y, location.z, name)
    oldBlip = customerBlip
    while customer == nil do
        Wait(2500)
        if currentJob == nil then break end
        local dist = #(GetEntityCoords(ped) - location)
        if dist <= 150.0 and customer == nil then
            lib.requestModel(model)
            customer = CreatePed(4, GetHashKey(model), location.x, location.y, location.z, 0.0, true, true)
            while not DoesEntityExist(customer) do
                Wait(0)
            end
            customerBlip = AddBlipForEntity(customer)
            SetEntityAsMissionEntity(customer, true, false)
            ClearPedTasksImmediately(customer)
            SetBlockingOfNonTemporaryEvents(customer, true)
            TaskStandStill(customer, 999999)
        end
    end
    if customer == nil or currentJob == nil then return print('failed to spawn ped') end
    pickupFare(customer, id, oldBlip)
end

local function spawnPed(zone)
    local pedData = Config.offices[zone].pedData
    local hash = GetHashKey(pedData.model)
    lib.requestModel(hash, 500)
    npc = CreatePed(pedData.gender == 'male' and 4 or 5, hash, pedData.coords.x, pedData.coords.y, pedData.coords.z - 1, pedData.heading, false, false)
    FreezeEntityPosition(npc, true)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    if Config.target then
        createTarget(npc, 'bossPed')
    end
end

local function handleVeh()
    if vehThread then return end
    vehThread = true
    while vehicle do
        local sleep = 500
        local onDuty = taxiDuty
        if customer ~= nil then
            if IsPedDeadOrDying(customer, true) then
                TriggerServerEvent('OT_taxijob:customerDead', currentJob)
                resetFare()
            end
        end
        if onDuty and inTaxi() then
            if not guiEnabled then
                openUI()
            end
            updateMeter()
        else
            closeUI()
            sleep = 1500
        end
        Wait(sleep)
    end
    closeUI()
    vehThread = false
end

local function handleCam()
    if camThread then return end
    camThread = true
    while focustablet do
        DisableControlAction(0, 1, true)
        DisableControlAction(0, 2, true)
        DisableControlAction(0, 106, true)
        Wait(0)
    end
    camThread = false
end

local function rentTaxi(model)
    if not taxiDuty then notification({ style = { backgroundColor = '#282c34', color = '#909296' }, icon = 'ban', iconColor = '#C53030', position = 'top', duration = 4000, title = _U('notification_title'), description = _U('offduty') }) return end
    if GlobalState.taxiRentals[cache.serverId] and GlobalState.taxiRentals[cache.serverId].entity then notification({ style = { backgroundColor = '#282c34', color = '#909296' }, icon = 'ban', iconColor = '#C53030', position = 'top', duration = 4000, title = _U('notification_title'), description = _U('has_rental') }) return end
    local spawns = Config.offices[currentZone].rentalSpawns
    for i = 1, #spawns do
        if isPointClear(GetGamePool('CVehicle'), false, vector3(spawns[i].x, spawns[i].y, spawns[i].z), 2.0) then
            if Config.debug then
                print('spawn clear')
            end
            return lib.callback.await('OT_taxijob:rentTaxi', false, model, spawns[i])
        end
        if i == #spawns then notification({ style = { backgroundColor = '#282c34', color = '#909296' }, icon = 'ban', iconColor = '#C53030', position = 'top', duration = 4000, title = _U('notification_title'), description = _U('no_spawns') }) end
    end
end

local function progressionMenu()
    local options = {}
    for k, v in pairs(Config.levels) do
        local i = #options + 1
        options[i] = {}
        options[i].title = string.format('%s %s', _U('level'), k)
        if v.vehicleLabel ~= nil and v.label ~= nil then
            options[i].description = string.format('%s: %s | %s', _U('reward'), v.label, v.vehicleLabel)
        elseif v.vehicleLabel ~= nil and v.label == nil then
            options[i].description = string.format('%s: %s', _U('reward'), v.vehicleLabel)
        elseif v.vehicleLabel == nil and v.label ~= nil then
            options[i].description = string.format('%s: %s', _U('reward'), v.label)
        elseif v.vehicleLabel == nil and v.label == nil then
            options[i].description = _U('no reward')
        end
    end
    lib.registerContext({
        id = 'taxi_progression',
        menu = 'taxi_menu',
        title = _U('menu_taxi_progression_title'),
        options = options
    })
end

local function rentalMenu(show)
    local options = {}
    local serverId = cache.serverId
    local rentals = GlobalState.taxiRentals
    local drivers = GlobalState.taxiDrivers
    local rental = rentals[serverId] and rentals[serverId].entity or false
    local progression = drivers[serverId] and drivers[serverId].progression
    if rental then
        local i = #options + 1
        options[i] = {}
        options[i].title = _U('menu_taxi_return_title')
        options[i].description = _U('menu_taxi_return_description')
        options[i].onSelect = function()
            TriggerServerEvent('OT_taxijob:returnTaxi')
            Wait(150)
            rentalMenu(true)
        end
    end
    for k, v in pairs(Config.levels) do
        if k <= progression.level and v.vehicle ~= nil and rental == false then
            local i = #options + 1
            options[i] = {}
            options[i].title = v.vehicleLabel
            options[i].description = string.format('%s: %s%s', _U('cost'), _U('ui_currency'), v.vehicleRentCost)
            options[i].onSelect = function()
                rentTaxi(v.vehicle)
                Wait(150)
                rentalMenu(true)
            end
        end
    end
    lib.registerContext({
        id = 'taxi_rentals',
        menu = 'taxi_menu',
        title = _U('menu_taxi_rental_title'),
        options = options
    })
    if show then
        lib.showContext('taxi_rentals')
    end
end

local function officeMenu()
    local options = {}
    if not taxiDuty then
        options = {
            {
                title = _U('menu_offduty_title'),
                description = _U('menu_offduty_description'),
                onSelect = function()
                    TriggerEvent('OT_taxijob:toggleDuty')
                    Wait(150)
                    officeMenu()
                end
            }
        }
    else
        local progression = GlobalState.taxiDrivers[cache.serverId].progression
        local maxxp = (progression.level * 100 * Config.skillMultiplier)
        local percentage = (progression.xp / maxxp) * 100
        options = {
            {
                title = _U('menu_onduty_title'),
                description = _U('menu_onduty_description'),
                onSelect = function()
                    TriggerEvent('OT_taxijob:toggleDuty')
                    Wait(100)
                    officeMenu()
                end
            },
            {
                title = _U('menu_taxi_rental_title'),
                description = _U('menu_taxi_rental_description'),
                menu = 'taxi_rentals'
            },
            {
                title = _U('menu_progression_title'),
                description = _U('menu_progression_description', progression.level, progression.xp, round(maxxp)),
                progress = percentage > 0.1 and percentage or 0.1,
                menu = 'taxi_progression'
            },
        }
        progressionMenu()
        rentalMenu()
    end
    lib.registerContext({
        id = 'taxi_menu',
        title = _U('menu_main_title'),
        options = options
    })
    lib.showContext('taxi_menu')
end
RegisterNetEvent("OT_taxijob:taxioffice", officeMenu)

RegisterNetEvent('OT_taxijob:startJob', function(id)
    currentJob = id
    startFare(id)
end)

RegisterNetEvent("OT_taxijob:toggleDuty", function()
    if Config.jobcheck then
        if not permCheck(Config.job, Config.grade) then return notification({style = { backgroundColor = '#282c34', color = '#909296' }, icon = 'ban', iconColor = '#C53030', position = 'top', duration = 4000, title = _U('notification_title'), description = _U('no_job', Config.job)}) end
    end
    taxiDuty = not taxiDuty
    TriggerServerEvent('OT_taxijob:toggleDuty', taxiDuty)
    if taxiDuty == false then
        resetFare(true)
    end
end)

------------------NUI CALLBACKS------------------

RegisterNUICallback('takejob', function(data, cb)
    if currentJob ~= nil then
        notification({style = {backgroundColor = '#282c34', color = '#909296'}, icon = 'ban', iconColor = '#C53030', position = 'top', duration = 4000, title = _U('notification_title'), description = _U('fare_active') })
        return cb({success = false})
    end
    local retData = lib.callback.await('OT_taxijob:takeJob', false, data.id)
    if retData.success == true then keybind:onPressed() end
    cb(retData)
end)

RegisterNUICallback('canceljob', function(data, cb)
    if currentJob == nil then
        notification({style = {backgroundColor = '#282c34', color = '#909296'}, icon = 'ban', iconColor = '#C53030', position = 'top', duration = 4000, title = _U('notification_title'), description = _U('fare_none')})
        return cb({success = false})
    end
    local reset = resetFare()
    cb(reset)
end)


CreateThread(function()
    SendReactMessage('setuplocale', {locale = Locales})

    keybind = lib.addKeybind({
        name = 'focustablet',
        description = 'focus taxi UI',
        defaultKey = 'N',
        onPressed = function(self)
            if guiEnabled then
                focustablet = not focustablet
                SetNuiFocus(focustablet, focustablet)
                SetNuiFocusKeepInput(true)
                if focustablet then
                    CreateThread(handleCam)
                end
            end
        end
    })

    lib.onCache('ped', function(value)
        ped = value
    end)
    
    lib.onCache('vehicle', function(value)
        vehicle = value
        if value then
            CreateThread(handleVeh)
        end
    end)

    for k, v in pairs(Config.offices) do

        blip = AddBlipForCoord(v.coords.x, v.coords.y, v.coords.z)

        SetBlipSprite(blip, v.blip.sprite)
        SetBlipScale(blip, v.blip.scale)
        SetBlipColour(blip, v.blip.colour)
        SetBlipAsShortRange(blip, true)

        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(tostring(k))
        EndTextCommandSetBlipName(blip)

        local point = lib.points.new(v.coords, 40, { zone = k })

        function point:onEnter()
            currentZone = self.zone
            spawnPed(self.zone)
        end

        function point:onExit()
            if Config.target then
                removeTarget(npc, 'bossPed')
            end
            DeletePed(npc)
            currentZone = nil
            npc = nil
        end

        if not Config.target then
            local interact = lib.points.new(v.pedData.coords, 2)

            function interact:onEnter()
                lib.showTextUI(_U('text_ui_taxi_office'))
            end

            function interact:onExit()
                lib.hideTextUI()
            end

            function interact:nearby()
                if self.currentDistance < 2.0 then
                    if IsControlJustReleased(0, 38) then
                        TriggerEvent('OT_taxijob:taxioffice')
                    end
                end
            end
        end
    end
end)