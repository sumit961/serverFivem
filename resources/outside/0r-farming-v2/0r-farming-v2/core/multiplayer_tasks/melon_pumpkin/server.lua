local lib = lib
local config = lib.load("core.multiplayer_tasks.melon_pumpkin.config")
local Inventory = require "modules.inventory.server"

local moduleName = "melon_pumpkin"

local MelonPumpkinServer = {}

--- Point states for farming
local POINT_STATES <const> = {
    EMPTY = "empty",
    RAKED = "raked",
    PLANTED = "planted",
    WATERED = "watered",
    GROWN = "grown",
    HARVESTED = "harvested"
}

---@type table<fieldId, lobbyId>
local activeFarmingFields = {
    -- Example structure:
    -- [1] = 123, -- Field ID 1 is active in lobby 123
}

--- Get the field data by ID
--- @param fieldId string|number
--- @return table|nil
local function getFieldById(fieldId)
    return config.fields[fieldId]
end

local function deleteNetworkedEntity(netIds)
    if (type(netIds) ~= "table") then
        netIds = { netIds }
    end
    if #netIds == 0 then return false end
    for _, netId in ipairs(netIds) do
        local entity = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end
    return true
end

local function setFarmingFieldActive(fieldId, lobbyId, state)
    if not fieldId then
        return
    end
    if state == false then state = nil end
    activeFarmingFields[fieldId] = state and lobbyId or nil
end

local function getFreeFarmingField(lobbyId)
    for fieldId, field in pairs(config.fields) do
        if activeFarmingFields[fieldId] == nil then
            setFarmingFieldActive(fieldId, lobbyId, true)
            return fieldId, field
        end
    end
    return nil, nil
end

local function createPlantingPoints(field)
    ---@type table<number, PlantingPoint>
    local plantingPoints = {}
    local center = field.center
    local radius = field.radius or 50        -- Varsayılan olarak 50 kullan
    local spacing = 3.0                      -- Her nokta arası mesafe
    local rotation = math.rad(field.rotation or 0)
    local maxPoints = field.maxPoints or 100 -- Her field için maksimum nokta sayısı

    -- İlk nokta merkez
    plantingPoints[#plantingPoints + 1] = {
        coords = vector3(center.x, center.y, center.z),
    }

    -- Maksimum nokta sayısına ulaştıysak dur
    if #plantingPoints >= maxPoints then
        return plantingPoints
    end

    -- Merkez etrafında katmanlar halinde genişle
    local layer = 1

    while layer * spacing <= radius and #plantingPoints < maxPoints do
        -- Her katman için Y koordinatları
        for yOffset = -layer, layer do
            if #plantingPoints >= maxPoints then break end

            local y = yOffset * spacing

            -- Bu Y seviyesinde X koordinatları
            local xRange = layer
            for xOffset = -xRange, xRange do
                if #plantingPoints >= maxPoints then break end

                local x = xOffset * spacing

                -- Merkez noktasını tekrar ekleme
                if x == 0 and y == 0 then
                    goto continue
                end

                -- Bu katmanın dış kenarında mı kontrol et
                if math.abs(x) == layer * spacing or math.abs(y) == layer * spacing then
                    -- Rotation uygula
                    local rotatedX = x * math.cos(rotation) - y * math.sin(rotation)
                    local rotatedY = x * math.sin(rotation) + y * math.cos(rotation)

                    -- Final koordinatlar
                    local finalX = center.x + rotatedX
                    local finalY = center.y + rotatedY

                    -- Merkeze olan mesafeyi kontrol et (daire içinde kalması için)
                    local distance = math.sqrt(rotatedX ^ 2 + rotatedY ^ 2)

                    if distance <= radius then
                        plantingPoints[#plantingPoints + 1] = {
                            coords = vector3(finalX, finalY, center.z),
                        }
                    end
                end

                ::continue::
            end
        end

        layer = layer + 1
    end

    return plantingPoints
end

local function updatePlantingPointState(playerId, lobbyId, data)
    local lobby = Lobby.getLobbyById(lobbyId)

    local meta = {}

    local plantingPoint = lobby.currentTask.game.plantingPoints[data.pointIndex]

    if data.newState then
        plantingPoint.state = data.newState
    end
    if data.cropName then
        plantingPoint.cropName = data.cropName
    end

    local networkId = lobby.currentTask.game.pointObjectNetIds[data.pointIndex]
    if data.newState == POINT_STATES.HARVESTED then
        Lobby.incMemberProgress(lobbyId, playerId)

        local pointObjectNetId = lobby.currentTask.game.pointObjectNetIds[data.pointIndex]
        if pointObjectNetId then
            deleteNetworkedEntity(pointObjectNetId)
            lobby.currentTask.game.pointObjectNetIds[data.pointIndex] = nil
        end
    elseif data.newState == POINT_STATES.WATERED then
        local objectOwner = nil
        if networkId then
            objectOwner = NetworkGetEntityOwner(NetworkGetEntityFromNetworkId(networkId))
        end
        if objectOwner then
            TriggerClientEvent(_e("client:melon_pumpkin:playWateringEffect"), objectOwner, {
                lobbyId = lobbyId,
                pointIndex = data.pointIndex,
                cropName = data.cropName,
                networkId = networkId,
            })
        end
    elseif data.newState == POINT_STATES.GROWN then
        local objectOwner = nil
        if networkId then
            objectOwner = NetworkGetEntityOwner(NetworkGetEntityFromNetworkId(networkId))
        end
        if objectOwner then
            TriggerClientEvent(_e("client:melon_pumpkin:playGrowthEffect"), objectOwner, {
                lobbyId = lobbyId,
                pointIndex = data.pointIndex,
                cropName = data.cropName,
                networkId = networkId,
                newState = data.newState,
            })
        end
    end

    PersonalChallengesServer.onFarmingActionTriggered(playerId, data.cropName, data.newState)

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:melon_pumpkin:onPlantingPointUpdate"), member.source, {
            playerId = playerId,
            lobbyId = lobbyId,
            pointIndex = data.pointIndex,
            cropName = data.cropName,
            newState = data.newState,
            networkId = networkId,
            meta = meta,
        })
    end

    shared.debug("debug:MelonPumpkinServer.updatePlantingPointState",
        ("playerId: %s, lobbyId: %s, pointIndex: %s, cropName: %s, newState: %s"):format(
            playerId, lobbyId, data.pointIndex, data.cropName, data.newState),
        lobby.currentTask.game.plantingPoints[data.pointIndex])
end

function MelonPumpkinServer.start(source, lobbyId)
    shared.debug("debug:MelonPumpkinServer.start", ("source: %s, lobbyId: %s"):format(source, lobbyId))

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    local freeFieldId, freeField = getFreeFarmingField(lobbyId)
    if not freeFieldId then
        shared.debug(("debug:No free farming field available for lobbyId: %s"):format(lobbyId), "error")
        return { error = locale("no_free_field") }
    end

    lobby.currentTask.game = {
        fieldId = freeFieldId,
        taskEntities = {},
        plantingPoints = createPlantingPoints(freeField),
        harvestedCropState = {
            harvestedPoints = {},
            loadedCount = 0,
            objectsInDeliveryVehicle = {},
        },
        pointObjectNetIds = {},
        selectedCropName = nil
    }

    return true
end

function MelonPumpkinServer.stop(source, lobbyId, force)
    shared.debug("debug:MelonPumpkinServer.stop", ("source: %s, lobbyId: %s, force: %s"):format(source, lobbyId, force))
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end
    if lobby.currentTask then
        local networkedEntityIds = {}
        if lobby.currentTask.game.taskEntities then
            for _, entity in pairs(lobby.currentTask.game.taskEntities or {}) do
                if entity.spawned and entity.netId then
                    table.insert(networkedEntityIds, entity.netId)
                end
            end
        end
        if lobby.currentTask.game.harvestedCropState and
            lobby.currentTask.game.harvestedCropState.objectsInDeliveryVehicle
        then
            for _, value in pairs(lobby.currentTask.game.harvestedCropState.objectsInDeliveryVehicle) do
                table.insert(networkedEntityIds, value)
            end
        end

        -- Point objelerini de sil
        if lobby.currentTask.game.pointObjectNetIds then
            for _, pointObjectNetId in pairs(lobby.currentTask.game.pointObjectNetIds) do
                table.insert(networkedEntityIds, pointObjectNetId)
            end
        end
        if #networkedEntityIds > 0 then
            deleteNetworkedEntity(networkedEntityIds)
        end
        if lobby.currentTask.game.fieldId then
            setFarmingFieldActive(lobby.currentTask.game.fieldId, lobbyId, false)
        end

        lobby.currentTask.game = {}
    end
    return true
end

--[[ Event Handlers ]]

lib.callback.register(_e("server:melon_pumpkin:onVehicleSpawned"), function(source, lobbyId, entityState)
    if not entityState or not entityState.key then
        shared.debug("debug:MelonPumpkinServer.onVehicleSpawned - Invalid entityState",
            ("source: %s, lobbyId: %s, entityState: %s"):format(source, lobbyId, json.encode(entityState)), "error")
        return false
    end

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    if not lobby.currentTask or
        not lobby.currentTask.game or
        not lobby.currentTask.game.fieldId
    then
        return { error = locale("tasks.no_active_task") }
    end

    if lobby.owner ~= source then
        shared.debug("debug:MelonPumpkinServer.onVehicleSpawned - Unauthorized access",
            ("source: %s, lobbyId: %s, key: %s"):format(source, lobbyId, entityState.key), "error")
        return false
    end

    local taskEntities = lobby.currentTask.game.taskEntities
    if taskEntities[entityState.key] then
        return false
    end
    taskEntities[entityState.key] = entityState
    shared.debug("debug:MelonPumpkinServer.onVehicleSpawned",
        ("source: %s, lobbyId: %s, key: %s"):format(source, lobbyId, entityState.key))

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:melon_pumpkin:onVehicleSpawned"), member.source, entityState)
    end

    return true
end)

lib.callback.register(_e("server:melon_pumpkin:onSellNpcInteraction"), function(source, data)
    if not data or not data.lobbyId then
        shared.debug("debug:MelonPumpkinServer.onSellNpcInteraction - Invalid data",
            ("source: %s, lobbyId: %s"):format(source, data.lobbyId), "error")
        return false
    end

    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(data.lobbyId, source) then
        shared.debug(("Player not in lobby or lobby not found: %s, %s"):format(source, data.lobbyId), "error")
        return false
    end

    local cropName = lobby.currentTask.game.selectedCropName
    if not cropName then
        shared.debug(("Crop name not found for lobbyId: %s, crop: %s"):format(data.lobbyId, cropName), "error")
        return false
    end

    local cropPrice = config.crops[cropName].sellPrice
    if not cropPrice then
        shared.debug(("Crop not found: %s"):format(cropName), "error")
        return false
    end

    local loadedCount = lobby.currentTask.game.harvestedCropState.loadedCount
    if loadedCount < 1 then
        shared.debug(("No crops loaded for lobbyId: %s"):format(data.lobbyId), "error")
        return { error = locale("melon_pumpkin.no_crops_loaded") }
    end

    local totalPayment = cropPrice * loadedCount

    if Config.CleanMoney.isItem then
        local itemName = Config.CleanMoney.itemName
        Inventory.giveItem(source, itemName, totalPayment)
    else
        local accountName = Config.CleanMoney.accountName
        server.playerAddMoney(source, accountName, totalPayment)
    end

    local objectsInDeliveryVehicle = lobby.currentTask.game.harvestedCropState.objectsInDeliveryVehicle
    deleteNetworkedEntity(objectsInDeliveryVehicle)
    lobby.currentTask.game.harvestedCropState.objectsInDeliveryVehicle = {}

    return true
end)

RegisterNetEvent(_e("server:melon_pumpkin:onPlantingPointStateChanged"), function(data)
    local source = source
    if not data or not data.lobbyId or not data.pointIndex or not data.newState then
        shared.debug(
            ("Invalid point state update data from source: %s, lobbyId: %s, pointIndex: %s, state: %s"):format(source,
                data.lobbyId, data.pointIndex, data.newState), "error")
        return
    end

    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(data.lobbyId, source) then
        shared.debug(("Player not in lobby or lobby not found: %s, %s"):format(source, data.lobbyId), "error")
        return
    end
    if not lobby.currentTask then
        shared.debug(("Lobby current task not found for lobbyId: %s"):format(lobbyId), "error")
        return
    end

    updatePlantingPointState(source, data.lobbyId, data)

    shared.debug("debug:MelonPumpkinServer.onPlantingPointStateChanged",
        ("source: %s, lobbyId: %s, pointIndex: %s, state: %s"):format(source, data.lobbyId, data.pointIndex,
            data.newState))
end)

RegisterNetEvent(_e("server:melon_pumpkin:loadHarvestedCropToDeliveryVehicle"), function(data)
    local source = source

    if not data or not data.lobbyId or not data.deliveryVehicleNetId then
        return
    end

    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(data.lobbyId, source) then
        return
    end

    local deliveryVehicle = NetworkGetEntityFromNetworkId(data.deliveryVehicleNetId)
    if not DoesEntityExist(deliveryVehicle) then
        return
    end

    lobby.currentTask.game.harvestedCropState.loadedCount =
        lobby.currentTask.game.harvestedCropState.loadedCount + 1

    local deliveryVehicleOwner = NetworkGetEntityOwner(deliveryVehicle)
    if not deliveryVehicleOwner or deliveryVehicleOwner == 0 then return end

    lib.callback(_e("server:melon_pumpkin:spawnObjectInDeliveryVehicle"), deliveryVehicleOwner, function(objectNetId)
        shared.debug("debug:MelonPumpkinServer.loadHarvestedCropToDeliveryVehicle", objectNetId)
        if not objectNetId then
            return
        end
        table.insert(lobby.currentTask.game.harvestedCropState.objectsInDeliveryVehicle, objectNetId)
    end, {
        deliveryVehicleNetId = data.deliveryVehicleNetId,
        cropName = data.cropName,
        loadedCount = lobby.currentTask.game.harvestedCropState.loadedCount,
    })
end)

RegisterNetEvent(_e("server:melon_pumpkin:onHarvestedCropPickedUp"), function(data)
    if not data.pointIndex or not data.lobbyId then
        shared.debug("debug:MelonPumpkinServer.onHarvestedCropPickedUp - Invalid data",
            ("pointIndex: %s, lobbyId: %s"):format(data.pointIndex, data.lobbyId), "error")
        return
    end

    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(data.lobbyId, source) then
        return
    end

    local point = lobby.currentTask.game.plantingPoints[data.pointIndex]
    if not point then
        return
    end

    if point.state == POINT_STATES.HARVESTED then
        return
    end

    if lobby.currentTask.game.harvestedCropState.harvestedPoints[data.pointIndex] then
        return
    end

    lobby.currentTask.game.harvestedCropState.harvestedPoints[data.pointIndex] = true

    for key, value in pairs(lobby.members) do
        TriggerClientEvent(_e("client:melon_pumpkin:onHarvestedCropPickedUp"), value.source, data)
    end
end)

RegisterNetEvent(_e("server:melon_pumpkin:onCropSelected"), function(data)
    local source = source
    if not data or not data.lobbyId or not data.cropName then
        return
    end

    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(data.lobbyId, source) then
        return
    end

    lobby.currentTask.game.selectedCropName = data.cropName

    for _, member in pairs(lobby.members) do
        if member.source ~= source then
            TriggerClientEvent(_e("client:melon_pumpkin:onCropSelected"), member.source, {
                cropName = lobby.currentTask.game.selectedCropName
            })
        end
    end
end)

-- Point objesi kaydı
lib.callback.register(_e("server:melon_pumpkin:registerPointObject"), function(source, data)
    local source = source
    if not data or not data.lobbyId or not data.pointIndex or not data.networkId then
        return
    end

    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(data.lobbyId, source) then
        return
    end

    if not lobby.currentTask or not lobby.currentTask.game then
        return
    end

    lobby.currentTask.game.pointObjectNetIds[data.pointIndex] = data.networkId

    shared.debug("debug:MelonPumpkinServer.registerPointObject",
        ("pointIndex: %s, networkId: %s, cropName: %s"):format(
            data.pointIndex, data.networkId, data.cropName))
end)

RegisterNetEvent(_e("server:melon_pumpkin:deletePointObject"), function(data)
    local source = source
    if not data or not data.lobbyId or not data.pointIndex then
        return
    end

    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(data.lobbyId, source) then
        return
    end

    if not lobby.currentTask or not lobby.currentTask.game then
        return
    end

    local pointObjectNetId = lobby.currentTask.game.pointObjectNetIds[data.pointIndex]
    if pointObjectNetId then
        deleteNetworkedEntity(pointObjectNetId)
        lobby.currentTask.game.pointObjectNetIds[data.pointIndex] = nil

        shared.debug("debug:MelonPumpkinServer.deletePointObject",
            ("pointIndex: %s, networkId: %s"):format(data.pointIndex, pointObjectNetId))
    end
end)

lib.callback.register(_e("server:melon_pumpkin:canHarvestCrop"), function(source, data)
    if not data or not data.lobbyId or not data.pointIndex then
        return false
    end

    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(data.lobbyId, source) then
        return false
    end

    local point = lobby.currentTask.game.plantingPoints[data.pointIndex]
    if not point then
        return false
    end

    -- Aynı anda birden fazla alma ve tekrar alma kontrolü
    if point.state ~= POINT_STATES.GROWN then
        return false
    end

    if lobby.currentTask.game.harvestedCropState.harvestedPoints[data.pointIndex] then
        return false
    end

    if point._isBeingHarvested then
        return false
    end

    point._isBeingHarvested = true

    return true
end)

lib.callback.register(_e("server:melon_pumpkin:canPlantCrop"), function(source, params)
    if not params or not params.lobbyId or not params.pointIndex then
        return false
    end

    local lobby = Lobby.getLobbyById(params.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(params.lobbyId, source) then
        return false
    end

    local point = lobby.currentTask.game.plantingPoints[params.pointIndex]
    if not point then
        return false
    end

    if point.state ~= POINT_STATES.RAKED then
        return false
    end
    if point._isBeingPlanted then
        return false
    end

    point._isBeingPlanted = true

    return true
end)

-- State ana modüle kaydet
if MultiplayerTasksServer and MultiplayerTasksServer.registerModuleState then
    MultiplayerTasksServer.registerModuleState("melon_pumpkin", MelonPumpkinServer, config)
end
