while not Config or not Config.Dispatch do
    Wait(100)
end

if Config.Dispatch.disableDispatch then
    return
end

while not Dispatch do
    Wait(0)
end

Dispatch.Menu = {
    state = false,
    antiSpam = GetGameTimer(),
}

function Dispatch.sortAlerts(self, alerts)
    local job = Bridge.Framework.fetchPlayerJob()
    local filtered = {}

    for _, alert in pairs(alerts) do
        if alert.jobs then
            if type(alert.jobs) == "string" then
                if alert.jobs == job.name then
                    filtered[#filtered + 1] = alert
                end
            elseif type(alert.jobs) == "table" then
                for key, value in pairs(alert.jobs) do
                    if type(key) == "string" and value == job.name then
                        filtered[#filtered + 1] = alert
                        break
                    elseif type(value) == "string" and value == job.name then
                        filtered[#filtered + 1] = alert
                        break
                    end
                end
            end
        else
            filtered[#filtered + 1] = alert
        end
    end

    return filtered
end

RegisterNetEvent("p_mdt/client/dispatch/deleteAlert", function(alertId, payload)
    local job = Bridge.Framework.fetchPlayerJob()
    if not Config.Departments[job.name] then
        return
    end

    if payload.calls then
        payload.calls = Dispatch:sortAlerts(payload.calls)
    end

    SendNUIMessage({
        action = "alertsMenu/refresh",
        data = {
            alerts = payload and payload.calls or {},
            identifier = Bridge.Framework.getIdentifier(),
        },
    })
end)

RegisterNetEvent("p_mdt/client/dispatch/notification", function(alert, payload)
    local job = Bridge.Framework.fetchPlayerJob()
    if not Config.Departments[job.name] then
        return
    end

    if payload.calls then
        payload.calls = Dispatch:sortAlerts(payload.calls)
    end

    SendNUIMessage({
        action = "alertsMenu/refresh",
        data = {
            alerts = payload and payload.calls or {},
            identifier = Bridge.Framework.getIdentifier(),
        },
    })
end)

RegisterNetEvent("p_mdt/client/dispatch/refresh", function(payload)
    local job = Bridge.Framework.fetchPlayerJob()
    if not Config.Departments[job.name] then
        return
    end

    if payload.calls then
        payload.calls = Dispatch:sortAlerts(payload.calls)
    end

    SendNUIMessage({
        action = "alertsMenu/refresh",
        data = {
            alerts = payload and payload.calls or {},
            identifier = Bridge.Framework.getIdentifier(),
        },
    })
end)

while not lib do
    Wait(0)
end

lib.addKeybind({
    name = "alerts_menu_previous",
    description = "Previous Alert",
    defaultKey = "LEFT",
    onPressed = function()
        if not Dispatch.Menu.state then
            return
        end
        SendNUIMessage({ action = "previousAlert" })
    end,
})

lib.addKeybind({
    name = "alerts_menu_next",
    description = "Next Alert",
    defaultKey = "RIGHT",
    onPressed = function()
        if not Dispatch.Menu.state then
            return
        end
        SendNUIMessage({ action = "nextAlert" })
    end,
})

lib.addKeybind({
    name = "alerts_menu_accept",
    description = "Accept Alert",
    defaultKey = "G",
    onPressed = function()
        if not Dispatch.Menu.state then
            return
        end
        SendNUIMessage({ action = "acceptAlert" })
    end,
})

lib.addKeybind({
    name = "alerts_menu_cancel",
    description = "Cancel Alert",
    defaultKey = "O",
    onPressed = function()
        if not Dispatch.Menu.state then
            return
        end
        SendNUIMessage({ action = "cancelAlert" })
    end,
})

function Dispatch.Menu.toggle(self, state)
    local job = Bridge.Framework.fetchPlayerJob()
    if not Config.Departments[job.name] then
        return
    end

    if self.antiSpam > GetGameTimer() then
        return
    end

    if state == nil then
        state = not self.state
    end

    self.state = state
    self.antiSpam = GetGameTimer() + 500
    SendNUIMessage({ action = "setVisibleAlertsMenu", data = state })
end

function Dispatch.Menu.editMode(self, enabled)
    local job = Bridge.Framework.fetchPlayerJob()
    if not Config.Departments[job.name] then
        return
    end

    SetNuiFocus(enabled, enabled)
    SendNUIMessage({ action = "toggleEditMode", data = enabled })
end

if Config.Dispatch.alertsMenuKey then
    lib.addKeybind({
        name = "alerts_menu_toggle",
        description = "Toggle Alerts Menu",
        defaultKey = Config.Dispatch.alertsMenuKey or "F9",
        onPressed = function()
            Dispatch.Menu:toggle()
        end,
    })
end

RegisterCommand("editalertsmenu", function()
    Dispatch.Menu:editMode(true)
end, false)

RegisterNUICallback("hideFrame", function(data, cb)
    if data.name == "setVisibleAlertsMenu" then
        Dispatch.Menu:editMode(false)
    end
    cb(1)
end)

RegisterNUICallback("alertsMenu/acceptAlert", function(data, cb)
    Dispatch:accept(data.id)
    cb(1)
end)

RegisterNUICallback("alertsMenu/cancelAlert", function(data, cb)
    Dispatch:cancel(data.id)
    cb(1)
end)

while not Base or not Base.exportHandler do
    Wait(0)
end

Base:exportHandler("piotreq_gpt", "OpenDispatch", function()
    Dispatch.Menu:toggle()
end)
