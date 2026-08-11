RegisterNUICallback("mdt/employees/fetch", function(data, cb)
    local employees = lib.callback.await("p_mdt/server/employees/fetch", false)

    for _, employee in ipairs(employees or {}) do
        local location = locale("no_data")
        if employee.coords then
            local streetHash = GetStreetNameAtCoord(employee.coords.x, employee.coords.y, employee.coords.z)
            local streetName = GetStreetNameFromHashKey(streetHash)
            if streetName then
                location = streetName
            end
        end
        employee.location = location
    end

    cb(employees)
end)

RegisterNUICallback("mdt/employees/getNearbyPlayers", function(data, cb)
    cb(lib.callback.await("p_mdt/server/employees/getNearbyPlayers", false))
end)

RegisterNUICallback("mdt/employees/hire", function(data, cb)
    cb(lib.callback.await("p_mdt/server/employees/hire", false, data))
end)

RegisterNUICallback("mdt/employees/update", function(data, cb)
    cb(lib.callback.await("p_mdt/server/employees/update", false, data))
end)

CreateThread(function()
    while not lib do
        Wait(0)
    end

    lib.callback.register("p_mdt/client/employees/hireRequest", function(data)
        local response = lib.alertDialog({
            header = locale("employee_hire_request"),
            content = locale("employee_hire_request_desc", data.playerName, data.gradeLabel, data.jobLabel),
            centered = true,
            cancel = true,
        })
        return response == "confirm"
    end)
end)

RegisterNUICallback("mdt/employees/fire", function(data, cb)
    cb(lib.callback.await("p_mdt/server/employees/fire", false, data))
end)
