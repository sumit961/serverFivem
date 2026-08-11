Chat = {}

function Chat.sendMessage(self, content)
    TriggerServerEvent("p_mdt/server/chat/sendMessage", content)
end

RegisterNUICallback("mdt/chat/sendMessage", function(data, cb)
    Chat:sendMessage(data.content)
    cb(1)
end)

RegisterNetEvent("p_mdt/client/chat/newMessage", function(message)
    if not Base.tabletState then
        return
    end
    SendNUIMessage({
        action = "mdt/chat/newMessage",
        data = message,
    })
end)
