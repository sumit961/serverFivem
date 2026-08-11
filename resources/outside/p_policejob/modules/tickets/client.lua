if not Config.Tickets.enabled then
    return
end

Tickets = {
    isOpen = false,
}

function Tickets.open(self)
    if self.isOpen then
        return
    end
    local job = Bridge.Framework.fetchPlayerJob()
    if not job or not Config.Jobs[job.name] then
        Bridge.Notify.showNotify(locale("not_on_duty"), "error")
        return
    end
    local tickets = lib.callback.await("p_policejob/server/tickets/getTickets", false)
    if not tickets then
        return
    end
    self.isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "setTicketsConfig",
        data = {
            violations = Config.Tickets.violations,
            categories = Config.Tickets.categories,
        },
    })
    SendNUIMessage({
        action = "setTicketsData",
        data = tickets,
    })
    SendNUIMessage({
        action = "setVisibleTrafficTickets",
        data = true,
    })
end

function Tickets.close(self)
    if not self.isOpen then
        return
    end
    self.isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "setVisibleTrafficTickets",
        data = false,
    })
end

exports("openTickets", function()
    Tickets:open()
end)

exports("isTicketsOpen", function()
    return Tickets.isOpen
end)

RegisterCommand(Config.Tickets.command or "issueTicket", function()
    Tickets:open()
end, false)

RegisterNUICallback("hideFrame", function(data, cb)
    if data.name == "setVisibleTrafficTickets" then
        Tickets:close()
    end
    cb("ok")
end)

RegisterNUICallback("tickets/create", function(data, cb)
    if not Tickets.isOpen then
        return cb(nil)
    end
    cb(lib.callback.await("p_policejob/server/tickets/createTicket", false, data))
end)

RegisterNUICallback("tickets/delete", function(data, cb)
    if not Tickets.isOpen then
        return cb(false)
    end
    cb(lib.callback.await("p_policejob/server/tickets/deleteTicket", false, data.ticketId))
end)

RegisterNUICallback("tickets/markPaid", function(data, cb)
    if not Tickets.isOpen then
        return cb(false)
    end
    cb(lib.callback.await("p_policejob/server/tickets/markPaid", false, data.ticketId))
end)

RegisterNUICallback("tickets/getNearbyPlayers", function(_, cb)
    if not Tickets.isOpen then
        return cb({})
    end
    cb(lib.callback.await("p_policejob/server/tickets/getNearbyPlayers", false) or {})
end)

RegisterNUICallback("tickets/sendForSigning", function(data, cb)
    if not Tickets.isOpen then
        return cb(false)
    end
    local closestPlayer = lib.getClosestPlayer(
        GetEntityCoords(cache.ped),
        Config.Tickets.maxDistance,
        false
    )
    if not closestPlayer or closestPlayer == 0 then
        Bridge.Notify.showNotify(locale("ticket_no_nearby_player"), "error")
        return cb(false)
    end
    cb(lib.callback.await("p_policejob/server/tickets/sendForSigning", false, {
        ticketId = data.ticketId,
        targetId = GetPlayerServerId(closestPlayer),
    }))
end)

RegisterNetEvent("p_policejob/client/tickets/requestSign", function(data)
    if not data or not data.ticketId then
        return
    end
    SendNUIMessage({
        action = "setTicketSignRequest",
        data = data,
    })
    SetNuiFocus(true, true)
end)

RegisterNUICallback("tickets/sign", function(data, cb)
    TriggerServerEvent("p_policejob/server/tickets/signTicket", {
        ticketId = data.ticketId,
        signature = data.signature or nil,
    })
    SetNuiFocus(false, false)
    cb("ok")
end)

RegisterNetEvent("p_policejob/client/tickets/onSigned", function(data)
    if not data then
        return
    end
    SendNUIMessage({
        action = "ticketOnSigned",
        data = data,
    })
end)

RegisterNUICallback("tickets/refuse", function(data, cb)
    TriggerServerEvent("p_policejob/server/tickets/refuseTicket", {
        ticketId = data.ticketId,
    })
    SetNuiFocus(false, false)
    cb("ok")
end)
