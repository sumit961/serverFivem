while not Config do
    Citizen.Wait(50)
end

local compatResources = {
    "qb-policejob",
    "qbx_police",
    "esx_policejob",
    "wasabi_police",
}

function registerCompatExport(exportName, handler)
    for _, resourceName in ipairs(compatResources) do
        AddEventHandler(("__cfx_export_%s_%s"):format(resourceName, exportName), function(setCB)
            setCB(handler)
        end)
    end
    exports(exportName, handler)
end

function getCopList()
    local cops = {}
    for _, playerId in ipairs(GetPlayers()) do
        local sourceId = tonumber(playerId)
        local job = sourceId and Bridge.Framework.getPlayerJob(sourceId) or nil
        if job and Config.Jobs[job.name] then
            cops[#cops + 1] = sourceId
        end
    end
    return cops
end

function getCopCount()
    return #getCopList()
end

function isCop(sourceId)
    sourceId = tonumber(sourceId)
    if not sourceId then
        return false
    end
    return Bridge.Framework.getPlayerJob(sourceId) ~= nil
end

function isPoliceForcePresent(minCount)
    return getCopCount() >= (tonumber(minCount) or 1)
end

registerCompatExport("GetCops", getCopCount)
registerCompatExport("GetCopCount", getCopCount)
registerCompatExport("GetCopList", getCopList)
registerCompatExport("IsPoliceForcePresent", isPoliceForcePresent)
registerCompatExport("IsCop", isCop)
registerCompatExport("IsPolice", isCop)
