-- cm-courier/client/main.lua
-- Client Gameplay Controller for Municipal Courier Delivery & Parcel Logistics.

local Config = CMCourier.Config
CMCourier = CMCourier or {}
CMCourier.Client = CMCourier.Client or {}

local onRoute = false
local currentRoute = nil
local currentStopIndex = 1
local parcelsTotal = 0
local parcelsDelivered = 0
local isLoaded = false
local allDelivered = false
local vanReturned = false
local isHandling = false

local vehicleNetId = nil
local vehiclePlate = nil

local activeBlip = nil
local activePromptOwner = nil

-- ---------------------------------------------------------------------------
-- Public Client State Queries
-- ---------------------------------------------------------------------------

function CMCourier.Client.IsOnRoute()
    return onRoute
end

function CMCourier.Client.GetActiveRoute()
    return currentRoute
end

function CMCourier.Client.GetCurrentStop()
    return currentStopIndex
end

-- ---------------------------------------------------------------------------
-- Prompt Helpers
-- ---------------------------------------------------------------------------

local function showPrompt(owner, label)
    if activePromptOwner == owner then return end
    if activePromptOwner and GetResourceState('cm-ui') == 'started' then
        pcall(function() exports['cm-ui']:HideInteract(activePromptOwner) end)
    end

    activePromptOwner = owner
    if GetResourceState('cm-ui') == 'started' then
        pcall(function()
            exports['cm-ui']:ShowInteract({
                owner = owner,
                priority = 10,
                key = Config.InteractKeyLabel or 'E',
                label = label,
                name = 'Municipal Courier',
                role = 'PARCEL DELIVERY',
            })
        end)
    end
end

local function hidePrompt(owner)
    if activePromptOwner == owner or (not owner and activePromptOwner) then
        local toHide = owner or activePromptOwner
        if GetResourceState('cm-ui') == 'started' then
            pcall(function() exports['cm-ui']:HideInteract(toHide) end)
        end
        activePromptOwner = nil
    end
end

-- ---------------------------------------------------------------------------
-- HUD Management
-- ---------------------------------------------------------------------------

local function updateHud()
    if not onRoute or not currentRoute then
        SendNUIMessage({ action = 'hide' })
        return
    end

    local totalStops = #currentRoute.stops
    local stop = not allDelivered and currentRoute.stops[currentStopIndex] or nil

    local instruction = 'PROCEED TO LOADING DOCK'
    local stopLabel = 'Depot Loading Dock'
    local recipient = 'Municipal Depot Staging'
    local percent = math.floor((parcelsDelivered / math.max(1, parcelsTotal)) * 100)

    if not isLoaded then
        instruction = 'LOAD PARCELS AT DEPOT LOADING DOCK'
        stopLabel = 'Depot Parcel Bay'
        recipient = 'Authorized Courier Manifest'
    elseif isHandling then
        instruction = 'VERIFYING PARCEL & RECIPIENT SIGNATURE...'
        stopLabel = stop and stop.label or 'Active Drop'
        recipient = stop and stop.recipient or 'Recipient'
    elseif allDelivered and not vanReturned then
        instruction = 'RETURN VAN TO COURIER DEPOT RETURN BAY'
        stopLabel = 'Depot Return Bay'
        recipient = 'Post OP Terminal Depot'
        percent = 100
    elseif vanReturned then
        instruction = 'SIGN OFF MANIFEST WITH DISPATCHER SAL MORENO'
        stopLabel = 'Dispatcher Office Desk'
        recipient = 'Sal Moreno (Dispatch)'
        percent = 100
    elseif stop then
        instruction = ('TRANSIT TO STOP %d // DELIVER PARCEL'):format(currentStopIndex)
        stopLabel = stop.label or ('Stop ' .. currentStopIndex)
        recipient = stop.recipient or 'Authorized Consignee'
    end

    SendNUIMessage({
        action = 'update',
        onRoute = onRoute,
        stopIndex = currentStopIndex,
        totalStops = totalStops,
        parcelsDelivered = parcelsDelivered,
        parcelsTotal = parcelsTotal,
        isLoaded = isLoaded,
        allDelivered = allDelivered,
        vanReturned = vanReturned,
        routeTitle = currentRoute.title or 'Municipal Delivery Route',
        stopLabel = stopLabel,
        recipient = recipient,
        percent = percent,
        instruction = instruction,
        payoutStatus = 'HELD IN DURABLE LEDGER // CANNOT BE COLLECTED IN-GAME',
    })
end

-- ---------------------------------------------------------------------------
-- Blip & Waypoint Management
-- ---------------------------------------------------------------------------

local function clearTrackedBlip()
    if activeBlip and DoesBlipExist(activeBlip) then
        RemoveBlip(activeBlip)
    end
    activeBlip = nil
end

local function setTrackedBlip(coords, name, sprite, color, setWaypoint)
    clearTrackedBlip()
    if not coords then return end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite or 1)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.80)
    SetBlipColour(blip, color or 5)
    SetBlipAsShortRange(blip, false)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, color or 5)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(name or 'Courier Delivery Waypoint')
    EndTextCommandSetBlipName(blip)

    if setWaypoint ~= false then
        SetNewWaypoint(coords.x, coords.y)
    end

    activeBlip = blip
end

-- ---------------------------------------------------------------------------
-- Server Event Handlers
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-courier:client:routeStarted', function(data)
    if type(data) ~= 'table' then return end

    onRoute = true
    currentRoute = {
        id = data.routeId,
        title = data.routeTitle,
        payout = data.payout,
        stops = data.stops,
    }
    parcelsTotal = data.parcelsTotal or (data.stops and #data.stops or 0)
    parcelsDelivered = 0
    currentStopIndex = 1
    isLoaded = false
    allDelivered = false
    vanReturned = false
    vehicleNetId = data.vehicleNetId
    vehiclePlate = data.vehiclePlate

    -- Guide player to the loading dock first
    local dock = Config.Facility.loadingDock.coords
    setTrackedBlip(dock, 'Depot Loading Dock - Load Parcels', 478, 5, true)

    updateHud()
end)

RegisterNetEvent('cm-courier:client:parcelsLoaded', function(data)
    isLoaded = true
    currentStopIndex = data.currentStopIndex or 1

    local stop = currentRoute and currentRoute.stops and currentRoute.stops[currentStopIndex]
    if stop then
        setTrackedBlip(stop.coords, ('Drop %d: %s'):format(currentStopIndex, stop.label), 1, 5, true)
    end

    updateHud()
end)

RegisterNetEvent('cm-courier:client:stopCompleted', function(data)
    parcelsDelivered = data.parcelsDelivered or (parcelsDelivered + 1)
    currentStopIndex = data.nextStopIndex or (currentStopIndex + 1)
    allDelivered = data.allDelivered == true

    if allDelivered then
        local returnBay = Config.Facility.returnBay.coords
        setTrackedBlip(returnBay, 'Courier Depot Return Bay', 357, 5, true)
    else
        local nextStop = currentRoute and currentRoute.stops and currentRoute.stops[currentStopIndex]
        if nextStop then
            setTrackedBlip(nextStop.coords, ('Drop %d: %s'):format(currentStopIndex, nextStop.label), 1, 5, true)
        end
    end

    updateHud()
end)

RegisterNetEvent('cm-courier:client:vanReturned', function()
    vanReturned = true
    local sup = Config.Facility.supervisor.coords
    setTrackedBlip(vector3(sup.x, sup.y, sup.z), 'Dispatcher Sal Moreno - Sign Off', 67, 5, true)
    updateHud()
end)

RegisterNetEvent('cm-courier:client:shiftEnded', function(reason)
    onRoute = false
    currentRoute = nil
    currentStopIndex = 1
    parcelsTotal = 0
    parcelsDelivered = 0
    isLoaded = false
    allDelivered = false
    vanReturned = false
    isHandling = false
    vehicleNetId = nil
    vehiclePlate = nil

    clearTrackedBlip()
    hidePrompt()
    SendNUIMessage({ action = 'hide' })
end)

-- ---------------------------------------------------------------------------
-- Active Gameplay Loop
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        local waitMs = 800

        if onRoute and currentRoute then
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)

            if not isLoaded then
                -- Step 1: Loading Parcels at Depot Dock
                local dock = Config.Facility.loadingDock.coords
                local dist = #(pCoords - dock)
                if dist <= 12.0 then
                    waitMs = 0
                    DrawMarker(1, dock.x, dock.y, dock.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.5, 3.5, 0.6, 0, 229, 255, 140, false, false, 2, false, nil, nil, false)

                    if dist <= 4.0 and not isHandling then
                        showPrompt('cm-courier:dock', 'LOAD PARCELS INTO COURIER VAN')
                        if IsControlJustReleased(0, Config.InteractKey or 38) then
                            isHandling = true
                            hidePrompt('cm-courier:dock')

                            -- Loading Animation
                            TaskStartScenarioInPlace(ped, 'PROP_HUMAN_BUM_BIN', 0, true)
                            SendNUIMessage({ action = 'progress_start', label = 'LOADING PARCEL MANIFEST...', durationMs = 3000 })
                            Wait(3000)
                            ClearPedTasks(ped)

                            isHandling = false
                            TriggerServerEvent('cm-courier:server:loadParcels')
                        end
                    else
                        hidePrompt('cm-courier:dock')
                    end
                end

            elseif not allDelivered then
                -- Step 2: Route Delivery Drops
                local stop = currentRoute.stops and currentRoute.stops[currentStopIndex]
                if stop and stop.coords then
                    local sCoords = vector3(stop.coords.x, stop.coords.y, stop.coords.z)
                    local dist = #(pCoords - sCoords)

                    if dist <= 25.0 then
                        waitMs = 0
                        DrawMarker(1, sCoords.x, sCoords.y, sCoords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 0.5, 0, 229, 255, 160, false, false, 2, false, nil, nil, false)

                        -- Must be on foot to deliver parcel
                        if not IsPedInAnyVehicle(ped, false) and dist <= 3.0 and not isHandling then
                            showPrompt('cm-courier:deliver', ('DELIVER PARCEL TO %s'):format(stop.recipient or 'RECIPIENT'))

                            if IsControlJustReleased(0, Config.InteractKey or 38) then
                                isHandling = true
                                hidePrompt('cm-courier:deliver')
                                updateHud()

                                -- Delivery Confirmation Animation (Clipboard signature verification)
                                TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
                                SendNUIMessage({ action = 'progress_start', label = 'OBTAINING RECIPIENT SIGNATURE...', durationMs = 3500 })
                                Wait(3500)
                                ClearPedTasks(ped)

                                isHandling = false
                                TriggerServerEvent('cm-courier:server:deliverParcel', currentStopIndex)
                            end
                        else
                            hidePrompt('cm-courier:deliver')
                        end
                    end
                end

            elseif not vanReturned then
                -- Step 3: Returning Van to Depot
                local returnBay = Config.Facility.returnBay.coords
                local dist = #(pCoords - returnBay)

                if dist <= 25.0 then
                    waitMs = 0
                    DrawMarker(1, returnBay.x, returnBay.y, returnBay.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 6.0, 6.0, 0.6, 0, 229, 255, 140, false, false, 2, false, nil, nil, false)

                    if dist <= 6.0 and not isHandling then
                        showPrompt('cm-courier:return_bay', 'STAGE COURIER VAN IN RETURN BAY')
                        if IsControlJustReleased(0, Config.InteractKey or 38) then
                            hidePrompt('cm-courier:return_bay')
                            TriggerServerEvent('cm-courier:server:returnToDepot')
                        end
                    else
                        hidePrompt('cm-courier:return_bay')
                    end
                end
            end
        end

        Wait(waitMs)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearTrackedBlip()
    hidePrompt()
    SendNUIMessage({ action = 'hide' })
end)

