local Config = CMGarbage.Config
CMGarbage.Client = CMGarbage.Client or {}

local onShift = false
local truckNetId = nil
local truckPlate = nil
local truckEntity = nil

local currentStop = nil
local currentStopIndex = 1
local totalStops = #Config.Route
local bagsCollectedAtStop = 0
local bagsRequiredAtStop = 2
local totalBagsInTruck = 0
local maxCapacity = Config.Capacity.maxBags

local carryingBag = false
local bagToken = nil
local bagProp = nil
local unloading = false
local payrollBlocked = false

local routeBlip = nil
local tippingBlip = nil
local activePromptOwner = nil

function CMGarbage.Client.IsOnShift()
    return onShift
end

-- ---------------------------------------------------------------------------
-- UI Helpers
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
                name = 'Sanitation Route',
                role = 'WASTE MANAGEMENT',
            })
        end)
    end
end

local function hidePrompt(owner)
    if activePromptOwner == owner then
        if GetResourceState('cm-ui') == 'started' then
            pcall(function() exports['cm-ui']:HideInteract(owner) end)
        end
        activePromptOwner = nil
    end
end

local function updateHud()
    if not onShift then
        SendNUIMessage({ action = 'hide' })
        return
    end

    local truckFull = totalBagsInTruck >= maxCapacity
    local instruction = 'PROCEED TO COLLECTION STOP'

    if payrollBlocked then
        instruction = 'PAYOUT STORED IN LEDGER // CANNOT BE COLLECTED IN-GAME'
    elseif truckFull then
        instruction = 'COMPACTOR FULL // PROCEED TO DEPOT TIPPING PIT'
    elseif carryingBag then
        instruction = 'CARRY RUBBISH TO REAR TRUCK HOPPER'
    elseif currentStop then
        instruction = ('COLLECT RUBBISH (%d/%d BAGS)'):format(bagsCollectedAtStop, bagsRequiredAtStop)
    end

    SendNUIMessage({
        action = 'update',
        onShift = onShift,
        stopIndex = currentStopIndex,
        totalStops = totalStops,
        stopLabel = currentStop and currentStop.label or 'South LS Curbside',
        bagsInTruck = totalBagsInTruck,
        maxCapacity = maxCapacity,
        percent = math.floor((totalBagsInTruck / maxCapacity) * 100),
        truckFull = truckFull,
        instruction = instruction,
    })
end

-- ---------------------------------------------------------------------------
-- Animation & Prop Management
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

local function loadModel(model)
    local hash = joaat(model)
    if not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 250 do
        Wait(10)
        timeout = timeout + 1
    end
    return HasModelLoaded(hash) and hash or nil
end

local function removeBagProp()
    if bagProp and DoesEntityExist(bagProp) then
        DetachEntity(bagProp, true, true)
        DeleteEntity(bagProp)
    end
    bagProp = nil
    carryingBag = false
    bagToken = nil
end

local function attachBagProp()
    removeBagProp()

    local ped = PlayerPedId()
    local propHash = loadModel(Config.Anim.prop)
    if not propHash then return end

    local pCoords = GetEntityCoords(ped)
    local obj = CreateObject(propHash, pCoords.x, pCoords.y, pCoords.z, true, true, false)
    if not DoesEntityExist(obj) then return end

    SetEntityCollision(obj, false, false)
    local boneIdx = GetPedBoneIndex(ped, Config.Anim.bone or 28422)
    local off = Config.Anim.offset or vector3(0.0, 0.0, -0.05)
    local rot = Config.Anim.rotation or vector3(0.0, 0.0, 0.0)

    AttachEntityToEntity(obj, ped, boneIdx, off.x, off.y, off.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    bagProp = obj
    carryingBag = true
    SetModelAsNoLongerNeeded(propHash)
end

-- ---------------------------------------------------------------------------
-- Blip Management
-- ---------------------------------------------------------------------------

local function clearBlips()
    if routeBlip and DoesBlipExist(routeBlip) then
        RemoveBlip(routeBlip)
    end
    routeBlip = nil

    if tippingBlip and DoesBlipExist(tippingBlip) then
        RemoveBlip(tippingBlip)
    end
    tippingBlip = nil
end

local function setRouteBlip(coords, label)
    clearBlips()
    if not coords then return end

    local cfg = Config.Blip.stop
    routeBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(routeBlip, cfg.sprite or 1)
    SetBlipDisplay(routeBlip, 4)
    SetBlipScale(routeBlip, cfg.scale or 0.70)
    SetBlipColour(routeBlip, cfg.color or 5)
    SetBlipRoute(routeBlip, true)
    SetBlipRouteColour(routeBlip, cfg.color or 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or cfg.name or 'Collection Stop')
    EndTextCommandSetBlipName(routeBlip)
end

local function setTippingBlip()
    clearBlips()
    local pit = Config.Depot.tippingPit
    local cfg = Config.Blip.tipping

    tippingBlip = AddBlipForCoord(pit.coords.x, pit.coords.y, pit.coords.z)
    SetBlipSprite(tippingBlip, cfg.sprite or 318)
    SetBlipDisplay(tippingBlip, 4)
    SetBlipScale(tippingBlip, cfg.scale or 0.85)
    SetBlipColour(tippingBlip, cfg.color or 5)
    SetBlipRoute(tippingBlip, true)
    SetBlipRouteColour(tippingBlip, cfg.color or 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(cfg.name or 'Depot Unload Pit')
    EndTextCommandSetBlipName(tippingBlip)
end

-- ---------------------------------------------------------------------------
-- Server Event Handlers
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-garbage:client:shiftStarted', function(data)
    if type(data) ~= 'table' then return end

    onShift = true
    truckNetId = data.truckNetId
    truckPlate = data.truckPlate
    currentStopIndex = data.stopIndex or 1
    totalStops = data.totalStops or #Config.Route
    currentStop = data.stop or Config.Route[1]
    bagsCollectedAtStop = 0
    bagsRequiredAtStop = currentStop and (currentStop.bagsRequired or Config.Capacity.bagsPerStop) or 2
    totalBagsInTruck = 0
    maxCapacity = data.maxCapacity or Config.Capacity.maxBags
    carryingBag = false
    unloading = false
    payrollBlocked = false

    if currentStop then
        setRouteBlip(currentStop.truckCoords, currentStop.label)
    end

    SendNUIMessage({ action = 'show' })
    updateHud()
end)

RegisterNetEvent('cm-garbage:client:shiftEnded', function(reason)
    onShift = false
    truckNetId = nil
    truckPlate = nil
    truckEntity = nil
    currentStop = nil
    carryingBag = false
    unloading = false
    payrollBlocked = false

    removeBagProp()
    clearBlips()
    hidePrompt('cm-garbage:pickup')
    hidePrompt('cm-garbage:deposit')
    hidePrompt('cm-garbage:unload')

    SendNUIMessage({ action = 'hide' })
end)

RegisterNetEvent('cm-garbage:client:bagAttached', function(data)
    if type(data) ~= 'table' then return end

    bagToken = data.token
    local ped = PlayerPedId()

    local anim = Config.Anim.pickup
    if loadAnimDict(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, anim.duration or 2400, 48, 0, false, false, false)
        Wait(1000)
    end

    attachBagProp()
    hidePrompt('cm-garbage:pickup')
    updateHud()
end)

RegisterNetEvent('cm-garbage:client:bagDeposited', function(data)
    if type(data) ~= 'table' then return end

    local ped = PlayerPedId()
    local anim = Config.Anim.throw

    if loadAnimDict(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, anim.duration or 2200, 48, 0, false, false, false)
        Wait(800)
    end

    removeBagProp()
    hidePrompt('cm-garbage:deposit')

    totalBagsInTruck = data.totalBags or (totalBagsInTruck + 1)
    currentStopIndex = data.stopIndex or currentStopIndex
    currentStop = data.nextStop

    if data.stopComplete then
        bagsCollectedAtStop = 0
        if currentStop then
            bagsRequiredAtStop = currentStop.bagsRequired or Config.Capacity.bagsPerStop
        end
    else
        bagsCollectedAtStop = bagsCollectedAtStop + 1
    end

    if data.truckFull then
        setTippingBlip()
    elseif currentStop then
        setRouteBlip(currentStop.truckCoords, currentStop.label)
    end

    updateHud()
end)

RegisterNetEvent('cm-garbage:client:startUnloading', function(data)
    unloading = true
    hidePrompt('cm-garbage:unload')
    updateHud()

    if truckEntity and DoesEntityExist(truckEntity) then
        SetVehicleIndicatorLights(truckEntity, 0, true)
        SetVehicleIndicatorLights(truckEntity, 1, true)
    end
end)

RegisterNetEvent('cm-garbage:client:unloadComplete', function(data)
    unloading = false
    payrollBlocked = false
    totalBagsInTruck = 0
    bagsCollectedAtStop = 0
    currentStopIndex = data.stopIndex or 1
    currentStop = data.stop or Config.Route[1]
    bagsRequiredAtStop = currentStop and (currentStop.bagsRequired or Config.Capacity.bagsPerStop) or 2

    if truckEntity and DoesEntityExist(truckEntity) then
        SetVehicleIndicatorLights(truckEntity, 0, false)
        SetVehicleIndicatorLights(truckEntity, 1, false)
    end

    if currentStop then
        setRouteBlip(currentStop.truckCoords, currentStop.label)
    end

    updateHud()
end)

RegisterNetEvent('cm-garbage:client:unloadFailed', function(data)
    unloading = false
    payrollBlocked = true

    if truckEntity and DoesEntityExist(truckEntity) then
        SetVehicleIndicatorLights(truckEntity, 0, false)
        SetVehicleIndicatorLights(truckEntity, 1, false)
    end

    -- Keep tipping blip active so the player can retry at the tipping pit
    setTippingBlip()
    updateHud()
end)

-- ---------------------------------------------------------------------------
-- Active Gameplay Loop (Proximity, Interactions, Carrying Constraints)
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        local waitMs = 600

        if onShift then
            waitMs = 250
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)

            -- Resolve truck entity from netId if needed
            if truckNetId and (not truckEntity or not DoesEntityExist(truckEntity)) then
                if NetworkDoesNetworkIdExist(truckNetId) then
                    truckEntity = NetToVeh(truckNetId)
                end
            end

            -- Constraint: while carrying heavy trash bag, disable sprint, jump, combat
            if carryingBag then
                waitMs = 0
                DisableControlAction(0, 21, true) -- SPRINT
                DisableControlAction(0, 22, true) -- JUMP
                DisableControlAction(0, 24, true) -- ATTACK
                DisableControlAction(0, 25, true) -- AIM

                -- Check proximity to assigned truck rear hopper
                if truckEntity and DoesEntityExist(truckEntity) then
                    local tCoords = GetEntityCoords(truckEntity)
                    local fwd = GetEntityForwardVector(truckEntity)
                    local rearCoords = tCoords + (fwd * -4.5)
                    local distToHopper = #(pCoords - rearCoords)

                    if distToHopper <= (Config.Security.hopperDistance or 4.2) then
                        showPrompt('cm-garbage:deposit', 'TOSS IN COMPACTOR')

                        if IsControlJustReleased(0, Config.InteractKey or 38) then
                            if bagToken then
                                TriggerServerEvent('cm-garbage:server:depositBag', bagToken)
                            end
                        end
                    else
                        hidePrompt('cm-garbage:deposit')
                    end
                end
            else
                hidePrompt('cm-garbage:deposit')
            end

            -- Pickup interaction: when stop is active and compactor not full
            local truckFull = totalBagsInTruck >= maxCapacity

            if not truckFull and not carryingBag and currentStop and currentStop.binCoords then
                local distToBin = #(pCoords - currentStop.binCoords)

                if distToBin <= (Config.Security.binDistance or 3.5) then
                    waitMs = 0
                    showPrompt('cm-garbage:pickup', 'COLLECT RUBBISH BAG')

                    if IsControlJustReleased(0, Config.InteractKey or 38) then
                        TriggerServerEvent('cm-garbage:server:pickupBag')
                    end
                else
                    hidePrompt('cm-garbage:pickup')
                end
            else
                hidePrompt('cm-garbage:pickup')
            end

            -- Tipping Pit interaction: when truck has an unloadable load and not currently unloading
            if (truckFull or payrollBlocked) and not unloading then
                local pit = Config.Depot.tippingPit
                local distToPit = #(pCoords - pit.coords)

                if truckEntity and DoesEntityExist(truckEntity) then
                    local tCoords = GetEntityCoords(truckEntity)
                    if #(tCoords - pit.coords) <= (Config.Security.unloadDistance or 8.5) then
                        waitMs = 0
                        showPrompt('cm-garbage:unload', 'EMPTY COMPACTOR')

                        if IsControlJustReleased(0, Config.InteractKey or 38) then
                            TriggerServerEvent('cm-garbage:server:unloadTruck')
                        end
                    else
                        hidePrompt('cm-garbage:unload')
                    end
                elseif distToPit <= 6.0 then
                    waitMs = 0
                    showPrompt('cm-garbage:unload', 'BACK TRUCK INTO PIT')
                else
                    hidePrompt('cm-garbage:unload')
                end
            end
        end

        Wait(waitMs)
    end
end)

-- Visual Marker Rendering (Cyan cylinder & destination beacon)
CreateThread(function()
    while true do
        local waitMs = 800

        if onShift then
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)

            -- If carrying bag: render rear hopper indicator on truck
            if carryingBag and truckEntity and DoesEntityExist(truckEntity) then
                waitMs = 0
                local tCoords = GetEntityCoords(truckEntity)
                local fwd = GetEntityForwardVector(truckEntity)
                local rear = tCoords + (fwd * -4.5)
                DrawMarker(27, rear.x, rear.y, rear.z + 0.1, 0, 0, 0, 0, 0, 0, 1.4, 1.4, 0.4, 0, 229, 255, 160, false, false, 2, false, nil, nil, false)
            -- If not carrying and stop is active: render beacon at bin
            elseif not carryingBag and currentStop and currentStop.binCoords then
                local b = currentStop.binCoords
                if #(pCoords - b) < 65.0 then
                    waitMs = 0
                    DrawMarker(27, b.x, b.y, b.z + 0.05, 0, 0, 0, 0, 0, 0, 1.2, 1.2, 0.35, 0, 229, 255, 140, false, false, 2, false, nil, nil, false)
                    DrawMarker(2, b.x, b.y, b.z + 1.2, 0, 0, 0, 180.0, 0, 0, 0.4, 0.4, 0.4, 0, 229, 255, 200, false, false, 2, true, nil, nil, false)
                end
            -- If truck full or retrying unload: render marker at depot tipping pit
            elseif (totalBagsInTruck >= maxCapacity or payrollBlocked) then
                local pit = Config.Depot.tippingPit.coords
                if #(pCoords - pit) < 80.0 then
                    waitMs = 0
                    DrawMarker(1, pit.x, pit.y, pit.z - 0.5, 0, 0, 0, 0, 0, 0, 7.0, 7.0, 1.0, 0, 229, 255, 100, false, false, 2, false, nil, nil, false)
                end
            end
        end

        Wait(waitMs)
    end
end)

-- Safe cleanup on stop
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    removeBagProp()
    clearBlips()
    hidePrompt('cm-garbage:pickup')
    hidePrompt('cm-garbage:deposit')
    hidePrompt('cm-garbage:unload')
    SendNUIMessage({ action = 'hide' })
end)

