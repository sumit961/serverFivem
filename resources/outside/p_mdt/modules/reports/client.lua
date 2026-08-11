RegisterNUICallback("mdt/reports/fetch", function(data, cb)
    local reports = lib.callback.await("p_mdt/server/reports/fetch", false, data)
    cb(Base:sanitizeForNui(reports) or {})
end)

RegisterNUICallback("mdt/reports/save", function(data, cb)
    local reports = lib.callback.await("p_mdt/server/reports/save", false, data)
    cb(Base:sanitizeForNui(reports) or {})
end)

RegisterNUICallback("mdt/reports/fetchEmployees", function(data, cb)
    local employees = lib.callback.await("p_mdt/server/reports/fetchEmployees", false, data.query)
    cb(Base:sanitizeForNui(employees) or {})
end)

RegisterNUICallback("mdt/reports/delete", function(data, cb)
    TriggerServerEvent("p_mdt/server/reports/delete", data.id)
    cb(1)
end)
