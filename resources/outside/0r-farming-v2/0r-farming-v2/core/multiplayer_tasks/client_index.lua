local lib = lib
local Utils = require("modules.utils.client")

MultiplayerTasksClient = {}
MultiplayerTasksClient.modules = MultiplayerTasksClient.modules or {}
MultiplayerTasksClient.configs = MultiplayerTasksClient.configs or {}

local givedVehicleKeys = {}

function MultiplayerTasksClient.registerModuleState(moduleName, stateTable, configTable)
    configTable = configTable or {}
    configTable.moduleName = moduleName

    MultiplayerTasksClient.modules[moduleName] = stateTable
    MultiplayerTasksClient.configs[moduleName] = configTable
end

function MultiplayerTasksClient.getModuleState(moduleName)
    return MultiplayerTasksClient.modules[moduleName]
end

function MultiplayerTasksClient.getModuleConfig(moduleName)
    local data = MultiplayerTasksClient.configs[moduleName]
    if not data then
        return nil
    end

    return lib.table.deepclone(data)
end

function MultiplayerTasksClient.start(moduleName, data)
    local moduleState = MultiplayerTasksClient.getModuleState(moduleName)
    if not moduleState or not moduleState.start then
        local reason = "Module state for " .. moduleName .. " not found or does not have start function."
        lib.callback.await(_e("server:multiplayer_tasks:abort"), false, moduleName, client.lobby.id, reason)
        return false
    end

    client.currentTask = data

    local response = moduleState.start()
    if not response then
        local reason = "Module state for " .. moduleName .. " failed to start."
        lib.callback.await(_e("server:multiplayer_tasks:abort"), false, moduleName, client.lobby.id, reason)
        return false
    end

    return true
end

function MultiplayerTasksClient.stop(moduleName, force)
    local moduleState = MultiplayerTasksClient.getModuleState(moduleName)
    if not moduleState or not moduleState.stop then
        lib.print.error("Module state for " .. moduleName .. " not found or does not have stop function.")
        return false
    end

    local lastTask = lib.table.deepclone(client.currentTask or {})
    moduleState.stop()

    client.currentTask = nil
    client.exports.onTaskStopped(cache.serverId, lastTask)

    for key, value in pairs(givedVehicleKeys) do
        Utils.removeVehicleKey(value.plate, NetToVeh(value.netId))
    end
    givedVehicleKeys = {}

    return true
end

function MultiplayerTasksClient.onUnload()
    if not client.currentTask then return end

    MultiplayerTasksClient.stop(client.currentTask.moduleName, true)
end

function MultiplayerTasksClient.giveVehicleKey(plate, vehicle)
    if not plate or not vehicle then return end

    local keyData = {
        plate = plate,
        netId = VehToNet(vehicle),
    }

    table.insert(givedVehicleKeys, keyData)
    Utils.giveVehicleKey(plate, vehicle)
end

--events

RegisterNUICallback("nui:startMultiplayerTask", function(data, resultCallback)
    if client.currentTask then
        client.sendReactAlert(locale("tasks.party_already_in_task"), "error")
        resultCallback(false)
        return
    end

    local moduleName = data.moduleName
    local moduleState = MultiplayerTasksClient.getModuleState(moduleName)
    local moduleConfig = MultiplayerTasksClient.getModuleConfig(moduleName)

    if not moduleState or not moduleState.start then
        lib.print.error("Module state for " .. moduleName .. " not found or does not have start function.")
        resultCallback(false)
        return
    end

    local response = lib.callback.await(_e("server:multiplayer_tasks:start"), false, moduleName, client.lobby.id)
    if not response then
        client.sendReactAlert(locale("tasks.start_failed"), "error")
        resultCallback(false)
        return
    end

    if type(response) == "table" and response.error then
        client.sendReactAlert(response.error, "error")
        resultCallback(false)
        return
    end

    client.hideUI()

    resultCallback(true)
end)

RegisterNUICallback("nui:stopMultiplayerTask", function(_, resultCallback)
    if not client.currentTask then
        resultCallback(false)
        return
    end

    local moduleName = client.currentTask.moduleName
    local moduleState = MultiplayerTasksClient.getModuleState(moduleName)
    if not moduleState or not moduleState.stop then
        shared.debug("Module state for " .. moduleName .. " not found or does not have stop function.")
        resultCallback(false)
        return
    end

    local response = lib.callback.await(_e("server:multiplayer_tasks:stop"), false, moduleName, client.lobby.id)
    if not response then
        client.sendReactAlert(locale("tasks.stop_failed"), "error")
        resultCallback(false)
        return
    end

    if type(response) == "table" and response.error then
        client.sendReactAlert(response.error, "error")
        resultCallback(false)
        return
    end

    client.hideUI()

    resultCallback(true)
end)

RegisterNetEvent(_e("client:multiplayer_tasks:onTaskStarted"), function(moduleName, data)
    shared.debug("debug:client:multiplayer_tasks:onTaskStarted", moduleName)

    local response = MultiplayerTasksClient.start(moduleName, data)
    if not response then return end

    client.setInfoBoxDisabledState(false)
    client.sendReactMessage("ui:setCurrentTask", client.currentTask)
    client.sendReactMessage("ui:setInfoBox", { hidden = false, texts = client.currentTask.infoBoxTable })
    client.sendReactMessage("ui:setProgressBox", true)
end)

RegisterNetEvent(_e("client:multiplayer_tasks:onTaskStopped"), function(moduleName)
    shared.debug("debug:client:multiplayer_tasks:onTaskStopped", moduleName)
    MultiplayerTasksClient.stop(moduleName)

    client.setInfoBoxDisabledState(true)
    client.sendReactMessage("ui:setInfoBox", nil)
    client.sendReactMessage("ui:setCurrentTask", nil)
    client.sendReactMessage("ui:setProgressBox", false)
    Utils.notify(locale("tasks.stopped"), "success", 4000)
end)

RegisterNetEvent(_e("client:multiplayer_tasks:onTaskAborted"), function(moduleName, reason)
    shared.debug("debug:client:multiplayer_tasks:onTaskAborted", moduleName, reason)
    MultiplayerTasksClient.stop(moduleName, true)

    client.currentTask = nil

    client.setInfoBoxDisabledState(true)
    client.sendReactMessage("ui:setInfoBox", nil)
    client.sendReactMessage("ui:setCurrentTask", nil)
    client.sendReactMessage("ui:setProgressBox", false)

    Utils.notify(locale("tasks.stopped"), "success", 4000)
    if reason then Utils.notify(reason, "error", 4000) end
end)
