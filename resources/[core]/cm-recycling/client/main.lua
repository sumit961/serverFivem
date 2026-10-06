local Config = CMRecycling.Config
CMRecycling.Client = CMRecycling.Client or {}

local onShift = false
local truckNetId = nil
local truckPlate = nil
local truckEntity = nil

local currentStop = nil
local currentStopIndex = 1
local totalStops = #Config.Route
local bundlesCollectedAtStop = 0
local bundlesPerStop = Config.Capacity.bundlesPerStop or 2
local totalBundlesInTruck = 0
local maxBundles = Config.Capacity.maxBundles or 10

local carryingBundle = false
local bundleToken = nil
local bundleProp = nil

local allPickupsComplete = false
local unloadedAtFacility = false
local sortingInProgress = false
local payrollBlocked = false

local routeBlip = nil
local facilityBlip = nil
local sortingBlip = nil
local activePromptOwner = nil

function CMRecycling.Client.IsOnShift()
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
                name = 'Salvage Operations',
                role = 'ROGERS RECYCLING',
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

    local instruction = 'PROCEED TO SALVAGE PICKUP POINT'

    if payrollBlocked then
        instruction = 'PAYOUT STORED IN LEDGER // CANNOT BE COLLECTED IN-GAME'
    elseif sortingInProgress then
        instruction = 'SORTING MATERIALS // MECHANICAL SEPARATION IN PROGRESS'
    elseif unloadedAtFacility then
        instruction = 'PROCEED TO SORTING STATION TO PROCESS BATCH'
    elseif allPickupsComplete or totalBundlesInTruck >= maxBundles then
        instruction = 'TRUCK AT CAPACITY // RETURN TO ROGERS SALVAGE UNLOAD BAY'
    elseif carryingBundle then
        instruction = 'LOAD SALVAGE BUNDLE INTO TRUCK BED'
    elseif currentStop then
        instruction = 'RECOVER SALVAGE MATERIAL FROM SITE'
    end

    local percent = math.floor((totalBundlesInTruck / maxBundles) * 100)

    SendNUIMessage({
        action = 'update',
        onShift = onShift,
        stopIndex = currentStopIndex,
        totalStops = totalStops,
        stopLabel = currentStop and currentStop.label or 'Industrial Compound',
        material = currentStop and currentStop.material or 'Industrial Scrap',
        bundlesInTruck = totalBundlesInTruck,
        maxBundles = maxBundles,
        percent = percent,
        allPickupsComplete = allPickupsComplete,
        unloadedAtFacility = unloadedAtFacility,
        sortingInProgress = sortingInProgress,
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

local function removeBundleProp()
    if bundleProp and DoesEntityExist(bundleProp) then
        DetachEntity(bundleProp, true, true)
        DeleteEntity(bundleProp)
    end
    bundleProp = nil
    carryingBundle = false
    bundleToken = nil
end

local function attachBundleProp()
    removeBundleProp()

    local ped = PlayerPedId()
    local propHash = loadModel(Config.Anim.prop)
    if not propHash then return end

    local pCoords = GetEntityCoords(ped)
    local obj = CreateObject(propHash, pCoords.x, pCoords.y, pCoords.z, true, true, false)
    if not DoesEntityExist(obj) then return end

    SetEntityCollision(obj, false, false)
    local boneIdx = GetPedBoneIndex(ped, Config.Anim.bone or 60309)
    local off = Config.Anim.offset or vector3(0.08, 0.08, 0.0)
    local rot = Config.Anim.rotation or vector3(0.0, 90.0, 0.0)

    AttachEntityToEntity(obj, ped, boneIdx, off.x, off.y, off.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    bundleProp = obj
    carryingBundle = true
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

    if facilityBlip and DoesBlipExist(facilityBlip) then
        RemoveBlip(facilityBlip)
    end
    facilityBlip = nil

    if sortingBlip and DoesBlipExist(sortingBlip) then
        RemoveBlip(sortingBlip)
    end
    sortingBlip = nil
end

local function setRouteBlip(coords, label)
    clearBlips()
    if not coords then return end

    local cfg = Config.Blip.pickup
    routeBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(routeBlip, cfg.sprite or 1)
    SetBlipDisplay(routeBlip, 4)
    SetBlipScale(routeBlip, cfg.scale or 0.70)
    SetBlipColour(routeBlip, cfg.color or 25)
    SetBlipRoute(routeBlip, true)
    SetBlipRouteColour(routeBlip, cfg.color or 25)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or cfg.name or 'Salvage Pickup Point')
    EndTextCommandSetBlipName(routeBlip)
end

local function setUnloadBlip()
    clearBlips()
    local bay = Config.Facility.unloadBay
    local cfg = Config.Blip.unload

    facilityBlip = AddBlipForCoord(bay.coords.x, bay.coords.y, bay.coords.z)
    SetBlipSprite(facilityBlip, cfg.sprite or 365)
    SetBlipDisplay(facilityBlip, 4)
    SetBlipScale(facilityBlip, cfg.scale or 0.85)
    SetBlipColour(facilityBlip, cfg.color or 5)
    SetBlipRoute(facilityBlip, true)
    SetBlipRouteColour(facilityBlip, cfg.color or 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(cfg.name or 'Salvage Unload Bay')
    EndTextCommandSetBlipName(facilityBlip)
end

local function setSortingBlip()
    clearBlips()
    local station = Config.Facility.sortingStation
    local cfg = Config.Blip.sorting

    sortingBlip = AddBlipForCoord(station.coords.x, station.coords.y, station.coords.z)
    SetBlipSprite(sortingBlip, cfg.sprite or 402)
    SetBlipDisplay(sortingBlip, 4)
    SetBlipScale(sortingBlip, cfg.scale or 0.80)
    SetBlipColour(sortingBlip, cfg.color or 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(cfg.name or 'Material Sorting Station')
    EndTextCommandSetBlipName(sortingBlip)
end

-- ---------------------------------------------------------------------------
-- Server Event Handlers
-- ---------------------------------------------------------------------------

RegisterNetEvent('cm-recycling:client:shiftStarted', function(data)
    if type(data) ~= 'table' then return end

    onShift = true
    truckNetId = data.truckNetId
    truckPlate = data.truckPlate
    currentStopIndex = data.stopIndex or 1
    totalStops = data.totalStops or #Config.Route
    currentStop = data.stop or Config.Route[1]
    bundlesCollectedAtStop = 0
    totalBundlesInTruck = data.bundlesInTruck or 0
    maxBundles = data.maxBundles or Config.Capacity.maxBundles or 10
    bundlesPerStop = data.bundlesPerStop or Config.Capacity.bundlesPerStop or 2

    carryingBundle = false
    allPickupsComplete = data.hasPendingBatch == true
    unloadedAtFacility = data.hasPendingBatch == true
    sortingInProgress = false
    payrollBlocked = false

    if data.hasPendingBatch then
        setSortingBlip()
    elseif currentStop then
        setRouteBlip(currentStop.truckCoords, currentStop.label)
    end

    SendNUIMessage({ action = 'show' })
    updateHud()
end)

RegisterNetEvent('cm-recycling:client:shiftEnded', function(reason)
    onShift = false
    truckNetId = nil
    truckPlate = nil
    truckEntity = nil
    currentStop = nil
    carryingBundle = false
    allPickupsComplete = false
    unloadedAtFacility = false
    sortingInProgress = false
    payrollBlocked = false

    removeBundleProp()
    clearBlips()
    hidePrompt('cm-recycling:salvage')
    hidePrompt('cm-recycling:load')
    hidePrompt('cm-recycling:unload')
    hidePrompt('cm-recycling:sort')

    SendNUIMessage({ action = 'hide' })
end)

RegisterNetEvent('cm-recycling:client:bundleCollected', function(data)
    if type(data) ~= 'table' then return end

    bundleToken = data.token
    local ped = PlayerPedId()

    local anim = Config.Anim.salvage
    if loadAnimDict(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, anim.duration or 2000, 0, 0, false, false, false)
        Wait(1200)
    end

    local carryAnim = Config.Anim.carry
    if loadAnimDict(carryAnim.dict) then
        TaskPlayAnim(ped, carryAnim.dict, carryAnim.clip, 8.0, -8.0, -1, 49, 0, false, false, false)
        Wait(300)
    end

    attachBundleProp()
    hidePrompt('cm-recycling:salvage')
    updateHud()
end)

RegisterNetEvent('cm-recycling:client:bundleLoaded', function(data)
    if type(data) ~= 'table' then return end

    local ped = PlayerPedId()
    removeBundleProp()
    ClearPedTasks(ped)
    hidePrompt('cm-recycling:load')

    totalBundlesInTruck = data.totalBundlesInTruck or (totalBundlesInTruck + 1)
    allPickupsComplete = data.allPickupsComplete or false
    currentStopIndex = data.stopIndex or currentStopIndex
    currentStop = data.nextStop

    if allPickupsComplete or totalBundlesInTruck >= maxBundles then
        setUnloadBlip()
    elseif currentStop then
        setRouteBlip(currentStop.truckCoords, currentStop.label)
    end

    updateHud()
end)

RegisterNetEvent('cm-recycling:client:truckUnloaded', function(data)
    unloadedAtFacility = true
    hidePrompt('cm-recycling:unload')
    setSortingBlip()
    updateHud()
end)

RegisterNetEvent('cm-recycling:client:startSorting', function(data)
    sortingInProgress = true
    hidePrompt('cm-recycling:sort')

    local ped = PlayerPedId()
    local anim = Config.Anim.sort
    if loadAnimDict(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, data.duration or 7000, 1, 0, false, false, false)
    end

    updateHud()
end)

RegisterNetEvent('cm-recycling:client:processingComplete', function(data)
    sortingInProgress = false
    payrollBlocked = false
    unloadedAtFacility = false
    allPickupsComplete = false
    totalBundlesInTruck = 0
    bundlesCollectedAtStop = 0
    currentStopIndex = data.stopIndex or 1
    currentStop = data.stop or Config.Route[1]

    local ped = PlayerPedId()
    ClearPedTasks(ped)

    if currentStop then
        setRouteBlip(currentStop.truckCoords, currentStop.label)
    end

    updateHud()
end)

RegisterNetEvent('cm-recycling:client:processingFailed', function(data)
    sortingInProgress = false
    payrollBlocked = true

    local ped = PlayerPedId()
    ClearPedTasks(ped)

    setSortingBlip()
    updateHud()
end)

-- ---------------------------------------------------------------------------
-- Active Gameplay Loop
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

            -- 1. Carrying bundle constraints: disable sprint, jump, combat
            if carryingBundle then
                waitMs = 0
                DisableControlAction(0, 21, true) -- SPRINT
                DisableControlAction(0, 22, true) -- JUMP
                DisableControlAction(0, 24, true) -- ATTACK
                DisableControlAction(0, 25, true) -- AIM

                -- Check proximity to truck bed to load bundle
                if truckEntity and DoesEntityExist(truckEntity) then
                    local tCoords = GetEntityCoords(truckEntity)
                    local fwd = GetEntityForwardVector(truckEntity)
                    local bedOffset = Config.Vehicle.truckBedOffset or vector3(0.0, -2.4, 0.0)
                    local bed = tCoords + (fwd * bedOffset.y)
                    local distToBed = #(pCoords - bed)

                    if distToBed <= (Config.Security.truckBedDistance or 3.8) then
                        showPrompt('cm-recycling:load', 'SECURE BUNDLE IN TRUCK BED')

                        if IsControlJustReleased(0, Config.InteractKey or 38) then
                            if bundleToken then
                                TriggerServerEvent('cm-recycling:server:loadBundleIntoTruck', bundleToken)
                            end
                        end
                    else
                        hidePrompt('cm-recycling:load')
                    end
                else
                    hidePrompt('cm-recycling:load')
                end
            else
                hidePrompt('cm-recycling:load')
            end

            -- 2. Salvage collection at stop
            if not carryingBundle and not allPickupsComplete and totalBundlesInTruck < maxBundles then
                if currentStop and currentStop.salvageCoords then
                    local distToSalvage = #(pCoords - currentStop.salvageCoords)
                    if distToSalvage <= (Config.Security.salvageDistance or 3.2) then
                        waitMs = 0
                        showPrompt('cm-recycling:salvage', 'RECOVER SALVAGE BUNDLE')

                        if IsControlJustReleased(0, Config.InteractKey or 38) then
                            TriggerServerEvent('cm-recycling:server:collectBundle')
                        end
                    else
                        hidePrompt('cm-recycling:salvage')
                    end
                else
                    hidePrompt('cm-recycling:salvage')
                end
            else
                hidePrompt('cm-recycling:salvage')
            end

            -- 3. Facility Unloading Bay: when capacity reached or all stops complete
            if (allPickupsComplete or totalBundlesInTruck >= maxBundles) and not unloadedAtFacility then
                local bay = Config.Facility.unloadBay
                if truckEntity and DoesEntityExist(truckEntity) then
                    local tCoords = GetEntityCoords(truckEntity)
                    if #(tCoords - bay.coords) <= (Config.Security.facilityUnloadDistance or 8.5) then
                        waitMs = 0
                        showPrompt('cm-recycling:unload', 'UNLOAD SALVAGE INTO HOPPER')

                        if IsControlJustReleased(0, Config.InteractKey or 38) then
                            TriggerServerEvent('cm-recycling:server:unloadTruck')
                        end
                    else
                        hidePrompt('cm-recycling:unload')
                    end
                else
                    hidePrompt('cm-recycling:unload')
                end
            else
                hidePrompt('cm-recycling:unload')
            end

            -- 4. Sorting Station: when unloaded or retrying failed payday
            if (unloadedAtFacility or payrollBlocked) and not sortingInProgress then
                local station = Config.Facility.sortingStation
                local distToStation = #(pCoords - station.coords)

                if distToStation <= (Config.Security.sortingStationDistance or 3.0) then
                    waitMs = 0
                    showPrompt('cm-recycling:sort', 'PROCESS & SORT SALVAGE')

                    if IsControlJustReleased(0, Config.InteractKey or 38) then
                        TriggerServerEvent('cm-recycling:server:processMaterials')
                    end
                else
                    hidePrompt('cm-recycling:sort')
                end
            else
                hidePrompt('cm-recycling:sort')
            end
        end

        Wait(waitMs)
    end
end)

-- Visual Marker Rendering (CM Cyan markers)
CreateThread(function()
    while true do
        local waitMs = 800

        if onShift then
            local ped = PlayerPedId()
            local pCoords = GetEntityCoords(ped)

            -- At salvage site
            if not carryingBundle and not allPickupsComplete and currentStop and currentStop.salvageCoords then
                local s = currentStop.salvageCoords
                if #(pCoords - s) < 50.0 then
                    waitMs = 0
                    DrawMarker(27, s.x, s.y, s.z + 0.05, 0, 0, 0, 0, 0, 0, 1.4, 1.4, 0.35, 0, 229, 255, 160, false, false, 2, false, nil, nil, false)
                    DrawMarker(2, s.x, s.y, s.z + 1.2, 0, 0, 0, 180.0, 0, 0, 0.35, 0.35, 0.35, 0, 229, 255, 200, false, false, 2, true, nil, nil, false)
                end
            -- While carrying to truck bed
            elseif carryingBundle and truckEntity and DoesEntityExist(truckEntity) then
                local tCoords = GetEntityCoords(truckEntity)
                local fwd = GetEntityForwardVector(truckEntity)
                local bedOffset = Config.Vehicle.truckBedOffset or vector3(0.0, -2.4, 0.0)
                local bed = tCoords + (fwd * bedOffset.y)
                if #(pCoords - bed) < 25.0 then
                    waitMs = 0
                    DrawMarker(27, bed.x, bed.y, bed.z + 0.05, 0, 0, 0, 0, 0, 0, 1.3, 1.3, 0.3, 0, 229, 255, 140, false, false, 2, false, nil, nil, false)
                end
            -- At facility unload bay
            elseif (allPickupsComplete or totalBundlesInTruck >= maxBundles) and not unloadedAtFacility then
                local bay = Config.Facility.unloadBay.coords
                if #(pCoords - bay) < 80.0 then
                    waitMs = 0
                    DrawMarker(1, bay.x, bay.y, bay.z - 0.5, 0, 0, 0, 0, 0, 0, 7.5, 7.5, 1.0, 0, 229, 255, 100, false, false, 2, false, nil, nil, false)
                end
            -- At facility sorting station
            elseif (unloadedAtFacility or payrollBlocked) and not sortingInProgress then
                local st = Config.Facility.sortingStation.coords
                if #(pCoords - st) < 50.0 then
                    waitMs = 0
                    DrawMarker(27, st.x, st.y, st.z + 0.05, 0, 0, 0, 0, 0, 0, 1.5, 1.5, 0.35, 0, 229, 255, 160, false, false, 2, false, nil, nil, false)
                    DrawMarker(2, st.x, st.y, st.z + 1.2, 0, 0, 0, 180.0, 0, 0, 0.35, 0.35, 0.35, 0, 229, 255, 200, false, false, 2, true, nil, nil, false)
                end
            end
        end

        Wait(waitMs)
    end
end)

-- Safe cleanup on stop
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    removeBundleProp()
    clearBlips()
    hidePrompt('cm-recycling:salvage')
    hidePrompt('cm-recycling:load')
    hidePrompt('cm-recycling:unload')
    hidePrompt('cm-recycling:sort')
    SendNUIMessage({ action = 'hide' })
end)

