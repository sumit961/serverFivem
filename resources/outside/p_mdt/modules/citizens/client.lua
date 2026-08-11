Citizens = {}

RegisterNUICallback("mdt/citizens/search", function(data, cb)
    cb(lib.callback.await("p_mdt/server/citizens/search", false, data))
end)

RegisterNUICallback("mdt/citizens/getProfile", function(data, cb)
    local profile = lib.callback.await("p_mdt/server/citizens/getProfile", false, data)

    if profile and profile.vehicles then
        profile.vehicles = Vehicles:sort(profile.vehicles)
    end

    if profile and profile.properties then
        profile.properties = Properties:sort(profile.properties)
    end

    cb(profile)
end)

RegisterNUICallback("mdt/citizen/createNote", function(data, cb)
    TriggerServerEvent("p_mdt/server/citizens/createNote", data)
    cb(1)
end)

RegisterNUICallback("mdt/citizen/deleteNote", function(data, cb)
    TriggerServerEvent("p_mdt/server/citizens/deleteNote", data)
    cb(1)
end)

RegisterNUICallback("mdt/citizen/changeAvatar", function(data, cb)
    TriggerServerEvent("p_mdt/server/citizens/changeAvatar", data)
    cb(1)
end)

RegisterNUICallback("mdt/citizens/deleteLicense", function(data, cb)
    TriggerServerEvent("p_mdt/server/citizens/deleteLicense", data)
    cb(1)
end)

RegisterNUICallback("mdt/citizens/removeJudgment", function(data, cb)
    TriggerServerEvent("p_mdt/server/citizens/removeJudgment", data)
    cb(1)
end)

RegisterNUICallback("mdt/citizen/addLicense", function(data, cb)
    TriggerServerEvent("p_mdt/server/citizens/addLicense", data)
    cb(1)
end)
