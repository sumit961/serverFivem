RegisterNUICallback("mdt/judgments/issue", function(data, cb)
    local result = lib.callback.await("p_mdt/server/judgments/issue", false, data)
    cb(result)
end)
