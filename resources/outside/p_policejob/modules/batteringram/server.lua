while not Config or not Config.BatteringRam do
    Citizen.Wait(500)
end

if not Config.BatteringRam.enabled then
    return
end

function hasBatteringRamAccess(playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    local allowedJobs = Config.BatteringRam.jobs or Config.Jobs
    local hasAccess = allowedJobs or job
    if job and allowedJobs then
        hasAccess = allowedJobs[job.name] ~= nil
    end
    return hasAccess
end

RegisterNetEvent("p_policejob/server/batteringram/forceDoor", function(doorId)
    local playerId = source
    if doorId == nil then
        return
    end
    if not hasBatteringRamAccess(playerId) then
        return
    end
    if GetResourceState("ox_doorlock") == "started" then
        exports.ox_doorlock:setDoorState(doorId, 0)
    end
    if Config.Webhooks and Config.Webhooks.interactions then
        Bridge.Logs.Send(playerId, "Interactions", "Forced a door open with the battering ram", Config.Webhooks.interactions)
    end
    Bridge.Debug(("[BatteringRam] Player %s forced door %s"):format(playerId, tostring(doorId)))
end)

RegisterNetEvent("p_policejob:batteringram:log", function()
    local playerId = source
    if Config.Webhooks and Config.Webhooks.interactions then
        Bridge.Logs.Send(playerId, "Interactions", "Forced a door open with the battering ram", Config.Webhooks.interactions)
    end
    Bridge.Debug(("[BatteringRam] Player %s forced a door"):format(playerId))
end)
