Lobby = {}

---@type table<string, Lobby>
local Lobbies = {}
local lastLobbyIndex = "0"

local function incrementStringNumber(str)
    local carry = 1
    local result = ""
    for i = #str, 1, -1 do
        local digit = tonumber(str:sub(i, i))
        local newDigit = digit + carry
        if newDigit >= 10 then
            newDigit = 0
            carry = 1
        else
            carry = 0
        end
        result = tostring(newDigit) .. result
    end
    if carry == 1 then
        result = "1" .. result
    end
    return result
end

function Lobby.getLobbyById(lobbyId)
    return lobbyId and Lobbies[lobbyId] or false
end

function Lobby.isPlayerFree(source)
    for _, lobby in pairs(Lobbies) do
        for _, member in pairs(lobby.members) do
            if member.source == source then
                return false
            end
        end
    end
    return true
end

function Lobby.updateMembers(lobbyId, exceptSource)
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end
    for _, member in pairs(lobby.members) do
        if member.source ~= exceptSource then
            TriggerClientEvent(_e("client:lobby:updateLobbyMembers"), member.source, lobby.members)
        end
    end
    return true
end

function Lobby.updateData(lobbyId)
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    if #lobby.members < 1 then
        return Lobby.delete(lobby.id)
    end

    if not lobby.owner then
        lobby.owner = lobby.members[1].source
    end

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:lobby:setPlayerLobby"), member.source, lobby)
    end

    return true
end

function Lobby.create(owner)
    if type(owner) == "number" then
        local ownerSource = owner
        local xOwnerProfile = Profile.getBySource(ownerSource)
        owner = {
            source = ownerSource,
            level = xOwnerProfile.level,
            name = server.getPlayerCharacterName(ownerSource),
            progress = 0
        }
    end

    lastLobbyIndex = incrementStringNumber(lastLobbyIndex)
    Lobbies[lastLobbyIndex] = {
        id = lastLobbyIndex,
        members = { owner },
        owner = owner.source,
        name = owner.name,
        progress = owner.progress
    }

    return Lobbies[lastLobbyIndex]
end

function Lobby.join(lobbyId, member)
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return { error = locale("lobby.lobby_not_found") } end
    if lobby.currentTask then return { error = locale("lobby.on_mission") } end
    if #lobby.members >= 4 then return { error = locale("lobby.lobby_is_full") } end
    if not Lobby.isPlayerFree(member.source) then
        Lobby.leaveInternal(lobbyId, member.source)
    end

    table.insert(lobby.members, member)

    local share = math.floor((100 / #lobby.members) * 10) / 10
    for _, m in pairs(lobby.members) do
        m.share = share
    end

    TriggerClientEvent(_e("client:lobby:setPlayerLobby"), member.source, lobby)
    Lobby.updateMembers(lobbyId, member.source)
    return {}
end

function Lobby.leaveInternal(lobbyId, source)
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    for i, member in pairs(lobby.members) do
        if member.source == source then
            table.remove(lobby.members, i)
            if lobby.owner == source then
                lobby.owner = nil
            end
            return Lobby.updateData(lobbyId)
        end
    end
    return false
end

function Lobby.leave(lobbyId, source)
    return Lobby.leaveInternal(lobbyId, source)
end

function Lobby.delete(lobbyId)
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end

    for _, member in pairs(lobby.members) do
        TriggerClientEvent(_e("client:lobby:setPlayerLobby"), member.source, nil)
    end

    Lobbies[lobbyId] = nil
    return true
end

function Lobby.isPlayerInLobby(lobbyId, source)
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end
    for _, member in pairs(lobby.members) do
        if member.source == source then
            return true
        end
    end
    return false
end

function Lobby.isPlayerInAnyLobby(source)
    for id, lobby in pairs(Lobbies) do
        for _, member in pairs(lobby.members) do
            if member.source == source then
                return id
            end
        end
    end
    return false
end

function Lobby.getAll()
    return Lobbies
end

function Lobby.invite(lobbyId, ownerSource, targetSource)
    if ownerSource == targetSource then
        return { error = locale("lobby.player_not_available") }
    end
    local xTargetPlayer = server.getPlayer(targetSource)
    if not xTargetPlayer then
        return { error = locale("lobby.player_not_available") }
    end
    local xTargetPlayerLobbyId = Lobby.isPlayerInAnyLobby(targetSource)
    if xTargetPlayerLobbyId then
        local xTargetLobby = Lobby.getLobbyById(xTargetPlayerLobbyId)
        if xTargetLobby and xTargetLobby.currentTask then
            return { error = locale("lobby.on_mission") }
        end
    end
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then
        local xOwnerProfile = Profile.getBySource(ownerSource)
        lobby = Lobby.create({
            source = ownerSource,
            level = xOwnerProfile.level,
            name = server.getPlayerCharacterName(ownerSource),
            progress = 0
        })
        TriggerClientEvent(_e("client:lobby:setPlayerLobby"), ownerSource, lobby)
    end
    local ownerName = server.getPlayerCharacterName(ownerSource)
    TriggerClientEvent(_e("client:lobby:receiveLobbyInvite"), targetSource, lobby.id, ownerName)
    return {}
end

function Lobby.incMemberProgress(lobbyId, source, amount)
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end
    if not amount then
        amount = 1
    end

    for _, member in pairs(lobby.members) do
        if member.source == source then
            member.progress = member.progress + amount
            return Lobby.updateData(lobbyId)
        end
    end
    return false
end

function Lobby.resetMemberProgress(lobbyId, source)
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then return false end
    for _, member in pairs(lobby.members) do
        if member.source == source then
            member.progress = 0
            return Lobby.updateData(lobbyId)
        end
    end
    return false
end

lib.callback.register(_e("server:lobby:invite"), function(source, lobbyId, targetSourceId)
    return Lobby.invite(lobbyId, source, targetSourceId)
end)

lib.callback.register(_e("server:lobby:fireMember"), function(source, lobbyId, targetSourceId)
    local lobby = Lobby.getLobbyById(lobbyId)
    if not lobby then
        return { error = locale("lobby.lobby_not_found") }
    end

    local isSelfKick = source == targetSourceId
    local isLeader = lobby.owner == source

    if isSelfKick or isLeader then
        Lobby.leave(lobbyId, targetSourceId)

        if isSelfKick then
            TriggerClientEvent(_e("client:lobby:setPlayerLobby"), source, nil)
        else
            Lobby.updateMembers(lobbyId)
            TriggerClientEvent(_e("client:lobby:setPlayerLobby"), targetSourceId, nil)
        end

        return {}
    end

    return { error = locale("lobby.you_are_not_leader") }
end)

lib.callback.register(_e("server:lobby:join"), function(source, lobbyId)
    local xPlayerProfile = Profile.getBySource(source)
    if not xPlayerProfile then
        xPlayerProfile = Profile.create(source)
    end
    return Lobby.join(lobbyId, {
        source = source,
        level = xPlayerProfile.level,
        name = server.getPlayerCharacterName(source),
        progress = 0
    })
end)
