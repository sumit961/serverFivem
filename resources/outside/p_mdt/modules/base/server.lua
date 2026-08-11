Base = {
    jobsData = {},
    playersCache = {},
    playersData = {},
    bulletinData = {},
    playersLicences = {},
}

function getDojGrades()
    local jobs = Bridge.Framework.getJobs() or {}
    if jobs.doj then
        return jobs.doj
    end
    for jobName, jobData in pairs(jobs) do
        if string.find(string.lower(jobName), "doj", 1, true) then
            return jobData
        end
    end
    return {}
end

function fetchDashboardData(source)
    local identifier = Bridge.Framework.getUniqueId(source)
    local job = Bridge.Framework.getPlayerJob(source)
    if Bridge and Bridge.Config and Bridge.Config.Debug then
        lib.print.info("Fetching dashboard data for player:", source, "with job:", job.name)
    end
    local departmentConfig = Config.Departments[job.name]
    local bossGrades = departmentConfig and departmentConfig.bossGrades or {}
    local playerRecord = Base.playersData[identifier]
    local dashboardData = {
        chat = Chat.messages,
        bolos = Bolo:getRecents(),
        incidents = Incidents:getRecents(),
        units = Editable.activeUnits[job.name] or {},
        bulletin = Base.bulletinData,
        playerData = {
            id = identifier,
            name = Bridge.Framework.getPlayerName(source),
            avatar = playerRecord and playerRecord.avatar or nil,
            duty = Bridge.Framework.CheckJobDuty(source),
            callsign = playerRecord and playerRecord.callsign or locale("no_data"),
            status = playerRecord and playerRecord.status or locale("no_data"),
            rank = job and job.grade_label or locale("no_data"),
            isBoss = lib.table.contains(bossGrades, job.grade),
        },
        permissions = Permissions.data[job.name]
            and Permissions.data[job.name][tostring(job.grade)]
            and Permissions.data[job.name][tostring(job.grade)].permissions
            or {},
        grades = Base.jobsData[job.name] or {},
        dojGrades = getDojGrades(),
        licences = departmentConfig and departmentConfig.licences or {},
        citizen_licences = departmentConfig and departmentConfig.citizen_licences or {},
        disabledSections = Config.MDT.disabledSections,
        dojAvailable = Reports.dojAvailable,
    }
    return dashboardData
end

function fetchDispatchData(_source)
    return {
        calls = Dispatch.alerts,
        units = {},
    }
end

function fetchBodycamsData(source)
    local job = Bridge.Framework.getPlayerJob(source)
    local bodycamsState = GlobalState["p_policejob/BodyCams"]
    local bodycams = {}
    local index = 1
    for playerId, bodycamData in pairs(bodycamsState or {}) do
        if job.name == bodycamData.jobName then
            local ped = GetPlayerPed(playerId)
            local vehicle = GetVehiclePedIsIn(ped, false)
            bodycams[index] = {
                playerId = playerId,
                name = bodycamData.name,
                badge = bodycamData.badge,
                coords = GetEntityCoords(ped),
                type = vehicle ~= 0 and "dashcam" or "bodycam",
            }
            index = index + 1
        end
    end
    return bodycams
end

Base.tabletFunctions = {
    dashboard = fetchDashboardData,
    dispatch = fetchDispatchData,
    bodycams = fetchBodycamsData,
}

exports("GetPlayerData", function(identifier)
    return Base.playersData[identifier] or nil
end)

function Base.exportHandler(self, resourceName, exportName, handler)
    AddEventHandler(("__cfx_export_%s_%s"):format(resourceName, exportName), function(setCB)
        setCB(handler)
    end)
end

CreateThread(function()
    while not MySQL or not MySQL.ready do
        Wait(100)
    end
    Wait(1000)
    local success, officers = pcall(MySQL.query.await, "SELECT * FROM p_mdt_officers")
    if not success or not officers then
        lib.print.error("[SQL-ERROR] Failed to fetch SQL data, please make sure SQL is imported and connected properly.")
        return
    end
    for _, row in ipairs(officers or {}) do
        if row.data then
            local playerData = json.decode(row.data)
            playerData.duty = nil
            Base.playersData[row.identifier] = playerData
        end
        if row.licences then
            Base.playersLicences[row.identifier] = json.decode(row.licences)
        end
    end
    while true do
        Wait(20000)
        for _, jobUnits in pairs(Editable.activeUnits) do
            jobUnits.coords = nil
            for playerId, unitData in pairs(jobUnits) do
                Wait(100)
                unitData.coords = GetEntityCoords(GetPlayerPed(playerId))
            end
        end
    end
end)

lib.callback.register("p_mdt/server/getMDTData", function(source, section, data)
    if Bridge and Bridge.Config and Bridge.Config.Debug then
        lib.print.info("MDT data request received from source:", source, "for section:", section, "with data:", data)
    end
    local sectionHandler = Base.tabletFunctions[section]
    if sectionHandler then
        return sectionHandler(source, data)
    end
    return nil
end)

RegisterNetEvent("p_mdt/server/updatePlayerData", function(data)
    local playerSource = source
    if Bridge and Bridge.Config and Bridge.Config.Debug then
        lib.print.info("Received player data update from source:", playerSource, data)
    end
    if not data or type(data) ~= "table" then
        return
    end
    local identifier = Bridge.Framework.getUniqueId(playerSource)
    Bridge.Framework.SetJobDuty(playerSource, data.duty)
    data.duty = nil
    Base.playersData[identifier] = data
    local job = Bridge.Framework.getPlayerJob(playerSource)
    local activeUnit = Editable.activeUnits[job.name] and Editable.activeUnits[job.name][playerSource]
    if activeUnit then
        activeUnit.callsign = data.callsign
        activeUnit.status = data.status
        activeUnit.avatar = data.avatar
    end
    MySQL.update("REPLACE INTO p_mdt_officers (data, identifier) VALUES (?, ?)", {
        json.encode(data),
        Bridge.Framework.getUniqueId(playerSource),
    })
    Editable:onPlayerDataChange(playerSource, data)
end)

CreateThread(function()
    while not Bridge or not Bridge.Framework do
        Wait(1000)
    end
    Base.jobLabels = Bridge.Framework.getJobLabels()
    local jobs = Bridge.Framework.getJobs()
    for departmentName in pairs(Config.Departments) do
        if jobs[departmentName] then
            Base.jobsData[departmentName] = jobs[departmentName]
        end
    end
end)

lib.callback.register("p_mdt/server/base/globalSearch", function(source, searchData)
    return {
        citizens = Editable:getCitizensByQuery(source, searchData.query, "global"),
        vehicles = Editable:getVehiclesByQuery(source, searchData.query, "global"),
        reports = Reports:getReportsByQuery(source, searchData.query),
    }
end)

RegisterNetEvent("p_mdt/server/bulletin/create", function(data)
    local bulletinEntry = {
        creator = Bridge.Framework.getUniqueId(source),
        id = #Base.bulletinData + 1,
        description = data.description,
        isImportant = data.isImportant,
        timestamp = os.time(),
    }
    table.insert(Base.bulletinData, 1, bulletinEntry)
end)

RegisterNetEvent("p_mdt/server/bulletin/edit", function(data)
    for _, bulletinEntry in pairs(Base.bulletinData) do
        if bulletinEntry.id == data.id then
            bulletinEntry.description = data.description
            break
        end
    end
end)

RegisterNetEvent("p_mdt/server/bulletin/delete", function(data)
    for index, bulletinEntry in pairs(Base.bulletinData) do
        if bulletinEntry.id == data.id then
            table.remove(Base.bulletinData, index)
            break
        end
    end
end)

Base:exportHandler("piotreq_gpt", "getLicenses", function()
    local licenses = {}
    for departmentName, departmentConfig in pairs(Config.Departments) do
        licenses[departmentName] = licenses[departmentName] or {}
        for licenseKey, licenseLabel in pairs(departmentConfig.licences) do
            licenses[departmentName][licenseKey] = { label = licenseLabel }
        end
    end
    return licenses
end)

Base:exportHandler("piotreq_gpt", "GenerateVIN", function()
    local vin = ""
    local charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    for _ = 1, 17 do
        local charIndex = math.random(1, #charset)
        vin = vin .. charset:sub(charIndex, charIndex)
    end
    return vin
end)

exports("GetConfig", function()
    return Config
end)
