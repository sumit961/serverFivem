while not Config or not Config.Locker do
    Citizen.Wait(500)
end

if not Config.Locker.Enabled then
    return
end

local registeredStashes = {}

function hasLockerAccess(playerId)
    if not Config.Jobs then
        return true
    end
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job then
        return false
    end
    local requiredGrade = Config.Jobs[job.name]
    if requiredGrade == nil then
        return false
    end
    return requiredGrade <= job.grade
end

RegisterNetEvent("p_policejob/server/locker/open", function(lockerId)
    local playerId = source
    if not lockerId or lockerId == "" then
        return
    end
    if not hasLockerAccess(playerId) then
        Bridge.Debug(("[Locker] Player %s denied access to locker %s"):format(playerId, tostring(lockerId)))
        return
    end
    lockerId = tostring(lockerId):sub(1, 64)
    local stashId = Config.Locker.StashPrefix .. "_" .. lockerId
    if registeredStashes[stashId] then
        return
    end
    registeredStashes[stashId] = true
    Bridge.Debug(("[Locker] Player %s opened locker %s (stash %s)"):format(playerId, lockerId, stashId))
    if Bridge.Inventory.registerStash then
        Bridge.Inventory.registerStash(stashId, stashId, Config.Locker.Slots, Config.Locker.MaxWeight)
    end
    local webhook = Config.Webhooks and Config.Webhooks.locker
    if webhook and webhook ~= "" then
        Bridge.Logs.Send(playerId, "Locker", ("Opened locker: %s"):format(lockerId), webhook)
    end
end)

lib.callback.register("p_policejob/server/locker/checkAccess", function(source)
    return hasLockerAccess(source)
end)
