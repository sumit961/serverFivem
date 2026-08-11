while not Config or not Config.Creator do
    Citizen.Wait(500)
end

if not Config.Creator.enabled then
    return
end

function hasCreatorJobAccess(sourceId)
    local job = Bridge.Framework.getPlayerJob(sourceId)
    if not job or not job.name then
        return false
    end
    local access = Config.Creator.access[job.name]
    if access == nil then
        return false
    end
    if type(access) == "number" then
        local playerGrade = job.grade or 0
        if access > playerGrade then
            return false
        end
    end
    return true
end

lib.callback.register("p_policejob/server/creator/canAccess", function(sourceId)
    if Config.Creator.allowAdmins and Config.Creator.adminPermission then
        if IsPlayerAceAllowed(sourceId, Config.Creator.adminPermission) then
            return true
        end
    end
    return hasCreatorJobAccess(sourceId)
end)
