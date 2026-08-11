while not Config or not Config.Breathalyzer do
    Citizen.Wait(500)
end

if not Config.Breathalyzer.Enabled then
    return
end

Breathalyzer = {
    activeTests = {},
}

function Breathalyzer.getTargetDrunkLevel(self, targetId)
    local drunkLevel = lib.callback.await("p_policejob/client/breathalyzer/getDrunkLevel", targetId)
    Bridge.Debug(("[Breathalyzer] Target %s drunk level: %s"):format(targetId, drunkLevel))
    return drunkLevel or 0
end

function Breathalyzer.startTest(self, officerId, targetId)
    if not targetId or not GetPlayerPed(targetId) then
        return Bridge.Notify.showNotify(officerId, locale("no_player_nearby"), "error")
    end
    Config.Breathalyzer.onTestStart_Server(officerId, targetId)
    local result = self:getTargetDrunkLevel(targetId)
    Bridge.Debug(("[Breathalyzer] Player %s tested player %s, result: %s"):format(officerId, targetId, result))
    Config.Breathalyzer.onTestComplete_Server(officerId, targetId, result)
    return result
end

function Breathalyzer.use(self, officerId, targetId)
    local job = Bridge.Framework.getPlayerJob(officerId)
    if not Config.Jobs[job.name] then
        return Bridge.Notify.showNotify(officerId, locale("no_access_breathalyzer"), "error")
    end
    if targetId then
        local numericTarget = tonumber(targetId)
        if numericTarget and numericTarget ~= officerId then
            if Config.Breathalyzer.requireConsent then
                local officerName = Bridge.Framework.getPlayerName(officerId)
                if not officerName then
                    officerName = "ID " .. tostring(officerId)
                end
                Bridge.Notify.showNotify(officerId, locale("test_request_sent"), "inform")
                local consented = lib.callback.await(
                    "p_policejob/client/breathalyzer/requestConsent",
                    numericTarget,
                    officerName
                )
                if not consented then
                    return Bridge.Notify.showNotify(officerId, locale("breathalyzer_declined"), "error")
                end
            end
        end
    end
    TriggerClientEvent("p_policejob/client/breathalyzer/open", officerId, targetId)
end

exports("useBreathalyzerItem", function(officerId, targetId)
    Breathalyzer:use(officerId, targetId)
end)

exports("breathalyzer", function(event, _, player, _, _)
    if event == "usingItem" then
        Breathalyzer:use(player.id)
    end
end)

RegisterNetEvent("p_policejob/server/breathalyzer/use", function(targetId)
    Breathalyzer:use(source, targetId)
end)

lib.callback.register("p_policejob/server/breathalyzer/startBreathalyzer", function(source, targetId)
    return Breathalyzer:startTest(source, targetId)
end)
