Dispatch = {
    currentAlert = nil,
    timeout = nil,
    alertFunctions = {
        acceptAlert = function()
            if not Dispatch.timeout then
                return
            end
            Dispatch:accept(Dispatch.currentAlert.id)
            Dispatch.timeout:forceEnd(false)
            SendNUIMessage({ action = "dismissAlert" })
            Wait(300)
            Dispatch.currentAlert = nil
        end,
        dismissAlert = function()
            if not Dispatch.timeout then
                return
            end
            Dispatch.timeout:forceEnd(false)
            SendNUIMessage({ action = "dismissAlert" })
            Wait(300)
            Dispatch.currentAlert = nil
        end,
        viewAlert = function()
            if not Base.tabletState then
                Base:OpenMDT()
                while not Base.tabletState do
                    Wait(100)
                end
                Wait(100)
                SendNUIMessage({ action = "openMap" })
                Wait(100)
            end

            SendNUIMessage({
                action = "viewAlert",
                data = Dispatch.currentAlert.id,
            })
            Dispatch.timeout:forceEnd(false)
            SendNUIMessage({ action = "dismissAlert" })
            Wait(300)
            Dispatch.currentAlert = nil
        end,
        expandAlert = function()
            SendNUIMessage({ action = "expandAlert" })
        end,
    },
    keybinds = {},
    blips = {},
    unitsThread = false,
}

while not Config or not Config.Dispatch do
    Wait(100)
end

if Config.Dispatch.disableDispatch then
    return
end

CreateThread(function()
    while not lib do
        Wait(0)
    end

    for name, defaultKey in pairs(Config.Dispatch.keybinds) do
        Dispatch.keybinds[name] = lib.addKeybind({
            name = name,
            description = locale("keybind_" .. name),
            defaultKey = defaultKey,
            onPressed = function()
                if not Dispatch.currentAlert then
                    return
                end
                Dispatch.alertFunctions[name]()
            end,
        })
    end
end)

function Dispatch.initUnitsThread(self)
    if self.unitsThread then
        return
    end

    self.unitsThread = true
    CreateThread(function()
        Wait(100)
        while Base.tabletState do
            if Base.tabletState then
                local units = {}
                local activeGPS = GlobalState.activeGPS or {}
                local count = 0

                for id, data in pairs(activeGPS) do
                    count = count + 1
                    units[count] = {
                        id = id,
                        player = data.name,
                        callsign = data.callsign,
                        street = GetStreetNameFromHashKey(GetStreetNameAtCoord(data.coords.x, data.coords.y, data.coords.z)),
                        location = {
                            x = data.coords.x,
                            y = data.coords.y,
                            z = data.coords.z,
                        },
                    }
                end

                SendNUIMessage({
                    action = "mdt/dispatch/refreshUnits",
                    data = units,
                })
            end
            Wait(5000)
        end
        self.unitsThread = false
    end)
end

function Dispatch.checkAlertJob(self, alert)
    local job = Bridge.Framework.fetchPlayerJob()
    if not Config.Departments[job.name] then
        return false
    end

    if not alert.jobs then
        return true
    end

    if type(alert.jobs) == "string" then
        return job.name == alert.jobs
    end

    if type(alert.jobs) == "table" then
        for _, allowedJob in pairs(alert.jobs) do
            if type(allowedJob) == "string" and job.name == allowedJob then
                return true
            end
        end
        return false
    end

    return true
end

RegisterNUICallback("mdt/dispatch/getData", function(data, cb)
    Dispatch:initUnitsThread()

    local mdtData = lib.callback.await("p_mdt/server/getMDTData", false, "dispatch") or {}
    local filteredCalls = {}

    if mdtData.calls then
        for _, alert in pairs(mdtData.calls) do
            if Dispatch:checkAlertJob(alert) then
                filteredCalls[#filteredCalls + 1] = alert
            end
        end
    end

    mdtData.calls = filteredCalls
    cb(mdtData)
end)

function Dispatch.notification(self, alert)
    while self.currentAlert do
        Wait(100)
    end

    self.currentAlert = alert
    SendNUIMessage({ action = "alertNotification", data = alert })
    self.timeout = lib.timer(alert.timeout + 300, function()
        self.currentAlert = nil
    end, true)
end

function Dispatch.alertBlip(self, alert)
    local blipEntry = self.blips[alert.id]
    if blipEntry then
        if DoesBlipExist(blipEntry[1]) then
            RemoveBlip(blipEntry[1])
        end
        if blipEntry[2] and DoesBlipExist(blipEntry[2]) then
            RemoveBlip(blipEntry[2])
        end
        self.blips[alert.id] = nil
    end

    if not alert.blip then
        return
    end

    if not self.blips[alert.id] then
        self.blips[alert.id] = {}
    end

    AddTextEntry("BLIP_CAT_69", locale("dispatch_alerts"))

    local mainBlip = AddBlipForCoord(
        alert.location.coords.x,
        alert.location.coords.y,
        alert.location.coords.z
    )

    SetBlipSprite(mainBlip, alert.blip.sprite or 280)
    SetBlipColour(mainBlip, alert.blip.color or 1)
    SetBlipScale(mainBlip, alert.blip.scale or 0.95)
    SetBlipAsShortRange(mainBlip, alert.blip.shortRange ~= nil and alert.blip.shortRange or true)
    SetBlipDisplay(mainBlip, 4)
    SetBlipCategory(mainBlip, 69)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(alert.blip.name or "Dispatch Alert")
    EndTextCommandSetBlipName(mainBlip)

    self.blips[alert.id][1] = mainBlip

    if alert.blip.pulseBlip then
        local pulseBlip = AddBlipForCoord(
            alert.location.coords.x,
            alert.location.coords.y,
            alert.location.coords.z
        )
        SetBlipSprite(pulseBlip, 161)
        SetBlipScale(pulseBlip, 1.0)
        SetBlipColour(pulseBlip, alert.blip.color or 1)
        PulseBlip(pulseBlip)
        SetBlipDisplay(pulseBlip, 4)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("")
        EndTextCommandSetBlipName(pulseBlip)
        self.blips[alert.id][2] = pulseBlip
    end

    self.blips[alert.id][3] = GetGameTimer() + (alert.alertTime * 1000)
end

CreateThread(function()
    while true do
        for alertId, blipEntry in pairs(Dispatch.blips) do
            Wait(100)
            if blipEntry[3] and GetGameTimer() >= blipEntry[3] then
                if DoesBlipExist(blipEntry[1]) then
                    RemoveBlip(blipEntry[1])
                end
                if blipEntry[2] and DoesBlipExist(blipEntry[2]) then
                    RemoveBlip(blipEntry[2])
                end
                Dispatch.blips[alertId] = nil
            end
        end
        Wait(5000)
    end
end)

RegisterNetEvent("p_mdt/client/dispatch/notification", function(alert, payload)
    local job = Bridge.Framework.fetchPlayerJob()
    if not Config.Departments[job.name] then
        return
    end

    if alert.jobs then
        if type(alert.jobs) == "string" then
            if job.name ~= alert.jobs then
                return
            end
        elseif type(alert.jobs) == "table" then
            local allowed = false
            for _, allowedJob in pairs(alert.jobs) do
                if type(allowedJob) == "string" and job.name == allowedJob then
                    allowed = true
                    break
                end
            end
            if not allowed then
                return
            end
        end
    end

    if Config.Dispatch.alertsNotification then
        if not Config.Dispatch.requireDuty or Bridge.Framework.CheckJobDuty() then
            Dispatch:notification(alert)
        end
    end

    if Base.tabletState then
        SendNUIMessage({ action = "dispatch/refresh", data = payload })
    end

    Dispatch:alertBlip(alert)
end)

function Dispatch.accept(self, alertId)
    if not alertId then
        return
    end
    TriggerServerEvent("p_mdt/server/dispatch/acceptAlert", alertId)
end

RegisterNUICallback("acceptAlert", function(data, cb)
    Dispatch:accept(data.id)
    cb(1)
end)

function Dispatch.cancel(self, alertId)
    if not alertId then
        return
    end
    TriggerServerEvent("p_mdt/server/dispatch/cancelAlert", alertId)
end

RegisterNUICallback("cancelAlert", function(data, cb)
    Dispatch:cancel(data.id)
    cb(1)
end)

function Dispatch.delete(self, alertId)
    if not alertId then
        return
    end
    TriggerServerEvent("p_mdt/server/dispatch/deleteAlert", alertId)
end

RegisterNUICallback("deleteAlert", function(data, cb)
    Dispatch:delete(data.id)
    cb(1)
end)

RegisterNetEvent("p_mdt/client/dispatch/refresh", function(payload)
    if not Base.tabletState then
        return
    end

    local filteredCalls = {}
    if payload and payload.calls then
        for _, alert in pairs(payload.calls) do
            if Dispatch:checkAlertJob(alert) then
                filteredCalls[#filteredCalls + 1] = alert
            end
        end
    end

    payload.calls = filteredCalls
    SendNUIMessage({ action = "dispatch/refresh", data = payload })
end)

RegisterNetEvent("p_mdt/client/dispatch/deleteAlert", function(alertId, payload)
    local job = Bridge.Framework.fetchPlayerJob()
    if not Config.Departments[job.name] then
        return
    end

    if Dispatch.blips[alertId] and Dispatch.blips[alertId][3] then
        Dispatch.blips[alertId][3] = GetGameTimer()
    end

    if not Base.tabletState then
        return
    end

    local filteredCalls = {}
    if payload and payload.calls then
        for _, alert in pairs(payload.calls) do
            if Dispatch:checkAlertJob(alert) then
                filteredCalls[#filteredCalls + 1] = alert
            end
        end
    end

    payload.calls = filteredCalls
    SendNUIMessage({ action = "dispatch/refresh", data = payload })
end)

function Dispatch.focus(self, enabled)
    SetNuiFocus(enabled, enabled)
end

RegisterCommand("dispatch:edit", function()
    Dispatch:focus(true)
end, false)

RegisterNUICallback("disableFocus", function(data, cb)
    Dispatch:focus(false)
    cb(1)
end)

RegisterNUICallback("createAlert", function(data, cb)
    local coords = GetEntityCoords(cache.ped)
    TriggerServerEvent("p_mdt/createAlert", {
        priority = data.priority,
        code = data.code,
        title = data.title,
        description = data.description,
        coords = coords,
        street = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z)),
        fields = {
            {
                label = locale("officer"),
                value = Bridge.Framework.getPlayerName(),
                icon = "fa-solid fa-user",
            },
        },
        blip = {
            sprite = 280,
            color = 1,
            scale = 1.0,
            shortRange = true,
            pulseBlip = true,
            name = data.title,
        },
        alertTime = 60,
    })
    cb(1)
end)

RegisterNUICallback("changeSupervisorUnit", function(data, cb)
    TriggerServerEvent("p_mdt/server/dispatch/changeSupervisorUnit", data)
    cb(1)
end)

function Dispatch.extractCoords(payload)
    if type(payload) ~= "table" then
        return nil, nil
    end

    if payload.x ~= nil and payload.y ~= nil then
        return tonumber(payload.x), tonumber(payload.y)
    end

    if payload.coords then
        return Dispatch.extractCoords(payload.coords)
    end

    if payload.location and payload.location.coords then
        return Dispatch.extractCoords(payload.location.coords)
    end

    if payload.lat ~= nil and (payload.lng ~= nil or payload.lon ~= nil) then
        return tonumber(payload.lat), tonumber(payload.lng or payload.lon)
    end

    if payload[1] ~= nil and payload[2] ~= nil then
        return tonumber(payload[1]), tonumber(payload[2])
    end

    return nil, nil
end

while not Base or not Base.exportHandler do
    Wait(0)
end

Base:exportHandler("cd_dispatch", "GetPlayerInfo", function()
    local coords = GetEntityCoords(cache.ped)
    local model = GetEntityModel(cache.ped)
    local sex

    if model == -1667301416 then
        sex = locale("female")
    else
        sex = locale("male")
    end

    return {
        coords = coords,
        sex = sex,
        street = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z)),
        unique_id = tostring(math.random(100000, 999999)),
    }
end)

RegisterNetEvent("p_mdt/client/dispatch/markAlert", function(payload)
    if not payload then
        return
    end

    local x, y = Dispatch.extractCoords(payload)
    if not x or not y then
        if Config.Debug then
            print(("[p_mdt] Invalid markAlert coords payload: %s"):format(json.encode(payload)))
        end
        return
    end

    SetNewWaypoint(x, y)
end)
