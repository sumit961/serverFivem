while not Config or not Config.Dispatch do
    Wait(100)
end

if Config.Dispatch.disableDispatch then
    return
end

Dispatch = {
    alerts = {},
    units = {},
}

local validPriorities = {
    low = true,
    medium = true,
    high = true,
}

function Dispatch.new(self, alertData)
    if not alertData.coords then
        lib.print.error(("Alert is missing coords, invoker resource: %s"):format(GetInvokingResource() or "unknown"))
        return
    end

    if not alertData.title then
        lib.print.error(("Alert is missing a title, invoker resource: %s"):format(GetInvokingResource() or "unknown"))
        return
    end

    if not alertData.priority then
        alertData.priority = "low"
    end

    if not validPriorities[alertData.priority] then
        alertData.priority = "low"
    end

    local coords = {
        x = alertData.coords.x or 0.0,
        y = alertData.coords.y or 0.0,
    }

    local alertId = #self.alerts + 1
    local alert = {
        id = alertId,
        priority = alertData.priority,
        code = alertData.code or nil,
        title = alertData.title,
        description = alertData.description or nil,
        location = {
            coords = coords,
            street = alertData.street or nil,
        },
        info = alertData.fields or {},
        blip = alertData.blip or nil,
        alertTime = alertData.alertTime or 180,
        sound = alertData.sound or nil,
        image = alertData.image or nil,
        timeout = alertData.timeout or 5000,
        timestamp = os.time(),
        units = {},
        jobs = alertData.jobs or nil,
    }

    table.insert(self.alerts, alert)

    local recipients = {}
    for _, playerId in ipairs(GetPlayers()) do
        local job = Bridge.Framework.getPlayerJob(tonumber(playerId))
        if job then
            if not alertData.jobs then
                if Config.Departments[job.name] then
                    recipients[#recipients + 1] = tonumber(playerId)
                end
            elseif type(alertData.jobs) == "string" then
                if job.name == alertData.jobs then
                    recipients[#recipients + 1] = tonumber(playerId)
                end
            elseif type(alertData.jobs) == "table" then
                for _, allowedJob in ipairs(alertData.jobs) do
                    if job.name == allowedJob then
                        recipients[#recipients + 1] = tonumber(playerId)
                        break
                    end
                end
            end
        end
    end

    for _, playerId in ipairs(recipients) do
        TriggerClientEvent("p_mdt/client/dispatch/notification", playerId, alert, {
            calls = self.alerts,
            units = self.units,
        })
    end

    if Bridge and Bridge.Logs and Bridge.Logs.Send and alertData.playerId then
        Bridge.Logs.Send(
            alertData.playerId,
            "Dispatch",
            ("Player with ID %s created an alert"):format(alertData.playerId),
            DISCORD_WEBHOOK
        )
    end

    return alertId
end

exports("CreateAlert", function(alertData)
    Dispatch:new(alertData)
end)

RegisterNetEvent("p_mdt/createAlert", function(alertData)
    if Config.Dispatch.disableClientExport then
        return
    end
    alertData.playerId = source
    Dispatch:new(alertData)
end)

function Dispatch.initLoop(self)
    CreateThread(function()
        while true do
            Wait(5000)
            for index, alert in pairs(self.alerts) do
                local expiresAt = alert.timestamp + (alert.alertTime or 180)
                if expiresAt <= os.time() and #alert.units < 1 then
                    table.remove(self.alerts, index)
                end
            end
        end
    end)
end

Dispatch:initLoop()

function Dispatch.accept(self, source, alertId)
    if not alertId then
        return
    end

    if not Config.Dispatch.allowJoiningMultipleAlerts then
        local playerState = Player(source).state
        local hasActiveAlert = false
        for _, active in pairs(playerState.currentAlerts or {}) do
            if active then
                hasActiveAlert = true
                break
            end
        end

        if hasActiveAlert then
            Bridge.Notify.showNotify(source, locale("already_active_alert"), "error")
            return
        end
    end

    for _, alert in pairs(self.alerts) do
        if alert.id == alertId then
            local isSupervisor = Config.Dispatch.supervisorRole and #alert.units < 1

            table.insert(alert.units, {
                id = source,
                identifier = Bridge.Framework.getUniqueId(source),
                name = Bridge.Framework.getPlayerName(source),
                supervisor = isSupervisor,
            })

            local playerState = Player(source).state
            if not playerState.currentAlerts then
                playerState.currentAlerts = {}
            end
            playerState.currentAlerts[alertId] = true
            playerState:set("currentAlerts", playerState.currentAlerts, true)

            TriggerClientEvent("p_mdt/client/dispatch/refresh", -1, {
                calls = Dispatch.alerts,
                units = Dispatch.units,
            })
            TriggerClientEvent("p_mdt/client/dispatch/markAlert", source, alert.location.coords)
            Bridge.Notify.showNotify(source, locale("you_accepted_alert"), "success")
            break
        end
    end
end

RegisterNetEvent("p_mdt/server/dispatch/acceptAlert", function(alertId)
    local source = source
    local job = Bridge.Framework.getPlayerJob(source)
    if not Config.Departments[job.name] then
        if Bridge and Bridge.Config and Bridge.Config.Debug then
            lib.print.error("Player job not authorized to accept alerts")
        end
        return
    end
    Dispatch:accept(source, alertId)
end)

function Dispatch.cancel(self, source, alertId)
    if not alertId then
        return
    end

    for _, alert in pairs(self.alerts) do
        if alert.id == alertId then
            for unitIndex, unit in pairs(alert.units) do
                if unit.id == source then
                    table.remove(alert.units, unitIndex)

                    local playerState = Player(source).state
                    if playerState.currentAlerts then
                        playerState.currentAlerts[alertId] = nil
                        playerState:set("currentAlerts", playerState.currentAlerts, true)
                    end

                    TriggerClientEvent("p_mdt/client/dispatch/refresh", -1, {
                        calls = Dispatch.alerts,
                        units = Dispatch.units,
                    })
                    break
                end
            end
            break
        end
    end
end

RegisterNetEvent("p_mdt/server/dispatch/cancelAlert", function(alertId)
    local source = source
    local job = Bridge.Framework.getPlayerJob(source)
    if not Config.Departments[job.name] then
        if Bridge and Bridge.Config and Bridge.Config.Debug then
            lib.print.error("Player job not authorized to cancel alerts")
        end
        return
    end
    Dispatch:cancel(source, alertId)
end)

RegisterNetEvent("p_mdt/server/dispatch/deleteAlert", function(alertId)
    if not alertId then
        if Bridge and Bridge.Config and Bridge.Config.Debug then
            lib.print.error("No alertId provided to deleteAlert")
        end
        return
    end

    local source = source
    local job = Bridge.Framework.getPlayerJob(source)
    if not Config.Departments[job.name] then
        if Bridge and Bridge.Config and Bridge.Config.Debug then
            lib.print.error("Player job not authorized to delete alerts")
        end
        return
    end

    for index, alert in pairs(Dispatch.alerts) do
        if alert.id == alertId then
            local isSupervisor = false
            if Config.Dispatch.supervisorRole then
                for _, unit in pairs(alert.units) do
                    if unit.id == source and unit.supervisor then
                        isSupervisor = true
                        break
                    end
                end
            end

            if not isSupervisor and not Config.Dispatch.allowDeleteWithActiveUnits and #alert.units > 0 then
                Bridge.Notify.showNotify(source, locale("alert_has_active_units"), "error")
                return
            end

            table.remove(Dispatch.alerts, index)
            TriggerClientEvent("p_mdt/client/dispatch/deleteAlert", -1, alertId, {
                calls = Dispatch.alerts,
                units = Dispatch.units,
            })
            Bridge.Notify.showNotify(source, locale("you_deleted_alert"), "success")
            break
        end
    end
end)

function Dispatch.changeSupervisorUnit(self, source, data)
    if not data.alertId or not data.unitId then
        return
    end

    for _, alert in pairs(self.alerts) do
        if alert.id == data.alertId then
            for _, unit in pairs(alert.units) do
                if unit.id == source then
                    unit.supervisor = false
                end
                if unit.id == data.unitId then
                    unit.supervisor = true
                end
            end

            TriggerClientEvent("p_mdt/client/dispatch/refresh", -1, {
                calls = self.alerts,
                units = self.units,
            })
            break
        end
    end
end

RegisterNetEvent("p_mdt/server/dispatch/changeSupervisorUnit", function(data)
    local source = source
    local job = Bridge.Framework.getPlayerJob(source)
    if not Config.Departments[job.name] then
        if Bridge and Bridge.Config and Bridge.Config.Debug then
            lib.print.error("Player job not authorized to change supervisor unit")
        end
        return
    end
    Dispatch:changeSupervisorUnit(source, data)
end)

Base:exportHandler("piotreq_gpt", "SendAlert", function(source, alertData)
    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)
    local fields = {}

    if alertData.info then
        for _, info in pairs(alertData.info) do
            if not info.isStreet then
                table.insert(fields, {
                    label = "",
                    value = info.data,
                    icon = info.icon,
                })
            end
        end
    end

    if not alertData.type then
        alertData.type = "normal"
    end

    if alertData.type == "risk" and alertData.blip then
        alertData.blip.pulseBlip = true
    end

    Dispatch:new({
        title = alertData.title,
        description = alertData.description or "",
        priority = alertData.type == "risk" and "high" or "low",
        coords = alertData.coords or coords,
        code = alertData.code or "",
        fields = (#fields > 0 and fields) or nil,
        blip = alertData.blip or nil,
        alertTime = (alertData.time or 5) * 60,
        timeout = alertData.notifyTime or 5000,
    })
end)

RegisterNetEvent("cd_dispatch:AddNotification", function(alertData)
    local blip = nil
    if alertData.blip then
        blip = {
            sprite = alertData.blip.sprite or 1,
            color = alertData.blip.colour or 1,
            scale = alertData.blip.scale or 1.0,
            shortRange = true,
            pulseBlip = alertData.blip.flashes or false,
            name = alertData.title,
        }
    end

    Dispatch:new({
        title = alertData.title,
        description = alertData.message,
        priority = alertData.flash and "high" or "low",
        coords = alertData.coords,
        code = alertData.code or "",
        jobs = alertData.job_table or nil,
        blip = blip,
    })
end)

Base:exportHandler("lb-tablet", "AddDispatch", function(alertData)
    local blip = nil
    if alertData.blip then
        blip = {
            sprite = alertData.blip.sprite or 1,
            color = alertData.blip.color or 1,
            scale = alertData.blip.size or 1.0,
            shortRange = alertData.blip.shortRange or false,
            pulseBlip = true,
            name = alertData.blip.label or alertData.title,
        }
    end

    return Dispatch:new({
        title = alertData.title,
        description = alertData.description,
        priority = alertData.priority,
        coords = vec3(alertData.location.coords.x, alertData.location.coords.y, 0.0),
        street = alertData.location.label or nil,
        code = alertData.code,
        fields = alertData.fields or nil,
        blip = blip,
        alertTime = alertData.time or 180,
        image = alertData.image or nil,
        sound = alertData.sound or nil,
        timeout = alertData.timeout or 5000,
    })
end)

RegisterNetEvent("ps-dispatch:server:notify", function(alertData)
    if not alertData.priority then
        alertData.priority = 2
    end

    local fields = {}
    if alertData.vehicle then
        table.insert(fields, { label = locale("vehicle"), value = alertData.vehicle, icon = "fa-solid fa-car" })
    end
    if alertData.plate then
        table.insert(fields, { label = locale("plate"), value = alertData.plate, icon = "fa-solid fa-id-card" })
    end
    if alertData.color then
        table.insert(fields, { label = locale("color"), value = alertData.color, icon = "fa-solid fa-palette" })
    end
    if alertData.class then
        table.insert(fields, { label = locale("class"), value = alertData.class, icon = "fa-solid fa-list" })
    end
    if alertData.doors then
        table.insert(fields, { label = locale("doors"), value = alertData.doors, icon = "fa-solid fa-door-open" })
    end
    if alertData.callsign then
        table.insert(fields, { label = locale("callsign"), value = alertData.callsign, icon = "fa-solid fa-shield-alt" })
    end
    if alertData.name then
        table.insert(fields, { label = locale("name"), value = alertData.name, icon = "fa-solid fa-user" })
    end

    local blip = nil
    if alertData.alert then
        blip = {
            sprite = alertData.alert.sprite or 1,
            color = alertData.alert.color or 1,
            scale = alertData.alert.scale or 0.5,
            shortRange = true,
            pulseBlip = alertData.alert.flash or false,
            name = alertData.message,
        }
    end

    Dispatch:new({
        title = alertData.message,
        priority = alertData.priority == 2 and "low" or "high",
        coords = alertData.coords,
        street = alertData.street or nil,
        code = alertData.code,
        fields = alertData.fields or nil,
        blip = blip,
        alertTime = alertData.alertTime or nil,
        image = alertData.image or nil,
        sound = alertData.sound or nil,
        timeout = alertData.timeout or 5000,
        jobs = alertData.jobs or nil,
    })
end)

RegisterNetEvent("qs-dispatch:server:CreateDispatchCall", function(alertData)
    local fields = {}
    for _, entry in pairs(alertData.otherData or {}) do
        table.insert(fields, {
            text = entry.value,
            icon = entry.icon,
        })
    end

    local blip = nil
    if alertData.blip then
        blip = {
            sprite = alertData.blip.sprite or 1,
            color = alertData.blip.colour or 1,
            scale = alertData.blip.scale or 1.0,
            shortRange = true,
            pulseBlip = alertData.blip.flashes or false,
            name = alertData.blip.text or alertData.title,
        }
    end

    Dispatch:new({
        title = alertData.callCode.snippet,
        description = alertData.message,
        priority = alertData.priority,
        coords = alertData.callLocation,
        code = alertData.callCode.code,
        fields = (#fields > 0 and fields) or nil,
        blip = blip,
        alertTime = alertData.blip and alertData.blip.time and (alertData.blip.time / 1000) or nil,
        image = alertData.image or nil,
        sound = alertData.sound or nil,
        timeout = alertData.timeout or 5000,
    })
end)
