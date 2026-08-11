RegisterNUICallback("mdt/permissions/fetch", function(_, cb)
    local data = lib.callback.await("p_mdt/server/permissions/fetch", false)
    cb(data)
end)

RegisterNUICallback("mdt/permissions/update", function(data, cb)
    TriggerServerEvent("p_mdt/server/permissions/update", data)
    cb(1)
end)
