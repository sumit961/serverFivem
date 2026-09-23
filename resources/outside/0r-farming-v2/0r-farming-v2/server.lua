--[[ Main Server File]]

server = {
    framework = shared.getFrameworkObject(),
    load = false,
    exports = {},
}

--[[ require ]]

require "modules.bridge.init"
require "modules.exports.server"

local Inventory = require "modules.inventory.server"

AddEventHandler("onResourceStart", function(resource)
    if resource ~= shared.resource then return end

    Citizen.Wait(1000)

    if not Resmon or
        not Resmon.Lib or
        not Resmon.Lib.hasLicense or
        not Resmon.Lib.hasLicense("0r-farming-v2")
    then
        local reason = "YOU DO NOT HAVE \"0r_lib\" or YOU NEED TO UPDATE FROM KEYMASTER !"
        StopResource(shared.resource)
        lib.print.error(reason)
        error(("Resource %s stopped !"):format(shared.resource))
        return
    end

    Profile.loadDatabase()

    --[[ ok ]]
    server.load = true
    lib.versionCheck("alikocidev/docs_0resmon_farming_v2")
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= shared.resource then return end
    MultiplayerTasksServer.onUnload()
end)

--[[ fuctions ]]

local function onPlayerDropped(source)
    local playerLobbyId = Lobby.isPlayerInAnyLobby(source)
    if playerLobbyId then
        local lobby = Lobby.getLobbyById(playerLobbyId)
        if lobby.currentTask and lobby.owner == source then
            MultiplayerTasksServer.abort(
                source,
                lobby.currentTask.moduleName,
                playerLobbyId,
                locale("lobby.leader_leave_game")
            )
        end
        Lobby.leave(playerLobbyId, source)
    end
    PersonalChallengesServer.onPlayerUnloaded(source)
end

if Config.FarmingMenu.openWithItem and Config.FarmingMenu.openWithItem.active then
    server.createUseableItem(Config.FarmingMenu.openWithItem.itemName, function(source)
        TriggerClientEvent("0r-farming-v2:client:openMenu", source)
    end)
end

--[[ events ]]

lib.callback.register(_e("server:inventory:getPlayerInventory"), function(source)
    local playerInventory = Inventory.getInventory(source)
    for slot, value in pairs(playerInventory) do
        if value then
            if not value.count then value.count = value.amount or 1 end
        end
    end

    return { items = playerInventory }
end)

lib.callback.register(_e("server:inventory:hasRequiredItem"), function(source, itemName, amount)
    return Inventory.hasItem(source, itemName, amount)
end)

lib.callback.register(_e("server:inventory:removeItem"), function(source, itemName, amount)
    return Inventory.removeItem(source, itemName, amount)
end)

-- Event handler triggered when a player logout
RegisterNetEvent(_e("server:onPlayerLogout"), function()
    local source = source
    onPlayerDropped(source)
end)

-- Event handler triggered when a player dropped.
AddEventHandler("playerDropped", function()
    local source = source
    onPlayerDropped(source)
end)
