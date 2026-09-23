local lib = lib
local Utils = require("modules.utils.client")
local config = lib.load("core.multiplayer_tasks.melon_pumpkin.config")

local MelonPumpkinClient = {}

local RES_MARKERS_YTD <const> = "res_markers"

--- Point states for farming
local POINT_STATES <const> = {
    EMPTY = "empty",
    RAKED = "raked",
    PLANTED = "planted",
    WATERED = "watered",
    GROWN = "grown",
    HARVESTED = "harvested"
}

--- Colors for point marker states
local POINT_COLORS <const> = {
    [POINT_STATES.EMPTY] = { r = 255, g = 255, b = 255 },   -- White
    [POINT_STATES.RAKED] = { r = 139, g = 69, b = 19 },     -- Brown
    [POINT_STATES.PLANTED] = { r = 255, g = 255, b = 0 },   -- Yellow
    [POINT_STATES.WATERED] = { r = 130, g = 255, b = 243 }, -- Light Blue
    [POINT_STATES.GROWN] = { r = 0, g = 255, b = 0 },       -- Green
    [POINT_STATES.HARVESTED] = { r = 255, g = 165, b = 0 }  -- Orange
}

--- Farming manual tools configuration
local MANUAL_FARMING_TOOLS <const> = {
    rakering = {
        action = "rakering",
        requiredState = POINT_STATES.EMPTY,
        targetState = POINT_STATES.RAKED,
        workRadius = 1.5,
        workTime = 2000,
        actionText = locale("melon_pumpkin.rake_crops"),
        anim = {
            dict = "anim@amb@drug_field_workers@rake@male_a@base",
            clip = "base",
            flags = 1
        },
        prop = {
            model = "prop_tool_rake",
            bone = 28422,
            pos = { x = 0.0, y = 0.0, z = -0.0300 },
            rot = { x = 0.0, y = 0.0, z = 0.0 }
        }
    },
    planting = {
        action = "planting",
        requiredState = POINT_STATES.RAKED,
        targetState = POINT_STATES.PLANTED,
        workRadius = 1.5,
        workTime = 5000,
        actionText = locale("melon_pumpkin.plant_crops"),
        anim = {
            scenario = "WORLD_HUMAN_GARDENER_PLANT"
        },
    },
    watering = {
        action = "watering",
        requiredState = POINT_STATES.PLANTED,
        targetState = POINT_STATES.WATERED,
        workRadius = 1.5,
        workTime = 2500,
        actionText = locale("melon_pumpkin.water_plants"),
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
    },
    harvesting = {
        action = "harvesting",
        requiredState = POINT_STATES.GROWN,
        targetState = POINT_STATES.HARVESTED,
        workRadius = 1.5,
        workTime = 5000,
        actionText = locale("melon_pumpkin.harvest_crops"),
        anim = {
            scenario = "WORLD_HUMAN_GARDENER_PLANT",
        },
    }
}

local HOLD_OBJECT_OFFSET <const> = config.holdObjectOffsets or {}

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

        selectedCropName = nil,

        carryingState = {
            isCarrying = false,
            carryingProp = nil,
        },
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
        Utils.notify(locale("melon_pumpkin.no_seeds_available"), "error")
        return nil
    end

    local input = lib.inputDialog(locale("melon_pumpkin.select_crop"), {
        {
            type = "select",
            label = locale("melon_pumpkin.crop_type"),
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
        shared.debug("debug:MelonPumpkinClient.onEnterSpawnTaskEntityPoint: Invalid model", meta.model)
        return
    end

    local entitySpawnCoords = meta.coords or self.coords

    lib.requestModel(entityModel)
    local entityId, entityNetId

    entityId = CreateVehicle(entityModel, entitySpawnCoords.x, entitySpawnCoords.y,
        entitySpawnCoords.z, entitySpawnCoords.w or 0.0, true, true)

    while not DoesEntityExist(entityId) do Citizen.Wait(0) end

    entityNetId = lib.waitFor(function()
        if not NetworkGetEntityIsNetworked(entityId) then
            NetworkRegisterEntityAsNetworked(entityId)
        else
            local netId = VehToNet(entityId)
            if NetworkDoesNetworkIdExist(netId) then
                return netId
            end
        end
    end, false, false)

    SetModelAsNoLongerNeeded(entityModel)

    SetEntityCoords(entityId, entitySpawnCoords.x, entitySpawnCoords.y, entitySpawnCoords.z)
    SetEntityRotation(entityId, 0.0, 0.0, entitySpawnCoords.w or 0.0, 2)

    Utils.setFuel(entityId, 100.0)

    local entityState = {
        key = meta.key,
        model = meta.model,
        coords = entitySpawnCoords,
        netId = entityNetId,
        spawned = true,
    }

    client.currentTask.game.taskEntities[meta.key] = entityState

    self:remove()
    state.fieldPoints["entity_" .. meta.key] = nil

    lib.callback.await(_e("server:melon_pumpkin:onVehicleSpawned"),
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
local function spawnPointObject(name, state, coords, pointIndex)
    local objectModel = "prop_veg_crop_03_pump"

    if state == POINT_STATES.PLANTED then
        if Config.DisableCustomProps then
            objectModel = config.crops[name] and config.crops[name].growthModel or "prop_veg_crop_03_pump"
        else
            objectModel = config.crops[name] and config.crops[name].seedModel or "0r_sapling"
        end
    elseif state == POINT_STATES.GROWN then
        if Config.DisableCustomProps then
            objectModel = config.crops[name] and config.crops[name].growthModel or "prop_veg_crop_03_pump"
        else
            objectModel = config.crops[name] and config.crops[name].growthModel or "prop_veg_crop_03_pump"
        end
    end

    lib.requestModel(objectModel)
    local pointObject = CreateObject(GetHashKey(objectModel), coords.x, coords.y, coords.z, true, true, false)

    if DoesEntityExist(pointObject) then
        NetworkRegisterEntityAsNetworked(pointObject)
        FreezeEntityPosition(pointObject, true)
        SetEntityCoords(pointObject, coords.x, coords.y, coords.z)
        SetModelAsNoLongerNeeded(objectModel)

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
            lib.callback.await(_e("server:melon_pumpkin:registerPointObject"), false, {
                lobbyId = client.lobby.id,
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

    ClearPedTasksImmediately(playerPed)

    lib.requestAnimDict("anim@heists@box_carry@")

    TaskPlayAnim(playerPed, "anim@heists@box_carry@", "idle", 8.0, 8.0, -1, 50, 0, false, false, false)
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

--- Load a harvested bale to the delivery vehicle
--- @param pointIndex number
--- @param deliveryVehicle number
local function loadHarvestedCropToDeliveryVehicle(pointIndex, deliveryVehicleNetId)
    if not state.carryingState.isCarrying then
        return
    end

    local deliveryVehicle = NetToVeh(deliveryVehicleNetId)

    local deliveryCoords = GetEntityCoords(deliveryVehicle)
    local playerCoords = GetEntityCoords(cache.ped)
    local distance = #(deliveryCoords - playerCoords)

    for i = 2, 3 do
        SetVehicleDoorOpen(deliveryVehicle, i, false, false)
    end

    if distance > 5.0 then
        return
    end

    local cropName = client.currentTask.game.plantingPoints[pointIndex].cropName

    stopCarryingAnimation()

    TriggerServerEvent(_e("server:melon_pumpkin:loadHarvestedCropToDeliveryVehicle"), {
        lobbyId = client.lobby.id,
        pointIndex = pointIndex,
        deliveryVehicleNetId = deliveryVehicleNetId,
        cropName = cropName
    })

    Utils.notify(locale("melon_pumpkin.harvested_crop_loaded"), "success")
end

--- @param pointIndex number
--- @param propModel string
local function pickupHarvestedCropObject(pointIndex, propModel)
    if state.carryingState.isCarrying then
        Utils.notify(locale("melon_pumpkin.already_carrying"), "error")
        return
    end

    local pointObjectCoords = GetEntityCoords(cache.ped)
    local pointObjectNetId = state.pointObjectNetIds[pointIndex]
    if pointObjectNetId then
        local pointObject = NetToObj(pointObjectNetId)
        if pointObject and DoesEntityExist(pointObject) then
            pointObjectCoords = GetEntityCoords(pointObject)
        end
    end

    local harvestedCropModel = propModel or "prop_veg_crop_03_cab"
    lib.requestModel(harvestedCropModel)
    local networkedObject = CreateObject(GetHashKey(harvestedCropModel),
        pointObjectCoords.x, pointObjectCoords.y, pointObjectCoords.z, true, true, false)

    NetworkRegisterEntityAsNetworked(networkedObject)

    local pointCropName = client.currentTask.game.plantingPoints[pointIndex].cropName
    local attachOffset = config.crops[pointCropName].attachOffset or vector3(0.0, 0.0, 0.0)
    AttachEntityToEntity(networkedObject, cache.ped,
        GetPedBoneIndex(playerPed, 28422),
        attachOffset.x, attachOffset.y, attachOffset.z,
        0.0, 0.0, 0.0,
        true, true, false, true, 2, true)

    state.carryingState.isCarrying = true
    state.carryingState.carryingProp = networkedObject

    SetModelAsNoLongerNeeded(harvestedCropModel)

    startCarryingAnimation()

    TriggerServerEvent(_e("server:melon_pumpkin:onHarvestedCropPickedUp"), {
        lobbyId = client.lobby.id,
        pointIndex = pointIndex,
    })

    Utils.notify(locale("melon_pumpkin.harvested_crop_picked_up"), "success")

    state.pointObjectNetIds[pointIndex] = nil

    Citizen.CreateThread(function()
        local pointIndex = pointIndex

        while state.carryingState.isCarrying do
            local waitMsec = 500
            local deliveryVehicleNetId = nil

            if not deliveryVehicleNetId and
                client.currentTask.game.taskEntities["deliveryVehicle"]
            then
                deliveryVehicleNetId = client.currentTask.game.taskEntities["deliveryVehicle"].netId
            end

            if deliveryVehicleNetId then
                local deliveryVehicle = NetToVeh(deliveryVehicleNetId)
                if deliveryVehicle and DoesEntityExist(deliveryVehicle) then
                    local playerCoords        = GetEntityCoords(cache.ped)
                    local deliveryVehicleBack = GetOffsetFromEntityInWorldCoords(deliveryVehicle, 0.0, -2.5, 0.0)
                    local distBack            = #(playerCoords - deliveryVehicleBack)

                    if distBack <= 1.5 then
                        loadHarvestedCropToDeliveryVehicle(pointIndex, deliveryVehicleNetId)
                        Citizen.Wait(1000)
                    end
                end
            end

            Citizen.Wait(waitMsec)
        end
    end)
end

--- Handle the state change of a planting point
--- @param index number
--- @param newState string
local function onPlantingPointStateChanged(index, newState)
    local plantingPoint = client.currentTask.game.plantingPoints[index]

    plantingPoint.state = newState

    local newStateBlipColorId = 0

    local pointCropName = plantingPoint.cropName
    if not pointCropName then
        client.currentTask.game.plantingPoints[index].cropName = state.selectedCropName
        pointCropName = state.selectedCropName
    end

    local cropModel = nil
    if Config.DisableCustomProps then
        cropModel = config.crops[pointCropName] and config.crops[pointCropName].growthModel or "prop_veg_crop_03_pump"
    else
        cropModel = config.crops[pointCropName] and config.crops[pointCropName].seedModel or "0r_sapling"
    end

    local spawnOffset = config.crops[pointCropName] and config.crops[pointCropName].spawnOffset or vector3(0.0, 0.0, 0.0)
    local normalizedCoords = vector3(
        plantingPoint.coords.x + spawnOffset.x,
        plantingPoint.coords.y + spawnOffset.y,
        (state.pointGroundZValues[index] or plantingPoint.coords.z) + spawnOffset.z
    )

    if newState == POINT_STATES.PLANTED then
        newStateBlipColorId = 5
        local pointObjectNetId = spawnPointObject(pointCropName, newState, normalizedCoords, index)
        if pointObjectNetId then
            local pointObject = NetToObj(pointObjectNetId)
            if Config.DisableCustomProps and DoesEntityExist(pointObject) then
                Citizen.Wait(100)
                PlaceObjectOnGroundProperly(pointObject)
                local objectGroundOffset = calculateModelGroundOffset(cropModel)
                local offsetCoords = GetOffsetFromEntityInWorldCoords(pointObject, 0.0, 0.0, -(objectGroundOffset / 1.2))
                SetEntityCoords(pointObject, offsetCoords.x, offsetCoords.y, offsetCoords.z)
            end
            state.pointObjectNetIds[index] = pointObjectNetId
        end
    elseif newState == POINT_STATES.WATERED then
        newStateBlipColorId = 29
    elseif newState == POINT_STATES.GROWN then
        newStateBlipColorId = 2
    elseif newState == POINT_STATES.HARVESTED then
        newStateBlipColorId = 17
        if state.fieldBlips["point_" .. index] then
            RemoveBlip(state.fieldBlips["point_" .. index])
            state.fieldBlips["point_" .. index] = nil
        end
        state.nearbyPoints[index] = nil
    end

    TriggerServerEvent(_e("server:melon_pumpkin:onPlantingPointStateChanged"), {
        lobbyId = client.lobby.id,
        pointIndex = index,
        newState = newState,
        cropName = pointCropName,
    })
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
            if pointState == tool.requiredState and nearbyPoint.distance < tool.workRadius then
                if nearbyPoint.distance < closestDistance then
                    closestDistance = nearbyPoint.distance
                    closestPoint = nearbyPoint
                    bestTool = tool
                end
            end
        end
    end

    if closestPoint and bestTool then
        local actionText = locale("melon_pumpkin.press_to_action", bestTool.actionText)
        if not state.showTextUI then
            Utils.showTextUI(actionText)
            state.showTextUI = true
        end

        if IsControlJustPressed(0, 38) then -- E key
            Utils.hideTextUI()
            state.showTextUI = false

            local progressLabel = "Processing point..."

            if bestTool.action == "watering" then
                if not hasRequiredItem(config.wateringCan.itemName, 1) then
                    Utils.notify(locale("melon_pumpkin.no_watercan"), "error")
                    return false, 1000
                end
                progressLabel = locale("melon_pumpkin.watering_plants")
            elseif bestTool.action == "planting" then
                if not state.selectedCropName then
                    Utils.notify(locale("melon_pumpkin.crop_selection_cancelled"), "error")
                    return false, 1000
                end
                local cropData = config.crops[state.selectedCropName]
                if not hasRequiredItem(cropData.seedItem, 1) then
                    Utils.notify(locale("melon_pumpkin.no_seeds_available", cropData.label), "error")
                    return false, 2000
                end
                if not removeItem(cropData.seedItem, 1) then
                    Utils.notify(locale("melon_pumpkin.failed_to_remove_item"), "error")
                    return false, 2000
                end
            end

            Utils.progressBar({
                duration = bestTool.workTime,
                label = progressLabel,
                useWhileDead = false,
                canCancel = false,
                disable = {
                    car = true,
                    move = true,
                    combat = true
                },
                anim = bestTool.anim,
                prop = bestTool.prop,
            })

            if bestTool.action == "harvesting" then
                local canHarvest = lib.callback.await(_e("server:melon_pumpkin:canHarvestCrop"), false, {
                    lobbyId = client.lobby.id,
                    pointIndex = closestPoint.index,
                })
                if not canHarvest then
                    return false, 2000
                end
            elseif bestTool.action == "planting" then
                local canPlant = lib.callback.await(_e("server:melon_pumpkin:canPlantCrop"), false, {
                    lobbyId = client.lobby.id,
                    pointIndex = closestPoint.index,
                    cropName = state.selectedCropName,
                })
                if not canPlant then
                    return false, 2000
                end
            end

            onPlantingPointStateChanged(closestPoint.index, bestTool.targetState)

            if bestTool.action == "harvesting" then
                pickupHarvestedCropObject(closestPoint.index,
                    config.crops[client.currentTask.game.plantingPoints[closestPoint.index].cropName].growthModel)
            else
                local workRadius = 3.5
                for ppIndex, ppPoint in pairs(client.currentTask.game.plantingPoints) do
                    if ppIndex ~= closestPoint.index then
                        local distance = #(closestPoint.coords - ppPoint.coords)
                        if distance <= workRadius then
                            if (bestTool.requiredState == "empty" and (not ppPoint.state or ppPoint.state == "empty")) or
                                ppPoint.state == bestTool.requiredState
                            then
                                onPlantingPointStateChanged(ppIndex, bestTool.targetState)
                            end
                        end
                    end
                end
            end

            local successMessage = locale("melon_pumpkin.point_processed", closestPoint.index, bestTool.action)
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

function MelonPumpkinClient.selectCrop()
    state.selectedCropName = showCropSelectionDialog()

    if not state.selectedCropName then
        local defaultCropKey, _ = next(config.crops)
        state.selectedCropName = defaultCropKey
    end

    TriggerServerEvent(_e("server:melon_pumpkin:onCropSelected"), {
        lobbyId = client.lobby.id,
        cropName = state.selectedCropName
    })

    return true
end

--- Worker thread for MelonPumpkinClient
--- This function handles the main logic for farming tasks, including rendering, farming mechanics, and state synchronization.
function MelonPumpkinClient.threadWorker()
    -- Plating points rendering thread
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

            local isManualFarmingWorking, manualExtraWait = handleManualFarming()

            if isManualFarmingWorking then
                wait = 0
            end

            if manualExtraWait then
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
    -- Delivery point rendering thread
    Citizen.CreateThread(function()
        while client.lobby and client.currentTask do
            local wait = 2000
            if cache.vehicle and cache.seat == -1 then
                local deliveryVehicle = client.currentTask.game.taskEntities["deliveryVehicle"]
                local deliveryVehicleNetId = deliveryVehicle and deliveryVehicle.netId
                local playerVehicleNetId = VehToNet(cache.vehicle)
                if deliveryVehicleNetId == playerVehicleNetId then
                    local closestNpc = client.getClosestSellNpc()
                    if closestNpc then
                        wait = 1000
                        local distance = #(vector3(closestNpc) - GetEntityCoords(cache.ped))
                        if distance < 5.0 then
                            local response = lib.callback.await(_e("server:melon_pumpkin:onSellNpcInteraction"), false, {
                                lobbyId = client.lobby.id,
                            })
                            if not response then
                                Utils.notify(locale("melon_pumpkin.sell_npc_interaction_error"), "error")
                            elseif type(response) == "table" and response.error then
                                Utils.notify(response.error, "error")
                                wait = 5000
                            elseif response then
                                return
                            end
                        end
                    end
                end
            end
            Citizen.Wait(wait)
        end
    end)
end

--- Initialize the MelonPumpkinClient state
function MelonPumpkinClient.clear()
    shared.debug("debug:MelonPumpkinClient.clear")

    if state.showTextUI then
        Utils.hideTextUI()
    end

    for _, blip in pairs(state.fieldBlips) do
        RemoveBlip(blip)
    end

    for _, points in pairs(state.fieldPoints) do
        if points then
            points:remove()
        end
    end

    stopCarryingAnimation()

    __init__()
    shared.debug("debug:MelonPumpkinClient.clear: State cleared")
end

--- Start MelonPumpkinClient state
function MelonPumpkinClient.start()
    shared.debug("debug:MelonPumpkinClient.start",
        ("lobby: %s, field: %s"):format(client.lobby and client.lobby.id or "nil",
            client.currentTask and client.currentTask.game.fieldId or "nil"))

    local field = getFieldById(client.currentTask.game.fieldId)
    if not field then
        shared.debug(
            ("MelonPumpkinClient start error: Field not found for ID %s"):format(client.currentTask.game.fieldId),
            "error")
        return false
    end

    -- Clear previous state
    __init__()

    state.fieldBlips.center = Utils.addBlip(field.center, config.blips.field, true)
    state.fieldBlips.radius = Utils.addRadiusBlip(field.center, field.radius, config.blips.field)

    for index, plantingPoint in pairs(client.currentTask.game.plantingPoints) do
        state.fieldBlips["point_" .. index] = Utils.addBlip(plantingPoint.coords, config.blips.point)
    end

    state.fieldBlips["entity_deliveryVehicle"] =
        Utils.addBlip(field.deliveryVehicle.location, config.blips["deliveryVehicle"], false)

    shared.debug(("debug:MelonPumpkinClient.start: Field blips created for ID %s"):format(client.currentTask.game
        .fieldId))

    if client.lobby.owner == cache.serverId then
        state.fieldPoints["entity_deliveryVehicle"] = lib.points.new({
            coords = field.deliveryVehicle.location,
            distance = 50.0,
            meta = {
                key = "deliveryVehicle",
                model = field.deliveryVehicle.model,
                coords = field.deliveryVehicle.location,
            },
            onEnter = onEnterSpawnTaskEntityPoint,
        })
    end

    if not Config.DisableCustomProps then
        lib.requestStreamedTextureDict(RES_MARKERS_YTD)
    end

    MelonPumpkinClient.threadWorker()

    Utils.notify(locale("tasks.started"), "success")

    if client.lobby.owner == cache.serverId then
        MelonPumpkinClient.selectCrop()
    end

    return true
end

--- Stop the MelonPumpkinClient and clear the state
function MelonPumpkinClient.stop()
    shared.debug("debug:MelonPumpkinClient.stop", ("lobby: %s, field: %s"):format(
        client.lobby and client.lobby.id or "nil",
        client.currentTask and client.currentTask.game.fieldId or "nil"
    ))

    MelonPumpkinClient.clear()

    if not Config.DisableCustomProps then
        SetStreamedTextureDictAsNoLongerNeeded(RES_MARKERS_YTD)
    end

    return true
end

--[[ Event Handlers ]]

RegisterNetEvent(_e("client:melon_pumpkin:onVehicleSpawned"), function(entityState)
    if not entityState or not entityState.key then
        shared.debug("debug:MelonPumpkinClient.onVehicleSpawned - Invalid entityState",
            ("entityState: %s"):format(json.encode(entityState)), "error")
        return
    end

    client.currentTask.game.taskEntities[entityState.key] = entityState

    Citizen.CreateThread(function()
        local entity = lib.waitFor(function()
            if NetworkDoesEntityExistWithNetworkId(entityState.netId) then
                local ent = NetToVeh(entityState.netId)
                if DoesEntityExist(ent) then return ent end
            end
        end, false, false)

        MultiplayerTasksClient.giveVehicleKey(GetVehicleNumberPlateText(entity), entity)
    end)
end)

RegisterNetEvent(_e("client:melon_pumpkin:onPlantingPointUpdate"), function(data)
    if not data.lobbyId then return end
    if not client.lobby or client.lobby.id ~= data.lobbyId then
        return
    end

    local plantingPoint = client.currentTask.game.plantingPoints[data.pointIndex]

    if data.newState then
        plantingPoint.state = data.newState
    end
    if data.cropName then
        plantingPoint.cropName = data.cropName
    end

    if data.playerId ~= cache.serverId then
        local normalizedCoords = vector3(
            plantingPoint.coords.x,
            plantingPoint.coords.y,
            (state.pointGroundZValues[data.pointIndex] or plantingPoint.coords.z))

        local newStateBlipColorId = 0
        local pointCropName = data.cropName

        local cropModel = nil
        if Config.DisableCustomProps then
            cropModel = config.crops[pointCropName] and config.crops[pointCropName].growthModel or
                "prop_veg_crop_03_pump"
        else
            cropModel = config.crops[pointCropName] and config.crops[pointCropName].seedModel or "0r_sapling"
        end

        if data.newState == POINT_STATES.PLANTED then
            newStateBlipColorId = 5
            if data.networkId then
                state.pointObjectNetIds[data.pointIndex] = data.networkId
                if Config.DisableCustomProps then
                    local pointObject = NetToObj(data.networkId)
                    if pointObject and DoesEntityExist(pointObject) then
                        local objectGroundOffset = calculateModelGroundOffset(cropModel)
                        local offsetCoords = GetOffsetFromEntityInWorldCoords(pointObject, 0.0, 0.0,
                            -(objectGroundOffset / 1.3))
                        SetEntityCoords(pointObject, offsetCoords.x, offsetCoords.y, offsetCoords.z)
                    end
                end
            end
        elseif data.newState == POINT_STATES.WATERED then
            newStateBlipColorId = 29
        elseif data.newState == POINT_STATES.GROWN then
            newStateBlipColorId = 2
            if data.networkId then
                state.pointObjectNetIds[data.pointIndex] = data.networkId
            end
        elseif data.newState == POINT_STATES.HARVESTED then
            newStateBlipColorId = 17
            if state.fieldBlips["point_" .. data.pointIndex] then
                RemoveBlip(state.fieldBlips["point_" .. data.pointIndex])
                state.fieldBlips["point_" .. data.pointIndex] = nil
            end
            state.nearbyPoints[data.pointIndex] = nil
        end

        local pointBlip = state.fieldBlips["point_" .. data.pointIndex]
        if pointBlip then
            SetBlipColour(pointBlip, newStateBlipColorId)
        end
    end
end)

RegisterNetEvent(_e("client:melon_pumpkin:onHarvestedCropPickedUp"), function(data)
    if not client.lobby or
        not client.currentTask or
        not data.lobbyId or
        client.lobby.id ~= data.lobbyId then
        return
    end
end)

lib.callback.register(_e("server:melon_pumpkin:spawnObjectInDeliveryVehicle"), function(data)
    if not data or not data.deliveryVehicleNetId then
        shared.debug("debug:MelonPumpkinClient.spawnObjectInDeliveryVehicle - Invalid data", "error")
        return false
    end
    local deliveryVehicleNetId = data.deliveryVehicleNetId
    local deliveryVehicle = NetToVeh(deliveryVehicleNetId)

    if not deliveryVehicle or not DoesEntityExist(deliveryVehicle) then
        shared.debug("debug:MelonPumpkinClient.spawnObjectInDeliveryVehicle - Invalid delivery vehicle", "error")
        return false
    end

    local model = config.crops[data.cropName] and config.crops[data.cropName].growthModel
        or
        "prop_veg_crop_03_pump"
    lib.requestModel(model)

    local holdOffset = HOLD_OBJECT_OFFSET[data.loadedCount]
    if not holdOffset then
        return false
    end

    local coords = GetEntityCoords(deliveryVehicle)
    local object = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
    shared.debug(("debug:melon_pumpkin:Object created: %s"):format(object))
    while not DoesEntityExist(object) do Wait(0) end

    SetEntityCollision(object, false, false)
    SetEntityCompletelyDisableCollision(object, true)
    SetEntityVisible(object, false)
    SetModelAsNoLongerNeeded(objectModel)

    AttachEntityToEntity(object, deliveryVehicle, nil,
        holdOffset.x, holdOffset.y, holdOffset.z,
        0.0, 0.0, 90.0,
        false, false, false, false, 0, true
    )

    local objectNetId = lib.waitFor(function()
        if not NetworkGetEntityIsNetworked(object) then
            NetworkRegisterEntityAsNetworked(object)
        else
            local netId = ObjToNet(object)
            if NetworkDoesNetworkIdExist(netId) then
                return netId
            end
        end
    end, false, false)
    SetEntityVisible(object, true)

    return objectNetId
end)

RegisterNetEvent(_e("client:melon_pumpkin:onCropSelected"), function(data)
    if not data or not data.cropName then
        shared.debug("debug:MelonPumpkinClient.onCropSelected - Invalid data", "error")
        return false
    end

    state.selectedCropName = data.cropName
end)

RegisterNetEvent(_e("client:melon_pumpkin:playWateringEffect"), function(data)
    local pointObjectNetId = data.networkId
    local pointCropName = data.cropName

    if pointObjectNetId then
        local pointObject = NetToObj(pointObjectNetId)
        if pointObject and DoesEntityExist(pointObject) then
            local cropModel = nil
            if Config.DisableCustomProps then
                cropModel = config.crops[pointCropName] and config.crops[pointCropName].growthModel or
                    "prop_veg_crop_03_pump"
            else
                cropModel = config.crops[pointCropName] and config.crops[pointCropName].seedModel or "0r_sapling"
            end

            if Config.DisableCustomProps then
                local objectCoords = GetEntityCoords(pointObject)
                local objectGroundOffset = calculateModelGroundOffset(cropModel)
                SetEntityCoords(pointObject, objectCoords.x, objectCoords.y,
                    objectCoords.z + (objectGroundOffset * .1))
            end
        end
    end
end)

RegisterNetEvent(_e("client:melon_pumpkin:playGrowthEffect"), function(data)
    local pointObjectNetId = data.networkId
    local pointCropName = data.cropName
    if pointObjectNetId then
        local pointObject = NetToObj(pointObjectNetId)
        if pointObject and DoesEntityExist(pointObject) then
            local getObjectCoords = GetEntityCoords(pointObject)
            TriggerServerEvent(_e("server:melon_pumpkin:deletePointObject"), {
                lobbyId = client.lobby.id,
                pointIndex = data.pointIndex,
            })

            local newPointObjectNetId = spawnPointObject(pointCropName,
                data.newState,
                getObjectCoords,
                data.pointIndex,
                data.lobbyId
            )
            if newPointObjectNetId then
                local newPointObject = NetToObj(newPointObjectNetId)
                if newPointObject and DoesEntityExist(newPointObject) then
                    PlaceObjectOnGroundProperly(newPointObject)
                end
                state.pointObjectNetIds[index] = newPointObjectNetId
            end
        end
    end
end)

--- Register the MelonPumpkinClient module with the MultiplayerTasksClient
if MultiplayerTasksClient and MultiplayerTasksClient.registerModuleState then
    MultiplayerTasksClient.registerModuleState("melon_pumpkin", MelonPumpkinClient, config)
end

if Config.debug then
    RegisterCommand("debug_melon_pumpkin", function()
        if not client.currentTask or not client.currentTask.game then
            Utils.notify(locale("tasks.no_active_task"), "error")
            return
        end
        getNearbyPlantingPoints(50.0)
        local count = 0
        local processedPoints = {}

        for pointIndex, point in pairs(client.currentTask.game.plantingPoints) do
            if count >= 10 then
                break
            end

            point.cropName = "melon" -- Set a default crop for testing
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
