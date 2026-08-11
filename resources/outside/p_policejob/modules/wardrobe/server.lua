if not Config or not Config.Wardrobe or not Config.Wardrobe.Enabled then
    return
end

MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `p_policejob_outfits` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(64) NOT NULL,
            `job` VARCHAR(50) NOT NULL,
            `grades` JSON NOT NULL,
            `gender` VARCHAR(10) NOT NULL,
            `licenses` JSON DEFAULT NULL,
            `skin` LONGTEXT NOT NULL,
            `created_by` VARCHAR(100) NOT NULL,
            `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_job_gender` (`job`, `gender`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    Bridge.Debug("[Wardrobe] Database table verified")
end)

function getJobGrades(jobName)
    local grades = {}
    local jobs = Bridge.Framework.getJobs()
    local jobData = jobs and jobs[jobName]
    if not jobData then
        return grades
    end
    for gradeId, gradeData in pairs(jobData) do
        grades[#grades + 1] = {
            value = tostring(gradeId),
            label = gradeData.label,
            grade = tonumber(gradeId),
        }
    end
    table.sort(grades, function(a, b)
        return a.grade < b.grade
    end)
    return grades
end

function hasWardrobeAccess(playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job then
        return false
    end
    if not Config.Jobs[job.name] then
        return false
    end
    return true, job
end

function hasManageAccess(playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not job then
        return false
    end
    if not Config.Jobs[job.name] then
        return false
    end
    if job.grade < Config.Wardrobe.ManageGrade then
        return false
    end
    return true, job
end

lib.callback.register("p_policejob/wardrobe/getConfig", function(source)
    local hasAccess, job = hasWardrobeAccess(source)
    if not hasAccess then
        return nil
    end
    return {
        grades = getJobGrades(job.name),
        licenses = Editable.getWardrobeLicenses(source),
        currentJob = job.name,
        currentGrade = job.grade,
        canManage = job.grade >= Config.Wardrobe.ManageGrade,
    }
end)

lib.callback.register("p_policejob/wardrobe/getOutfits", function(source, gender)
    local hasAccess, job = hasWardrobeAccess(source)
    if not hasAccess then
        return {}
    end
    local rows = MySQL.query.await([[
        SELECT id, name, job, grades, gender, licenses, created_by, created_at
        FROM p_policejob_outfits
        WHERE job = ? AND gender = ?
        ORDER BY name ASC
    ]], { job.name, gender })
    local outfits = {}
    for _, row in ipairs(rows or {}) do
        outfits[#outfits + 1] = {
            id = row.id,
            name = row.name,
            job = row.job,
            grades = json.decode(row.grades) or {},
            gender = row.gender,
            licenses = row.licenses and json.decode(row.licenses) or nil,
            createdBy = row.created_by,
            createdAt = row.created_at,
        }
    end
    return outfits
end)

lib.callback.register("p_policejob/wardrobe/getOutfitSkin", function(source, outfitId)
    if not hasWardrobeAccess(source) then
        return nil
    end
    local row = MySQL.single.await("SELECT skin FROM p_policejob_outfits WHERE id = ?", { outfitId })
    if not row then
        return nil
    end
    return json.decode(row.skin)
end)

lib.callback.register("p_policejob/wardrobe/create", function(source, data)
    local hasAccess, job = hasManageAccess(source)
    if not hasAccess then
        return { success = false, error = "No permission" }
    end
    if not data.name or not data.grades or not data.gender or not data.skin then
        return { success = false, error = "Missing data" }
    end
    local createdBy = Bridge.Framework.getPlayerName(source) or ("Player " .. source)
    local licenses = nil
    if data.licenses and #data.licenses > 0 then
        licenses = json.encode(data.licenses)
    end
    local insertId = MySQL.insert.await([[
        INSERT INTO p_policejob_outfits (name, job, grades, gender, licenses, skin, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.name,
        job.name,
        json.encode(data.grades),
        data.gender,
        licenses,
        json.encode(data.skin),
        createdBy,
    })
    if not insertId then
        return { success = false, error = "Database error" }
    end
    Bridge.Debug(("[Wardrobe] Player %s created outfit id=%s name=%s job=%s"):format(
        source, insertId, data.name, job.name
    ))
    Bridge.Notify.showNotify(source, locale("outfit_created"), "success")
    return {
        success = true,
        outfit = {
            id = insertId,
            name = data.name,
            job = job.name,
            grades = data.grades,
            gender = data.gender,
            licenses = data.licenses and #data.licenses > 0 and data.licenses or nil,
            createdBy = createdBy,
            createdAt = os.date("%Y-%m-%d"),
        },
    }
end)

lib.callback.register("p_policejob/wardrobe/delete", function(source, data)
    local hasAccess, job = hasManageAccess(source)
    if not hasAccess then
        return { success = false }
    end
    if not data.outfitId then
        return { success = false }
    end
    local row = MySQL.single.await("SELECT job FROM p_policejob_outfits WHERE id = ?", { data.outfitId })
    if not row or row.job ~= job.name then
        return { success = false }
    end
    MySQL.query.await("DELETE FROM p_policejob_outfits WHERE id = ?", { data.outfitId })
    Bridge.Notify.showNotify(source, locale("outfit_deleted"), "success")
    return { success = true }
end)
