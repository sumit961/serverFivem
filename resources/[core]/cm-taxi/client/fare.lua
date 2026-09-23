local Config = CMTaxi.Config
local State = CMTaxi.Client.State
local notify = CMTaxi.Client.Notify
local zoneLabel = CMTaxi.Client.ZoneLabel
local request = CMTaxi.Client.Request

local customer, customerBlip, oldBlip, dropoffBlip
local nearCustomer, isEntering, enteredVehicle = false, false, false
local customerGreeted = false
local passengerCall
local passengerRouteBlip
local passengerRouteEntity

local function requestModel(model)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    RequestModel(hash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return hash
end

local function freePassengerSeat(vehicle)
    for seat = GetVehicleMaxNumberOfPassengers(vehicle) - 1, 0, -1 do
        if IsVehicleSeatFree(vehicle, seat) then return seat end
    end
end

local function deleteCustomerPed()
    if customer and DoesEntityExist(customer) then
        SetEntityAsMissionEntity(customer, true, true)
        DeleteEntity(customer)
    end
    customer = nil
end

local function customerBlipFor(x, y, z, name)
    local blip = AddBlipForCoord(x, y, z)
    SetBlipScale(blip, 1.0)
    SetBlipColour(blip, 5)
    SetBlipAsShortRange(blip, false)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(CMTaxi.Locale('customer_blip_name', name))
    EndTextCommandSetBlipName(blip)
    return blip
end

local function resetFare(offduty)
    TriggerServerEvent('cm-taxi:server:cancelJob', nil, offduty)
    if DoesBlipExist(customerBlip) then RemoveBlip(customerBlip) end
    if DoesBlipExist(oldBlip) then RemoveBlip(oldBlip) end
    if DoesBlipExist(dropoffBlip) then RemoveBlip(dropoffBlip) end
    deleteCustomerPed()
    customerBlip, oldBlip, dropoffBlip = nil, nil, nil
    nearCustomer, isEntering, enteredVehicle = false, false, false
    customerGreeted = false
    State.currentJob = nil
    State.currentJobData = nil
end

CMTaxi.Client.ResetFare = resetFare

local function manageFare(id)
    local ped = PlayerPedId()
    local vehicle = State.vehicle
    local lastBoardTaskVehicleCoords = GetEntityCoords(vehicle)
    local nextFinishAttemptAt = 0

    local timer = GetGameTimer()
    while customer and DoesEntityExist(customer) and not IsPedInVehicle(customer, vehicle, false) do
        Wait(200)
        if State.currentJob ~= id then return end

        -- Refresh the approach task if the taxi moved away while the passenger
        -- was walking to it. GTA can leave the ped walking toward its old spot.
        local vehicleCoords = GetEntityCoords(vehicle)
        local retaskDistance = Config.CustomerBoardRetaskDistance or 10.0
        if not IsPedGettingIntoAVehicle(customer)
            and #(vehicleCoords - lastBoardTaskVehicleCoords) >= retaskDistance then
            local seat = freePassengerSeat(vehicle)
            if seat then
                ClearPedTasks(customer)
                TaskEnterVehicle(customer, vehicle, -1, seat, 1.0, 0)
                lastBoardTaskVehicleCoords = vehicleCoords
            end
        end

        if GetGameTimer() - timer > Config.CustomerBoardTimeoutMs then
            resetFare()
            return
        end
    end
    if not customer or not DoesEntityExist(customer) then
        resetFare()
        return
    end

    while customer ~= nil do
        if not DoesEntityExist(customer) then
            resetFare()
            return
        end
        local playerCoords = GetEntityCoords(ped)
        local fare = (GlobalState.cmTaxiFares or {})[id]
        if not fare then break end
        local dropoffCoords = fare.finish

        if isEntering then
            if enteredVehicle then
                if #(playerCoords - dropoffCoords) <= Config.CustomerDropoffDistance then
                    TaskLeaveVehicle(customer, vehicle, 0)
                    local exitDeadline = GetGameTimer() + Config.CustomerExitTimeoutMs
                    while IsPedInVehicle(customer, vehicle, false) and GetGameTimer() < exitDeadline do Wait(100) end

                    if IsPedInVehicle(customer, vehicle, false) then
                        ClearPedTasks(customer)
                        TaskLeaveVehicle(customer, vehicle, 0)
                        exitDeadline = GetGameTimer() + math.floor(Config.CustomerExitTimeoutMs / 2)
                        while IsPedInVehicle(customer, vehicle, false) and GetGameTimer() < exitDeadline do Wait(100) end
                    end

                    if IsPedInVehicle(customer, vehicle, false) then
                        notify(CMTaxi.Locale('customer_exit_failed'), 'error')
                        resetFare()
                        return
                    end

                    notify(CMTaxi.Locale('fare_dropoff'), 'success')
                    TaskGoStraightToCoord(customer, dropoffCoords.x, dropoffCoords.y, dropoffCoords.z, 1.0, -1, 0.0, 0.0)
                    SetEntityAsMissionEntity(customer, false, true)
                    if GetGameTimer() >= nextFinishAttemptAt then
                        local result = request('cm-taxi:server:finishJob', 6000, id)
                        if result and result.success then
                            if DoesBlipExist(dropoffBlip) then RemoveBlip(dropoffBlip) end
                            customer, customerBlip, oldBlip, dropoffBlip = nil, nil, nil, nil
                            nearCustomer, isEntering, enteredVehicle = false, false, false
                            State.currentJob = nil
                        else
                            notify((result and result.error) or 'The fare could not be completed yet.', 'error')
                            nextFinishAttemptAt = GetGameTimer() + 3000
                        end
                    end
                end
            else
                local boardResult = request('cm-taxi:server:boardJob', 6000, id)
                if not boardResult or not boardResult.success then
                    notify(CMTaxi.Locale('fare_board_validation_failed'), 'error')
                    resetFare()
                    return
                end

                if DoesBlipExist(customerBlip) then RemoveBlip(customerBlip) end
                customerBlip = nil
                notify(CMTaxi.Locale('fare_goto', zoneLabel(dropoffCoords)), 'info')

                dropoffBlip = AddBlipForCoord(dropoffCoords.x, dropoffCoords.y, dropoffCoords.z)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(CMTaxi.Locale('destination_blip_name'))
                EndTextCommandSetBlipName(dropoffBlip)
                SetBlipRoute(dropoffBlip, true)
                enteredVehicle = true
            end
        end
        Wait(200)
    end
end

local function pickupFare(target, id)
    local vehicle = State.vehicle
    local boardWaitStartedAt

    while not isEntering do
        if not customer or not DoesEntityExist(customer) or State.currentJob ~= id then return end
        local ped = PlayerPedId()
        local playerCoords = GetEntityCoords(ped)
        local customerCoords = GetEntityCoords(customer)

        if customer == target then
            local customerDist = #(playerCoords - customerCoords)

            if customerDist <= Config.CustomerNearbyDistance and not nearCustomer then
                TaskTurnPedToFaceCoord(customer, playerCoords.x, playerCoords.y, playerCoords.z, 1000)
                if DoesBlipExist(oldBlip) then RemoveBlip(oldBlip) end
                notify(CMTaxi.Locale('fare_nearby'), 'warning')
                nearCustomer = true
            end

            if customerDist <= Config.CustomerHailDistance then
                boardWaitStartedAt = boardWaitStartedAt or GetGameTimer()
                if not customerGreeted then
                    customerGreeted = true
                    TaskTurnPedToFaceEntity(customer, ped, 1000)
                    PlayPedAmbientSpeechNative(customer, 'GENERIC_HI', 'SPEECH_PARAMS_FORCE_NORMAL_CLEAR')
                    Wait(900)
                end

                if not isEntering then
                    local freeSeat = freePassengerSeat(vehicle)

                    if freeSeat then
                        TaskEnterVehicle(customer, vehicle, -1, freeSeat, 1.0, 0)
                        isEntering = true
                        manageFare(id)
                    else
                        if GetGameTimer() - boardWaitStartedAt >= Config.CustomerBoardTimeoutMs then
                            notify(CMTaxi.Locale('customer_no_seat'), 'error')
                            resetFare()
                            return
                        end
                        Wait(750)
                    end
                end
            end
        end
        Wait(50)
    end
end

local function startFare(id)
    local fare = (GlobalState.cmTaxiFares or {})[id]
    if not fare then return end

    customerBlip = customerBlipFor(fare.start.x, fare.start.y, fare.start.z, fare.name)
    oldBlip = customerBlip

    local timeout = GetGameTimer() + Config.CustomerSpawnTimeoutMs
    while customer == nil do
        Wait(500)
        if State.currentJob == nil then return end
        if GetGameTimer() > timeout then break end

        local ped = PlayerPedId()
        local dist = #(GetEntityCoords(ped) - fare.start)
        if dist <= Config.CustomerSpawnRadius and customer == nil then
            local hash = requestModel(fare.model)
            customer = CreatePed(4, hash, fare.start.x, fare.start.y, fare.start.z, 0.0, true, true)

            local spawnTimeout = GetGameTimer() + 2000
            while not DoesEntityExist(customer) and GetGameTimer() < spawnTimeout do Wait(0) end
            if not DoesEntityExist(customer) then break end

            local netId = 0
            local networkTimeout = GetGameTimer() + 2000
            while netId == 0 and DoesEntityExist(customer) and GetGameTimer() < networkTimeout do
                if NetworkGetEntityIsNetworked(customer) then
                    netId = NetworkGetNetworkIdFromEntity(customer)
                end
                if netId == 0 then Wait(50) end
            end
            if netId > 0 then
                TriggerServerEvent('cm-taxi:server:registerCustomer', id, netId)
            end

            SetEntityAsMissionEntity(customer, true, false)
            ClearPedTasksImmediately(customer)
            SetBlockingOfNonTemporaryEvents(customer, true)
            TaskStandStill(customer, 999999)
            customerGreeted = false
            SetModelAsNoLongerNeeded(hash)
        end
    end

    if customer == nil or State.currentJob == nil then
        resetFare()
        return
    end
    pickupFare(customer, id)
end

local function clearPlayerFareDriverState()
    if DoesBlipExist(customerBlip) then RemoveBlip(customerBlip) end
    if DoesBlipExist(oldBlip) then RemoveBlip(oldBlip) end
    if DoesBlipExist(dropoffBlip) then RemoveBlip(dropoffBlip) end
    customerBlip, oldBlip, dropoffBlip = nil, nil, nil
    nearCustomer, isEntering, enteredVehicle = false, false, false
    customerGreeted = false
    State.currentJob = nil
    State.currentJobData = nil
end

local function startPlayerFare(id, data)
    if type(data) ~= 'table' or not data.start or not data.finish or not data.taxiNetId then
        notify(CMTaxi.Locale('player_fare_data_missing'), 'error')
        resetFare()
        return
    end

    State.currentJobData = data
    customerBlip = customerBlipFor(data.start.x, data.start.y, data.start.z, data.name or 'Passenger')
    oldBlip = customerBlip
    notify(CMTaxi.Locale('player_fare_pickup'), 'info')

    local nextFinishAttemptAt = 0
    local lastFinishError
    local dropoffNotified = false
    while State.currentJob == id do
        if State.currentJobData ~= data then
            clearPlayerFareDriverState()
            return
        end

        if data.boarded and not enteredVehicle then
            if DoesBlipExist(customerBlip) then RemoveBlip(customerBlip) end
            if DoesBlipExist(oldBlip) then RemoveBlip(oldBlip) end
            customerBlip, oldBlip = nil, nil
            dropoffBlip = AddBlipForCoord(data.finish.x, data.finish.y, data.finish.z)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(CMTaxi.Locale('destination_blip_name'))
            EndTextCommandSetBlipName(dropoffBlip)
            SetBlipRoute(dropoffBlip, true)
            enteredVehicle = true
            notify(CMTaxi.Locale('player_fare_goto', zoneLabel(data.finish)), 'info')
        end

        local playerCoords = GetEntityCoords(PlayerPedId())
        if not data.boarded and not dropoffNotified
            and #(playerCoords - data.start) <= Config.CustomerNearbyDistance then
            dropoffNotified = true
            notify(CMTaxi.Locale('player_fare_waiting'), 'info')
        end

        if data.boarded and #(playerCoords - data.finish) <= Config.CustomerDropoffDistance
            and GetGameTimer() >= nextFinishAttemptAt then
            local result = request('cm-taxi:server:finishJob', 6000, id)
            if result and result.success then
                clearPlayerFareDriverState()
                return
            end
            local errorText = result and result.error
            if errorText and errorText ~= 'The passenger must exit the taxi before the fare can finish.'
                and errorText ~= lastFinishError then
                notify(errorText, 'warning')
                lastFinishError = errorText
            end
            nextFinishAttemptAt = GetGameTimer() + 2000
        end
        Wait(250)
    end
end

RegisterNetEvent('cm-taxi:client:startJob', function(id, data)
    State.currentJob = id
    State.currentJobData = data
    if data and data.playerRequested then
        CreateThread(function() startPlayerFare(id, data) end)
    else
        CreateThread(function() startFare(id) end)
    end
end)

RegisterNetEvent('cm-taxi:client:playerFareBoarded', function(id, finish)
    if State.currentJob ~= id or not State.currentJobData then return end
    State.currentJobData.finish = finish
    State.currentJobData.boarded = true
end)

local function clearPassengerRoute()
    if DoesBlipExist(passengerRouteBlip) then RemoveBlip(passengerRouteBlip) end
    passengerRouteBlip = nil
    passengerRouteEntity = nil
end

local function setPassengerRoute(coords, label)
    clearPassengerRoute()
    if not coords then return end
    passengerRouteBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(passengerRouteBlip, 280)
    SetBlipScale(passengerRouteBlip, 0.9)
    SetBlipColour(passengerRouteBlip, 5)
    SetBlipRoute(passengerRouteBlip, true)
    SetBlipRouteColour(passengerRouteBlip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label or 'Taxi')
    EndTextCommandSetBlipName(passengerRouteBlip)
end

RegisterNetEvent('cm-taxi:client:passengerRequestStatus', function(status, data)
    data = type(data) == 'table' and data or {}
    local fareId = tonumber(data.fareId)

    if status == 'queued' then
        if fareId and (not passengerCall or passengerCall.id ~= fareId) then
            passengerCall = { id = fareId }
        end
    elseif status == 'accepted' then
        passengerCall = passengerCall or { id = fareId }
        if not passengerCall then return end
        if fareId and passengerCall.id and fareId ~= passengerCall.id then return end
        passengerCall.id = fareId or passengerCall.id
        passengerCall.assigned = true
        passengerCall.taxiNetId = tonumber(data.taxiNetId)
        passengerCall.finish = data.finish
        passengerCall.driverCoords = data.driverCoords
        passengerCall.boarded = false
        if passengerCall.driverCoords then
            setPassengerRoute(passengerCall.driverCoords, CMTaxi.Locale('player_fare_taxi_blip'))
        end
    elseif status == 'searching' then
        if passengerCall and (not fareId or not passengerCall.id or fareId == passengerCall.id) then
            passengerCall.assigned = false
            passengerCall.taxiNetId = nil
            passengerCall.finish = nil
            passengerCall.boarded = false
            clearPassengerRoute()
        end
    elseif status == 'expired' or status == 'cancelled' or status == 'completed' then
        if not fareId or not passengerCall or not passengerCall.id or fareId == passengerCall.id then
            passengerCall = nil
            clearPassengerRoute()
        end
    end
end)

local function passengerBoardTaxi(call, vehicle)
    if call.boarding or passengerCall ~= call or GetGameTimer() < (call.nextBoardAt or 0) then return end
    call.boarding = true
    CreateThread(function()
        local ped = PlayerPedId()
        if vehicle ~= 0 and GetVehiclePedIsIn(ped, false) ~= vehicle then
            local freeSeat
            for seat = 0, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
                if IsVehicleSeatFree(vehicle, seat) then
                    freeSeat = seat
                    break
                end
            end
            if not freeSeat then
                notify(CMTaxi.Locale('player_fare_no_seat'), 'error')
                call.boarding = false
                call.nextBoardAt = GetGameTimer() + 5000
                return
            end
            TaskEnterVehicle(ped, vehicle, 10000, freeSeat, 1.0, 0, 0)
            local deadline = GetGameTimer() + 11000
            while passengerCall == call and GetGameTimer() < deadline
                and GetVehiclePedIsIn(ped, false) ~= vehicle do
                Wait(100)
            end
        end

        if passengerCall ~= call or vehicle == 0 or GetVehiclePedIsIn(ped, false) ~= vehicle then
            call.boarding = false
            return
        end

        local result = request('cm-taxi:server:boardPassenger', 7000, call.id)
        if passengerCall ~= call then return end
        call.boarding = false
        if not result or not result.success then
            notify(CMTaxi.Locale('player_fare_board_failed'), 'error')
            call.nextBoardAt = GetGameTimer() + 2000
            return
        end

        call.boarded = true
        call.finish = result.finish or call.finish
        if call.finish then
            setPassengerRoute(call.finish, CMTaxi.Locale('destination_blip_name'))
            SetNewWaypoint(call.finish.x, call.finish.y)
            notify(CMTaxi.Locale('player_fare_ride_started', zoneLabel(call.finish)), 'success')
        end
    end)
end

CreateThread(function()
    while true do
        local call = passengerCall
        if not call or not call.assigned then
            Wait(500)
        else
            local taxi = call.taxiNetId and NetworkGetEntityFromNetworkId(call.taxiNetId) or 0
            if taxi and taxi ~= 0 and DoesEntityExist(taxi)
                and Config.Vehicles[GetEntityModel(taxi)] == true then
                if not call.boarded and passengerRouteEntity ~= taxi then
                    setPassengerRoute(nil)
                    passengerRouteBlip = AddBlipForEntity(taxi)
                    passengerRouteEntity = taxi
                    SetBlipScale(passengerRouteBlip, 0.9)
                    SetBlipColour(passengerRouteBlip, 5)
                    SetBlipRoute(passengerRouteBlip, true)
                    SetBlipRouteColour(passengerRouteBlip, 5)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentSubstringPlayerName(CMTaxi.Locale('player_fare_taxi_blip'))
                    EndTextCommandSetBlipName(passengerRouteBlip)
                end

                local ped = PlayerPedId()
                local currentVehicle = GetVehiclePedIsIn(ped, false)
                if not call.boarded and currentVehicle == taxi then
                    passengerBoardTaxi(call, taxi)
                    Wait(300)
                elseif not call.boarded and currentVehicle == 0
                    and #(GetEntityCoords(ped) - GetEntityCoords(taxi)) <= (Config.PlayerTaxiBoardDistance or 5.0) then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName(CMTaxi.Locale('player_fare_board_hint'))
                    EndTextCommandDisplayHelp(0, false, true, -1)
                    if IsControlJustReleased(0, Config.InteractKey) then
                        passengerBoardTaxi(call, taxi)
                    end
                    Wait(0)
                elseif call.boarded then
                    local passengerVehicle = GetVehiclePedIsIn(ped, false)
                    local passengerDead = IsPedDeadOrDying(ped, true)
                    if passengerDead then
                        TriggerServerEvent('cm-taxi:server:passengerAbandoned', call.id)
                        call.assigned = false
                    elseif passengerVehicle ~= taxi then
                        local atDestination = call.finish
                            and #(GetEntityCoords(ped) - call.finish) <= Config.FareDropoffValidationDistance
                        if not atDestination then
                            TriggerServerEvent('cm-taxi:server:passengerAbandoned', call.id)
                            call.assigned = false
                        end
                    elseif call.finish and #(GetEntityCoords(ped) - call.finish) <= Config.CustomerDropoffDistance then
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName(CMTaxi.Locale('player_fare_exit_hint'))
                        EndTextCommandDisplayHelp(0, false, true, -1)
                        Wait(0)
                    else
                        Wait(300)
                    end
                else
                    Wait(300)
                end
            else
                Wait(500)
            end
        end
    end
end)

RegisterNetEvent('cm-taxi:client:jobCancelled', function(message)
    if State.currentJob == nil then return end
    if type(message) == 'string' and message ~= '' then notify(message, 'warning') end
    resetFare()
end)

-- Guards against the customer dying mid-fare (fell, run over, etc).
CreateThread(function()
    while true do
        Wait(1000)
        if customer and DoesEntityExist(customer) and IsPedDeadOrDying(customer, true) and State.currentJob ~= nil then
            TriggerServerEvent('cm-taxi:server:customerDead', State.currentJob)
            resetFare()
        end
    end
end)

-- Keep a clear floating arrow above the active passenger without running a
-- full-frame loop while the passenger is distant or not on screen.
CreateThread(function()
    while true do
        if customer and DoesEntityExist(customer) and not enteredVehicle and not IsPedDeadOrDying(customer, true) then
            local playerCoords = GetEntityCoords(PlayerPedId())
            local customerCoords = GetEntityCoords(customer)
            local distance = #(playerCoords - customerCoords)
            if distance <= 125.0 and IsEntityOnScreen(customer) then
                DrawMarker(2, customerCoords.x, customerCoords.y, customerCoords.z + 1.15,
                    0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                    0.32, 0.32, 0.32, 0, 229, 255, 220,
                    true, true, 2, false, nil, nil, false)
                Wait(0)
            else
                Wait(200)
            end
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if DoesBlipExist(customerBlip) then RemoveBlip(customerBlip) end
    if DoesBlipExist(oldBlip) then RemoveBlip(oldBlip) end
    if DoesBlipExist(dropoffBlip) then RemoveBlip(dropoffBlip) end
    if customer and DoesEntityExist(customer) then DeleteEntity(customer) end
    clearPassengerRoute()
    passengerCall = nil
    customer, customerBlip, oldBlip, dropoffBlip = nil, nil, nil, nil
    nearCustomer, isEntering, enteredVehicle = false, false, false
    State.currentJobData = nil
end)
