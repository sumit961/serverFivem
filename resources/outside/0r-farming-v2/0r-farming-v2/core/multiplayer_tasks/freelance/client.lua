local lib = lib
local Utils = require("modules.utils.client")
local Target = require("modules.target.client")
local config = lib.load("core.multiplayer_tasks.freelance.config")

local FreelanceClient = {}

local RES_MARKERS_YTD <const> = "res_markers"

--- Point states for farming
local POINT_STATES <const> = {
    EMPTY = "empty",
    PLANTED = "planted",
    WATERED = "watered",
    GROWN = "grown",
    HARVESTED = "harvested"
}

--- Colors for point marker states
local POINT_COLORS <const> = {
    [POINT_STATES.EMPTY] = { r = 255, g = 255, b = 255 },   -- White
    [POINT_STATES.PLANTED] = { r = 255, g = 255, b = 0 },   -- Yellow
    [POINT_STATES.WATERED] = { r = 130, g = 255, b = 243 }, -- Light Blue
    [POINT_STATES.GROWN] = { r = 0, g = 255, b = 0 },       -- Green
    [POINT_STATES.HARVESTED] = { r = 255, g = 165, b = 0 }  -- Orange
}

--- Farming vehicles configuration
local FARMING_VEHICLES <const> = {
    tractor = {
        action = "planting",
        requiredState = POINT_STATES.EMPTY,
        targetState = POINT_STATES.PLANTED,
        maxSpeed = 20.0,
        workRadius = 3.0
    },
    harvester = {
        action = "harvesting",
        requiredState = POINT_STATES.GROWN,
        targetState = POINT_STATES.HARVESTED,
        maxSpeed = 16.0,
        workRadius = 4.0
    }
}

--- Farming manual tools configuration
local MANUAL_FARMING_TOOLS <const> = {
    watercan = {
        action = "watering",
        requiredState = POINT_STATES.PLANTED,
        targetState = POINT_STATES.WATERED,
        workRadius = 1.5,
        workTime = 2500,
        actionText = locale("freelance.water_plants"),
        anim = {
            dict = "weapon@w_sp_jerrycan",
            clip = "fire",
            flags = 1
        },
        prop = {
            model = "prop_wateringcan",
            bone = 18905,
            pos = { x = 0.08, y = -0.2, z = 0.3 },
            rot = { x = -10.0, y = 80.0, z = 90.0 }
        }
    }
}

local state = {}

--- Initialize the state
--- This function should be called once at the start of the script
local function __init__()
    state = {
        showTextUI = false,

        fieldBlips = {},
        fieldPoints = {},

        pointGroundZValues = {},
        pointWaterTimes = {},

        nearbyPoints = {},

        pointObjectNetIds = {},

        vehicleFarmingOperation = {
            isWorking = false,
            lastVehicle = nil,
            currentVehicleType = nil,
            lastProcessedPoints = {},
            selectedCropName = nil,
            grainUnloading = false,
            unloadingParticle = nil,
            lastGrainUpdateTime = 0,
            harvesterDoorIsOpen = false
        },

        carryingState = {
            isCarrying = false,
            carryingProp = nil,
        },

        latestSpeedWarningTime = nil,
    }
end

--- Check if the player has the required item
--- @param itemName string
--- @param amount number
--- @return boolean
local function hasRequiredItem(itemName, amount)
    return lib.callback.await(_e("server:inventory:hasRequiredItem"), false, itemName, amount)
end

--- Remove the specified item from the player"s inventory
--- @param itemName string
--- @param amount number
--- @return boolean
local function removeItem(itemName, amount)
    return lib.callback.await(_e("server:inventory:removeItem"), false, itemName, amount)
end

--- Get the field data by ID
--- @param fieldId string|number
--- @return table|nil
local function getFieldById(fieldId)
    return config.fields[fieldId]
end

--- Draw planting point markers
--- @param point
local function drawPlantingPoint(point)
    local pointState = point.state or POINT_STATES.EMPTY
    local markerColor = POINT_COLORS[pointState] or POINT_COLORS[POINT_STATES.EMPTY]

    local textureName = "s1"
    if pointState == POINT_STATES.WATERED then
        textureName = "s2"
    elseif pointState == POINT_STATES.GROWN then
        textureName = "s3"
    end

    if not Config.DisableCustomProps then
        DrawMarker(9, point.coords.x, point.coords.y, point.coords.z + 1.0,
            0.0, 0.0, 0.0,
            90.0, 0.0, 0.0,
            .2, .25, 0.0,
            markerColor.r, markerColor.g, markerColor.b, 255,
            false, true, 2, false, RES_MARKERS_YTD, textureName, false)
    else
        DrawMarker(28, point.coords.x, point.coords.y, point.coords.z + 1.0,
            0.0, 0.0, 0.0,
            0.0, 0.0, 0.0,
            .1, .1, .1,
            markerColor.r, markerColor.g, markerColor.b, 200,
            false, true, 2, false, nil, nil, false)
    end
end

--- Show crop selection dialogue
--- @return string|nil
local function showCropSelectionDialog()
    local availableCrops = {}

    for cropKey, cropData in pairs(config.crops) do
        table.insert(availableCrops, {
            label = cropData.label,
            value = cropKey,
        })
    end

    if #availableCrops == 0 then
        Utils.notify(locale("freelance.no_seeds_available"), "error")
        return nil
    end

    local input = lib.inputDialog(locale("freelance.select_crop"), {
        {
            type = "select",
            label = locale("freelance.crop_type"),
            options = availableCrops,
            required = true
        }
    })

    if input and input[1] then
        return input[1]
    end

    return nil
end

--- Check if the player can process a planting point
--- @param pointIndex number
--- @param requiredState string
--- @return boolean
local function canProcessPoint(pointIndex, requiredState)
    local point = client.currentTask.game.plantingPoints[pointIndex] or {}
    local currentState = point.state or POINT_STATES.EMPTY
    return currentState == requiredState
end

---@param self CPoint
local function onEnterSpawnTaskEntityPoint(self)
    local meta = self.meta
    if not meta or not meta.key or not meta.model then
        return
    end

    local entityModel = type(meta.model) == "string" and GetHashKey(meta.model) or meta.model
    if not IsModelValid(entityModel) then
        shared.debug("debug:FreelanceClient.onEnterSpawnTaskEntityPoint: Invalid model", meta.model)
        return
    end

    local isEntityModelAVehicle = IsModelAVehicle(entityModel)
    local entitySpawnCoords = meta.coords or self.coords

    lib.requestModel(entityModel)
    local entityId, entityNetId

    if isEntityModelAVehicle then
        entityId = CreateVehicle(entityModel, entitySpawnCoords.x, entitySpawnCoords.y,
            entitySpawnCoords.z, entitySpawnCoords.w or 0.0, true, true)
    else
        entityId = CreateObject(entityModel, entitySpawnCoords.x, entitySpawnCoords.y, entitySpawnCoords.z,
            true, true, false)
    end

    while not DoesEntityExist(entityId) do Citizen.Wait(0) end

    entityNetId = lib.waitFor(function()
        if not NetworkGetEntityIsNetworked(entityId) then
            NetworkRegisterEntityAsNetworked(entityId)
        else
            local netId = isEntityModelAVehicle and VehToNet(entityId) or ObjToNet(entityId)
            if NetworkDoesNetworkIdExist(netId) then
                return netId
            end
        end
    end, false, false)

    SetModelAsNoLongerNeeded(entityModel)

    SetEntityCoords(entityId, entitySpawnCoords.x, entitySpawnCoords.y, entitySpawnCoords.z)
    SetEntityRotation(entityId, 0.0, 0.0, entitySpawnCoords.w or 0.0, 2)

    if isEntityModelAVehicle then
        Utils.setFuel(entityId, 100.0)
    else
        FreezeEntityPosition(entityId, true)
    end

    local entityState = {
        key = meta.key,
        index = meta.index,
        model = meta.model,
        coords = entitySpawnCoords,
        netId = entityNetId,
        spawned = true,
    }

    client.currentTask.game.taskEntities[meta.key][meta.index] = entityState

    self:remove()
    state.fieldPoints["entity_" .. meta.key .. "_" .. meta.index] = nil

    lib.callback.await(_e("server:freelance:onVehicleSpawned"),
        false, client.lobby.id, entityState)
end

--- Get nearby planting points within a specified distance
--- @param maxDistance number
--- @return table -- Array of nearby planting points
local function getNearbyPlantingPoints(maxDistance)
    if not maxDistance or maxDistance <= 0 then
        maxDistance = 15.0
    end

    local playerCoords = GetEntityCoords(cache.ped)
    local nearbyPoints = {}

    if not client.currentTask or not client.currentTask.game.plantingPoints then
        return nearbyPoints
    end

    for index, point in pairs(client.currentTask.game.plantingPoints) do
        local distance = #(playerCoords - point.coords)
        if distance <= maxDistance and
            point.state ~= POINT_STATES.HARVESTED
        then
            if not state.pointGroundZValues[index] then
                local groundZ, response = Utils.getGroundZ(point.coords)
                if response then
                    state.pointGroundZValues[index] = response and groundZ or point.coords.z
                end
            end
            nearbyPoints[index] = {
                coords = vector3(point.coords.x, point.coords.y, state.pointGroundZValues[index]),
                index = index,
                state = point.state,
                distance = distance,
            }
        end
    end

    return nearbyPoints
end

--- Spawn a point object at the specified coordinates (Network Entity)
--- @param name string
--- @param state table
--- @param coords vector3
--- @param pointIndex number
--- @return number|nil -- The spawned object network ID
local function spawnPointObject(name, state, coords, pointIndex, lobbyId)
    local objectModel = config.crops[name] and config.crops[name].model or "prop_plant_01"
    lib.requestModel(objectModel)
    local pointObject = CreateObject(GetHashKey(objectModel), coords.x, coords.y, coords.z, true, true, false)

    if DoesEntityExist(pointObject) then
        NetworkRegisterEntityAsNetworked(pointObject)
        FreezeEntityPosition(pointObject, true)
        SetModelAsNoLongerNeeded(objectModel)
        SetEntityCollision(pointObject, false, false)
        SetEntityCompletelyDisableCollision(pointObject, false, false)

        -- NetworkId'yi sunucuya gönder
        local netId = lib.waitFor(function()
            if NetworkGetEntityIsNetworked(pointObject) then
                local networkId = ObjToNet(pointObject)
                if NetworkDoesNetworkIdExist(networkId) then
                    return networkId
                end
            end
        end, false, false)

        if netId then
            lib.callback.await(_e("server:freelance:registerPointObject"), false, {
                lobbyId = lobbyId or client.lobby.id,
                pointIndex = pointIndex,
                networkId = netId,
                cropName = name,
                pointState = state
            })
            return netId
        end
    end
    return nil
end

--- Detect the type of vehicle the player is currently in
--- @param vehicle number
--- @return string|nil, table|nil -- Returns vehicle type and its data if found
local function detectPlayerVehicleType(vehicle)
    if not vehicle then return nil, nil end

    local vehicleModel = GetEntityModel(vehicle)

    for vehicleType, vehicleData in pairs(FARMING_VEHICLES) do
        local field = getFieldById(client.currentTask.game.fieldId)
        if field and field[vehicleType] and field[vehicleType].model then
            local modelHash = type(field[vehicleType].model) == "string" and
                GetHashKey(field[vehicleType].model) or
                field[vehicleType].model
            if vehicleModel == modelHash then
                return vehicleType, vehicleData
            end
        end
    end

    return nil, nil
end

--- Calculate the ground offset for a model
--- @param model string|number
--- @return number -- Returns the ground offset for the model
local function calculateModelGroundOffset(model)
    if not model then return 0.0 end

    local modelHash = type(model) == "string" and GetHashKey(model) or model
    if not IsModelValid(modelHash) then return 0.0 end

    local minDim, maxDim = GetModelDimensions(modelHash)
    local modelHeight = maxDim.z - minDim.z
    local modelBottomOffset = math.abs(modelHeight)

    return modelBottomOffset
end

--- Start carrying animation and attach the prop to the player
local function startCarryingAnimation()
    local playerPed = cache.ped

    lib.requestAnimDict("anim@heists@box_carry@")

    TaskPlayAnim(playerPed, "anim@heists@box_carry@", "idle", 8.0, 8.0, -1, 50, 0, false, false, false)

    if state.carryingState.carryingProp and DoesEntityExist(state.carryingState.carryingProp) then
        AttachEntityToEntity(state.carryingState.carryingProp, playerPed,
            GetPedBoneIndex(playerPed, 28422),
            0.0, -0.5, -0.2, 0.0, 0.0, 0.0,
            true, true, false, true, 1, true)
    end
end

--- Stop carrying animation and detach the prop
local function stopCarryingAnimation()
    local playerPed = cache.ped

    ClearPedTasks(playerPed)

    if state.carryingState.carryingProp and DoesEntityExist(state.carryingState.carryingProp) then
        DetachEntity(state.carryingState.carryingProp, true, false)
        DeleteEntity(state.carryingState.carryingProp)
    end

    state.carryingState.isCarrying = false
    state.carryingState.carryingProp = nil
end

--- Load a harvested bale to the trailer vehicle
--- @param pointIndex number
--- @param trailerVehicle number
local function loadHarvestedBaleToTrailer(pointIndex, trailerVehicleNetId)
    if not state.carryingState.isCarrying then
        return
    end

    local trailerVehicle = NetToVeh(trailerVehicleNetId)

    local trailerCoords = GetEntityCoords(trailerVehicle)
    local playerCoords = GetEntityCoords(cache.ped)
    local distance = #(trailerCoords - playerCoords)

    if distance > 5.0 then
        return
    end

    if client.currentTask.game.harvesterState.harvestedBaleState.loadedCount > 5 then
        Utils.notify(locale("freelance.trailer_full"), "error")
        return
    end

    stopCarryingAnimation()

    TriggerServerEvent(_e("server:freelance:loadHarvestedBaleToTrailer"), {
        lobbyId = client.lobby.id,
        pointIndex = pointIndex,
        trailerNetId = trailerVehicleNetId,
    })

    Utils.notify(locale("freelance.harvested_bale_loaded"), "success")
end

--- @param pointIndex number
--- @param propModel string
local function pickupHarvestedBaleObject(pointIndex, propModel)
    if state.carryingState.isCarrying then
        Utils.notify(locale("freelance.already_carrying"), "error")
        return
    end

    Target.removeZone("pickup_harvested_bale_" .. pointIndex)

    local pointObjectCoords = GetEntityCoords(cache.ped)
    local pointObjectNetId = state.pointObjectNetIds[pointIndex]
    if pointObjectNetId then
        local pointObject = NetToObj(pointObjectNetId)
        if pointObject and DoesEntityExist(pointObject) then
            pointObjectCoords = GetEntityCoords(pointObject)
        end
    end

    local harvestedBaleModel = propModel or "prop_haybale_03"
    lib.requestModel(harvestedBaleModel)
    local networkedObject = CreateObject(GetHashKey(harvestedBaleModel),
        pointObjectCoords.x, pointObjectCoords.y, pointObjectCoords.z,
        true, true, false)

    state.carryingState.isCarrying = true
    state.carryingState.carryingProp = networkedObject

    SetModelAsNoLongerNeeded(harvestedBaleModel)

    startCarryingAnimation()

    TriggerServerEvent(_e("server:freelance:onHarvestedBalePickedUp"), {
        lobbyId = client.lobby.id,
        pointIndex = pointIndex,
    })

    Utils.notify(locale("freelance.harvested_bale_picked_up"), "success")

    state.pointObjectNetIds[pointIndex] = nil

    Citizen.CreateThread(function()
        local pointIndex = pointIndex

        while state.carryingState.isCarrying do
            local waitMsec = 500
            local playerCoords = GetEntityCoords(cache.ped)
            local trailerVehicleNetId = nil

            if not trailerVehicleNetId and
                client.currentTask.game.taskEntities["trailer"]
            then
                local nearestTrailer = nil
                local nearestDistance = math.huge
                local playerCoords = GetEntityCoords(cache.ped)

                -- Find the nearest spawned trailer
                for index, trailerData in pairs(client.currentTask.game.taskEntities["trailer"]) do
                    if trailerData.spawned and trailerData.netId then
                        local trailer = NetToVeh(trailerData.netId)
                        if trailer and DoesEntityExist(trailer) then
                            local trailerCoords = GetEntityCoords(trailer)
                            local distance = #(playerCoords - trailerCoords)

                            if distance < nearestDistance then
                                nearestDistance = distance
                                nearestTrailer = trailerData.netId
                            end
                        end
                    end
                end

                trailerVehicleNetId = nearestTrailer
            end

            if trailerVehicleNetId then
                local trailerVehicle = NetToVeh(trailerVehicleNetId)
                if trailerVehicle and DoesEntityExist(trailerVehicle) then
                    local trailerVehicleCoords = GetEntityCoords(trailerVehicle)

                    local minDim, maxDim       = GetModelDimensions(GetEntityModel(trailerVehicle))
                    local trailerLength        = maxDim.y - minDim.y

                    local trailerFront         = GetOffsetFromEntityInWorldCoords(trailerVehicle,
                        0.0,
                        trailerLength / 2,
                        0.0)
                    local trailerBack          = GetOffsetFromEntityInWorldCoords(trailerVehicle,
                        0.0,
                        -trailerLength / 2,
                        0.0)

                    local trailerCenter        = GetEntityCoords(trailerVehicle)

                    local distFront            = #(playerCoords - trailerFront)
                    local distBack             = #(playerCoords - trailerBack)
                    local distCenter           = #(playerCoords - trailerCenter)

                    if distFront <= 2.5 or distBack <= 2.5 or distCenter <= 2.5 then
                        loadHarvestedBaleToTrailer(pointIndex, trailerVehicleNetId)
                        Citizen.Wait(1000)
                    end
                end
            end

            Citizen.Wait(waitMsec)
        end
    end)
end

--- Setup harvested bale target for the prop
--- @param prop number
--- @param pointIndex number
--- @param propModel string
local function setupHarvestedBaleTargetBox(centerCoords, pointIndex, propModel)
    local zoneKey = "pickup_harvested_bale_" .. pointIndex
    Target.addBoxZone(zoneKey, {
        coords = centerCoords,
        name = zoneKey,
        size = vector3(1.7, 2.1, 2.0),
        debug = false,
        options = {
            {
                label = locale("freelance.pickup_harvested_bale"),
                icon = "fas fa-hand-paper",
                distance = 2.0,
                canInteract = function()
                    return not state.carryingState.isCarrying
                end,
                onSelect = function()
                    pickupHarvestedBaleObject(pointIndex, propModel)
                end,
            }
        }
    })
end

--- Handle the state change of a planting point
--- @param index number
--- @param newState string
local function onPlantingPointStateChanged(index, newState)
    local plantingPoint = client.currentTask.game.plantingPoints[index]

    plantingPoint.state = newState

    local newStateBlipColorId = 0

    local pointCropName = plantingPoint.cropName

    if newState == POINT_STATES.PLANTED then
        newStateBlipColorId = 5

        local cropModel = config.crops[pointCropName] and config.crops[pointCropName].model or "prop_plant_01"
        local modelGroundOffset = calculateModelGroundOffset(cropModel)

        local normalizedCoords = vector3(
            plantingPoint.coords.x,
            plantingPoint.coords.y,
            (state.pointGroundZValues[index] or plantingPoint.coords.z) - (modelGroundOffset / 1.5))

        if cropModel == "prop_veg_crop_rose" or
            cropModel == "prop_veg_crop_green" or
            cropModel == "prop_veg_crop_daisy" or
            cropModel == "prop_veg_crop_poppy"
        then
            -- # Rose, Green, Daisy, Poppy
            normalizedCoords = vector3(
                normalizedCoords.x,
                normalizedCoords.y,
                normalizedCoords.z + .02)
        end

        local pointObjectNetId = spawnPointObject(pointCropName, newState, normalizedCoords, index)
        if pointObjectNetId then
            state.pointObjectNetIds[index] = pointObjectNetId
        end
    elseif newState == POINT_STATES.WATERED then
        newStateBlipColorId = 29
        local pointObjectNetId = state.pointObjectNetIds[index]
        if pointObjectNetId then
            local pointObject = NetToObj(pointObjectNetId)
            if pointObject and DoesEntityExist(pointObject) then
                local pointObjectCoords = GetEntityCoords(pointObject)
                SetEntityCoords(pointObject, pointObjectCoords.x, pointObjectCoords.y, pointObjectCoords.z + 0.2)
            end
        end
    elseif newState == POINT_STATES.GROWN then
        newStateBlipColorId = 2
    elseif newState == POINT_STATES.HARVESTED then
        newStateBlipColorId = 17
        state.nearbyPoints[index] = nil
    end

    local pointBlip = state.fieldBlips["point_" .. index]
    if pointBlip then
        SetBlipColour(pointBlip, newStateBlipColorId)
    end

    TriggerServerEvent(_e("server:freelance:onPlantingPointStateChanged"), {
        lobbyId = client.lobby.id,
        pointIndex = index,
        newState = newState,
        cropName = pointCropName,
    })
end

--- Process the vehicle planting point
--- @param index number
--- @param newState string
--- @param vehicleType string
local function processVehiclePlantingPoint(index, newState, vehicleType)
    if not index or not newState or not vehicleType then
        return false
    end

    -- Duplicate check
    if state.vehicleFarmingOperation.lastProcessedPoints[index] then
        local lastProcessTime = state.vehicleFarmingOperation.lastProcessedPoints[index]
        if GetGameTimer() - lastProcessTime < 2000 then
            return false
        end
    end

    if vehicleType == "tractor" and newState == POINT_STATES.PLANTED then
        local cropName = state.vehicleFarmingOperation.selectedCropName
        if not cropName then return false, 2000 end
        local cropData = config.crops[cropName]
        if not cropData then return false, 2000 end

        if not hasRequiredItem(cropData.seedItem) then
            Utils.notify(locale("freelance.insufficient_seeds_for_tractor", cropData.label), "error")
            return false, 2000
        end

        if not removeItem(cropData.seedItem, 1) then
            Utils.notify(locale("freelance.failed_to_remove_item"), "error")
            return false, 2000
        end

        client.currentTask.game.plantingPoints[index].cropName = cropName
    end

    onPlantingPointStateChanged(index, newState)

    local actionText = FARMING_VEHICLES[vehicleType] and FARMING_VEHICLES[vehicleType].action or "farming"
    local notificationMessage = locale("freelance.point_processed", index, actionText)

    Utils.notify(notificationMessage, "success", 1500)

    return true
end

--- Handle grain unloading started event
local function onGrainUnloadingStarted()
    lib.callback.await(_e("server:freelance:onGrainUnloadingStarted"),
        false, client.lobby.id)
end

--- Handle grain unloading stopped event
local function onGrainUnloadingStopped()
    lib.callback.await(_e("server:freelance:onGrainUnloadingStopped"),
        false, client.lobby.id)
end

--- Handle plant growth and watering
local function handlePlantGrowth()
    if client.lobby.owner ~= cache.serverId then
        return
    end

    for index, point in pairs(client.currentTask.game.plantingPoints) do
        if point.state == POINT_STATES.WATERED then
            if not state.pointWaterTimes[index] then
                state.pointWaterTimes[index] = GetGameTimer()
            end

            local plantedCropName = point.cropName
            local growthTime = 60 -- Default 60 seconds

            if plantedCropName and config.crops[plantedCropName] then
                growthTime = config.crops[plantedCropName].growthTime
            end

            local waterTime = GetGameTimer() - state.pointWaterTimes[index]
            local growthTimeMs = growthTime * 1000

            if waterTime >= growthTimeMs then
                onPlantingPointStateChanged(index, POINT_STATES.GROWN)
                state.pointWaterTimes[index] = nil
            end
        end
    end

    if state.pointWaterTimes then
        for index, _ in pairs(state.pointWaterTimes) do
            local point = client.currentTask.game.plantingPoints[index]
            if point.state ~= POINT_STATES.WATERED then
                state.pointWaterTimes[index] = nil
            end
        end
    end
end

--- Handle vehicle farming operations
local function handleVehicleFarming()
    local playerPed = cache.ped
    local playerVehicle = cache.vehicle

    if not playerVehicle then
        if state.vehicleFarmingOperation.isWorking then
            client.sendReactMessage("ui:setInfoBox", { inHarvester = false })
            Utils.notify(locale("freelance.farming_stopped"), "info")

            if state.vehicleFarmingOperation.currentVehicleType == "harvester" then
                if state.vehicleFarmingOperation.unloadingParticle then
                    StopParticleFxLooped(state.vehicleFarmingOperation.unloadingParticle, false)
                    state.vehicleFarmingOperation.unloadingParticle = nil
                end
                if DoesEntityExist(state.vehicleFarmingOperation.lastVehicle) then
                    SetVehicleDoorShut(state.vehicleFarmingOperation.lastVehicle, 4, false)
                end
            end

            state.vehicleFarmingOperation.isWorking = false
            state.vehicleFarmingOperation.currentVehicleType = nil

            return false, 2000
        end
        return false
    end

    local vehicleType, vehicleData = detectPlayerVehicleType(playerVehicle)
    if not vehicleType or not vehicleData then
        return false, 2000
    end

    if state.vehicleFarmingOperation.currentVehicleType ~= vehicleType then
        state.vehicleFarmingOperation.isWorking = true
        state.vehicleFarmingOperation.currentVehicleType = vehicleType
        state.vehicleFarmingOperation.lastVehicle = playerVehicle

        Utils.notify(locale("freelance.farming_started", vehicleData.action), "info")

        client.sendReactMessage("ui:setInfoBox", { inHarvester = vehicleType == "harvester" })

        if vehicleType == "harvester" then
            state.vehicleFarmingOperation.grainUnloading = false
            state.vehicleFarmingOperation.unloadingParticle = nil
        end
    end

    if vehicleType == "harvester" then
        local currentGrainLevel = client.currentTask.game.harvesterState.grainLevel or 0
        local vehicleSpeed = GetEntitySpeed(playerVehicle) * 3.6 -- m/s to km/h
        local isMoving = vehicleSpeed > 2.0

        local nearestTrailer = nil
        local nearestDistance = math.huge

        if client.currentTask.game.taskEntities["trailer"] then
            local vehicleCoords = GetEntityBonePosition_2(playerVehicle,
                GetEntityBoneIndexByName(playerVehicle, "bonnet"))

            for index, trailerData in pairs(client.currentTask.game.taskEntities["trailer"]) do
                if trailerData.spawned and trailerData.netId then
                    local trailer = NetToVeh(trailerData.netId)
                    if trailer and DoesEntityExist(trailer) then
                        local trailerCoords = GetOffsetFromEntityInWorldCoords(trailer, 0.0, -3.0, 0.0)
                        local distance = #(vehicleCoords - trailerCoords)

                        if distance < nearestDistance then
                            nearestDistance = distance
                            nearestTrailer = trailer
                        end
                    end
                end
            end
        end

        if nearestTrailer and nearestDistance < 15.0 then
            if currentGrainLevel > 0 and
                not state.vehicleFarmingOperation.harvesterDoorIsOpen
            then
                SetVehicleDoorOpen(playerVehicle, 4, false, false)
                state.vehicleFarmingOperation.harvesterDoorIsOpen = true
            end
        elseif state.vehicleFarmingOperation.harvesterDoorIsOpen then
            SetVehicleDoorShut(playerVehicle, 4, false)
            state.vehicleFarmingOperation.harvesterDoorIsOpen = false
        end

        if nearestTrailer and nearestDistance <= 10.0 and currentGrainLevel > 0 then
            if not state.vehicleFarmingOperation.grainUnloading and not isMoving then
                state.vehicleFarmingOperation.grainUnloading = true
                SetVehicleDoorOpen(playerVehicle, 4, false, false)

                -- # TODO: Implement unloading particle effect
                if false and not state.vehicleFarmingOperation.unloadingParticle then
                    local particleCoords = GetEntityBonePosition_2(playerVehicle,
                        GetEntityBoneIndexByName(playerVehicle, "bonnet"))

                    lib.requestNamedPtfxAsset("core")
                    UseParticleFxAssetNextCall("core")
                    state.vehicleFarmingOperation.unloadingParticle = StartParticleFxLoopedAtCoord(
                        "ent_amb_sprinkler_crop",
                        particleCoords.x, particleCoords.y, particleCoords.z,
                        0.0, 0.0, 90.0,
                        1.0, false, false, false
                    )
                    RemoveNamedPtfxAsset("core")
                end

                onGrainUnloadingStarted()

                Utils.notify(locale("freelance.grain_unloading_started"), "info")
            elseif isMoving and state.vehicleFarmingOperation.grainUnloading then
                state.vehicleFarmingOperation.grainUnloading = false
                SetVehicleDoorShut(playerVehicle, 4, false)

                if state.vehicleFarmingOperation.unloadingParticle then
                    StopParticleFxLooped(state.vehicleFarmingOperation.unloadingParticle, false)
                    state.vehicleFarmingOperation.unloadingParticle = nil
                end

                onGrainUnloadingStopped()

                Utils.notify(locale("freelance.grain_unloading_stopped"), "warning")
            end
        elseif state.vehicleFarmingOperation.grainUnloading and (not nearestTrailer or nearestDistance > 10.0) then
            state.vehicleFarmingOperation.grainUnloading = false

            if state.vehicleFarmingOperation.unloadingParticle then
                StopParticleFxLooped(state.vehicleFarmingOperation.unloadingParticle, false)
                state.vehicleFarmingOperation.unloadingParticle = nil
            end

            onGrainUnloadingStopped()

            Utils.notify(locale("freelance.grain_unloading_stopped"), "warning")
        end

        if state.vehicleFarmingOperation.grainUnloading and currentGrainLevel <= 0 then
            state.vehicleFarmingOperation.grainUnloading = false
            SetVehicleDoorShut(playerVehicle, 4, false)

            if state.vehicleFarmingOperation.unloadingParticle then
                StopParticleFxLooped(state.vehicleFarmingOperation.unloadingParticle, false)
                state.vehicleFarmingOperation.unloadingParticle = nil
            end

            onGrainUnloadingStopped()

            Utils.notify(locale("freelance.grain_unloading_completed"), "success")
        end

        if state.vehicleFarmingOperation.lastGrainUpdateTime == 0 or
            GetGameTimer() - state.vehicleFarmingOperation.lastGrainUpdateTime > 2000
        then
            state.vehicleFarmingOperation.lastGrainUpdateTime = GetGameTimer()

            TriggerServerEvent(_e("server:freelance:fetchGrainLevel"), { lobbyId = client.lobby.id })
        end
    end

    local hasTrailer = IsVehicleAttachedToTrailer(playerVehicle)
    local hasHarvestTrailer = false
    local hasAttachedSeeder = false
    local attachedSeederObject = nil

    -- Check for attached seeder
    if client.currentTask.game.taskEntities["seeder"] then
        for index, seederData in pairs(client.currentTask.game.taskEntities["seeder"]) do
            if seederData.spawned and seederData.netId then
                local NetToConverter = IsModelAVehicle(seederData.model) and NetToVeh or NetToObj
                local seederEntity = NetToConverter(seederData.netId)
                if DoesEntityExist(seederEntity) and IsEntityAttached(seederEntity) then
                    hasAttachedSeeder = true
                    attachedSeederObject = seederEntity
                    break
                end
            end
        end

        if hasAttachedSeeder then
            if not state.vehicleFarmingOperation.selectedCropName and
                client.lobby.owner == cache.serverId
            then
                local selectedCrop = showCropSelectionDialog()
                if not selectedCrop then
                    local cropKey, _ = next(config.crops)
                    selectedCrop = cropKey
                end

                state.vehicleFarmingOperation.selectedCropName = selectedCrop

                Utils.notify(locale("freelance.crop_selected_for_tractor", config.crops[selectedCrop].label),
                    "success"
                )
                TriggerServerEvent(_e("server:freelance:onSeederCropSelected"), {
                    lobbyId = client.lobby.id,
                    cropName = selectedCrop,
                })
            end
        end

        if not hasAttachedSeeder then
            local nearestSeeder = nil
            local nearestDistance = math.huge
            local vehicleCoords = GetEntityCoords(playerVehicle)

            for index, seederData in pairs(client.currentTask.game.taskEntities["seeder"]) do
                if seederData.spawned and seederData.netId then
                    local NetToConverter = IsModelAVehicle(seederData.model) and NetToVeh or NetToObj
                    local seederObject = NetToConverter(seederData.netId)

                    if DoesEntityExist(seederObject) and not IsEntityAttached(seederObject) then
                        local seederCoords = GetEntityCoords(seederObject)
                        local distance = #(vehicleCoords - seederCoords)

                        if distance < nearestDistance then
                            nearestDistance = distance
                            nearestSeeder = seederObject
                        end
                    end
                end
            end

            if nearestSeeder and nearestDistance < 5.0 then
                AttachEntityToEntity(nearestSeeder, playerVehicle, 0, 0.0, -3.75, -0.4,
                    0.0, 0.0, 0.0,
                    false, false, false, false, 20, true)
                Utils.notify(locale("freelance.seeder_attached"), "success")
                return true, 2000
            end
        end
    end

    if vehicleType == "tractor" then
        -- Handle harvest trailer functionality
        if hasTrailer then
            local _, attachedTrailer = GetVehicleTrailerVehicle(playerVehicle)
            if attachedTrailer and attachedTrailer ~= 0 and DoesEntityExist(attachedTrailer) then
                local trailerModel = GetEntityModel(attachedTrailer)
                local field = getFieldById(client.currentTask.game.fieldId)
                local harvestTrailerModel = field.trailer and GetHashKey(field.trailer.model)

                if harvestTrailerModel and trailerModel == harvestTrailerModel then
                    hasHarvestTrailer = true

                    local targetCoords = field.dropHarvestedBaleCoords
                    local vehicleCoords = GetEntityCoords(playerVehicle)
                    local distanceToTarget = #(vehicleCoords - targetCoords)

                    if distanceToTarget < 25.0 then
                        DrawMarker(1, targetCoords.x, targetCoords.y, targetCoords.z - 1.0,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            2.5, 2.5, 2.0,
                            255, 255, 255, 150,
                            false, true, 2, false, nil, nil, false)

                        if distanceToTarget < 5.0 then
                            if not state.showTextUI then
                                Utils.showTextUI(locale("freelance.drop_harvested_bale"))
                                state.showTextUI = true
                            end
                            if IsControlJustPressed(0, 38) then -- E key
                                local response = lib.callback.await(_e("server:freelance:dropHarvestedBale"), false, {
                                    lobbyId = client.lobby.id,
                                })
                                if response then
                                    if type(response) == "table" and response.error then
                                        Utils.notify(response.error, "error")
                                    end
                                else
                                    Utils.notify(locale("freelance.harvested_bale_drop_failed"), "error")
                                end
                                if state.showTextUI then
                                    Utils.hideTextUI()
                                    state.showTextUI = false
                                end
                                return true, 1000
                            end
                        else
                            if state.showTextUI then
                                Utils.hideTextUI()
                                state.showTextUI = false
                            end
                        end
                        return false, 0
                    end
                    return false, 1000
                end
            end
        end

        -- Show seeder warning only if no seeder attached and no harvest trailer
        if not hasAttachedSeeder and not hasHarvestTrailer then
            if state.vehicleFarmingOperation.isWorking then
                Utils.notify(locale("freelance.tractor_needs_seeder_for_planting"), "error")
            end
            return false, 3000
        end
    end

    -- Check vehicle speed
    local vehicleSpeed = GetEntitySpeed(playerVehicle) * 3.6 -- m/s to km/h
    if vehicleSpeed < 5.0 then                               -- minimum speed threshold
        return false, 500
    end

    -- Check if the vehicle is exceeding the maximum speed
    if vehicleData.maxSpeed and vehicleSpeed > vehicleData.maxSpeed + 5.0 then
        if not state.latestSpeedWarningTime or
            (GetGameTimer() - state.latestSpeedWarningTime) > 2000
        then
            state.latestSpeedWarningTime = GetGameTimer()
            Utils.notify(locale("freelance.too_fast", vehicleData.maxSpeed), "error", 2000)
        end
        return false, 500
    end

    -- Get working coordinates based on vehicle type
    local offsetProcessCoords = GetEntityCoords(playerVehicle)
    if vehicleType == "tractor" then
        if hasAttachedSeeder then
            offsetProcessCoords = GetEntityCoords(attachedSeederObject)
        end
    elseif vehicleType == "harvester" then
        offsetProcessCoords = GetOffsetFromEntityInWorldCoords(playerVehicle, 0.0, 2.0, 0.0)
    end

    local workablePoints = {}
    for index, point in pairs(state.nearbyPoints) do
        local distance = #(offsetProcessCoords - point.coords)
        if distance <= vehicleData.workRadius then
            if canProcessPoint(index, vehicleData.requiredState) then
                workablePoints[index] = point
            end
        end
    end

    for index, point in pairs(workablePoints) do
        local response, extraWait = processVehiclePlantingPoint(index, vehicleData.targetState, vehicleType)
        if not response then
            return false, extraWait
        end
    end

    return next(workablePoints) ~= nil
end

--- Handle manual farming operations
local function handleManualFarming()
    local playerPed = cache.ped
    if cache.vehicle then
        return false
    end

    local nearbyPoints = getNearbyPlantingPoints(5.0)
    if not next(nearbyPoints) then
        if state.showTextUI then
            Utils.hideTextUI()
            state.showTextUI = false
        end
        return false
    end

    local closestPoint = nil
    local closestDistance = math.huge
    local bestTool = nil

    for index, nearbyPoint in pairs(nearbyPoints) do
        local plantingPoint = client.currentTask.game.plantingPoints[index]
        local pointState = plantingPoint and plantingPoint.state or POINT_STATES.EMPTY

        for _, tool in pairs(MANUAL_FARMING_TOOLS) do
            local playerCoords = GetEntityCoords(cache.ped)
            local pointCoords = plantingPoint and plantingPoint.coords or vector3(0, 0, 0)
            local dx = math.abs(playerCoords.x - pointCoords.x)
            local dy = math.abs(playerCoords.y - pointCoords.y)
            local dz = math.abs(playerCoords.z - pointCoords.z)
            if pointState == tool.requiredState and dx < tool.workRadius and dy < tool.workRadius and dz < (tool.workRadius + 2.0) then
                local planarDistance = math.sqrt(dx * dx + dy * dy)
                if planarDistance < closestDistance then
                    closestDistance = planarDistance
                    closestPoint = nearbyPoint
                    bestTool = tool
                end
            end
        end
    end

    if closestPoint and bestTool then
        local actionText = locale("freelance.press_to_action", bestTool.actionText)
        if not state.showTextUI then
            Utils.showTextUI(actionText)
            state.showTextUI = true
        end

        if IsControlJustPressed(0, 38) then -- E key
            Utils.hideTextUI()
            state.showTextUI = false

            local selectedCrop = nil
            local progressLabel = "Processing point..."

            if bestTool.action == "watering" then
                if not hasRequiredItem(config.wateringCan.itemName, 1) then
                    Utils.notify(locale("freelance.no_watercan"), "error")
                    return false, 1000
                end
                progressLabel = locale("freelance.watering_plants")
            end

            Utils.progressBar({
                duration = bestTool.workTime,
                label = progressLabel,
                useWhileDead = false,
                canCancel = false,
                disable = {
                    car = true,
                    move = false,
                    combat = true
                },
                anim = bestTool.anim,
                prop = bestTool.prop,
            })

            onPlantingPointStateChanged(closestPoint.index, bestTool.targetState)

            if bestTool.action == "watering" then
                local wateredCount = 1  -- Ana nokta
                local waterRadius = 7.0 -- Sulama yarıçapı

                for index, point in pairs(client.currentTask.game.plantingPoints) do
                    if index ~= closestPoint.index then
                        local distance = #(closestPoint.coords - point.coords)
                        if distance <= waterRadius and point.state == POINT_STATES.PLANTED then
                            onPlantingPointStateChanged(index, POINT_STATES.WATERED)
                            wateredCount = wateredCount + 1
                        end
                    end
                end
                Utils.notify(locale("freelance.watering_success", wateredCount), "success")
            end

            local successMessage = locale("freelance.point_processed", closestPoint.index, bestTool.action)
            Utils.notify(successMessage, "success")

            return true, 1000
        end

        return true, 0
    else
        if state.showTextUI then
            Utils.hideTextUI()
            state.showTextUI = false
        end
    end
    return false, 1000
end

--- Worker thread for FreelanceClient
--- This function handles the main logic for farming tasks, including rendering, farming mechanics, and state synchronization.
function FreelanceClient.threadWorker()
    Citizen.CreateThread(function()
        local lastUpdate = GetGameTimer()
        local maxDistance = 25.0
        state.nearbyPoints = getNearbyPlantingPoints(maxDistance)

        while client.currentTask do
            local wait = 1000

            if next(state.nearbyPoints) then
                for _, point in pairs(state.nearbyPoints) do
                    drawPlantingPoint(point)
                end
                wait = 1
            end

            if GetGameTimer() - lastUpdate > 1000 then
                nearbyPoints = getNearbyPlantingPoints(maxDistance)
                lastUpdate = GetGameTimer()
                state.nearbyPoints = nearbyPoints
            end

            Citizen.Wait(wait)
        end
    end)

    -- Farming mechanics thread
    Citizen.CreateThread(function()
        while client.currentTask do
            local wait = 1000

            local isVehFarmingWorking, vehicleExtraWait = handleVehicleFarming()
            local isManualFarmingWorking, manualExtraWait = handleManualFarming()

            if isVehFarmingWorking then
                wait = 100
            elseif isManualFarmingWorking then
                wait = 0
            end

            if vehicleExtraWait and manualExtraWait then
                wait = math.max(vehicleExtraWait, manualExtraWait)
            elseif vehicleExtraWait then
                wait = vehicleExtraWait
            elseif manualExtraWait then
                wait = manualExtraWait
            end

            Citizen.Wait(wait)
        end
    end)

    -- State sync thread
    Citizen.CreateThread(function()
        local wait = 1000 * (Config.debug and 5 or 30)

        while client.lobby and client.currentTask do
            handlePlantGrowth()
            Citizen.Wait(wait)
        end
    end)
end

--- Initialize the FreelanceClient state
function FreelanceClient.clear()
    shared.debug("debug:FreelanceClient.clear")

    if state.showTextUI then
        Utils.hideTextUI()
    end

    if state.vehicleFarmingOperation and state.vehicleFarmingOperation.unloadingParticle then
        StopParticleFxLooped(state.vehicleFarmingOperation.unloadingParticle, false)
    end

    for _, blip in pairs(state.fieldBlips) do
        RemoveBlip(blip)
    end

    for _, points in pairs(state.fieldPoints) do
        if points.harvester then
            points.harvester:remove()
        end
        if points.tractor then
            points.tractor:remove()
        end
        if points.trailer then
            points.trailer:remove()
        end
        if points.seeder then
            points.seeder:remove()
        end
    end

    if state.carryingState.carryingProp and DoesEntityExist(state.carryingState.carryingProp) then
        DetachEntity(state.carryingState.carryingProp, true, false)
        DeleteEntity(state.carryingState.carryingProp)
    end

    __init__()
    shared.debug("debug:FreelanceClient.clear: State cleared")
end

--- Start FreelanceClient state
function FreelanceClient.start()
    shared.debug("debug:FreelanceClient.start",
        ("lobby: %s, field: %s"):format(client.lobby and client.lobby.id or "nil",
            client.currentTask and client.currentTask.game.fieldId or "nil"))

    local field = getFieldById(client.currentTask.game.fieldId)
    if not field then
        shared.debug(("Freelance start error: Field not found for ID %s"):format(client.currentTask.game.fieldId),
            "error")
        return false
    end

    -- Clear previous state
    __init__()

    state.fieldBlips.center = Utils.addBlip(field.center, config.blips.field, true)
    state.fieldBlips.radius = Utils.addRadiusBlip(field.center, field.radius, config.blips.field)
    state.fieldBlips.dropHarvestedBale = Utils.addBlip(field.dropHarvestedBaleCoords, config.blips.dropHarvestedBale)

    for index, plantingPoint in pairs(client.currentTask.game.plantingPoints) do
        state.fieldBlips["point_" .. index] = Utils.addBlip(plantingPoint.coords, config.blips.point)
    end

    shared.debug(("debug:FreelanceClient.start: Field blips created for ID %s"):format(client.currentTask.game.fieldId))

    if client.lobby.owner == cache.serverId then
        for _, entityKey in pairs({ "tractor", "harvester", "trailer", "seeder" }) do
            local locations = field[entityKey].locations
            -- local spawnCount = #client.lobby.members > 2 and 2 or 1
            local spawnCount = 1

            for i = 1, math.min(spawnCount, #locations) do
                local pointCoords = locations[i]
                local point = lib.points.new({
                    coords = pointCoords,
                    distance = 50.0,
                    meta = {
                        key = entityKey,
                        model = field[entityKey].model,
                        coords = pointCoords,
                        index = i,
                    },
                    onEnter = onEnterSpawnTaskEntityPoint,
                })
                state.fieldPoints["entity_" .. entityKey .. "_" .. i] = point
                state.fieldBlips["entity_" .. entityKey .. "_" .. i] =
                    Utils.addBlip(pointCoords, config.blips[entityKey], true)
            end
        end
        shared.debug(("debug:FreelanceClient.start: Field vehicle points created for ID: %s")
            :format(client.currentTask.game.fieldId))
    end

    if not Config.DisableCustomProps then
        lib.requestStreamedTextureDict(RES_MARKERS_YTD)
    end

    FreelanceClient.threadWorker()

    Utils.notify(locale("tasks.started"), "success")

    return true
end

--- Stop the FreelanceClient and clear the state
function FreelanceClient.stop()
    shared.debug("debug:FreelanceClient.stop", ("lobby: %s, field: %s"):format(
        client.lobby and client.lobby.id or "nil",
        client.currentTask and client.currentTask.game.fieldId or "nil"
    ))

    FreelanceClient.clear()

    if not Config.DisableCustomProps then
        SetStreamedTextureDictAsNoLongerNeeded(RES_MARKERS_YTD)
    end

    return true
end

--[[ Event Handlers ]]

RegisterNetEvent(_e("client:freelance:onVehicleSpawned"), function(entityState)
    if not entityState or not entityState.key or not entityState.index then
        shared.debug("debug:FreelanceClient.onVehicleSpawned - Invalid entityState",
            ("entityState: %s"):format(json.encode(entityState)), "error")
        return false
    end

    client.currentTask.game.taskEntities[entityState.key][entityState.index] = entityState

    Citizen.CreateThread(function()
        local entity = lib.waitFor(function()
            if NetworkDoesEntityExistWithNetworkId(entityState.netId) then
                local ent = entityState.key == "seedMachine" and
                    NetToObj(entityState.netId) or
                    NetToVeh(entityState.netId)
                if DoesEntityExist(ent) then return ent end
            end
        end, false, false)

        if entityState.key ~= "seedMachine" then
            MultiplayerTasksClient.giveVehicleKey(GetVehicleNumberPlateText(entity), entity)
        end
    end)

    return true
end)

RegisterNetEvent(_e("client:freelance:onHarvestedBaleDropped"), function(data)
    if client.lobby and data.lobbyId == client.lobby.id then
        client.currentTask.game.harvesterState.harvestedBaleState.loadedCount = 0
        Utils.notify(locale("freelance.harvested_bale_dropped"), "success")
    end
end)

lib.callback.register(_e("client:freelance:spawnHarvestedBale"), function(data)
    if not data.lobbyId then return false end
    if not client.lobby or client.lobby.id ~= data.lobbyId then
        return false
    end

    local propModel = config.crops[data.cropName] and config.crops[data.cropName].harvestedBaleModel or nil
    lib.requestModel(propModel)

    local vehicle = cache.vehicle or GetEntityCoords(cache.ped)
    local zoneCoords = GetOffsetFromEntityInWorldCoords(vehicle, 2.5, -5.0, 0.0)
    local groundZ = Utils.getGroundZ(zoneCoords)

    local prop = CreateObject(propModel, zoneCoords.x, zoneCoords.y, groundZ, true, true)

    local propNetId = lib.waitFor(function()
        if not NetworkGetEntityIsNetworked(prop) then
            NetworkRegisterEntityAsNetworked(prop)
        else
            local netId = ObjToNet(prop)
            if NetworkDoesNetworkIdExist(netId) then
                return netId
            end
        end
    end, false, false)

    SetModelAsNoLongerNeeded(propModel)
    FreezeEntityPosition(prop, true)

    setupHarvestedBaleTargetBox(zoneCoords, data.pointIndex, propModel)

    if DoesEntityExist(prop) then
        return {
            netId = propNetId,
            coords = zoneCoords,
            pointIndex = data.pointIndex,
            model = propModel,
        }
    end

    return false
end)

RegisterNetEvent(_e("client:freelance:onPlantingPointUpdate"), function(data)
    if not data.lobbyId then return end
    if not client.lobby or client.lobby.id ~= data.lobbyId then
        return
    end

    local plantingPoint = client.currentTask.game.plantingPoints[data.pointIndex]

    if data.newState then
        plantingPoint.state = data.newState
    end
    if data.cropName then
        if not state.vehicleFarmingOperation.selectedCropName then
            state.vehicleFarmingOperation.selectedCropName = data.cropName
        end
        plantingPoint.cropName = data.cropName
    end

    if data.meta.grainLevel then
        client.currentTask.game.harvesterState.grainLevel = data.meta.grainLevel
        client.sendReactMessage("ui:setInfoBox", {
            grainLevel = data.meta.grainLevel,
        })
    end

    if data.playerId ~= cache.serverId then
        local newStateBlipColorId = 0
        local pointCropName = data.cropName

        if data.newState == POINT_STATES.PLANTED then
            newStateBlipColorId = 5
            if data.networkId then
                state.pointObjectNetIds[data.pointIndex] = data.networkId
            end
        elseif data.newState == POINT_STATES.WATERED then
            newStateBlipColorId = 29
        elseif data.newState == POINT_STATES.GROWN then
            newStateBlipColorId = 2
        elseif data.newState == POINT_STATES.HARVESTED then
            newStateBlipColorId = 17
            if state.fieldBlips["point_" .. data.pointIndex] then
                RemoveBlip(state.fieldBlips["point_" .. data.pointIndex])
                state.fieldBlips["point_" .. data.pointIndex] = nil
            end
            state.nearbyPoints[data.pointIndex] = nil
        end

        if data.meta then
            if data.meta.harvestedBale then
                local propModel = config.crops[data.cropName] and config.crops[data.cropName].harvestedBaleModel or nil
                setupHarvestedBaleTargetBox(data.meta.harvestedBale.coords, data.pointIndex, propModel)
            end
        end

        local pointBlip = state.fieldBlips["point_" .. data.pointIndex]
        if pointBlip then
            SetBlipColour(pointBlip, newStateBlipColorId)
        end
    end
end)

RegisterNetEvent(_e("client:freelance:onHarvestedBalePickedUp"), function(data)
    if not client.lobby or
        not client.currentTask or
        not data.lobbyId or
        client.lobby.id ~= data.lobbyId then
        return
    end

    local zoneKey = "pickup_harvested_bale_" .. data.pointIndex
    Target.removeZone(zoneKey)
end)

lib.callback.register(_e("client:freelance:attachHarvestedBaleToTrailer"), function(data)
    if not data or not data.trailerNetId then
        return nil
    end

    local trailer = NetToVeh(data.trailerNetId)
    if not DoesEntityExist(trailer) then
        return nil
    end

    local attachCoords = GetEntityCoords(trailer)
    local harvestedBaleModel = config.crops[data.cropName] and
        config.crops[data.cropName].harvestedBaleModel or "prop_haybale_03"
    lib.requestModel(harvestedBaleModel)
    local harvestedBale = CreateObject(GetHashKey(harvestedBaleModel),
        attachCoords.x, attachCoords.y, attachCoords.z + 1.0, true, true, false)

    if not DoesEntityExist(harvestedBale) then
        return nil
    end

    local harvestedBaleNetId = lib.waitFor(function()
        if not NetworkGetEntityIsNetworked(harvestedBale) then
            NetworkRegisterEntityAsNetworked(harvestedBale)
        else
            local netId = ObjToNet(harvestedBale)
            if NetworkDoesNetworkIdExist(netId) then
                return netId
            end
        end
    end, false, false)

    local attachIndex = (data.loadedCount - 1) % 5
    local offset = vector3(0.0, 1.5 - (attachIndex * 1.25), 0.55)

    AttachEntityToEntity(harvestedBale, trailer, nil,
        offset.x, offset.y, offset.z, 0.0, 0.0, 90.0,
        false, false, false, false, 2, true)

    FreezeEntityPosition(harvestedBale, true)
    SetModelAsNoLongerNeeded(harvestedBaleModel)

    return harvestedBaleNetId
end)

RegisterNetEvent(_e("client:freelance:onHarvestedBaleAttached"), function(data)
    if not client.lobby or
        not client.currentTask or
        not data.lobbyId or
        client.lobby.id ~= data.lobbyId then
        return
    end

    client.currentTask.game.harvesterState.harvestedBaleState.loadedCount = data.loadedCount
end)

RegisterNetEvent(_e("client:freelance:onGrainLevelChanged"), function(data)
    if not client.lobby or
        not client.currentTask or
        not data.lobbyId or
        client.lobby.id ~= data.lobbyId then
        return
    end

    client.currentTask.game.harvesterState.grainLevel = data.grainLevel

    client.sendReactMessage("ui:setInfoBox", {
        grainLevel = data.grainLevel,
    })
end)

RegisterNetEvent(_e("client:freelance:onSeederCropSelected"), function(data)
    if not client.lobby or
        not client.currentTask or
        not data.lobbyId or
        client.lobby.id ~= data.lobbyId then
        return
    end

    if not state.vehicleFarmingOperation.selectedCropName then
        state.vehicleFarmingOperation.selectedCropName = data.cropName
    end

    Utils.notify(locale("freelance.seeder_crop_selected", config.crops[data.cropName].label), "success")
end)

RegisterNetEvent(_e("client:freelance:playWateringEffect"), function(data)
    local pointObjectNetId = data.networkId
    local pointCropName = data.cropName

    if pointObjectNetId then
        local pointObject = NetToObj(pointObjectNetId)
        if pointObject and DoesEntityExist(pointObject) then
            local pointObjectCoords = GetEntityCoords(pointObject)
            SetEntityCoords(pointObject, pointObjectCoords.x, pointObjectCoords.y, pointObjectCoords.z + 0.2)
        end
    end
end)

RegisterNetEvent(_e("client:freelance:playGrowthEffect"), function(data)
    local pointObjectNetId = data.networkId
    local pointCropName = data.cropName
    if pointObjectNetId then
        local pointObject = NetToObj(pointObjectNetId)
        if pointObject and DoesEntityExist(pointObject) then
            TriggerServerEvent(_e("server:freelance:deletePointObject"), {
                lobbyId = client.lobby.id,
                pointIndex = data.pointIndex,
            })

            local getObjectCoords = GetEntityCoords(pointObject)
            local newPointObjectNetId = spawnPointObject(pointCropName, data.newState, getObjectCoords, data.pointIndex)
            if newPointObjectNetId then
                local newPointObject = NetToObj(newPointObjectNetId)
                if newPointObject and DoesEntityExist(newPointObject) then
                    PlaceObjectOnGroundOrObjectProperly(newPointObject)
                    local pointObjectCoords = GetEntityCoords(newPointObject)
                    local cropModel = config.crops[pointCropName] and config.crops[pointCropName].model or
                        "prop_plant_01"
                    if cropModel == "prop_veg_crop_rose" or
                        cropModel == "prop_veg_crop_green" or
                        cropModel == "prop_veg_crop_daisy" or
                        cropModel == "prop_veg_crop_poppy"
                    then
                        SetEntityCoords(newPointObject, pointObjectCoords.x, pointObjectCoords.y,
                            pointObjectCoords.z - 2.0)
                    else
                        SetEntityCoords(newPointObject, pointObjectCoords.x, pointObjectCoords.y,
                            pointObjectCoords.z - 0.1)
                    end
                    SetEntityRotation(newPointObject, 0.0, 0.0, 0.0, 2, true)
                end
                state.pointObjectNetIds[data.pointIndex] = newPointObjectNetId
            end
        end
    end
end)

if config.detachTrailerKey then
    lib.addKeybind({
        name = "farming_v2_detach_trailer",
        description = "Detach trailer/object from Tractor",
        defaultKey = config.detachTrailerKey,
        onPressed = function()
            if not client.lobby then return end
            if not client.currentTask then return end
            local vehicle = cache.vehicle
            if not vehicle then return end
            if VehToNet(vehicle) == 0 then return end

            local isCurrentVehicleTractor = false
            if client.currentTask.game.taskEntities.tractor then
                for index, tractorData in pairs(client.currentTask.game.taskEntities.tractor) do
                    if tractorData.spawned and tractorData.netId then
                        if tractorData.netId == VehToNet(vehicle) then
                            isCurrentVehicleTractor = true
                            break
                        end
                    end
                end
            end

            if not isCurrentVehicleTractor then
                return
            end

            local detached = false
            local detachedType = ""

            if IsVehicleAttachedToTrailer(vehicle) then
                DetachVehicleFromTrailer(vehicle)
                detached = true
                detachedType = "trailer"
            else
                local currentSeeder = nil
                if client.currentTask.game.taskEntities.seeder then
                    for index, seederData in pairs(client.currentTask.game.taskEntities.seeder) do
                        if seederData.spawned and seederData.netId then
                            currentSeeder = seederData
                            break
                        end
                    end
                end
                if currentSeeder and currentSeeder.spawned and currentSeeder.netId then
                    local seederObject = NetToObj(currentSeeder.netId)
                    if DoesEntityExist(seederObject) then
                        if IsEntityAttached(seederObject) then
                            DetachEntity(seederObject, true, false)
                            detached = true
                            detachedType = "seeder"
                        end
                    end
                end
            end

            if detached then
                if detachedType == "trailer" then
                    Utils.notify(locale("freelance.trailer_detached"), "success")
                elseif detachedType == "seeder" then
                    Utils.notify(locale("freelance.seeder_detached"), "success")
                end
            else
                Utils.notify(locale("freelance.nothing_to_detach"), "info")
            end
        end
    })
end

if Config.debug then
    RegisterCommand("debug_freelance", function()
        if not client.currentTask or not client.currentTask.game then
            Utils.notify(locale("tasks.no_active_task"), "error")
            return
        end
        getNearbyPlantingPoints(50.0)
        local count = 0
        local processedPoints = {}
        local cropName = showCropSelectionDialog()
        for pointIndex, point in pairs(client.currentTask.game.plantingPoints) do
            if count >= 20 then
                break
            end

            point.cropName = cropName
            for _, value in pairs({ POINT_STATES.PLANTED, POINT_STATES.WATERED, POINT_STATES.GROWN }) do
                onPlantingPointStateChanged(pointIndex, value)
                Citizen.Wait(50)
            end

            count = count + 1
        end

        shared.debug("debug:FreelanceClient.debug_freelance",
            ("Processed %s points"):format(count))
    end, false)
end

--- Register the FreelanceClient module with the MultiplayerTasksClient
if MultiplayerTasksClient and MultiplayerTasksClient.registerModuleState then
    MultiplayerTasksClient.registerModuleState("freelance", FreelanceClient, config)
end
