Charges = {}

RegisterNUICallback("mdt/charges/fetch", function(_, cb)
    local data = lib.callback.await("p_mdt/server/charges/fetch", false)
    cb(data)
end)

RegisterNUICallback("mdt/charges/createCategory", function(data, cb)
    TriggerServerEvent("p_mdt/server/charges/createCategory", data)
    cb(1)
end)

RegisterNUICallback("mdt/charges/createCharge", function(data, cb)
    local result = lib.callback.await("p_mdt/server/charges/createCharge", false, data)
    cb(result)
end)

RegisterNUICallback("mdt/charges/deleteCharge", function(data, cb)
    TriggerServerEvent("p_mdt/server/charges/deleteCharge", data)
    cb(1)
end)

RegisterNUICallback("mdt/charges/editCharge", function(data, cb)
    local result = lib.callback.await("p_mdt/server/charges/editCharge", false, data)
    cb(result)
end)

RegisterNUICallback("mdt/charges/deleteCategory", function(data, cb)
    TriggerServerEvent("p_mdt/server/charges/deleteCategory", data)
    cb(1)
end)
