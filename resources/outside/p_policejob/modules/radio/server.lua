if not Config.RadioList.Enabled then
    return
end

Radio = {}

local channelUsers = {}

function Radio.refreshChannel(channel)
    local users = channelUsers[channel] or {}
    for _, user in ipairs(users) do
        TriggerClientEvent("p_policejob/client_radio/refreshRadioChannels", user.player, channel, users)
    end
end

function Radio.removePlayerFromChannel(playerId, channel, refresh)
    local users = channelUsers[channel] or {}
    for index = 1, #users do
        if users[index].player == playerId then
            table.remove(users, index)
            Player(playerId).state.lastRadioChannel = 0
            if refresh then
                Radio.refreshChannel(channel)
            end
            break
        end
    end
end

RegisterNetEvent("pma-voice:setPlayerRadio", function(channel)
    local playerId = source
    local playerState = Player(playerId).state
    channel = tonumber(channel)
    TriggerClientEvent("p_policejob/client_radio/connectedChannel", playerId, channel)
    local previousChannel = tonumber(playerState.lastRadioChannel)
    if previousChannel and previousChannel ~= 0 and previousChannel ~= channel then
        Radio.removePlayerFromChannel(playerId, previousChannel, true)
    end
    if channel and channel ~= 0 then
        channelUsers[channel] = channelUsers[channel] or {}
        local alreadyListed = false
        for index = 1, #channelUsers[channel] do
            if channelUsers[channel][index].player == playerId then
                alreadyListed = true
                break
            end
        end
        if not alreadyListed then
            local uniqueId = Bridge.Framework.getUniqueId(playerId)
            local name = Bridge.Framework.getPlayerName(playerId)
            local badge = Config.RadioList.GetBadge(playerId, uniqueId)
            channelUsers[channel][#channelUsers[channel] + 1] = {
                name = name,
                badge = badge,
                talking = playerState.radioTalking and true or false,
                isDead = Editable:isPlayerDead(playerId),
                player = playerId,
            }
            playerState.lastRadioChannel = channel
            Radio.refreshChannel(channel)
        end
    end
end)

AddEventHandler("playerDropped", function()
    local playerId = source
    local playerState = Player(playerId).state
    if not playerState then
        return
    end
    local channel = tonumber(playerState.lastRadioChannel)
    if channel and channel ~= 0 then
        Radio.removePlayerFromChannel(playerId, channel, true)
    end
end)

AddStateBagChangeHandler("radioTalking", nil, function(bagName, _, value)
    local playerId = GetPlayerFromStateBagName(bagName)
    if playerId == 0 then
        return
    end
    local channel = tonumber(Player(playerId).state.lastRadioChannel)
    if not channel or not channelUsers[channel] then
        return
    end
    for _, user in ipairs(channelUsers[channel]) do
        if user.player == playerId then
            user.talking = value and true or false
            break
        end
    end
end)

function playerRadioDeath(playerId, isDead)
    local channel = Player(playerId).state.lastRadioChannel
    if not channel or channel == 0 then
        return
    end
    local users = channelUsers[channel]
    if not users then
        return
    end
    for index = 1, #users do
        if users[index].player == playerId then
            users[index].isDead = isDead
            for _, channelUser in ipairs(users) do
                TriggerClientEvent("p_policejob/client_radio/playerDead", channelUser.player, channel, playerId, isDead)
            end
            break
        end
    end
end

AddStateBagChangeHandler("isDead", nil, function(bagName, _, value)
    local playerId = GetPlayerFromStateBagName(bagName)
    if playerId == 0 then
        return
    end
    playerRadioDeath(playerId, value and true or false)
end)
