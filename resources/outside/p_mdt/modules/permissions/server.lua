Permissions = {
    data = {},
}

local function copyPermissions(permissions)
    local copied = {}
    for permission, enabled in pairs(permissions or {}) do
        if enabled then
            copied[permission] = true
        end
    end
    return copied
end

local function getDefaultPermissions(gradeKey)
    local defaults = Config.DefaultPermissions
    if not defaults then
        return {}
    end

    local grade = tonumber(gradeKey)
    if grade and grade >= (defaults.minOfficerGrade or 2) then
        return copyPermissions(defaults.officer)
    end

    return copyPermissions(defaults.cadet)
end

CreateThread(function()
    while not Config or not Config.Departments or not MySQL or not MySQL.ready do
        Wait(1000)
    end

    local dbPermissions = {}
    local rows = MySQL.query.await("SELECT * FROM p_mdt_permissions")

    for _, row in pairs(rows) do
        if not dbPermissions[row.job] then
            dbPermissions[row.job] = {}
        end
        dbPermissions[row.job][tostring(row.grade)] = {
            permissions = json.decode(row.permissions),
            modifiedBy = row.modifiedBy,
            timestamp = row.timestamp,
        }
    end

    local frameworkJobs = Bridge.Framework.getJobs()

    for departmentName in pairs(Config.Departments) do
        Permissions.data[departmentName] = {}
        local jobGrades = frameworkJobs[departmentName] or {}

        for gradeLevel, gradeData in pairs(jobGrades) do
            local gradeKey = tostring(gradeLevel)
            local stored = dbPermissions[departmentName] and dbPermissions[departmentName][gradeKey]

            if not stored or not next(stored.permissions or {}) then
                stored = {
                    permissions = getDefaultPermissions(gradeKey),
                    modifiedBy = stored and stored.modifiedBy or 'System',
                    timestamp = stored and stored.timestamp or os.time(),
                }
            end

            Permissions.data[departmentName][gradeKey] = stored
            Permissions.data[departmentName][gradeKey].label = gradeData.label
        end
    end
end)

function Permissions.getPerms(playerSource)
    local job = Bridge.Framework.getPlayerJob(playerSource)
    if not job then
        return {}
    end

    local jobPermissions = Permissions.data[job.name]
    local gradePermissions = jobPermissions and jobPermissions[tostring(job.grade)]
    return (gradePermissions and gradePermissions.permissions) or {}
end

function Permissions.hasPerm(playerSource, permission)
    local job = Bridge.Framework.getPlayerJob(playerSource)
    local bossGrades = Config.Departments[job.name] and Config.Departments[job.name].bossGrades or {}

    if bossGrades and lib.table.contains(bossGrades, job.grade) then
        return true
    end

    local perms = Permissions.getPerms(playerSource)
    return perms[permission] == true
end

function Permissions.editPerms(playerSource, grade, permissionList)
    local job = Bridge.Framework.getPlayerJob(playerSource)
    if not job or not Config.Departments[job.name] then
        return false
    end

    if not Permissions.data[job.name] then
        Permissions.data[job.name] = {}
    end

    local gradeKey = tostring(grade)
    local gradeData = Permissions.data[job.name][gradeKey]
    gradeData.permissions = {}

    for _, permission in pairs(permissionList) do
        gradeData.permissions[permission] = true
    end

    gradeData.modifiedBy = Bridge.Framework.getPlayerName(playerSource)
    gradeData.timestamp = os.time()

    MySQL.update.await("DELETE FROM p_mdt_permissions WHERE job = ? AND grade = ?", {
        job.name,
        grade,
    })

    MySQL.insert(
        "INSERT INTO p_mdt_permissions (job, grade, permissions, modifiedBy, timestamp) VALUES (?, ?, ?, ?, ?)",
        {
            job.name,
            grade,
            json.encode(gradeData.permissions),
            gradeData.modifiedBy,
            gradeData.timestamp,
        }
    )

    Logs:new(playerSource, {
        category = "permissions",
        action = "update",
        message = ("Updated permissions for grade %s"):format(grade),
    })

    return true
end

lib.callback.register("p_mdt/server/permissions/fetch", function(playerSource)
    local job = Bridge.Framework.getPlayerJob(playerSource)
    if not job then
        return {}
    end

    local result = {}
    local index = 0
    local jobData = Permissions.data[job.name] or {}

    for gradeKey, gradeInfo in pairs(jobData) do
        index = index + 1
        result[index] = {
            label = gradeInfo.label,
            grade = tonumber(gradeKey),
            permissions = gradeInfo.permissions,
            modifiedBy = gradeInfo.modifiedBy,
            modifiedAt = gradeInfo.timestamp and gradeInfo.timestamp * 1000 or nil,
        }
    end

    table.sort(result, function(a, b)
        return a.grade < b.grade
    end)

    return result
end)

RegisterNetEvent("p_mdt/server/permissions/update", function(data)
    Permissions.editPerms(source, data.grade, data.permissions)
end)

exports("GetPermissions", Permissions.getPerms)
exports("HasPermission", Permissions.hasPerm)
exports("EditPermissions", Permissions.editPerms)
