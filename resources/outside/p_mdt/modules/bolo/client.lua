Bolo = {}

RegisterNUICallback("mdt/bolo/fetch", function(_, cb)
    local data = lib.callback.await("p_mdt/server/bolo/fetch", false)
    cb(Base:sanitizeForNui(data, true) or {})
end)

RegisterNUICallback("mdt/bolo/create", function(data, cb)
    local result = lib.callback.await("p_mdt/server/bolo/create", false, data)
    cb(Base:sanitizeForNui(result) or {})
end)

RegisterNUICallback("mdt/bolo/changeStatus", function(data, cb)
    TriggerServerEvent("p_mdt/server/bolo/changeStatus", data)
    cb(1)
end)

RegisterNUICallback("mdt/bolo/delete", function(data, cb)
    TriggerServerEvent("p_mdt/server/bolo/delete", data)
    cb(1)
end)

RegisterNUICallback("mdt/bolo/edit", function(data, cb)
    TriggerServerEvent("p_mdt/server/bolo/edit", data)
    cb(1)
end)

RegisterNetEvent("p_mdt/bolo/client/createBolo", function(data)
    SendNUIMessage({
        action = "mdt/bolo/create",
        data = Base:sanitizeForNui(data) or {},
    })
end)

RegisterNetEvent("p_mdt/bolo/client/deleteBolo", function(data)
    if not data then
        return
    end
    SendNUIMessage({
        action = "mdt/bolo/remove",
        data = data,
    })
end)
