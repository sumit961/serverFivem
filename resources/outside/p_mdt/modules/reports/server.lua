Reports = {
    data = {},
    dojAvailable = GetResourceState("p_dojmdt") == "started",
}

function Reports.isDojJob(jobName)
    if not jobName then
        return false
    end
    return string.lower(jobName) == "doj"
end

function Reports.meetsRankRequirement(requiredRank, playerGrade)
    if requiredRank == nil then
        return true
    end

    local grade = tonumber(playerGrade) or 0
    local required = tonumber(requiredRank) or 0
    return grade >= required
end

function Reports.canAccessReport(report, job)
    if not report or not job then
        return false
    end

    if Reports.isDojJob(job.name) then
        return Reports:meetsRankRequirement(report.doj_rank_lock, job.grade)
    end

    return Reports:meetsRankRequirement(report.rank_lock, job.grade)
end

CreateThread(function()
    while not MySQL or not MySQL.ready do
        Wait(100)
    end

    local rows = MySQL.query.await("SELECT * FROM p_mdt_reports")

    for _, row in ipairs(rows) do
        Reports.data[row.id] = {
            id = row.id,
            title = row.title,
            type = row.type,
            status = row.status,
            content = row.content,
            tags = json.decode(row.tags),
            civilians = json.decode(row.civilians),
            officers = json.decode(row.officers),
            suspects = json.decode(row.suspects),
            vehicles = json.decode(row.vehicles),
            photos = json.decode(row.photos),
            weapons = json.decode(row.weapons),
            evidences = json.decode(row.evidences),
            incidents = json.decode(row.incidents),
            warrants = json.decode(row.warrants),
            charges = json.decode(row.charges),
            timestamp = row.timestamp,
            creator = json.decode(row.creator),
            rank_lock = row.rank_lock,
            doj_rank_lock = row.doj_rank_lock,
        }
    end
end)

function Reports.fetch(self, source)
    local job = Bridge.Framework.getPlayerJob(source)
    if not job then
        return {}
    end

    local accessibleReports = {}
    for reportId, report in pairs(self.data) do
        if Reports:canAccessReport(report, job) then
            accessibleReports[reportId] = report
        end
    end

    return accessibleReports
end

lib.callback.register("p_mdt/server/reports/fetch", function(source)
    return Reports:fetch(source)
end)

function Reports.new(self, source, data)
    if not Permissions.hasPerm(source, "reports.create") then
        Bridge.Notify.showNotify(source, locale("no_permission"), "error")
        return
    end

    data.timestamp = os.time()
    data.creator = {
        id = Bridge.Framework.getUniqueId(source),
        name = Bridge.Framework.getPlayerName(source),
    }
    data.status = "open"
    data.rank_lock = tonumber(data.rank_lock) or nil
    data.doj_rank_lock = tonumber(data.doj_rank_lock) or nil

    local insertId = MySQL.insert.await([[
        INSERT INTO p_mdt_reports
        (title, type, content, tags, civilians, officers, suspects, vehicles, photos, weapons, evidences, incidents, warrants, charges, timestamp, creator, rank_lock, doj_rank_lock)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.title,
        data.type,
        data.content,
        json.encode(data.tags),
        json.encode(data.civilians),
        json.encode(data.officers),
        json.encode(data.suspects),
        json.encode(data.vehicles),
        json.encode(data.photos),
        json.encode(data.weapons),
        json.encode(data.evidences),
        json.encode(data.incidents),
        json.encode(data.warrants),
        json.encode(data.charges),
        data.timestamp,
        json.encode(data.creator),
        data.rank_lock,
        data.doj_rank_lock,
    })

    if not insertId then
        return nil
    end

    data.id = insertId
    self.data[insertId] = data

    Logs:new(source, {
        category = "reports",
        action = "create",
        message = ("Created report %s"):format(data.id),
    })

    return self:fetch(source)
end

function Reports.update(self, source, data)
    local report = self.data[data.id]
    if not report then
        Bridge.Notify.showNotify(source, locale("report_not_found"), "error")
        return nil
    end

    if not Permissions.hasPerm(source, "reports.edit") then
        Bridge.Notify.showNotify(source, locale("no_permission"), "error")
        return
    end

    report.title = data.title
    report.type = data.type
    report.content = data.content
    report.tags = data.tags
    report.civilians = data.civilians
    report.officers = data.officers
    report.suspects = data.suspects
    report.vehicles = data.vehicles
    report.photos = data.photos
    report.weapons = data.weapons
    report.evidences = data.evidences
    report.incidents = data.incidents
    report.warrants = data.warrants
    report.charges = data.charges
    report.rank_lock = tonumber(data.rank_lock) or nil
    report.doj_rank_lock = tonumber(data.doj_rank_lock) or nil

    local updated = MySQL.update.await([[
        UPDATE p_mdt_reports SET
        title = ?, type = ?, content = ?, tags = ?, civilians = ?, officers = ?, suspects = ?, vehicles = ?, photos = ?, weapons = ?, evidences = ?, incidents = ?, warrants = ?, charges = ?, rank_lock = ?, doj_rank_lock = ?
        WHERE id = ?
    ]], {
        report.title,
        report.type,
        report.content,
        json.encode(report.tags),
        json.encode(report.civilians),
        json.encode(report.officers),
        json.encode(report.suspects),
        json.encode(report.vehicles),
        json.encode(report.photos),
        json.encode(report.weapons),
        json.encode(report.evidences),
        json.encode(report.incidents),
        json.encode(report.warrants),
        json.encode(report.charges),
        report.rank_lock,
        report.doj_rank_lock,
        report.id,
    })

    if not updated then
        return nil
    end

    Logs:new(source, {
        category = "reports",
        action = "update",
        message = ("Updated report %s"):format(report.id),
    })

    return self:fetch(source)
end

lib.callback.register("p_mdt/server/reports/save", function(source, data)
    if data.id then
        return Reports:update(source, data)
    end
    return Reports:new(source, data)
end)

function Reports.getCitizenReports(self, citizenId)
    local matchingReports = {}
    local index = 1

    for _, report in pairs(self.data) do
        for _, suspect in pairs(report.suspects) do
            if tostring(suspect.id) == tostring(citizenId) then
                matchingReports[index] = report
                index = index + 1
                break
            end
        end
    end

    return matchingReports
end

lib.callback.register("p_mdt/server/reports/fetchEmployees", function(source, query)
    return Editable:fetchEmployeesByQuery(source, query)
end)

function Reports.getVehicleReports(self, plate)
    local matchingReports = {}
    local index = 1

    for _, report in pairs(self.data) do
        for _, vehicle in pairs(report.vehicles) do
            if tostring(vehicle.plate) == tostring(plate) then
                matchingReports[index] = report
                index = index + 1
                break
            end
        end
    end

    return matchingReports
end

function Reports.deleteReport(self, source, reportId)
    local report = self.data[reportId]
    if not report then
        Bridge.Notify.showNotify(source, locale("report_not_found"), "error")
        return
    end

    if not Permissions.hasPerm(source, "reports.delete") then
        Bridge.Notify.showNotify(source, locale("no_permission"), "error")
        return
    end

    local deleted = MySQL.update.await("DELETE FROM p_mdt_reports WHERE id = ?", { reportId })
    if not deleted then
        return
    end

    self.data[reportId] = nil

    Logs:new(source, {
        category = "reports",
        action = "delete",
        message = ("Deleted report %s"):format(reportId),
    })

    Bridge.Notify.showNotify(source, locale("report_deleted_success"), "success")
end

RegisterNetEvent("p_mdt/server/reports/delete", function(reportId)
    Reports:deleteReport(source, reportId)
end)

function Reports.getReportsByQuery(self, source, query)
    local job = Bridge.Framework.getPlayerJob(source)
    if not job then
        return {}
    end

    local results = {}
    local resultIndex = 0
    local loweredQuery = string.lower(query)

    for _, report in pairs(self.data) do
        if Reports:canAccessReport(report, job) and string.find(string.lower(report.title), loweredQuery, 1, true) then
            resultIndex = resultIndex + 1
            results[resultIndex] = {
                id = report.id,
                title = report.title,
                fields = {
                    ("%s: %s"):format(locale("id"), report.id),
                    ("%s: %s"):format(locale("type"), report.type),
                    ("%s: %s"):format(locale("status"), report.status),
                },
            }
        end
    end

    return results
end

exports("GetDOJSharedReports", function(sourceOrGrade)
    local playerGrade = nil

    if type(sourceOrGrade) == "number" then
        local job = Bridge.Framework.getPlayerJob(sourceOrGrade)
        if job and Reports.isDojJob(job.name) then
            playerGrade = job.grade
        end
    elseif type(sourceOrGrade) == "table" then
        playerGrade = sourceOrGrade.grade
    end

    local sharedReports = {}
    for reportId, report in pairs(Reports.data) do
        if Reports:meetsRankRequirement(report.doj_rank_lock, playerGrade) then
            sharedReports[reportId] = report
        end
    end

    return sharedReports
end)

exports("IsDOJAvailable", function()
    return Reports.dojAvailable
end)
