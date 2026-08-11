Applications = {
    jobName = nil,
}

RegisterNUICallback("mdt/applications/fetch", function(data, cb)
    local job = Bridge.Framework.fetchPlayerJob()
    cb(lib.callback.await("p_mdt/server/application/getApplications", false, job and job.name))
end)

RegisterNUICallback("mdt/applications/getQuestions", function(data, cb)
    local job = Bridge.Framework.fetchPlayerJob()
    cb(lib.callback.await("p_mdt/server/applications/getQuestions", false, job and job.name))
end)

RegisterNUICallback("mdt/applications/saveQuestions", function(data, cb)
    TriggerServerEvent("p_mdt/server/applications/saveQuestions", data)
    cb(1)
end)

function Applications.open(self, jobName, pointConfig)
    local questions = lib.callback.await("p_mdt/server/applications/getQuestions", false, jobName)

    if not questions or #questions == 0 then
        Bridge.Notify.showNotify(locale("applications_no_questions"), "error")
        return
    end

    self.jobName = jobName
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "setVisibleApplication", data = true })
    SendNUIMessage({
        action = "setApplication",
        data = {
            questions = questions or {},
            title = pointConfig.title,
            subtitle = pointConfig.subtitle,
        },
    })
end

function Applications.close(self)
    self.jobName = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "setVisibleApplication", data = false })
end

RegisterNUICallback("hideFrame", function(data, cb)
    if data.name == "setVisibleApplication" then
        Applications:close()
    end
end)

CreateThread(function()
    while not Config or not Config.Applications do
        Wait(100)
    end

    while not Bridge or not Bridge.Target do
        Wait(0)
    end

    if not Config.Applications.enabled then
        return
    end

    for jobName, pointConfig in pairs(Config.Applications.points) do
        for _, coords in ipairs(pointConfig.coords) do
            Bridge.Target.addSphereZone({
                coords = coords,
                radius = 1.0,
                options = {
                    {
                        label = locale("open_application"),
                        icon = "fas fa-file-alt",
                        distance = 2.5,
                        onSelect = function()
                            Applications:open(jobName, pointConfig)
                        end,
                    },
                },
            })
        end
    end
end)

RegisterNUICallback("mdt/applications/submit", function(data, cb)
    if not Applications.jobName then
        cb(1)
        return
    end

    data.job = Applications.jobName
    TriggerServerEvent("p_mdt/server/applications/submit", data)
    Applications:close()
    cb(1)
end)

RegisterNUICallback("mdt/applications/review", function(data, cb)
    cb(lib.callback.await("p_mdt/server/applications/review", false, data))
end)
