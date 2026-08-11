while not Config or not Config.Tackle do
    Wait(500)
end

if not Config.Tackle.Enabled then
    return
end

function hasTackleAccess(sourceId)
    if not Config.Tackle.JobRestricted then
        return true
    end
    local job = Bridge.Framework.getPlayerJob(sourceId)
    if not job or not job.name then
        return false
    end
    local requiredGrade = Config.Jobs[job.name]
    if requiredGrade == nil then
        return false
    end
    local playerGrade = job.grade or 0
    return requiredGrade <= playerGrade
end

RegisterNetEvent("p_policejob/server/tackle/tacklePlayer", function(targetId)
    if type(targetId) ~= "number" or targetId < 1 then
        return
    end
    local sourceId = source
    if not hasTackleAccess(sourceId) then
        return
    end
    local tacklerPed = GetPlayerPed(sourceId)
    local targetPed = GetPlayerPed(targetId)
    if not tacklerPed or tacklerPed == 0 then
        return
    end
    if not targetPed or targetPed == 0 then
        return
    end
    local distance = #(GetEntityCoords(tacklerPed) - GetEntityCoords(targetPed))
    if distance > 4.0 then
        return
    end
    TriggerClientEvent("p_policejob/client/tackle/tacklePlayer", sourceId, {
        targetId = targetId,
        isTackler = true,
    })
    TriggerClientEvent("p_policejob/client/tackle/tacklePlayer", targetId, {
        targetId = sourceId,
        isTackler = false,
    })
end)
