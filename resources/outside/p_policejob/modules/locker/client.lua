while not Config or not Config.Locker do
    Citizen.Wait(500)
end

if not Config.Locker.Enabled then
    return
end

Locker = {}

function hasLockerAccess()
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

function Locker.openById(self, lockerId)
    if not lockerId or lockerId == "" then
        return
    end
    if not hasLockerAccess() then
        Bridge.Notify.showNotify(locale("locker_no_access"), "error")
        return
    end
    lockerId = tostring(lockerId):sub(1, 64)
    TriggerServerEvent("p_policejob/server/locker/open", lockerId)
    Citizen.Wait(100)
    Bridge.Inventory.openInventory("stash", {
        id = Config.Locker.StashPrefix .. "_" .. lockerId,
    })
end

function Locker.openWithInput(self)
    if not hasLockerAccess() then
        Bridge.Notify.showNotify(locale("locker_no_access"), "error")
        return
    end
    local input = lib.inputDialog(locale("locker_input_title"), {
        {
            type = "input",
            label = locale("locker_input_label"),
            required = true,
        },
    })
    if not input or not input[1] then
        return
    end
    self:openById(input[1])
end

exports("openLocker", function(lockerId)
    Locker:openById(lockerId)
end)

exports("openLockerWithInput", function()
    Locker:openWithInput()
end)
