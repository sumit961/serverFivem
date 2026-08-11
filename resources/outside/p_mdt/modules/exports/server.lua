Exports = {}

function Exports.isESX()
    return GetResourceState("es_extended") == "started"
end

function Exports.isQBCore()
    return GetResourceState("qb-core") == "started"
end

function Exports.normalizePlate(plate)
    if not plate then
        return nil
    end
    return tostring(plate):gsub("^%s+", ""):gsub("%s+$", ""):upper()
end

function Exports.getPlayerSource(player)
    if not player then
        return nil
    end

    local source = player.source
    if not source and player.PlayerData then
        source = player.PlayerData.source
    end

    return source
end

function Exports.resolveCitizen(citizenId)
    if citizenId == nil then
        return nil
    end

    citizenId = tostring(citizenId)
    local offlinePlayer = Bridge.Framework.getOfflinePlayerByCitizenId(citizenId)

    if not offlinePlayer and citizenId:upper() ~= citizenId then
        citizenId = citizenId:upper()
        offlinePlayer = Bridge.Framework.getOfflinePlayerByCitizenId(citizenId)
    end

    if not offlinePlayer and Bridge.Framework.getOfflinePlayerByUniqueId then
        offlinePlayer = Bridge.Framework.getOfflinePlayerByUniqueId(citizenId)
    end

    if not offlinePlayer then
        return nil
    end

    local identifier = offlinePlayer.identifier or offlinePlayer.citizenid or citizenId
    local onlinePlayer = Bridge.Framework.getPlayerByUniqueId(identifier)
    local source = Exports.getPlayerSource(onlinePlayer)

    return {
        cid = citizenId,
        identifier = identifier,
        firstname = offlinePlayer.firstname,
        lastname = offlinePlayer.lastname,
        source = source,
        online = source ~= nil,
    }
end

function Exports.isDepartmentOfficer(source)
    if not source then
        return false
    end

    local job = Bridge.Framework.getPlayerJob(source)
    return job and Config.Departments[job.name] ~= nil
end

function Exports.hasFeatureAccess(source, permission)
    if not Exports.isDepartmentOfficer(source) then
        return false
    end
    return Permissions.hasPerm(source, permission)
end

exports("GetOfficerRoster", function(department)
    local departments = {}
    if department then
        departments[1] = department
    else
        for dept in pairs(Config.Departments) do
            departments[#departments + 1] = dept
        end
    end

    local roster = {}

    for _, dept in ipairs(departments) do
        if Exports.isESX() then
            local rows = MySQL.query.await("SELECT * FROM users WHERE job = ?", { dept }) or {}
            for _, row in ipairs(rows) do
                local onlinePlayer = Bridge.Framework.getPlayerByUniqueId(row.identifier)
                local source = Exports.getPlayerSource(onlinePlayer)
                local playerData = Base.playersData[row.identifier]

                roster[#roster + 1] = {
                    cid = row[Editable.citizenId],
                    identifier = row.identifier,
                    name = ("%s %s"):format(row.firstname, row.lastname),
                    job = dept,
                    grade = tonumber(row.job_grade),
                    callsign = playerData and playerData.callsign or nil,
                    unit = playerData and playerData.unit or nil,
                    status = playerData and playerData.status or nil,
                    online = source ~= nil,
                    source = source,
                    onDuty = source and Bridge.Framework.CheckJobDuty(source) or false,
                    lastSeen = row.last_seen or nil,
                }
            end
        elseif Exports.isQBCore() then
            local rows = MySQL.query.await([[
                SELECT *,
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) as firstname,
                    JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) as lastname
                FROM players
                WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?
            ]], { dept }) or {}

            for _, row in ipairs(rows) do
                local jobData = json.decode(row.job)
                local onlinePlayer = Bridge.Framework.getPlayerByUniqueId(row.citizenid)
                local source = Exports.getPlayerSource(onlinePlayer)
                local playerData = Base.playersData[row.citizenid]

                roster[#roster + 1] = {
                    cid = row[Editable.citizenId] or row.citizenid,
                    identifier = row.citizenid,
                    name = ("%s %s"):format(row.firstname, row.lastname),
                    job = dept,
                    grade = tonumber(jobData and jobData.grade and jobData.grade.level) or 0,
                    callsign = playerData and playerData.callsign or nil,
                    unit = playerData and playerData.unit or nil,
                    status = playerData and playerData.status or nil,
                    online = source ~= nil,
                    source = source,
                    onDuty = source and Bridge.Framework.CheckJobDuty(source) or false,
                    lastSeen = row.last_updated or nil,
                }
            end
        end
    end

    return roster
end)

exports("GetOnDutyOfficers", function(department)
    local officers = {}
    local activeUnits = Editable.activeUnits or {}

    for jobName, units in pairs(activeUnits) do
        if not department or jobName == department then
            for source, unitData in pairs(units) do
                local ped = GetPlayerPed(source)
                if ped and ped ~= 0 and Bridge.Framework.CheckJobDuty(source) then
                    local coords = GetEntityCoords(ped)
                    officers[#officers + 1] = {
                        source = source,
                        job = jobName,
                        cid = Bridge.Framework.getUniqueId(source, true),
                        identifier = Bridge.Framework.getUniqueId(source),
                        name = unitData.name,
                        grade = unitData.grade,
                        callsign = unitData.callsign,
                        status = unitData.status,
                        coords = { x = coords.x, y = coords.y, z = coords.z },
                        heading = GetEntityHeading(ped),
                    }
                end
            end
        end
    end

    return officers
end)

CreateThread(function()
    while not Bridge or not Bridge.Framework or not Editable do
        Wait(1000)
    end

    local dutyStates = {}

    while true do
        Wait(5000)

        local activeSources = {}
        local activeUnits = Editable.activeUnits or {}

        for _, units in pairs(activeUnits) do
            for source in pairs(units) do
                activeSources[source] = true
                local onDuty = Bridge.Framework.CheckJobDuty(source) and true or false

                if dutyStates[source] == nil then
                    dutyStates[source] = onDuty
                elseif dutyStates[source] ~= onDuty then
                    dutyStates[source] = onDuty
                    TriggerEvent("p_mdt:OnOfficerDutyChange", {
                        src = source,
                        cid = Bridge.Framework.getUniqueId(source, true),
                        onDuty = onDuty,
                    })
                end
            end
        end

        for source, wasOnDuty in pairs(dutyStates) do
            if not activeSources[source] then
                if wasOnDuty then
                    TriggerEvent("p_mdt:OnOfficerDutyChange", {
                        src = source,
                        cid = nil,
                        onDuty = false,
                    })
                end
                dutyStates[source] = nil
            end
        end
    end
end)

exports("GetCitizenByCid", function(citizenId)
    if not citizenId then
        return nil
    end

    citizenId = tostring(citizenId)
    local profile = Editable:getCitizenProfile(citizenId)
    if not profile and citizenId:upper() ~= citizenId then
        profile = Editable:getCitizenProfile(citizenId:upper())
    end

    return profile
end)

exports("SearchCitizens", function(query, limit)
    if not query or tostring(query):len() < 1 then
        return {}
    end

    local results = Editable:getCitizensByQuery(nil, tostring(query), "simple") or {}
    limit = tonumber(limit)

    if limit and limit < #results then
        local limited = {}
        for index = 1, limit do
            limited[index] = results[index]
        end
        return limited
    end

    return results
end)

function Exports.getCitizenOffenseHistory(citizenId)
    local citizen = Exports.resolveCitizen(citizenId)
    local identifiers = { tostring(citizenId) }

    if citizen then
        if citizen.identifier and citizen.identifier ~= tostring(citizenId) then
            identifiers[#identifiers + 1] = citizen.identifier
        end
        if citizen.cid ~= tostring(citizenId) then
            identifiers[#identifiers + 1] = citizen.cid
        end
    end

    local history = {}
    local seen = {}

    for _, identifier in ipairs(identifiers) do
        local judgments = Judgments:getCitizenJudgments(identifier) or {}
        for _, judgment in ipairs(judgments) do
            local key = ("%s_%s"):format(judgment.id, judgment.title)
            if not seen[key] then
                seen[key] = true
                history[#history + 1] = judgment
            end
        end
    end

    return history
end

exports("GetCitizenOffenseHistory", Exports.getCitizenOffenseHistory)
exports("GetOffenseLog", Exports.getCitizenOffenseHistory)

function Exports.findActiveVehicleBolo(plate)
    local normalizedPlate = Exports.normalizePlate(plate)
    for _, bolo in pairs(Bolo.Data) do
        if bolo.status == "active" and bolo.target and bolo.target.type == "vehicle" then
            if Exports.normalizePlate(bolo.target.value) == normalizedPlate then
                return bolo
            end
        end
    end
    return nil
end

exports("GetVehicleByPlate", function(plate)
    if not plate then
        return nil
    end

    local profile = Editable:getVehicleProfile(nil, tostring(plate))
    if not profile then
        profile = Editable:getVehicleProfile(nil, Exports.normalizePlate(plate))
    end

    if not profile then
        return nil
    end

    local bolo = Exports.findActiveVehicleBolo(profile.plate)
    profile.isFlagged = bolo ~= nil
    profile.flagReason = bolo and (bolo.description or bolo.title) or nil
    return profile
end)

exports("SearchVehiclesByPlate", function(query, limit)
    if not query or tostring(query):len() < 1 then
        return {}
    end

    local results = Editable:getVehiclesByQuery(nil, tostring(query), "simple") or {}
    limit = tonumber(limit)

    if limit and limit < #results then
        local limited = {}
        for index = 1, limit do
            limited[index] = results[index]
        end
        return limited
    end

    return results
end)

exports("GetFlaggedPlates", function()
    local flagged = {}
    for _, bolo in pairs(Bolo.Data) do
        if bolo.status == "active" and bolo.target and bolo.target.type == "vehicle" then
            flagged[#flagged + 1] = {
                plate = bolo.target.value,
                reason = bolo.description or bolo.title,
                flaggedBy = bolo.creator,
                flaggedAt = tonumber(bolo.timestamp),
                boloId = bolo.id,
            }
        end
    end
    return flagged
end)

exports("FlagPlate", function(source, plate, reason)
    if not plate then
        return false, "invalid_plate"
    end

    if not source or not Bridge.Framework.getPlayerJob(source) then
        return false, "invalid_officer"
    end

    if not Exports.hasFeatureAccess(source, "bolo.create") then
        return false, "no_permission"
    end

    if Exports.findActiveVehicleBolo(plate) then
        return false, "already_flagged"
    end

    local created = Bolo:new(source, {
        title = ("Flagged Plate: %s"):format(Exports.normalizePlate(plate)),
        description = reason or "",
        target = tostring(plate),
        tags = { "flagged" },
    })

    if not created then
        return false, "vehicle_not_found"
    end

    return true, "flagged"
end)

exports("UnflagPlate", function(source, plate)
    if not plate then
        return false, "invalid_plate"
    end

    if not source or not Bridge.Framework.getPlayerJob(source) then
        return false, "invalid_officer"
    end

    if not Exports.hasFeatureAccess(source, "bolo.change_status") then
        return false, "no_permission"
    end

    local bolo = Exports.findActiveVehicleBolo(plate)
    if not bolo then
        return false, "not_flagged"
    end

    Bolo:changeStatus(bolo.id, "expired")
    return true, "unflagged"
end)

CreateThread(function()
    while not Bolo do
        Wait(500)
    end

    local originalNew = Bolo.new
    Bolo.new = function(self, source, data)
        local created = originalNew(self, source, data)
        if created and created.target and created.target.type == "vehicle" then
            TriggerEvent("p_mdt:OnPlateFlagged", {
                plate = created.target.value,
                action = "flagged",
                reason = created.description or created.title,
                boloId = created.id,
            })
        end
        return created
    end

    local originalChangeStatus = Bolo.changeStatus
    Bolo.changeStatus = function(self, boloId, status)
        local previous = self.Data[tostring(boloId)]
        local changed = originalChangeStatus(self, boloId, status)

        if changed and previous and previous.target and previous.target.type == "vehicle" then
            TriggerEvent("p_mdt:OnPlateFlagged", {
                plate = previous.target.value,
                action = status == "active" and "flagged" or "unflagged",
                reason = previous.description or previous.title,
                boloId = previous.id,
            })
        end

        return changed
    end

    local originalDelete = Bolo.delete
    Bolo.delete = function(self, boloId)
        local previous = self.Data[tostring(boloId)]
        local deleted = originalDelete(self, boloId)

        if deleted and previous and previous.target and previous.target.type == "vehicle" and previous.status == "active" then
            TriggerEvent("p_mdt:OnPlateFlagged", {
                plate = previous.target.value,
                action = "unflagged",
                reason = previous.description or previous.title,
                boloId = previous.id,
            })
        end

        return deleted
    end
end)

exports("GetAuthorizedVehicles", function(jobName)
    if jobName then
        return Garage.vehicles[jobName] or {}
    end
    return Garage.vehicles
end)

exports("GetVehicleSpawnPoints", function(jobName)
    local points = lib.load("data.garages") or {}
    if jobName then
        return points[jobName] or {}
    end
    return points
end)

exports("IssueFine", function(source, citizenId, amount, reason)
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        return false, "invalid_amount"
    end

    reason = reason and tostring(reason) or "Fine"
    local citizen = Exports.resolveCitizen(citizenId)
    if not citizen then
        return false, "citizen_not_found"
    end

    if not citizen.source then
        return false, "target_offline"
    end

    local job = source and Bridge.Framework.getPlayerJob(source) or nil
    local society = job and job.name or "police"
    local paymentMethod = nil

    if GetResourceState("okokBilling") == "started" then
        TriggerEvent("okokBilling:CreateCustomInvoice", citizen.source, amount, reason, "Police", society, "Police")
        paymentMethod = "invoice"
    elseif GetResourceState("peleg-billing") == "started" then
        exports["peleg-billing"]:CreateBill(source, citizen.source, society, amount, reason, "bank")
        paymentMethod = "invoice"
    else
        Bridge.Framework.removeMoney(citizen.source, "bank", amount)
        paymentMethod = "bank"
    end

    local officer = {
        identifier = "external",
        name = "External Terminal",
    }

    if source and job then
        officer = {
            identifier = Bridge.Framework.getUniqueId(source),
            name = Bridge.Framework.getPlayerName(source),
        }
    end

    MySQL.insert([[
        INSERT INTO p_mdt_judgments (targets, charges, timestamp, officer)
        VALUES (?, ?, ?, ?)
    ]], {
        json.encode({ citizen.identifier }),
        json.encode({ {
            title = reason,
            customFine = amount,
            customSentence = 0,
        } }),
        os.time(),
        json.encode(officer),
    })

    if source and job then
        Logs:new(source, {
            category = "judgments",
            action = "issue",
            message = ("Issued fine of $%s to %s (export)"):format(amount, citizen.cid),
        })
    end

    TriggerEvent("p_mdt:OnFineIssued", {
        officerSrc = source,
        targetCid = citizen.cid,
        amount = amount,
        method = paymentMethod,
        reason = reason,
    })

    return true, paymentMethod
end)

exports("GrantLicense", function(source, citizenId, licenseType)
    if not licenseType then
        return false, "invalid_license_type"
    end

    if not Exports.isDepartmentOfficer(source) then
        return false, "invalid_officer"
    end

    local citizen = Exports.resolveCitizen(citizenId)
    if not citizen then
        return false, "citizen_not_found"
    end

    Editable:addCitizenLicense(source, {
        identifier = citizen.identifier,
        type = tostring(licenseType),
    })

    return true, "granted"
end)

exports("RevokeLicense", function(source, citizenId, licenseType)
    if not licenseType then
        return false, "invalid_license_type"
    end

    if not Exports.isDepartmentOfficer(source) then
        return false, "invalid_officer"
    end

    local citizen = Exports.resolveCitizen(citizenId)
    if not citizen then
        return false, "citizen_not_found"
    end

    Editable:deleteCitizenLicense(source, {
        identifier = citizen.identifier,
        type = tostring(licenseType),
    })

    return true, "revoked"
end)

exports("GetLicenseTypes", function(department)
    local types = {}
    local seen = {}

    for dept, config in pairs(Config.Departments) do
        if not department or dept == department then
            for licenseType in pairs(config.citizen_licences or {}) do
                if not seen[licenseType] then
                    seen[licenseType] = true
                    types[#types + 1] = licenseType
                end
            end
        end
    end

    return types
end)

exports("GetEvidenceList", function(sinceTimestamp)
    sinceTimestamp = tonumber(sinceTimestamp)
    local evidence = {}

    for _, entry in pairs(Evidences.data) do
        if not sinceTimestamp or sinceTimestamp <= (tonumber(entry.timestamp) or 0) then
            evidence[#evidence + 1] = entry
        end
    end

    return evidence
end)

exports("BroadcastAlert", function(source, message, priority)
    if not Dispatch then
        return false, "dispatch_disabled"
    end

    if not message then
        return false, "invalid_message"
    end

    local alertPriority = "low"
    if priority == "high" or priority == "emergency" or priority == "panic" then
        alertPriority = "high"
    elseif priority == "medium" then
        alertPriority = "medium"
    end

    local coords = vector3(0.0, 0.0, 0.0)
    if source then
        local ped = GetPlayerPed(source)
        if ped and ped ~= 0 then
            coords = GetEntityCoords(ped)
        end
    end

    local alertId = Dispatch:new({
        title = tostring(message),
        description = priority and ("[%s]"):format(tostring(priority)) or nil,
        priority = alertPriority,
        coords = coords,
        playerId = source,
    })

    if not alertId then
        return false, "failed"
    end

    return true, "dispatch"
end)

exports("GetActiveAlerts", function(maxAge)
    if not Dispatch then
        return {}
    end

    maxAge = tonumber(maxAge)
    local alerts = {}
    local now = os.time()

    for _, alert in ipairs(Dispatch.alerts) do
        if not maxAge or maxAge >= (now - (tonumber(alert.timestamp) or 0)) then
            alerts[#alerts + 1] = alert
        end
    end

    return alerts
end)

CreateThread(function()
    while not Config or not Config.Dispatch do
        Wait(100)
    end

    if Config.Dispatch.disableDispatch then
        return
    end

    while not Dispatch do
        Wait(500)
    end

    local originalNew = Dispatch.new
    Dispatch.new = function(self, alertData)
        local alertId = originalNew(self, alertData)
        if alertId then
            TriggerEvent("p_mdt:OnAlert", {
                id = alertId,
                title = alertData.title,
                message = alertData.description,
                coords = alertData.coords,
                by = alertData.playerId,
                timeUnix = os.time(),
            })
        end
        return alertId
    end
end)

exports("HasFeatureAccess", function(source, permission)
    return Exports.hasFeatureAccess(source, permission)
end)
