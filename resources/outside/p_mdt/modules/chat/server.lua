Chat = {
    messages = {},
}

RegisterNetEvent("p_mdt/server/chat/sendMessage", function(content)
    local playerSource = source
    local uniqueId = Bridge.Framework.getUniqueId(playerSource)
    local message = {
        player = uniqueId,
        name = Bridge.Framework.getPlayerName(playerSource),
        text = content,
        timestamp = os.time() * 1000,
        avatar = Base.playersData[uniqueId] and Base.playersData[uniqueId].avatar or nil,
    }
    table.insert(Chat.messages, message)
    TriggerClientEvent("p_mdt/client/chat/newMessage", -1, message)
end)
