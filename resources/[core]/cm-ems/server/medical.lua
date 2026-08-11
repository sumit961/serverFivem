-- Server-authoritative medical reports and patient history.

local function cleanText(value, maximum, fallback)
    local text = tostring(value or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #text > maximum then text = text:sub(1, maximum) end
    return text ~= '' and text or fallback
end

local function playerPosition(src)
    local ped = GetPlayerPed(tonumber(src))
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local coords = GetEntityCoords(ped)
    return { x = math.floor(coords.x * 10) / 10, y = math.floor(coords.y * 10) / 10, z = math.floor(coords.z * 10) / 10 }
end

local function reportRow(row)
    row.id, row.incidentId, row.billing = tonumber(row.id), tonumber(row.incident_id), tonumber(row.billing) or 0
    row.patientCid, row.patientName = tostring(row.patient_cid), tostring(row.patient_name)
    row.medicCid = row.medic_cid and tostring(row.medic_cid) or nil
    row.medicName, row.hospitalId = tostring(row.medic_name or 'Hospital'), row.hospital_id
    row.injuries, row.medications, row.vitals = decode(row.injuries), decode(row.medications), decode(row.vitals)
    row.createdAt = tostring(row.created_at or '')
    row.incident_id, row.patient_cid, row.patient_name, row.medic_cid, row.medic_name = nil, nil, nil, nil, nil
    row.hospital_id, row.created_at = nil, nil
    return row
end

local function insertReport(data)
    return MySQL.insert.await([[INSERT INTO cm_ems_medical_reports
        (incident_id, patient_cid, patient_name, medic_cid, medic_name, hospital_id, location,
         injuries, treatment, medications, vitals, outcome, billing)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
        data.incidentId, data.patientCid, data.patientName, data.medicCid, data.medicName,
        data.hospitalId, data.location, json.encode(data.injuries or {}), data.treatment,
        json.encode(data.medications or {}), json.encode(data.vitals or {}), data.outcome, data.billing or 0,
    })
end

AddEventHandler('cm-ems:server:recordMedicalEvent', function(patientSrc, payload)
    patientSrc = tonumber(patientSrc)
    payload = type(payload) == 'table' and payload or {}
    local patientCid = patientSrc and cid(patientSrc)
    if not patientCid then return end
    local medicSrc = tonumber(payload.medicSource)
    local medicCid = medicSrc and cid(medicSrc) or nil
    local event = cleanText(payload.event, 48, 'medical_event')
    local position = playerPosition(patientSrc)
    local location = cleanText(payload.location, 160,
        position and ('%.1f, %.1f, %.1f'):format(position.x, position.y, position.z) or 'Location unavailable')
    local reportId = insertReport({
        incidentId = tonumber(payload.incidentId), patientCid = patientCid, patientName = nameFor(patientCid),
        medicCid = medicCid, medicName = medicCid and nameFor(medicCid)
            or event:find('government', 1, true) and 'Government Doctor' or 'Hospital System',
        hospitalId = cleanText(payload.hospitalId, 48, nil), location = location,
        injuries = type(payload.injuries) == 'table' and payload.injuries or {},
        treatment = cleanText(payload.treatment, 2000, event:gsub('_', ' ')),
        medications = type(payload.medications) == 'table' and payload.medications or {},
        vitals = type(payload.vitals) == 'table' and payload.vitals or {},
        outcome = cleanText(payload.outcome, 48, event), billing = math.max(0, math.floor(tonumber(payload.billing) or 0)),
    })
    log(medicCid or patientCid, 'medical_report_automatic', { reportId = reportId, patientCid = patientCid, event = event })
end)

lib.callback.register('cm-ems:server:createMedicalReport', function(src, payload)
    if not rateLimit(src, 'create_medical_report', 1500) then return false, 'Please wait.' end
    local medicCid = cid(src)
    local member = medicCid and memberFor(medicCid)
    if not member or not dbBoolean(member.on_duty) or not has(member, 'ems.write_medical_reports') then
        return false, 'You must be on duty with report permission.'
    end
    payload = type(payload) == 'table' and payload or {}
    local patientCid = tostring(payload.patientCid or '')
    if patientCid == '' or not MySQL.scalar.await('SELECT id FROM characters WHERE id = ? LIMIT 1', { patientCid }) then
        return false, 'Patient character ID does not exist.'
    end
    local contextValid = false
    local patientSrc = sourceFor(patientCid)
    if patientSrc and GetPlayerRoutingBucket(src) == GetPlayerRoutingBucket(patientSrc) then
        local medicPed, patientPed = GetPlayerPed(src), GetPlayerPed(patientSrc)
        if medicPed and medicPed ~= 0 and patientPed and patientPed ~= 0 then
            contextValid = #(GetEntityCoords(medicPed) - GetEntityCoords(patientPed)) <= 10.0
        end
    end
    local incidentId = tonumber(payload.incidentId)
    if not contextValid and incidentId then
        contextValid = MySQL.scalar.await([[SELECT 1 FROM cm_ems_incident_events
            WHERE incident_id = ? AND actor_cid = ? AND event_type IN ('accepted','on_scene','transporting','at_hospital')
            LIMIT 1]], { incidentId, medicCid }) ~= nil
    end
    local admin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true
    if not contextValid and not admin then
        return false, 'Move near the patient or link a dispatch incident you responded to.'
    end
    local injuries = {}
    if type(payload.injuries) == 'table' then
        for _, injury in ipairs(payload.injuries) do
            local value = cleanText(injury, 80, nil)
            if value and #injuries < 12 then injuries[#injuries + 1] = value end
        end
    elseif payload.injuries then
        local value = cleanText(payload.injuries, 500, nil)
        if value then injuries[1] = value end
    end
    local medications = {}
    if type(payload.medications) == 'table' then
        for _, medication in ipairs(payload.medications) do
            local value = cleanText(medication, 80, nil)
            if value and #medications < 12 then medications[#medications + 1] = value end
        end
    end
    local position = playerPosition(src)
    local reportId = insertReport({
        incidentId = incidentId, patientCid = patientCid, patientName = nameFor(patientCid),
        medicCid = medicCid, medicName = nameFor(medicCid), hospitalId = cleanText(payload.hospitalId, 48, nil),
        location = position and ('%.1f, %.1f, %.1f'):format(position.x, position.y, position.z) or 'Location unavailable',
        injuries = injuries, treatment = cleanText(payload.treatment, 2000, 'Assessment only'),
        medications = medications, vitals = type(payload.vitals) == 'table' and payload.vitals or {},
        outcome = cleanText(payload.outcome, 48, 'treated'), billing = math.max(0, math.floor(tonumber(payload.billing) or 0)),
    })
    log(medicCid, 'medical_report_created', { reportId = reportId, patientCid = patientCid })
    if EMSAddTaskProgress then EMSAddTaskProgress(medicCid, 'medical_reports', 1, 'report:' .. tostring(reportId)) end
    return true, ('Medical report #%d was saved.'):format(tonumber(reportId) or 0), reportId
end)

local function historyFor(patientCid, limit)
    limit = math.max(1, math.min(math.floor(tonumber(limit) or 50), 100))
    local rows = MySQL.query.await(([=[SELECT * FROM cm_ems_medical_reports
        WHERE patient_cid = ? ORDER BY id DESC LIMIT %d]=]):format(limit), { tostring(patientCid) }) or {}
    for _, row in ipairs(rows) do reportRow(row) end
    return rows
end

lib.callback.register('cm-ems:server:medicalHistory', function(src, patientCid, limit)
    if not rateLimit(src, 'medical_history', 700) then return nil, 'Please wait.' end
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    local admin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true
    if not admin and (not member or not dbBoolean(member.on_duty) or not has(member, 'ems.view_medical_reports')) then
        return nil, 'You are not authorized to view patient history.'
    end
    patientCid = tostring(patientCid or '')
    if patientCid == '' then return nil, 'Enter a patient character ID.' end
    log(characterId, 'medical_history_viewed', { patientCid = patientCid })
    return historyFor(patientCid, limit)
end)

exports('GetPatientHistory', function(requesterCid, patientCid, limit)
    local member = requesterCid and memberFor(tostring(requesterCid))
    if not member or not has(member, 'ems.view_medical_reports') then return nil end
    return historyFor(patientCid, limit)
end)
