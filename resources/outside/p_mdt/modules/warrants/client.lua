RegisterNUICallback("mdt/warrants/fetch", function(_, cb)
    local data = lib.callback.await("p_mdt/server/warrants/fetch", false)
    cb(Base:sanitizeForNui(data, true) or {})
end)

RegisterNUICallback("mdt/warrants/search", function(data, cb)
    local results = lib.callback.await("p_mdt/server/warrants/search", false, data)
    cb(Base:sanitizeForNui(results) or {})
end)

RegisterNUICallback("mdt/warrants/create", function(data, cb)
    local result = lib.callback.await("p_mdt/server/warrants/create", false, data)
    cb(result)
end)

RegisterNUICallback("mdt/warrants/delete", function(data, cb)
    TriggerServerEvent("p_mdt/server/warrants/delete", data)
    cb(1)
end)
