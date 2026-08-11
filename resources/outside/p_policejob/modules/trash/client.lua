while not Config or not Config.Trash do
    Citizen.Wait(500)
end

if not Config.Trash.Enabled then
    return
end

Trash = {}

function hasTrashAccess()
    if not Config.Jobs then
        return true
    end
    local job = Bridge.Framework.fetchPlayerJob()
    if not job then
        return false
    end
    local requiredGrade = Config.Jobs[job.name]
    if requiredGrade == nil then
        return false
    end
    return requiredGrade <= job.grade
end

function Trash.open(self, trashId)
    if not trashId or trashId == "" then
        return
    end
    if not hasTrashAccess() then
        Bridge.Notify.showNotify(locale("trash_no_access"), "error")
        return
    end
    trashId = tostring(trashId):sub(1, 64)
    TriggerServerEvent("p_policejob/server/trash/open", trashId)
    Citizen.Wait(100)
    Bridge.Inventory.openInventory("stash", {
        id = Config.Trash.StashPrefix .. "_" .. trashId,
    })
end

function Trash.clear(self, trashId)
    if not trashId or trashId == "" then
        return
    end
    if not hasTrashAccess() then
        Bridge.Notify.showNotify(locale("trash_no_access"), "error")
        return
    end
    local confirmed = lib.alertDialog({
        header = locale("trash_clear_title"),
        content = locale("trash_clear_desc"),
        centered = true,
        cancel = true,
    })
    if confirmed ~= "confirm" then
        return
    end
    TriggerServerEvent("p_policejob/server/trash/clear", tostring(trashId):sub(1, 64))
end

exports("openTrash", function(trashId)
    Trash:open(trashId)
end)

exports("clearTrash", function(trashId)
    Trash:clear(trashId)
end)
