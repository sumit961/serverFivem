local lib = lib
local config = lib.load("core.multiplayer_tasks.freelance.config")
local Inventory = require "modules.inventory.server"

local moduleName = "freelance"

local FreelanceServer = {}

--- Point states for farming
local POINT_STATES <const> = {
    EMPTY = "empty",
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
    if not fieldId or not getFieldById(fieldId) then
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
    local spacing = 5.0                      -- Her nokta arası mesafe
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

    -- Obje durumu yönetimi
    local networkId = lobby.currentTask.game.pointObjectNetIds[data.pointIndex]
    if data.newState == POINT_STATES.WATERED then
        local objectOwner = nil
        if networkId then
            objectOwner = NetworkGetEntityOwner(NetworkGetEntityFromNetworkId(networkId))
        end
        if objectOwner then
            TriggerClientEvent(_e("client:freelance:playWateringEffect"), objectOwner, {
                pointIndex = data.pointIndex,
                cropName = data.cropName,
                networkId = networkId,
                newState = data.newState,
                lobbyId = lobbyId,
            })
        end
    elseif data.newState == POINT_STATES.GROWN then
        local objectOwner = nil
        if networkId then
            objectOwner = NetworkGetEntityOwner(NetworkGetEntityFromNetworkId(networkId))
        end
        if objectOwner then
            TriggerClientEvent(_e("client:freelance:playGrowthEffect"), objectOwner, {
                pointIndex = data.pointIndex,
                cropName = data.cropName,
                networkId = networkId,
                newState = data.newState,
                lobbyId = lobbyId,
            })
        end
    elseif data.newState == POINT_STATES.HARVESTED then
        Lobby.incMemberProgress(lobbyId, playerId)

        -- Harvest durumunda objeyi sil
        local pointObjectNetId = lobby.currentTask.game.pointObjectNetIds[data.pointIndex]
        if pointObjectNetId then
            deleteNetworkedEntity(pointObjectNetId)
            lobby.currentTask.game.pointObjectNetIds[data.pointIndex] = nil
        end

        lobby.currentTask.game.harvesterState.grainLevel =
            math.min(100, lobby.currentTask.game.harvesterState.grainLevel + 2)
        lobby.currentTask.game.harvesterState.harvestedBaleState.harvestedCount =
            lobby.currentTask.game.harvesterState.harvestedBaleState.harvestedCount + 1

        if lobby.currentTask.game.harvesterState.harvestedBaleState.harvestedCount % 8 == 0 then
            if data.cropName then
                local response = lib.callback.await(
                    _e("client:freelance:spawnHarvestedBale"), playerId,
                    { lobbyId = lobbyId, pointIndex = data.pointIndex, cropName = data.cropName })
                if response then
                    meta.harvestedBale = {
                        netId = response.netId,
                        coords = response.coords
                    }
                    lobby.currentTask.game.harvesterState.harvestedBaleState.createdBales[data.pointIndex] = {
                        netId = response.netId,
                        cropName = data.cropName,
                    }
                end
            end
        end

        meta.grainLevel = lobby.currentTask.game.harvesterState.grainLevel

        plantingPoint = { coords = plantingPoint.coords }
    end

    PersonalChallengesServer.onFarmingActionTriggered(playerId, data.cropName, data.newState)

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:freelance:onPlantingPointUpdate"), member.source, {
            playerId = playerId,
            lobbyId = lobbyId,
            pointIndex = data.pointIndex,
            cropName = data.cropName,
            newState = data.newState,
            networkId = networkId,
            meta = meta,
        })
    end

    shared.debug("debug:FreelanceServer.updatePlantingPointState",
        ("playerId: %s, lobbyId: %s, pointIndex: %s, cropName: %s, newState: %s"):format(
            playerId, lobbyId, data.pointIndex, data.cropName, data.newState),
        lobby.currentTask.game.plantingPoints[data.pointIndex])
end

function FreelanceServer.start(source, lobbyId)
    shared.debug("debug:FreelanceServer.start", ("source: %s, lobbyId: %s"):format(source, lobbyId))

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    local freeFieldId, freeField = getFreeFarmingField(lobbyId)
    if not freeFieldId then
        shared.debug(("debug:No free farming field available for lobbyId: %s"):format(lobbyId), "error")
        return { error = locale("no_free_field") }
    end

    lobby.currentTask.game = {
        fieldId = freeFieldId,
        taskEntities = {
            tractor   = {},
            seeder    = {},
            harvester = {},
            trailer   = {},
        },
        plantingPoints = createPlantingPoints(freeField),
        harvesterState = {
            grainLevel = 0,
            lastGrainUnloadingStartTime = nil,
            harvestedBaleState = {
                harvestedCount = 0,
                loadedCount = 0,
                attachedBales = {},
                createdBales = {},
            },
        },
        pointObjectNetIds = {}, -- NetworkId'leri saklayacağız
    }

    return true
end

function FreelanceServer.stop(source, lobbyId, force)
    shared.debug("debug:FreelanceServer.stop", ("source: %s, lobbyId: %s, force: %s"):format(source, lobbyId, force))
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end
    if lobby.currentTask then
        local networkedEntityIds = {}
        if lobby.currentTask.game.taskEntities then
            for _, taskEntity in pairs(lobby.currentTask.game.taskEntities) do
                for _, entity in pairs(taskEntity) do
                    if entity.spawned and entity.netId then
                        table.insert(networkedEntityIds, entity.netId)
                    end
                end
            end
        end
        if lobby.currentTask.game.harvesterState and
            lobby.currentTask.game.harvesterState.harvestedBaleState and
            lobby.currentTask.game.harvesterState.harvestedBaleState.attachedBales
        then
            for _, attachedBaleData in pairs(lobby.currentTask.game.harvesterState.harvestedBaleState.attachedBales or {}) do
                table.insert(networkedEntityIds, attachedBaleData.netId)
            end
        end
        if lobby.currentTask.game.harvesterState and
            lobby.currentTask.game.harvesterState.harvestedBaleState and
            lobby.currentTask.game.harvesterState.harvestedBaleState.createdBales
        then
            for _, harvestedBaleData in pairs(lobby.currentTask.game.harvesterState.harvestedBaleState.createdBales or {}) do
                table.insert(networkedEntityIds, harvestedBaleData.netId)
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

lib.callback.register(_e("server:freelance:onVehicleSpawned"), function(source, lobbyId, entityState)
    if not entityState or not entityState.key or not entityState.index then
        shared.debug("debug:FreelanceServer.onVehicleSpawned - Invalid entityState",
            ("source: %s, lobbyId: %s, entityState: %s"):format(source, lobbyId, json.encode(entityState)), "error")
        return false
    end

    shared.debug("debug:FreelanceServer.onVehicleSpawned",
        ("source: %s, lobbyId: %s, key: %s"):format(source, lobbyId, entityState.key))

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    if not lobby.currentTask or
        not lobby.currentTask.game or
        not lobby.currentTask.game.fieldId
    then
        return { error = locale("tasks.no_active_task") }
    end

    if lobby.owner ~= source then
        shared.debug("debug:FreelanceServer.onVehicleSpawned - Unauthorized access",
            ("source: %s, lobbyId: %s, key: %s"):format(source, lobbyId, entityState.key), "error")
        return false
    end

    local taskEntities = lobby.currentTask.game.taskEntities
    if taskEntities[entityState.key] then
        taskEntities[entityState.key][entityState.index] = entityState
    end

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:freelance:onVehicleSpawned"), member.source, entityState)
    end

    return true
end)

lib.callback.register(_e("server:freelance:dropHarvestedBale"), function(source, data)
    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(data.lobbyId, source) then
        return { error = locale("lobby.not_in_lobby") }
    end

    if lobby.currentTask.game.harvesterState.harvestedBaleState.loadedCount == 0 then
        return { error = locale("freelance.trailer_empty") }
    end

    local xPlayerCoords = GetEntityCoords(GetPlayerPed(source))
    local dropHarvestedBaleCoords = getFieldById(lobby.currentTask.game.fieldId).dropHarvestedBaleCoords
    local distance = #(xPlayerCoords - vector3(dropHarvestedBaleCoords))
    if distance > 15.0 then
    end

    local attachedHarvestedBales = lobby.currentTask.game.harvesterState.harvestedBaleState.attachedBales
    local harvestedBaleNetIds = {}
    for _, harvestedBaleData in pairs(attachedHarvestedBales) do
        table.insert(harvestedBaleNetIds, harvestedBaleData.netId)
    end
    deleteNetworkedEntity(harvestedBaleNetIds)

    for _, value in pairs(attachedHarvestedBales) do
        local cropName = value.cropName
        local configCrop = config.crops[cropName]
        local harvestAmount = configCrop and configCrop.harvestAmount or 1
        local harvestItem = configCrop and configCrop.harvestItem
        if harvestItem then
            Inventory.giveItem(source, harvestItem, harvestAmount)
        end
    end

    lobby.currentTask.game.harvesterState.harvestedBaleState.attachedBales = {}
    lobby.currentTask.game.harvesterState.harvestedBaleState.loadedCount = 0

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:freelance:onHarvestedBaleDropped"), member.source, {
            lobbyId = data.lobbyId,
        })
    end

    return true
end)

RegisterNetEvent(_e("server:freelance:onPlantingPointStateChanged"), function(data)
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

    shared.debug("debug:FreelanceServer.onPlantingPointStateChanged",
        ("source: %s, lobbyId: %s, pointIndex: %s, state: %s"):format(source, data.lobbyId, data.pointIndex,
            data.newState))
end)

RegisterNetEvent(_e("server:freelance:onHarvestedBalePickedUp"), function(data)
    local source = source

    if not data or not data.lobbyId or not data.pointIndex then
        return
    end

    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(data.lobbyId, source) then
        return
    end

    local pointHarvestedBale = lobby.currentTask.game.harvesterState.harvestedBaleState.createdBales[data.pointIndex]
    if pointHarvestedBale then
        deleteNetworkedEntity({ pointHarvestedBale.netId })
    end

    for _, member in pairs(lobby.members) do
        if member.source ~= source then
            TriggerClientEvent(_e("client:freelance:onHarvestedBalePickedUp"), member.source, data)
        end
    end
end)

RegisterNetEvent(_e("server:freelance:loadHarvestedBaleToTrailer"), function(data)
    local source = source

    if not data or not data.lobbyId or not data.trailerNetId then
        return
    end

    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(data.lobbyId, source) then
        return
    end

    local trailer = NetworkGetEntityFromNetworkId(data.trailerNetId)
    if not DoesEntityExist(trailer) then
        return
    end

    local trailerOwner = NetworkGetEntityOwner(trailer)
    if not trailerOwner or trailerOwner == 0 then
        return
    end

    local plantingPoint = lobby.currentTask.game.plantingPoints[data.pointIndex]

    lobby.currentTask.game.harvesterState.harvestedBaleState.loadedCount =
        lobby.currentTask.game.harvesterState.harvestedBaleState.loadedCount + 1

    local harvestedBaleNetId = lib.callback.await(_e("client:freelance:attachHarvestedBaleToTrailer"), trailerOwner, {
        lobbyId = data.lobbyId,
        trailerNetId = data.trailerNetId,
        loadedCount = lobby.currentTask.game.harvesterState.harvestedBaleState.loadedCount,
        cropName = plantingPoint.cropName,
    })
    if not harvestedBaleNetId then
        return
    end

    table.insert(lobby.currentTask.game.harvesterState.harvestedBaleState.attachedBales, {
        netId = harvestedBaleNetId,
        cropName = plantingPoint.cropName,
    })

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:freelance:onHarvestedBaleAttached"), member.source, {
            lobbyId = data.lobbyId,
            harvestedBaleNetId = harvestedBaleNetId,
            trailerNetId = data.trailerNetId,
            loadedCount = lobby.currentTask.game.harvesterState.harvestedBaleState.loadedCount
        })
    end
end)

lib.callback.register(_e("server:freelance:onGrainUnloadingStarted"), function(source, lobbyId)
    if not lobbyId then
        return false
    end

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then
        return false
    end

    if not lobby.currentTask or
        not lobby.currentTask.game or
        not lobby.currentTask.game.harvesterState then
        return false
    end

    if lobby.currentTask.game.harvesterState.grainLevel <= 0 then
        return false
    end

    if not lobby.currentTask.game.harvesterState.lastGrainUnloadingStartTime then
        lobby.currentTask.game.harvesterState.lastGrainUnloadingStartTime = os.time()
    end

    return true
end)

lib.callback.register(_e("server:freelance:onGrainUnloadingStopped"), function(source, lobbyId)
    if not lobbyId then
        return false
    end

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then
        return false
    end

    if not lobby.currentTask or
        not lobby.currentTask.game or
        not lobby.currentTask.game.harvesterState then
        return false
    end

    lobby.currentTask.game.harvesterState.lastGrainUnloadingStartTime = nil

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:freelance:onGrainLevelChanged"), member.source, {
            lobbyId = lobbyId,
            grainLevel = lobby.currentTask.game.harvesterState.grainLevel,
        })
    end

    return true
end)

RegisterNetEvent(_e("server:freelance:fetchGrainLevel"), function(data)
    if not data or not data.lobbyId then
        return
    end

    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby then
        return
    end

    if lobby.currentTask.game.harvesterState.lastGrainUnloadingStartTime then
        lobby.currentTask.game.harvesterState.grainLevel =
            math.max(0, lobby.currentTask.game.harvesterState.grainLevel - 1)
    end

    for _, member in pairs(lobby.members) do
        local grainLevel = lobby.currentTask.game.harvesterState.grainLevel
        TriggerClientEvent(_e("client:freelance:onGrainLevelChanged"), member.source, {
            lobbyId = data.lobbyId,
            grainLevel = grainLevel,
        })
    end
end)

RegisterNetEvent(_e("server:freelance:onSeederCropSelected"), function(data)
    local source = source

    if not data or not data.lobbyId or not data.cropName then
        return
    end

    local lobby = Lobby.getLobbyById(data.lobbyId)
    if not lobby or not Lobby.isPlayerInLobby(data.lobbyId, source) then
        return
    end

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:freelance:onSeederCropSelected"), member.source, {
            lobbyId = data.lobbyId,
            cropName = data.cropName,
        })
    end
end)

-- Point objesi kaydı
lib.callback.register(_e("server:freelance:registerPointObject"), function(source, data)
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

    -- NetworkId'yi sakla
    lobby.currentTask.game.pointObjectNetIds[data.pointIndex] = data.networkId

    shared.debug("debug:FreelanceServer.registerPointObject",
        ("pointIndex: %s, networkId: %s, cropName: %s"):format(
            data.pointIndex, data.networkId, data.cropName))
end)

-- Point objesi silme
RegisterNetEvent(_e("server:freelance:deletePointObject"), function(data)
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

        shared.debug("debug:FreelanceServer.deletePointObject",
            ("pointIndex: %s, networkId: %s"):format(data.pointIndex, pointObjectNetId))
    end
end)

-- State ana modüle kaydet
if MultiplayerTasksServer and MultiplayerTasksServer.registerModuleState then
    MultiplayerTasksServer.registerModuleState("freelance", FreelanceServer, config)
end
