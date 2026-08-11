Applications = {
    data = {},
    questions = {},
}

CreateThread(function()
    local questionsFile = LoadResourceFile(GetCurrentResourceName(), "questions.json")
    Applications.questions = questionsFile and json.decode(questionsFile) or {}

    local rows = MySQL.query.await("SELECT * FROM p_mdt_applications")

    for _, row in ipairs(rows) do
        if not Applications.data[row.job] then
            Applications.data[row.job] = {}
        end

        Applications.data[row.job][tostring(row.id)] = {
            id = tostring(row.id),
            applicant = json.decode(row.applicant),
            questions = json.decode(row.questions),
            status = row.status,
            timestamp = row.timestamp,
            job = row.job,
            reviewer = json.decode(row.reviewer),
            reviewedAt = row.reviewedAt,
            reviewNote = row.reviewNote,
        }
    end
end)

function Applications.saveQuestions(self, jobName, data)
    self.questions[jobName] = data and data.questions or {}

    SaveResourceFile(
        GetCurrentResourceName(),
        "questions.json",
        json.encode(self.questions, { indent = true }),
        -1
    )
end

RegisterNetEvent("p_mdt/server/applications/saveQuestions", function(data)
    local source = source
    local job = Bridge.Framework.getPlayerJob(source)
    local jobName = job and job.name

    if not jobName or not Config.Departments[jobName] then
        return
    end

    Applications:saveQuestions(jobName, data)
end)

lib.callback.register("p_mdt/server/applications/getQuestions", function(source, jobName)
    return Applications.questions[jobName] or {}
end)

lib.callback.register("p_mdt/server/application/getApplications", function(source, jobName)
    return Applications.data[jobName] or {}
end)

function Applications.submit(self, source, data)
    if not data or not data.applicant or not data.questions then
        return false
    end

    local insertId = MySQL.insert.await([[
        INSERT INTO p_mdt_applications (applicant, questions, timestamp, job)
        VALUES (?, ?, ?, ?)
    ]], {
        json.encode(data.applicant),
        json.encode(data.questions),
        os.time(),
        data.job,
    })

    if not insertId then
        return false
    end

    if not self.data[data.job] then
        self.data[data.job] = {}
    end

    self.data[data.job][tostring(insertId)] = {
        id = tostring(insertId),
        applicant = data.applicant,
        questions = data.questions,
        status = "pending",
        timestamp = os.time(),
        job = data.job,
    }

    return true
end

RegisterNetEvent("p_mdt/server/applications/submit", function(data)
    Applications:submit(source, data)
end)

function Applications.review(self, source, data)
    local job = Bridge.Framework.getPlayerJob(source)
    local jobName = job and job.name

    if not jobName or not Config.Departments[jobName] then
        return
    end

    if not data or not data.id then
        return
    end

    local application = self.data[jobName] and self.data[jobName][tostring(data.id)]
    if not application then
        return
    end

    local updated = MySQL.update.await([[
        UPDATE p_mdt_applications
        SET status = ?, reviewer = ?, reviewedAt = ?, reviewNote = ?
        WHERE id = ? AND job = ?
    ]], {
        data.status,
        json.encode({
            id = Bridge.Framework.getUniqueId(source),
            name = Bridge.Framework.getPlayerName(source),
        }),
        os.time(),
        data.note or "",
        data.id,
        jobName,
    })

    if updated <= 0 then
        return false
    end

    application.status = data.status
    application.reviewer = {
        id = Bridge.Framework.getUniqueId(source),
        name = Bridge.Framework.getPlayerName(source),
    }
    application.reviewedAt = os.time()
    application.reviewNote = data.note or ""

    Config.Applications.onReview(source, application, data.message)

    Logs:new(source, {
        category = "applications",
        action = "review",
        message = ("Reviewed application %s with status %s"):format(data.id, data.status),
    })

    return application
end

lib.callback.register("p_mdt/server/applications/review", function(source, data)
    return Applications:review(source, data)
end)
