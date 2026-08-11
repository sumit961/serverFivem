RegisterNUICallback("mdt/incidents/create", function(data, cb)
    local incident = lib.callback.await("p_mdt/server/incidents/create", false, data)
    cb(Base:sanitizeForNui(incident) or {})
end)

RegisterNUICallback("mdt/incidents/fetch", function(data, cb)
    local incidents = lib.callback.await("p_mdt/server/incidents/fetch", false)
    cb(Base:sanitizeForNui(incidents, true) or {})
end)

RegisterNUICallback("mdt/incidents/search", function(data, cb)
    local incidents = lib.callback.await("p_mdt/server/incidents/search", false, data)
    cb(Base:sanitizeForNui(incidents) or {})
end)

RegisterNUICallback("mdt/incidents/update", function(data, cb)
    lib.callback.await("p_mdt/server/incidents/edit", false, data)
    cb(1)
end)

RegisterNUICallback("mdt/incidents/delete", function(data, cb)
    TriggerServerEvent("p_mdt/server/incidents/delete", data.id)
    cb(1)
end)

RegisterNUICallback("mdt/incidents/close", function(data, cb)
    TriggerServerEvent("p_mdt/server/incidents/close", data.id)
    cb(1)
end)
