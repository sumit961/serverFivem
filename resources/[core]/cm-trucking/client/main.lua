-- cm-trucking/client/main.lua
-- Commercial Freight Trucking Client Controller.

local Config = CMTrucking.Config
CMTrucking = CMTrucking or {}
CMTrucking.Client = CMTrucking.Client or {}

local onShift = false
local truckNetId = nil
local truckPlate = nil
local truckEntity = nil

local currentContract = nil
local contractState = nil
local payrollBlocked = false
local isLoadingOrUnloading = false

local activeBlip = nil
local activePromptOwner = nil

-- ---------------------------------------------------------------------------
-- Public Client State Queries
-- ---------------------------------------------------------------------------

function CMTrucking.Client.IsOnShift()
    return onShift
end

function CMTrucking.Client.GetActiveContract()
    return currentContract
end

function CMTrucking.Client.GetContractState()
    return contractState
end

-- ---------------------------------------------------------------------------
-- UI Helpers (cm-ui and NUI HUD)
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
                name = 'Freight Logistics',
                role = 'COMMERCIAL TRANSPORT',
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

local function updateHud()
    if not onShift or not currentContract then
        SendNUIMessage({ action = 'hide' })
        return
    end

    local instruction = 'PROCEED TO FREIGHT LOADING DOCK'
    if payrollBlocked then
        instruction = 'PAYOUT STORED IN LEDGER // CANNOT BE COLLECTED IN-GAME'
    elseif contractState == Config.ContractState.Loading then
        instruction = 'SECURING BULK CARGO MANIFEST...'
    elseif contractState == Config.ContractState.InTransit then
        instruction = ('TRANSPORT CARGO TO %s'):format(string.upper(currentContract.destinationLabel or 'DESTINATION'))
    elseif contractState == Config.ContractState.Delivered then
        instruction = 'RETURN HAULER TO TERMINAL ISLAND TO SUBMIT MANIFEST'
    elseif contractState == Config.ContractState.Completed then
        instruction = 'WORK COMPLETED // PAYOUT STORED IN LEDGER (CANNOT BE COLLECTED IN-GAME)'
    end

    SendNUIMessage({
        action = 'update',
        onShift = onShift,
        contractLabel = currentContract.label or 'Commercial Freight Run',
        cargo = currentContract.cargo or 'General Cargo',
        cargoClass = string.upper(currentContract.cargoClass or 'General'),
        distanceKm = currentContract.distanceKm or 0.0,
        destinationLabel = currentContract.destinationLabel or 'Distribution Depot',
        payout = currentContract.payout or 8400,
        state = contractState,
        payrollBlocked = payrollBlocked,
        instruction = instruction,
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
    SetBlipSprite(blip, sprite or 477)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.85)
    SetBlipColour(blip, color or 5)
    SetBlipAsShortRange(blip, false)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, color or 5)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(name or 'Freight Waypoint')
    EndTextCommandSetBlipName(blip)

    activeBlip = blip

    if setWaypoint then
        SetNewWaypoint(coords.x, coords.y)
    end
end

-- ---------------------------------------------------------------------------
-- Animation Helpers
-- ---------------------------------------------------------------------------

local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) and timeout < 250 do
        Wait(10)
        timeout = timeout + 1
    end
    return HasAnimDictLoaded(dict)
end

-- ---------------------------------------------------------------------------
-- Entity Resolution
-- ---------------------------------------------------------------------------

local function resolveTruckEntity()
    if truckEntity and DoesEntityExist(truckEntity) then
        return truckEntity
    end
    if truckNetId and NetworkDoesNetworkIdExist(truckNetId) then
        local ent = NetworkGetEntityFromNetworkId(truckNetId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then
            truckEntity = ent
            return truckEntity
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- 3D Marker Thread (CM Cyan theme: #00e5ff)
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        local waitMs = 800

        if onShift and currentContract and not isLoadingOrUnloading then
            local targetCoords = nil

            if contractState == Config.ContractState.Selected then
                targetCoords = currentContract.pickupCoords or Config.Depot.pickupBay.coords
            elseif contractState == Config.ContractState.InTransit then
                targetCoords = currentContract.destinationCoords
            elseif contractState == Config.ContractState.Delivered then
                targetCoords = Config.Depot.returnBay.coords
            end

            if targetCoords then
                local ped = PlayerPedId()
                local pCoords = GetEntityCoords(ped)
                local dist = #(pCoords - targetCoords)

                if dist < 120.0 then
                    waitMs = 0
                    local r = Config.Beacon.color.r or 0
                    local g = Config.Beacon.color.g or 229
                    local b = Config.Beacon.color.b or 255

                    -- Flat cylindrical landing marker
                    DrawMarker(1, targetCoords.x, targetCoords.y, targetCoords.z - 1.0,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        8.0, 8.0, 1.2,
                        r, g, b, 70,
                        false, false, 2, false, nil, nil, false)

                    -- Inner cyan beacon ring
                    DrawMarker(27, targetCoords.x, targetCoords.y, targetCoords.z + 0.1,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        6.5, 6.5, 1.0,
                        r, g, b, 120,
                        false, false, 2, false, nil, nil, false)
                end
            end
        end

        Wait(waitMs)
    end
end)

-- ---------------------------------------------------------------------------
-- Proximity and Interaction Loop
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        local waitMs = 500

        if onShift and currentContract and not isLoadingOrUnloading then
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)
            local truck = resolveTruckEntity()
            local tCoords = (truck and DoesEntityExist(truck)) and GetEntityCoords(truck) or pCoords

            if contractState == Config.ContractState.Selected then
                local pickup = currentContract.pickupCoords or Config.Depot.pickupBay.coords
                local distTruck = #(tCoords - pickup)
                local distPed = #(pCoords - pickup)

                if distTruck <= (Config.Security.pickupBayDistance or 14.0) or distPed <= 6.0 then
                    waitMs = 0
                    showPrompt('cm-trucking:pickup', 'SECURE & LOAD CONTAINER FREIGHT')

                    if IsControlJustReleased(0, Config.InteractKey or 38) then
                        hidePrompt('cm-trucking:pickup')
                        TriggerServerEvent('cm-trucking:server:loadCargo')
                    end
                else
                    hidePrompt('cm-trucking:pickup')
                end

            elseif contractState == Config.ContractState.InTransit then
                local dest = currentContract.destinationCoords
                local distTruck = #(tCoords - dest)
                local distPed = #(pCoords - dest)

                if distTruck <= (Config.Security.destinationBayDistance or 14.0) or distPed <= 6.0 then
                    waitMs = 0
                    showPrompt('cm-trucking:deliver', 'UNLOAD FREIGHT & SIGN DELIVERY RECEIPT')

                    if IsControlJustReleased(0, Config.InteractKey or 38) then
                        hidePrompt('cm-trucking:deliver')
                        TriggerServerEvent('cm-trucking:server:deliverCargo')
                    end
                else
                    hidePrompt('cm-trucking:deliver')
                end

            elseif contractState == Config.ContractState.Delivered then
                local returnBay = Config.Depot.returnBay.coords
                local distTruck = #(tCoords - returnBay)
                local distPed = #(pCoords - returnBay)

                if distTruck <= (Config.Security.depotReturnDistance or 14.0) or distPed <= 6.0 then
                    waitMs = 0
                    local label = payrollBlocked
                        and 'RETRY SUBMITTING FREIGHT MANIFEST'
                        or 'CHECK IN MANIFEST & FINALIZE RECEIPT'
                    showPrompt('cm-trucking:return', label)

                    if IsControlJustReleased(0, Config.InteractKey or 38) then
                        hidePrompt('cm-trucking:return')
                        TriggerServerEvent('cm-trucking:server:completeContract')
                    end
                else
                    hidePrompt('cm-trucking:return')
                end
            end
        else
            hidePrompt()
        end

        Wait(waitMs)
    end
end)

-- ---------------------------------------------------------------------------
-- Net Events from Server
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-trucking:client:contractStarted', function(data)
    if type(data) ~= 'table' then return end

    onShift = true
    truckNetId = data.truckNetId
    truckPlate = data.truckPlate
    currentContract = data.contract
    contractState = data.state or Config.ContractState.Selected
    payrollBlocked = false
    isLoadingOrUnloading = false

    if data.hasPendingDelivery then
        contractState = Config.ContractState.Delivered
        setTrackedBlip(Config.Depot.returnBay.coords, Config.Blip.depotReturn.name, Config.Blip.depotReturn.sprite, Config.Blip.depotReturn.color, true)
    else
        local pickupCoords = currentContract.pickupCoords or Config.Depot.pickupBay.coords
        setTrackedBlip(pickupCoords, Config.Blip.pickup.name, Config.Blip.pickup.sprite, Config.Blip.pickup.color, true)
    end

    updateHud()
end)

RegisterNetEvent('cm-trucking:client:startCargoLoading', function(data)
    isLoadingOrUnloading = true
    hidePrompt()

    local ped = PlayerPedId()
    local anim = Config.Anim.secureCargo
    if loadAnimDict(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, -1, 1, 0, false, false, false)
    end

    contractState = Config.ContractState.Loading
    updateHud()
end)

RegisterNetEvent('cm-trucking:client:cargoLoaded', function(data)
    isLoadingOrUnloading = false
    local ped = PlayerPedId()
    ClearPedTasks(ped)

    contractState = Config.ContractState.InTransit
    if data and data.contract then
        currentContract = data.contract
    end

    local destCoords = (data and data.destinationCoords) or (currentContract and currentContract.destinationCoords)
    local destLabel = (data and data.destinationLabel) or (currentContract and currentContract.destinationLabel) or Config.Blip.destination.name
    setTrackedBlip(destCoords, destLabel, Config.Blip.destination.sprite, Config.Blip.destination.color, true)

    updateHud()
end)

RegisterNetEvent('cm-trucking:client:startCargoUnloading', function(data)
    isLoadingOrUnloading = true
    hidePrompt()

    local ped = PlayerPedId()
    local anim = Config.Anim.inspectManifest
    if loadAnimDict(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, -1, 49, 0, false, false, false)
    end

    updateHud()
end)

RegisterNetEvent('cm-trucking:client:cargoDelivered', function(data)
    isLoadingOrUnloading = false
    local ped = PlayerPedId()
    ClearPedTasks(ped)

    contractState = Config.ContractState.Delivered
    if data and data.contract then
        currentContract = data.contract
    end

    local returnCoords = (data and data.returnBayCoords) or Config.Depot.returnBay.coords
    setTrackedBlip(returnCoords, Config.Blip.depotReturn.name, Config.Blip.depotReturn.sprite, Config.Blip.depotReturn.color, true)

    updateHud()
end)

RegisterNetEvent('cm-trucking:client:contractCompleted', function(data)
    onShift = false
    currentContract = nil
    contractState = nil
    truckNetId = nil
    truckPlate = nil
    truckEntity = nil
    payrollBlocked = false
    isLoadingOrUnloading = false

    hidePrompt()
    clearTrackedBlip()
    updateHud()
end)

RegisterNetEvent('cm-trucking:client:contractFailed', function(data)
    isLoadingOrUnloading = false
    local ped = PlayerPedId()
    ClearPedTasks(ped)

    payrollBlocked = true
    contractState = Config.ContractState.Delivered
    updateHud()
end)

RegisterNetEvent('cm-trucking:client:shiftEnded', function(reason)
    onShift = false
    currentContract = nil
    contractState = nil
    truckNetId = nil
    truckPlate = nil
    truckEntity = nil
    payrollBlocked = false
    isLoadingOrUnloading = false

    hidePrompt()
    clearTrackedBlip()
    updateHud()
end)

RegisterNetEvent('cm-trucking:client:notify', function(message, kind)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message or '')
    EndTextCommandThefeedPostTicker(false, true)
end)

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

exports('IsOnShift', function()
    return onShift
end)

exports('GetActiveContract', function()
    return currentContract
end)

exports('GetContractState', function()
    return contractState
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    hidePrompt()
    clearTrackedBlip()
    SendNUIMessage({ action = 'hide' })
end)

