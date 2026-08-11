while not Config or not Config.Breathalyzer do
    Citizen.Wait(500)
end

if not Config.Breathalyzer.Enabled then
    return
end

Breathalyzer = {
    isActive = false,
    targetId = nil,
    localAlcohol = 0,
}

RegisterNetEvent("evidence:client:SetStatus", function(status, value)
    if status:find("alcohol") then
        Breathalyzer.localAlcohol = value
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        if Breathalyzer.localAlcohol > 0 then
            Breathalyzer.localAlcohol = Breathalyzer.localAlcohol - 1
        end
    end
end)

exports("isBreathalyzerActive", function()
    return Breathalyzer.isActive
end)

exports("useBreathalyzer", function(targetId)
    Breathalyzer:use(targetId)
end)

exports("OpenBreathalyzer", function(targetId)
    Breathalyzer:open(targetId)
end)

exports("CloseBreathalyzer", function()
    Breathalyzer:close()
end)

function Breathalyzer.getDrunkLevel(self)
    local drunkLevel = Config.Breathalyzer.getDrunkLevel()
    if not drunkLevel or drunkLevel == 0 then
        return self.localAlcohol
    end
    return drunkLevel or 0
end

function Breathalyzer.open(self, targetId)
    self.isActive = true
    self.targetId = targetId
    Config.Breathalyzer.onOpen()
    SendNUIMessage({
        action = "setBreathalyzerConfig",
        data = {
            thresholds = Config.Breathalyzer.thresholds,
            colors = Config.Breathalyzer.colors,
            locales = {
                guide_title = locale("breathalyzer_guide_title"),
                guide_step_1 = locale("breathalyzer_guide_step_1"),
                guide_step_2 = locale("breathalyzer_guide_step_2"),
                guide_step_3 = locale("breathalyzer_guide_step_3"),
                start = locale("breathalyzer_start"),
                stop = locale("breathalyzer_stop"),
            },
        },
    })
    SendNUIMessage({
        action = "setVisibleBreathalyzer",
        data = true,
    })
    SendNUIMessage({
        action = "setBreathalyzerData",
        data = {
            status = "idle",
            value = 0,
        },
    })
    SetNuiFocus(true, true)
end

function Breathalyzer.close(self)
    self.isActive = false
    self.targetId = nil
    Config.Breathalyzer.onClose()
    SendNUIMessage({
        action = "setVisibleBreathalyzer",
        data = false,
    })
    SetNuiFocus(false, false)
end

function Breathalyzer.toggle(self, state, targetId)
    if state == nil then
        state = not self.isActive
    end
    if state then
        self:open(targetId or self.targetId)
    else
        self:close()
    end
end

function Breathalyzer.startTest(self)
    if not self.targetId then
        return Bridge.Notify.showNotify(locale("no_player_nearby"), "error")
    end
    Config.Breathalyzer.onTestStart(self.targetId)
    SendNUIMessage({
        action = "setBreathalyzerData",
        data = {
            status = "testing",
            value = 0,
        },
    })
    local result = lib.callback.await("p_policejob/server/breathalyzer/startBreathalyzer", false, self.targetId)
    if result then
        SendNUIMessage({
            action = "setBreathalyzerData",
            data = {
                status = "complete",
                value = result,
            },
        })
        Config.Breathalyzer.onTestComplete(self.targetId, result)
    else
        SendNUIMessage({
            action = "setBreathalyzerData",
            data = {
                status = "idle",
                value = 0,
            },
        })
    end
    return result
end

function Breathalyzer.resetTest(self)
    SendNUIMessage({
        action = "setBreathalyzerData",
        data = {
            status = "idle",
            value = 0,
        },
    })
end

function Breathalyzer.use(self, targetId)
    local job = Bridge.Framework.fetchPlayerJob()
    if not Config.Jobs[job.name] then
        return Bridge.Notify.showNotify(locale("no_access_breathalyzer"), "error")
    end
    if not targetId or type(targetId) ~= "number" then
        local closestPlayer = lib.getClosestPlayer(GetEntityCoords(cache.ped), 4.0, false)
        if closestPlayer and closestPlayer ~= 0 then
            local serverId = GetPlayerServerId(closestPlayer)
            if serverId ~= cache.serverId then
                targetId = serverId
            end
        end
    end
    if not targetId or type(targetId) ~= "number" then
        return Bridge.Notify.showNotify(locale("no_player_nearby"), "error")
    end
    self:open(targetId)
end

RegisterNUICallback("StartBreathalyzer", function(_, cb)
    local result = Breathalyzer:startTest()
    cb(result or 0)
end)

RegisterNUICallback("StopBreathalyzer", function(_, cb)
    Breathalyzer:resetTest()
    cb("ok")
end)

RegisterNUICallback("CloseBreathalyzer", function(_, cb)
    Breathalyzer:close()
    cb("ok")
end)

RegisterNUICallback("hideFrame", function(data, cb)
    if data.name == "setVisibleBreathalyzer" then
        Breathalyzer:close()
    end
    cb("ok")
end)

RegisterNetEvent("p_policejob/client/breathalyzer/toggle", function(state, targetId)
    Breathalyzer:toggle(state, targetId)
end)

RegisterNetEvent("p_policejob/client/breathalyzer/open", function(targetId)
    Breathalyzer:use(targetId)
end)

RegisterNetEvent("p_policejob/client/breathalyzer/close", function()
    Breathalyzer:close()
end)

lib.callback.register("p_policejob/client/breathalyzer/getDrunkLevel", function()
    return Breathalyzer:getDrunkLevel()
end)

lib.callback.register("p_policejob/client/breathalyzer/requestConsent", function(officerName)
    local response = lib.alertDialog({
        header = locale("breathalyzer_consent_header"),
        content = locale("breathalyzer_consent_content"):format(officerName or "?"),
        centered = true,
        cancel = true,
        labels = {
            confirm = locale("breathalyzer_consent_accept"),
            cancel = locale("breathalyzer_consent_decline"),
        },
    })
    return response == "confirm"
end)
