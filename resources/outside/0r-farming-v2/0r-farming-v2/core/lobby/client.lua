Lobby = {}

local Utils = require "modules.utils.client"

Lobby.isIn = function()
    return client.lobby.id ~= nil
end

RegisterNUICallback("nui:lobby:hireTeamMember", function(targetSourceId, resultCallback)
    local response = lib.callback.await(_e("server:lobby:invite"), false, client.lobby.id, targetSourceId)
    if response.error then
        client.sendReactAlert(response.error, "error")
        return resultCallback(false)
    end
    client.sendReactAlert(locale("lobby.invited_player"), "success")
    resultCallback(true)
end)

RegisterNUICallback("nui:lobby:fireTeamMember", function(targetSourceId, resultCallback)
    local response = lib.callback.await(_e("server:lobby:fireMember"), false, client.lobby.id, targetSourceId)
    if response.error then
        client.sendReactAlert(response.error, "error")
        return resultCallback(false)
    end
    resultCallback(true)
end)

RegisterNetEvent(_e("client:lobby:setPlayerLobby"), function(newLobby)
    if not newLobby then
        client.lobby = {}
    else
        client.lobby = newLobby
    end

    client.sendReactMessage("ui:setLobby", newLobby)
end)

RegisterNetEvent(_e("client:lobby:receiveLobbyInvite"), function(lobbyId, ownerName)
    if client.currentTask then return end

    client.sendReactMessage("ui:inviteReceived", { lobbyId = lobbyId, ownerName = ownerName })
    if not client.uiOpen then SetNuiFocus(true, true) end
end)

RegisterNUICallback("nui:lobby:acceptJoinInvite", function(lobbyId, resultCallback)
    local response = lib.callback.await(_e("server:lobby:join"), false, lobbyId)
    if response.error then
        if not client.uiOpen then
            client.hideUI()
            Utils.notify(response.error, "error")
        else
            client.sendReactAlert(response.error, "error")
        end
        return resultCallback(false)
    end
    client.sendReactAlert(locale("lobby.joined_lobby"), "success")
    if not client.uiOpen then
        client.hideUI()
    end
    resultCallback(true)
end)

RegisterNUICallback("nui:lobby:onInviteModalClosed", function(_, resultCallback)
    if not client.uiOpen then
        client.hideUI()
    end
    resultCallback(true)
end)

RegisterNetEvent(_e("client:lobby:updateLobbyMembers"), function(newMembers)
    client.lobby.members = newMembers
    client.sendReactMessage("ui:setLobbyMembers", newMembers)
end)
