local lib = lib

MultiplayerTasksServer = {}
MultiplayerTasksServer.modules = MultiplayerTasksServer.modules or {}
MultiplayerTasksServer.configs = MultiplayerTasksServer.configs or {}

local activeJobTimeLimitThreads = {}

local cooldownPlayers = {}

-- Cooldown set etme fonksiyonu
local function setPlayerCooldownForTask(source, moduleName, durationInSeconds)
    shared.debug("debug:setPlayerCooldownForTask",
        ("source: %s, moduleName: %s, durationInSeconds: %s"):format(source, moduleName, durationInSeconds))

    if not cooldownPlayers[source] then
        cooldownPlayers[source] = {}
    end
    cooldownPlayers[source][moduleName] = os.time() + durationInSeconds
end

-- Cooldown kontrol fonksiyonu
local function isPlayerInCooldownForTask(source, moduleName)
    local playerCooldowns = cooldownPlayers[source]
    if not playerCooldowns then return false end

    local cooldownEndTime = playerCooldowns[moduleName]
    if not cooldownEndTime then return false end

    if os.time() >= cooldownEndTime then
        -- Süre dolmuşsa cooldown"u temizle
        cooldownPlayers[source][moduleName] = nil
        if next(cooldownPlayers[source]) == nil then
            cooldownPlayers[source] = nil
        end
        return false
    end

    return true
end

local function checkStepTimeoutThread(lobbyId)
    if activeJobTimeLimitThreads[lobbyId] then return end
    activeJobTimeLimitThreads[lobbyId] = true

    Citizen.CreateThread(function()
        while true do
            local lobby = Lobby.getLobbyById(lobbyId)
            if not lobby or not lobby.currentTask then
                break
            end
            local job = lobby.currentTask

            if not job or not job.moduleName then
                break
            end

            if not job.timeLimit then
                break
            end

            if not job.endTime then
                job.endTime = os.time() + job.timeLimit
            end

            if job.endTime <= os.time() then
                MultiplayerTasksServer.abort(nil, job.moduleName, lobbyId, locale("tasks.time_is_up"))
                break
            end

            lobby = Lobby.getLobbyById(lobbyId)
            if not lobby or not lobby.currentTask then
                break
            end

            Citizen.Wait(1000)
        end

        activeJobTimeLimitThreads[lobbyId] = nil
    end)
end

function MultiplayerTasksServer.registerModuleState(moduleName, stateTable, configTable)
    shared.debug("debug:MultiplayerTasksServer.registerModuleState",
        ("moduleName: %s"):format(moduleName))

    MultiplayerTasksServer.modules[moduleName] = stateTable
    MultiplayerTasksServer.configs[moduleName] = configTable
end

function MultiplayerTasksServer.getModuleState(moduleName)
    return MultiplayerTasksServer.modules[moduleName]
end

function MultiplayerTasksServer.getModuleConfig(moduleName)
    local data = MultiplayerTasksServer.configs[moduleName]
    if not data then
        return nil
    end
    return lib.table.deepclone(data)
end

---comment
---@param source? number
---@param moduleName string
---@param lobbyId number
---@param force boolean
---@return boolean
function MultiplayerTasksServer.stop(source, moduleName, lobbyId, force)
    shared.debug("debug:MultiplayerTasksServer.stop",
        ("source: %s, moduleName: %s, lobbyId: %s, force: %s"):format(source, moduleName, lobbyId, force))

    local moduleState = MultiplayerTasksServer.getModuleState(moduleName)
    if not moduleState or not moduleState.stop then
        lib.print.error("Module state for " .. moduleName .. " not found or does not have stop function.")
        return false
    end

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    local lastTask = lib.table.deepclone(lobby.currentTask or {})

    if not moduleState.stop(source, lobbyId, force) then return false end

    if not force then
        for _, member in pairs(lobby.members) do
            TriggerClientEvent(_e("client:multiplayer_tasks:onTaskStopped"), member.source, moduleName)
        end
    end

    lobby.currentTask = nil

    for _, member in pairs(lobby.members) do
        member.progress = 0
    end

    server.exports.onTaskStopped(lobby, lastTask)

    return true
end

function MultiplayerTasksServer.abort(source, moduleName, lobbyId, reason)
    shared.debug("debug:MultiplayerTasksServer.abort",
        ("source: %s, moduleName: %s, lobbyId: %s, reason: %s"):format(source, moduleName, lobbyId, reason))
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    local lastTask = lib.table.deepclone(lobby.currentTask or {})

    MultiplayerTasksServer.stop(source, moduleName, lobbyId, true)

    lobby.currentTask = nil

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:multiplayer_tasks:onTaskAborted"), member.source, moduleName, reason)
    end

    return true
end

function MultiplayerTasksServer.start(source, moduleName, lobbyId)
    shared.debug("debug:MultiplayerTasksServer.start",
        ("source: %s, moduleName: %s, lobbyId: %s"):format(source, moduleName, lobbyId))

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    local moduleState = MultiplayerTasksServer.getModuleState(moduleName)
    local moduleConfig = MultiplayerTasksServer.getModuleConfig(moduleName)

    lobby.currentTask = {
        moduleName = moduleName,
        startTime = os.time(),
        timeLimit = moduleConfig.timeLimit,
        infoBoxTable = moduleConfig.infoBoxTable or {},
        game = {},
    }

    if not server.exports.beforeTaskStart(lobby, lobby.currentTask) then
        return false
    end

    local moduleStartResponse = moduleState.start(source, lobbyId)
    if not moduleStartResponse then
        local reason = "Module state for " .. moduleName .. " failed to start."
        MultiplayerTasksServer.abort(source, moduleName, lobbyId, reason)
        return false
    end

    if type(moduleStartResponse) == "table" and moduleStartResponse.error then
        MultiplayerTasksServer.abort(source, moduleName, lobbyId, moduleStartResponse.error)
        return { error = moduleStartResponse.error }
    end

    for _, member in pairs(lobby.members) do
        Lobby.resetMemberProgress(lobbyId, member.source)
        TriggerClientEvent(_e("client:multiplayer_tasks:onTaskStarted"), member.source, moduleName, lobby.currentTask)
    end

    server.exports.onTaskStarted(lobby, lobby.currentTask)

    checkStepTimeoutThread(lobby.id)

    return true
end

function MultiplayerTasksServer.onUnload()
    shared.debug("debug:MultiplayerTasksServer.onUnload")
    local lobbies = Lobby.getAll()
    for _, lobby in pairs(lobbies) do
        if lobby.currentTask then
            MultiplayerTasksServer.stop(nil, lobby.currentTask.moduleName, lobby.id, true)
        end
    end
end

lib.callback.register(_e("server:multiplayer_tasks:start"), function(source, moduleName, lobbyId)
    local moduleState = MultiplayerTasksServer.getModuleState(moduleName)
    local moduleConfig = MultiplayerTasksServer.getModuleConfig(moduleName)

    if not moduleState or not moduleState.start then
        lib.print.error("Module state for " .. moduleName .. " not found or does not have start function.")
        return { error = "Module state not found or invalid." }
    end

    if not moduleConfig then
        lib.print.error("Module config for " .. moduleName .. " not found.")
        return { error = "Module config not found." }
    end

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then
        lobby = Lobby.create(source)
        TriggerClientEvent(_e("client:lobby:setPlayerLobby"), source, lobby)
    end

    if lobby.owner ~= source then
        return { error = locale("lobby.you_are_not_leader") }
    end
    if lobby.currentTask then
        return { error = locale("tasks.party_already_in_task") }
    end

    if moduleConfig.teamSize then
        if moduleConfig.teamSize.min and #lobby.members < moduleConfig.teamSize.min then
            return { error = locale("tasks.not_enough_players", moduleConfig.teamSize.min) }
        end
        if moduleConfig.teamSize.max and #lobby.members > moduleConfig.teamSize.max then
            return { error = locale("tasks.too_many_players", moduleConfig.teamSize.max) }
        end
    end

    for _, member in pairs(lobby.members) do
        if moduleConfig.requiredJobNames then
            if type(moduleConfig.requiredJobNames) == "string" then
                moduleConfig.requiredJobNames = { moduleConfig.requiredJobNames }
            end

            local xPlayerJob = server.getPlayerJob(member.source)
            if not moduleConfig.requiredJobNames[xPlayerJob.name] then
                local errorText = locale("lobby.member_doesnot_have_required_job", member.name,
                    table.concat(moduleConfig.requiredJobNames, ", "))
                return { error = errorText }
            end
        end

        if moduleConfig.requiredLevel and member.level < moduleConfig.requiredLevel then
            return { error = locale("lobby.member_doesnot_have_required_level", member.name, moduleConfig.requiredLevel) }
        end
        if isPlayerInCooldownForTask(member.source, moduleName) then
            return { error = locale("lobby.member_is_cooldown", member.name) }
        end
    end

    local response = MultiplayerTasksServer.start(source, moduleName, lobby.id)
    if not response then
        return false
    end

    if type(response) == "table" and response.error then
        return { error = response.error }
    end

    return true
end)

lib.callback.register(_e("server:multiplayer_tasks:abort"), function(source, moduleName, lobbyId, reason)
    return MultiplayerTasksServer.abort(source, moduleName, lobbyId, reason)
end)

lib.callback.register(_e("server:multiplayer_tasks:stop"), function(source, moduleName, lobbyId)
    if not moduleName or not lobbyId then
        lib.print.error("Module name or lobby ID is missing.")
        return false
    end

    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then
        lib.print.error("Lobby with ID " .. lobbyId .. " not found.")
        return false
    end

    if not lobby.currentTask then
        lib.print.error("Current task does not match the module name or is not set.")
        return false
    end

    if lobby.owner ~= source then
        lib.print.error("Only the lobby owner or an admin can stop the task.")
        return false
    end

    return MultiplayerTasksServer.stop(source, moduleName, lobbyId)
end)
