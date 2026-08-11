if not Config or not Config.Prison or not Config.Prison.Enabled then
    return
end

function Prison.openManagement(self)
    if not self:hasJobAccess() then
        Bridge.Notify.showNotify(locale("no_access"), "error")
        return
    end

    local prisoners = lib.callback.await("p_policejob/server/prison/getAllPrisoners", false)

    SendNUIMessage({ action = "setVisiblePrisonManagement", data = true })
    SendNUIMessage({
        action = "setPrisonManagementData",
        data = {
            prisoners = prisoners or {},
            cells = (Prison.Map and Prison.Map.cells) or {},
            solitaryEnabled = Config.Prison.Solitary.enabled,
            solitaryMaxTime = Config.Prison.Solitary.maxTime,
            officerTasks = (Config.Prison.OfficerTasks and Config.Prison.OfficerTasks.enabled and Prison.getOfficerTasksForUI and Prison:getOfficerTasksForUI()) or {},
            activeOfficerTaskId = (Prison.getActiveOfficerTaskId and Prison:getActiveOfficerTaskId()) or nil,
        },
    })
    SetNuiFocus(true, true)
end

RegisterNUICallback("prison/management/close", function(_, cb)
    SendNUIMessage({ action = "setVisiblePrisonManagement", data = false })
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback("prison/management/release", function(data, cb)
    if not data or not data.identifier then
        cb({ success = false })
        return
    end
    TriggerServerEvent("p_policejob/server/prison/management/release", { identifier = data.identifier })
    cb({ success = true })
end)

RegisterNUICallback("prison/management/reduceSentence", function(data, cb)
    if not data or not data.identifier or not data.minutes then
        cb({ success = false })
        return
    end
    TriggerServerEvent("p_policejob/server/prison/management/reduceSentence", {
        identifier = data.identifier,
        minutes = tonumber(data.minutes) or 0,
    })
    cb({ success = true })
end)

RegisterNUICallback("prison/management/increaseSentence", function(data, cb)
    if not data or not data.identifier or not data.minutes then
        cb({ success = false })
        return
    end
    TriggerServerEvent("p_policejob/server/prison/management/increaseSentence", {
        identifier = data.identifier,
        minutes = tonumber(data.minutes) or 0,
    })
    cb({ success = true })
end)

RegisterNUICallback("prison/management/sendToSolitary", function(data, cb)
    if not data or not data.identifier then
        cb({ success = false })
        return
    end
    TriggerServerEvent("p_policejob/server/prison/management/solitary", {
        identifier = data.identifier,
        minutes = tonumber(data.minutes) or 15,
        release = false,
    })
    cb({ success = true })
end)

RegisterNUICallback("prison/management/releaseFromSolitary", function(data, cb)
    if not data or not data.identifier then
        cb({ success = false })
        return
    end
    TriggerServerEvent("p_policejob/server/prison/management/solitary", {
        identifier = data.identifier,
        release = true,
    })
    cb({ success = true })
end)

RegisterNUICallback("prison/management/moveToCell", function(data, cb)
    if not data or not data.identifier or not data.cellId then
        cb({ success = false })
        return
    end
    TriggerServerEvent("p_policejob/server/prison/management/moveToCell", {
        identifier = data.identifier,
        cellId = tonumber(data.cellId),
    })
    cb({ success = true })
end)

RegisterNUICallback("prison/management/refreshPrisoners", function(_, cb)
    local prisoners = lib.callback.await("p_policejob/server/prison/getAllPrisoners", false)
    cb({ prisoners = prisoners or {} })
end)

RegisterNUICallback("prison/management/releaseAllExpired", function(_, cb)
    TriggerServerEvent("p_policejob/server/prison/management/releaseAllExpired")
    cb({ success = true })
end)

RegisterNUICallback("prison/management/startOfficerTask", function(data, cb)
    if not data or not data.taskId then
        cb({ success = false })
        return
    end

    SendNUIMessage({ action = "setVisiblePrisonManagement", data = false })
    SetNuiFocus(false, false)

    local success = false
    if Prison.startOfficerTaskById then
        success = Prison:startOfficerTaskById(tostring(data.taskId)) or false
    end
    cb({ success = success })
end)

RegisterNUICallback("prison/management/cancelOfficerTask", function(_, cb)
    if Prison.cancelOfficerTask then
        Prison:cancelOfficerTask()
    end
    cb({ success = true })
end)

RegisterNetEvent("p_policejob/client/prison/openManagement", function()
    Prison:openManagement()
end)

exports("openPrisonManagement", function()
    Prison:openManagement()
end)

RegisterCommand("prisonmanagement", function()
    Prison:openManagement()
end, false)
