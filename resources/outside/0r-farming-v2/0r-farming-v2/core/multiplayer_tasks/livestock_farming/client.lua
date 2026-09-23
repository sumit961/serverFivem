local lib = lib
local Utils = require("modules.utils.client")
local Target = require("modules.target.client")
local config = lib.load("core.multiplayer_tasks.livestock_farming.config")

local LivestockFarmingClient = {}

local state = {}

local function __init__()
    state = {
        showTextUI = false, -- Whether to show the text UI
        blips = {},         -- Blips for the livestock farming fields
        points = {},        -- Points of interest for the livestock farming
        targets = {},       -- Target zones for interaction

        carryingState = {
            isCarrying = false, -- Whether the player is currently carrying a prop
            carryingProp = nil, -- The prop that the player is currently carrying
            type = nil,         -- The type of prop being carried (e.g., "feed")
        },

        isMilking = false, -- Whether the player is currently milking a cow
        isBusy = false,    -- Whether the player is busy with an action
    }
end

--- Get the field data by ID
--- @param fieldId string|number
--- @return table|nil
local function getFieldById(fieldId)
    return config.fields[fieldId]
end

---@param self CPoint
local function onEnterVehicleSpawnPoint(self)
    local meta = self.meta
    if not meta or not meta.key or not meta.model then
        return self:remove()
    end

    local entityModel = type(meta.model) == "string" and GetHashKey(meta.model) or meta.model
    if not IsModelValid(entityModel) then
        shared.debug("debug:livestock_farming.onEnterVehicleSpawnPoint: Invalid model", meta.model)
        return self:remove()
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
    state.points[meta.key] = nil

    lib.callback.await(_e("server:livestock_farming:onVehicleSpawned"),
        false, client.lobby.id, entityState)
end

---@param self CPoint
local function onEnterCowSpawnPoint(self)
    local meta = self.meta
    if not meta or not meta.key or not meta.model then
        return self:remove()
    end

    local entityModel = type(meta.model) == "string" and GetHashKey(meta.model) or meta.model
    if not IsModelValid(entityModel) then
        shared.debug("debug:livestock_farming.onEnterCowSpawnPoint: Invalid model", meta.model)
        return self:remove()
    end

    local entitySpawnCoords = meta.coords or self.coords

    lib.requestModel(entityModel)
    local entityId, entityNetId

    entityId = CreatePed(4, entityModel,
        entitySpawnCoords.x, entitySpawnCoords.y, entitySpawnCoords.z, entitySpawnCoords.w or 0.0,
        true, true)

    while not DoesEntityExist(entityId) do Citizen.Wait(0) end

    entityNetId = lib.waitFor(function()
        if not NetworkGetEntityIsNetworked(entityId) then
            NetworkRegisterEntityAsNetworked(entityId)
        else
            local netId = ObjToNet(entityId)
            if NetworkDoesNetworkIdExist(netId) then
                return netId
            end
        end
    end, false, false)

    FreezeEntityPosition(entityId, true)
    SetEntityCoords(entityId, entitySpawnCoords.x, entitySpawnCoords.y, entitySpawnCoords.z)
    SetEntityRotation(entityId, 0.0, 0.0, entitySpawnCoords.w or 0.0, 2)
    SetEntityInvincible(entityId, true)
    SetPedDiesWhenInjured(entityId, false)
    TaskSetBlockingOfNonTemporaryEvents(entityId, true)
    SetBlockingOfNonTemporaryEvents(entityId, true)
    SetModelAsNoLongerNeeded(entityModel)

    local entityState = {
        key = meta.key,
        model = meta.model,
        coords = entitySpawnCoords,
        netId = entityNetId,
        spawned = true,
    }

    client.currentTask.game.taskEntities[meta.key] = entityState

    self:remove()
    state.points[meta.key] = nil

    lib.callback.await(_e("server:livestock_farming:onCowSpawned"),
        false, client.lobby.id, entityState)
end

--- Start carrying animation and attach the prop to the player
local function startCarryingAnimation(options)
    local playerPed = cache.ped
    local playerCoords = GetEntityCoords(playerPed)

    state.carryingState.isCarrying = true

    lib.requestModel(options.model)

    local networkedObject = CreateObject(GetHashKey(options.model),
        playerCoords.x, playerCoords.y, playerCoords.z, true, true, false)

    NetworkRegisterEntityAsNetworked(networkedObject)

    AttachEntityToEntity(networkedObject, cache.ped,
        GetPedBoneIndex(playerPed, options.bone),
        options.offset.x, options.offset.y, options.offset.z,
        options.rotation.x, options.rotation.y, options.rotation.z,
        true, true, false, true, 2, true)

    SetModelAsNoLongerNeeded(options.model)

    state.carryingState.carryingProp = networkedObject
    state.carryingState.carryingType = options.type

    ClearPedTasksImmediately(playerPed)

    lib.requestAnimDict(options.dict)

    TaskPlayAnim(playerPed, options.dict, options.name, 8.0, 8.0, -1, 50, 0, false, false, false)
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

local function setupFeedTarget(models)
    local options = { {
        label = locale("livestock_farming.feed_animal"),
        icon = "fa-solid fa-wheat-awn",
        distance = 2.0,
        onSelect = function()
            if state.carryingState.isCarrying then
                Utils.notify(locale("livestock_farming.already_carrying"), "error")
                return
            end
            local mayI = lib.callback.await(_e("server:livestock_farming:canCarryFeed"),
                false, client.lobby.id)
            if not mayI then
                Utils.notify(locale("livestock_farming.cannot_carry"), "error")
                return
            end
            startCarryingAnimation(config.animalFeed.hold)
        end,
        canInteract = function()
            if not (client.currentTask and client.currentTask.game and client.currentTask.game.taskEntities) then
                return true
            end
            local playerCoords = GetEntityCoords(cache.ped)
            for entityKey, entityData in pairs(client.currentTask.game.taskEntities) do
                if type(entityKey) == "string" and entityKey:find("^cow_") and entityData.netId then
                    local cowEntity = NetToPed(entityData.netId)
                    if DoesEntityExist(cowEntity) then
                        local cowCoords = GetEntityCoords(cowEntity)
                        local distance = #(playerCoords - cowCoords)
                        if distance <= 5.0 then
                            return false
                        end
                    end
                end
            end
            return true
        end,
    } }
    Target.addModel(models, options)
    table.insert(state.targets, { type = "model", model = model })
end

local function setupCowTarget(locations)
    for key, value in pairs(locations) do
        local zoneKey = ("livestock_farming_cow_feed_%s"):format(key)
        local options = {
            {
                label = locale("livestock_farming.feed_cow"),
                distance = 2.0,
                icon = "fa-solid fa-bowl-food",
                canInteract = function()
                    return state.carryingState.isCarrying and
                        not client.currentTask.game.fedCowPoints[key]
                end,
                onSelect = function()
                    if not state.carryingState.isCarrying then
                        Utils.notify(locale("livestock_farming.not_carrying"), "error")
                        return
                    end
                    if client.currentTask.game.fedCowPoints[key] then
                        return
                    end

                    local response = lib.callback.await(_e("server:livestock_farming:feedCow"),
                        false, client.lobby.id, key)
                    if not response then
                        return Utils.notify(locale("livestock_farming.feed_failed"), "error")
                    end

                    client.currentTask.game.fedCowPoints[key] = true
                    stopCarryingAnimation()
                    Utils.notify(locale("livestock_farming.cow_fed"), "success")
                end,
            },
            {
                label = locale("livestock_farming.milk_cow"),
                distance = 2.0,
                icon = "fa-solid fa-cow",
                canInteract = function()
                    return not state.carryingState.isCarrying and
                        client.currentTask.game.fedCowPoints[key] and
                        not state.isMilking
                end,
                onSelect = function()
                    if state.isBusy then return end
                    if state.carryingState.isCarrying then return end
                    if not client.currentTask.game.fedCowPoints[key] then return end
                    if client.currentTask.game.milkedCowPoints[key] then return end

                    local response = lib.callback.await(_e("server:livestock_farming:milkCow"),
                        false, client.lobby.id, key)
                    if not response then
                        return Utils.notify(locale("livestock_farming.feed_failed"), "error")
                    end
                    if type(response) == "table" and response.error then
                        return Utils.notify(response.error, "error")
                    end

                    local nearestCowNetId = client.currentTask.game.taskEntities["cow_" .. key].netId
                    if nearestCowNetId then
                        local nearestCow = NetToPed(nearestCowNetId)
                        if nearestCow ~= 0 and DoesEntityExist(nearestCow) then
                            FreezeEntityPosition(cache.ped, true)
                            TaskTurnPedToFaceEntity(cache.ped, nearestCow, 500)
                            Citizen.Wait(500)
                            FreezeEntityPosition(cache.ped, false)
                        end
                    end
                    state.isBusy = true
                    lib.playAnim(cache.ped,
                        "anim@amb@clubhouse@tutorial@bkr_tut_ig3@", "machinic_loop_mechandplayer",
                        nil, nil, 10000)

                    Utils.progressBar({
                        duration = 10000,
                        label = locale("livestock_farming.milk_cow"),
                        useWhileDead = false,
                        canCancel = false,
                        disable = {
                            move = true,
                            combat = true,
                            vehicle = true,
                        },
                    })

                    ClearPedTasks(cache.ped)

                    state.isBusy = false

                    startCarryingAnimation(config.animalFeed.milkProp)
                    Citizen.CreateThread(function()
                        while state.carryingState.isCarrying do
                            local wait = 500
                            local playerCoords = GetEntityCoords(cache.ped)
                            local truckNetId = client.currentTask.game.taskEntities["truck"] and
                                client.currentTask.game.taskEntities["truck"].netId
                            if truckNetId then
                                local truck = NetToVeh(truckNetId)
                                if DoesEntityExist(truck) then
                                    local truckCoords = GetOffsetFromEntityInWorldCoords(truck, 0.0, -4.0, 0.0)
                                    local distance = #(playerCoords - truckCoords)
                                    if distance < 2.0 then
                                        wait = 1
                                        if not state.showTextUI then
                                            Utils.showTextUI(locale("livestock_farming.deliver_milk"))
                                            state.showTextUI = true
                                        end
                                        if IsControlJustPressed(0, 38) then
                                            stopCarryingAnimation()
                                            local nearestNpc, _ = client.getClosestSellNpc()
                                            if nearestNpc then
                                                SetNewWaypoint(nearestNpc.x, nearestNpc.y)
                                            end
                                            Utils.hideTextUI()
                                            state.showTextUI = false
                                            return
                                        end
                                    elseif state.showTextUI then
                                        Utils.hideTextUI()
                                        state.showTextUI = false
                                    end
                                end
                            end
                            Citizen.Wait(wait)
                        end
                    end)
                end,
            }
        }
        Target.addBoxZone(zoneKey, {
            name = zoneKey,
            coords = vector3(value.coords.x, value.coords.y, value.coords.z + 1.0),
            size = vector3(1.2, 2.0, 1.5),
            debug = false,
            options = options,
            rotation = value.coords.w or 0.0,
        })
        table.insert(state.targets, { type = "zone", zone = zoneKey })
    end
end

local function setupDeliveryPoint()
    Citizen.CreateThread(function()
        while client.currentTask do
            local wait = 1000
            local vehicle = cache.vehicle
            local truck = client.currentTask.game.taskEntities["truck"]
            if vehicle and truck and VehToNet(vehicle) == truck.netId and cache.seat == -1 then
                local nearestNpc, nearestDistance = client.getClosestSellNpc()
                if nearestNpc then
                    if nearestDistance < 20.0 then
                        DrawMarker(1, nearestNpc.x, nearestNpc.y, nearestNpc.z - 1.0,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 10.0, 10.0, 1.0,
                            255, 255, 0, 100, false, true, 2, nil, nil, false)
                        if not state.showTextUI then
                            Utils.showTextUI(locale("livestock_farming.sell_milk"))
                            state.showTextUI = true
                        end
                        wait = 0
                        if IsControlJustPressed(0, 38) then
                            Utils.hideTextUI()
                            state.showTextUI = false
                            lib.callback.await(_e("server:livestock_farming:sellMilk"),
                                false, client.lobby.id)
                            break
                        end
                    elseif state.showTextUI then
                        state.showTextUI = false
                        Utils.hideTextUI()
                    end
                end
            end
            Citizen.Wait(wait)
        end
        if client.currentTask then
            Utils.notify(locale("livestock_farming.return_truck"), "info")
            local truck = client.currentTask.game.taskEntities["truck"]
            local targetCoords = truck.coords
            SetNewWaypoint(truck.coords.x, truck.coords.y)
            while client.currentTask do
                local wait = 1000
                local vehicle = cache.vehicle
                if vehicle and truck and VehToNet(vehicle) == truck.netId and cache.seat == -1 then
                    local vehicleCoords = GetEntityCoords(vehicle)
                    local distance = #(vehicleCoords - vector3(targetCoords.x, targetCoords.y, targetCoords.z))
                    if distance < 35.0 then
                        wait = 0
                        DrawMarker(1, targetCoords.x, targetCoords.y, targetCoords.z - 1.0,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 3.0, 1.0,
                            255, 255, 0, 100, false, true, 2, nil, nil, false)
                        if distance < 7.5 then
                            lib.callback.await(_e("server:multiplayer_tasks:stop"), false,
                                client.currentTask.moduleName, client.lobby.id)
                            return
                        end
                    end
                end
                Citizen.Wait(wait)
            end
        end
    end)
end

local function setupFeedMarker()
    local markerConfig = config.feedMarker
    if not markerConfig then return end
    Citizen.CreateThread(function()
        if not client.currentTask then return end
        local field = getFieldById(client.currentTask.game.fieldId)
        while client.currentTask do
            local wait = 1000
            local playerCoords = GetEntityCoords(cache.ped)
            for _, value in pairs(field.feedBlipLocations) do
                local distance = #(playerCoords - value)
                if distance < 20.0 then
                    wait = 0
                    DrawMarker(markerConfig.type, value.x, value.y, value.z - 1.0,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        markerConfig.scale.x, markerConfig.scale.y, markerConfig.scale.z,
                        markerConfig.color.r, markerConfig.color.g, markerConfig.color.b, markerConfig.color.a,
                        false, true, 2, false, nil, nil, false)
                end
            end
            Citizen.Wait(wait)
        end
    end)
end

function LivestockFarmingClient.clear()
    shared.debug("debug:livestock_farming.clear")

    if state.showTextUI then
        Utils.hideTextUI()
    end

    for _, value in pairs(state.blips) do
        if DoesBlipExist(value) then
            RemoveBlip(value)
        end
    end

    for _, value in pairs(state.points) do
        value:remove()
    end

    if state.carryingState.isCarrying then
        stopCarryingAnimation()
    end

    for _, value in pairs(state.targets) do
        if value.type == "model" then
            Target.removeModel(value.model)
        elseif value.type == "zone" then
            Target.removeZone(value.zone)
        end
    end

    __init__()

    shared.debug("debug:livestock_farming.clear: Cleared state")
end

function LivestockFarmingClient.start()
    shared.debug("debug:livestock_farming.start",
        ("lobby: %s, field: %s"):format(client.lobby.id, client.currentTask.game.fieldId))

    local field = getFieldById(client.currentTask.game.fieldId)
    if not field then
        shared.debug(("debug:livestock_farming.start: Field not found for ID %s"):format(client.currentTask.game.fieldId))
        return false
    end

    __init__()

    for key, value in pairs(field.cowLocations) do
        local blip = Utils.addBlip(value.coords, config.blips.cow, key == 1)
        state.blips["cow_" .. key] = blip
    end
    state.blips["truck"] = Utils.addBlip(field.truckLocation.coords, config.blips.truck)
    for key, value in pairs(field.feedBlipLocations) do
        state.blips["feed_" .. key] = Utils.addBlip(value, config.blips.feed)
    end

    setupDeliveryPoint()

    if client.lobby.owner == cache.serverId then
        state.points["truck"] = lib.points.new({
            coords = field.truckLocation.coords,
            distance = 50.0,
            meta = {
                key = "truck",
                model = field.truckLocation.model,
                coords = field.truckLocation.coords,
            },
            onEnter = onEnterVehicleSpawnPoint,
        })
        for key, value in pairs(field.cowLocations) do
            state.points["cow_" .. key] = lib.points.new({
                coords = value.coords,
                distance = 50.0,
                meta = {
                    key = "cow_" .. key,
                    model = value.model,
                    coords = value.coords,
                },
                onEnter = onEnterCowSpawnPoint,
            })
        end
    end

    setupFeedTarget(config.animalFeed.targetModels)
    setupCowTarget(field.cowLocations)
    setupFeedMarker()

    Utils.notify(locale("tasks.started"), "success")

    return true
end

function LivestockFarmingClient.stop()
    shared.debug("debug:livestock_farming.stop", "Stopping Livestock Farming Client")

    LivestockFarmingClient.clear()

    return true
end

RegisterNetEvent(_e("client:livestock_farming:onVehicleSpawned"), function(data)
    if not data or not data.key then
        return
    end

    client.currentTask.game.taskEntities[data.key] = data

    Citizen.CreateThread(function()
        local entity = lib.waitFor(function()
            if NetworkDoesEntityExistWithNetworkId(data.netId) then
                local ent = NetToVeh(data.netId)
                if DoesEntityExist(ent) then return ent end
            end
        end, false, false)

        MultiplayerTasksClient.giveVehicleKey(GetVehicleNumberPlateText(entity), entity)
    end)
end)

RegisterNetEvent(_e("client:livestock_farming:onCowSpawned"), function(data)
    if not data or not data.key then
        return
    end

    client.currentTask.game.taskEntities[data.key] = data
end)

RegisterNetEvent(_e("client:livestock_farming:onCowFed"), function(key, allCowFed)
    if not client.currentTask then return end
    if not key then return end

    client.currentTask.game.fedCowPoints[key] = true

    if allCowFed then
        Target.removeModel(config.animalFeed.targetModels)
        if state.carryingState.isCarrying then
            stopCarryingAnimation()
        end
    end
end)

lib.callback.register(_e("client:livestock_farming:playFeedAnimation"), function(data)
    local key, cowNetId = data.key, data.cowNetId
    local cowPed = lib.waitFor(function()
        if NetworkDoesEntityExistWithNetworkId(cowNetId) then
            local ent = NetToPed(cowNetId)
            if DoesEntityExist(ent) then return ent end
        end
    end, false, false)

    local haybaleNetId = nil
    local model = config.animalFeed.hold.model
    local boneCoords = GetWorldPositionOfEntityBone(cowPed, 24)

    lib.requestModel(model)
    local haybale = CreateObject(model, boneCoords.x, boneCoords.y, boneCoords.z, true, true, false)
    PlaceObjectOnGroundProperly(haybale)
    local haybaleCoords = GetEntityCoords(haybale)
    SetEntityCoords(haybale, haybaleCoords.x, haybaleCoords.y, haybaleCoords.z - 0.35)
    lib.playAnim(cowPed, "creatures@cow@amb@world_cow_grazing@base", "base", 8.0, -8.0, -1, 50, 0, false, false, false)

    haybaleNetId = lib.waitFor(function()
        if NetworkGetEntityIsNetworked(haybale) then
            local netId = ObjToNet(haybale)
            if NetworkDoesNetworkIdExist(netId) then
                return netId
            end
        else
            NetworkRegisterEntityAsNetworked(haybale)
        end
    end, false, false)

    SetModelAsNoLongerNeeded(model)

    return haybaleNetId
end)

if MultiplayerTasksClient and MultiplayerTasksClient.registerModuleState then
    MultiplayerTasksClient.registerModuleState("livestock_farming", LivestockFarmingClient, config)
end
