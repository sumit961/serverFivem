while not Config or not Config.Trash do
    Citizen.Wait(500)
end

if not Config.Trash.Enabled then
    return
end

local registeredStashes = {}

function hasTrashAccess(playerId)
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

function ensureTrashStash(trashId)
    local stashId = Config.Trash.StashPrefix .. "_" .. trashId
    if registeredStashes[stashId] then
        return stashId
    end
    registeredStashes[stashId] = true
    Bridge.Inventory.registerStash(stashId, locale("trash"), Config.Trash.Slots, Config.Trash.MaxWeight)
    return stashId
end

RegisterNetEvent("p_policejob/server/trash/open", function(trashId)
    local playerId = source
    if not trashId or trashId == "" then
        return
    end
    if not hasTrashAccess(playerId) then
        Bridge.Debug(("[Trash] Player %s denied access to trash %s"):format(playerId, tostring(trashId)))
        return
    end
    trashId = tostring(trashId):sub(1, 64)
    local stashId = ensureTrashStash(trashId)
    Bridge.Debug(("[Trash] Player %s opened trash %s (stash %s)"):format(playerId, trashId, stashId))
end)

RegisterNetEvent("p_policejob/server/trash/clear", function(trashId)
    local playerId = source
    if not trashId or trashId == "" then
        return
    end
    if not hasTrashAccess(playerId) then
        Bridge.Debug(("[Trash] Player %s denied clearing trash %s"):format(playerId, tostring(trashId)))
        return
    end
    trashId = tostring(trashId):sub(1, 64)
    local stashId = ensureTrashStash(trashId)
    if Bridge.Inventory.clearInventory then
        Bridge.Inventory.clearInventory(stashId)
    end
    Bridge.Debug(("[Trash] Player %s cleared trash %s (stash %s)"):format(playerId, trashId, stashId))
    local webhook = Config.Webhooks and Config.Webhooks.trash
    if webhook and webhook ~= "" then
        Bridge.Logs.Send(playerId, "Trash", ("Cleared trash: %s"):format(trashId), webhook)
    end
end)
