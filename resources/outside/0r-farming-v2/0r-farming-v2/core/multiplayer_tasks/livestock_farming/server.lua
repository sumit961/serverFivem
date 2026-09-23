local lib = lib
local config = lib.load("core.multiplayer_tasks.livestock_farming.config")
local Inventory = require "modules.inventory.server"

local moduleName = "livestock_farming"

local LivestockFarmingServer = {}

---@type table<fieldId, lobbyId>
local activeLivestockFields = {}

local function deleteNetworkedEntity(netIds)
    if (type(netIds) ~= "table") then
        netIds = { netIds }
    end
    if #netIds == 0 then return end
    for _, netId in ipairs(netIds) do
        local entity = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end
end

local function setLivestockFieldActive(fieldId, lobbyId, state)
    if not fieldId then
        return
    end
    if state == false then state = nil end

    activeLivestockFields[fieldId] = state and lobbyId or nil
end

local function getFreeLivestockField(lobbyId)
    for key, field in pairs(config.fields) do
        if activeLivestockFields[key] == nil then
            setLivestockFieldActive(key, lobbyId, true)
            return key, field
        end
    end
    return nil, nil
end

function LivestockFarmingServer.start(source, lobbyId)
    shared.debug("debug:LivestockFarmingServer.start", ("source: %s, lobbyId: %s"):format(source, lobbyId))

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    local freeFieldId, freeField = getFreeLivestockField(lobbyId)
    if not freeFieldId then
        shared.debug("debug:No free livestock field available for lobbyId:", lobbyId)
        return { error = locale("no_free_field") }
    end

    lobby.currentTask.game = {
        fieldId = freeFieldId,
        taskEntities = {},
        fedCowPoints = {},
        milkedCowPoints = {},
    }

    return true
end

function LivestockFarmingServer.stop(source, lobbyId, force)
    shared.debug("debug:LivestockFarmingServer.stop",
        ("source: %s, lobbyId: %s, force: %s"):format(source, lobbyId, force))
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end
    if lobby.currentTask then
        local networkedEntityIds = {}

        if lobby.currentTask.game.taskEntities then
            for _, entity in pairs(lobby.currentTask.game.taskEntities) do
                table.insert(networkedEntityIds, entity.netId)
            end
        end
        if #networkedEntityIds > 0 then
            deleteNetworkedEntity(networkedEntityIds)
        end
        if lobby.currentTask.game.fieldId then
            setLivestockFieldActive(lobby.currentTask.game.fieldId, lobbyId, false)
        end

        lobby.currentTask.game = {}
    end
    return true
end

lib.callback.register(_e("server:livestock_farming:onVehicleSpawned"), function(source, lobbyId, data)
    if not lobbyId then return false end
    if not data or not data.key or not data.model or not data.coords then
        shared.debug("debug:livestock_farming:Invalid data received for vehicle spawn:", data)
        return false
    end

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    if not lobby.currentTask then
        return false
    end

    if lobby.owner ~= source then
        return false
    end

    local taskEntities = lobby.currentTask.game.taskEntities
    if not taskEntities or taskEntities[data.key] then
        return false
    end

    taskEntities[data.key] = data

    shared.debug("debug:livestock_farming:Vehicle spawned:", data)

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:livestock_farming:onVehicleSpawned"), member.source, data)
    end

    return true
end)

lib.callback.register(_e("server:livestock_farming:onCowSpawned"), function(source, lobbyId, data)
    if not lobbyId then return false end
    if not data or not data.key or not data.model or not data.coords then
        shared.debug("debug:livestock_farming:Invalid data received for cow spawn:", data)
        return false
    end

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    if not lobby.currentTask then
        return false
    end

    if lobby.owner ~= source then
        return false
    end

    local taskEntities = lobby.currentTask.game.taskEntities
    if not taskEntities or taskEntities[data.key] then
        return false
    end

    taskEntities[data.key] = data

    shared.debug("debug:livestock_farming:Cow spawned:", data)

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:livestock_farming:onCowSpawned"), member.source, data)
    end

    return true
end)

lib.callback.register(_e('server:livestock_farming:feedCow'), function(source, lobbyId, key)
    if not lobbyId or not key then return false end

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    if not lobby.currentTask or not lobby.currentTask.game then
        return false
    end

    local cow = lobby.currentTask.game.taskEntities["cow_" .. key]
    if not cow then return false end

    lobby.currentTask.game.fedCowPoints = lobby.currentTask.game.fedCowPoints or {}
    lobby.currentTask.game.fedCowPoints[key] = true

    local cowPed = NetworkGetEntityFromNetworkId(cow.netId)
    if not DoesEntityExist(cowPed) then return false end
    local cowOwnerSource = NetworkGetEntityOwner(cowPed)

    local haybaleNetId = lib.callback.await(_e("client:livestock_farming:playFeedAnimation"), cowOwnerSource, {
        key = key,
        cowNetId = cow.netId,
    })
    if not haybaleNetId then
        shared.debug("debug:Failed to play feed animation for source:", cowOwnerSource)
        return
    end

    lobby.currentTask.game.taskEntities["haybale_" .. key] = { netId = haybaleNetId }
    lobby.currentTask.game.taskEntities["cow_" .. key].fedTime = os.time()

    local allCowFed = true
    for k, v in pairs(lobby.currentTask.game.taskEntities) do
        if string.find(k, "cow_") and v and not v.fedTime then
            allCowFed = false
            break
        end
    end

    for _, value in pairs(lobby.members) do
        TriggerClientEvent(_e("client:livestock_farming:onCowFed"), value.source, key, allCowFed)
    end

    PersonalChallengesServer.onFarmingActionTriggered(source, "cow", "fed")

    return true
end)

lib.callback.register(_e("server:livestock_farming:milkCow"), function(source, lobbyId, key)
    if not lobbyId or not key then return false end

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    if not lobby.currentTask or not lobby.currentTask.game then
        return false
    end

    local cow = lobby.currentTask.game.taskEntities["cow_" .. key]
    if not cow then
        return false
    end

    if not lobby.currentTask.game.fedCowPoints[key] then
        return false
    end

    if lobby.currentTask.game.milkedCowPoints[key] and
        lobby.currentTask.game.milkedCowPoints[key] >= config.animalFeed.maxMilkPerCow
    then
        return { error = locale("livestock_farming.cow_no_more_milk") }
    end

    local currentTime = os.time()
    local fedTime = cow.fedTime or os.time()
    local diffTime = currentTime - fedTime

    if diffTime < config.animalFeed.requiredFeedingTimeForMilk then
        return { error = locale("livestock_farming.cow_not_fed") }
    end

    if not lobby.currentTask.game.milkedCowPoints[key] then
        lobby.currentTask.game.milkedCowPoints[key] = 0
    end

    lobby.currentTask.game.milkedCowPoints[key] = lobby.currentTask.game.milkedCowPoints[key] + 1
    Lobby.incMemberProgress(lobbyId, source)
    PersonalChallengesServer.onFarmingActionTriggered(source, "cow", "milked")

    return true
end)

lib.callback.register(_e("server:livestock_farming:sellMilk"), function(source, lobbyId)
    if not lobbyId then return false end

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    if not lobby.currentTask or not lobby.currentTask.game then
        return false
    end

    local milkedCowCount = 0
    for _, value in pairs(lobby.currentTask.game.milkedCowPoints) do
        if value then
            milkedCowCount = milkedCowCount + value
        end
    end
    if milkedCowCount == 0 then
        return false
    end
    local milkBottleSalesPrice = math.random(
        config.milkBottleSalesPriceRange.min or 1,
        config.milkBottleSalesPriceRange.max or 1
    )

    if Config.CleanMoney.isItem then
        Inventory.giveItem(source, Config.CleanMoney.itemName, milkedCowCount * milkBottleSalesPrice)
    else
        server.playerAddMoney(source, Config.CleanMoney.accountName, milkedCowCount * milkBottleSalesPrice)
    end

    return true
end)

lib.callback.register(_e("server:livestock_farming:canCarryFeed"), function(source, lobbyId)
    if not lobbyId then return false end

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end
    if not lobby.currentTask or not lobby.currentTask.game then
        return false
    end

    local mayI = false
    for key, value in pairs(lobby.currentTask.game.taskEntities) do
        if string.find(key, "cow_") and value and not value.fedTime then
            mayI = true
            break
        end
    end

    return mayI
end)

-- State ana modüle kaydet
if MultiplayerTasksServer and MultiplayerTasksServer.registerModuleState then
    MultiplayerTasksServer.registerModuleState("livestock_farming", LivestockFarmingServer, config)
end
