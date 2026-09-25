-- Cross-agency legal MDT. Identity/vehicle/wanted/licence/booking records
-- remain owned by their established resources; cm-law owns shared agency
-- notes, reports and warrants.

local MdtReady = false

local function authorized(src)
    if not MdtReady then return nil, nil, 'Shared MDT is still loading.' end
    local member, characterId = activeMemberForSource(src)
    if not member or member.suspended or not member.onDuty
        or not LawCapabilityEnabled(member.organizationId, 'mdt')
        or not (member.isLeader or member.permissions['law.mdt'] == true) then
        return nil, characterId, 'You must be on duty with MDT permission.'
    end
    return member, characterId
end

local function clean(value, limit)
    return tostring(value or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, limit)
end

local function citizenExists(characterId)
    return MySQL.scalar.await('SELECT id FROM characters WHERE id=? LIMIT 1', { tostring(characterId or '') }) ~= nil
end

local function safeRows(query, values)
    local ok, rows = pcall(function() return MySQL.query.await(query, values or {}) end)
    return ok and rows or {}
end

lib.callback.register('cm-law:server:mdtSearchCitizens', function(src, query)
    local member, _, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_search', 500) then return { ok = false, error = 'Please wait.' } end
    query = clean(query, 64)
    if #query < 2 then return { ok = false, error = 'Enter at least two characters.' } end
    local like, numeric = '%' .. query .. '%', tonumber(query)
    local rows = numeric and MySQL.query.await([[SELECT id,first_name,last_name FROM characters
        WHERE id=? OR first_name LIKE ? OR last_name LIKE ? ORDER BY first_name,last_name LIMIT 30]], { numeric, like, like })
        or MySQL.query.await([[SELECT id,first_name,last_name FROM characters
        WHERE first_name LIKE ? OR last_name LIKE ? ORDER BY first_name,last_name LIMIT 30]], { like, like })
    local statusMap = {}
    for _, status in ipairs(safeRows('SELECT character_id,stars,wanted FROM cm_police_criminal_status WHERE wanted=1', {})) do
        statusMap[tostring(status.character_id)] = status
    end
    local result = {}
    for _, row in ipairs(rows or {}) do
        local id, status = tostring(row.id), statusMap[tostring(row.id)]
        result[#result + 1] = { characterId = id,
            name = clean(('%s %s'):format(row.first_name or '', row.last_name or ''), 100),
            stars = status and tonumber(status.stars) or 0, wanted = status and tonumber(status.wanted) == 1 or false }
    end
    return { ok = true, citizens = result }
end)

lib.callback.register('cm-law:server:mdtCitizenProfile', function(src, characterId)
    local member, _, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    characterId = tostring(characterId or '')
    local citizen = MySQL.single.await('SELECT id,first_name,last_name FROM characters WHERE id=? LIMIT 1', { characterId })
    if not citizen then return { ok = false, error = 'Citizen not found.' } end
    local criminal = safeRows('SELECT stars,wanted,wanted_reason,photo_url FROM cm_police_criminal_status WHERE character_id=? LIMIT 1', { characterId })[1]
    local licenses = safeRows('SELECT license_type,status,reason,license_number FROM cm_police_licenses WHERE character_id=?', { characterId })
    local bookings = safeRows([[SELECT id,reason,wanted_stars,sentence_minutes,handoff_status,booked_at,release_at,released_at
        FROM cm_police_bookings WHERE character_id=? ORDER BY id DESC LIMIT 25]], { characterId })
    local legalBookings = safeRows([[SELECT id,organization_id,officer_cid,reason,charges,sentence_minutes,fine_amount,
        handoff_status,failure_reason,booked_at,confirmed_at,release_at,released_at
        FROM cm_legal_bookings WHERE character_id=? ORDER BY id DESC LIMIT 50]], { characterId })
    for _, row in ipairs(legalBookings) do
        local ok, decoded = pcall(json.decode, row.charges or '[]')
        row.charges = ok and type(decoded) == 'table' and decoded or {}
    end
    local citations = safeRows([[SELECT id,violation_label,fine,created_at
        FROM cm_police_citations WHERE target_cid=? ORDER BY id DESC LIMIT 50]], { characterId })
    local sharedCitations = safeRows([[SELECT id,organization_id,violation_label,amount AS fine,status,created_at
        FROM cm_legal_citations WHERE target_cid=? ORDER BY id DESC LIMIT 50]], { characterId })
    for _, citation in ipairs(sharedCitations) do
        citation.id = ('law:%s'):format(tostring(citation.id))
        citations[#citations + 1] = citation
    end
    table.sort(citations, function(a, b) return tostring(a.created_at or '') > tostring(b.created_at or '') end)
    while #citations > 100 do table.remove(citations) end
    local notes = MySQL.query.await([[SELECT n.id,n.organization_id,n.author_cid,n.note,n.created_at,
        CONCAT(COALESCE(c.first_name,''),' ',COALESCE(c.last_name,'')) author_name
        FROM cm_legal_mdt_notes n LEFT JOIN characters c ON c.id=n.author_cid
        WHERE n.target_cid=? ORDER BY n.id DESC LIMIT 100]], { characterId }) or {}
    local reports = MySQL.query.await([[SELECT r.id,r.organization_id,r.author_cid,r.title,r.narrative,r.summary,
        r.status,r.evidence,r.linked_officers,r.photo_url,r.created_at,
        CONCAT(COALESCE(c.first_name,''),' ',COALESCE(c.last_name,'')) author_name
        FROM cm_legal_mdt_reports r LEFT JOIN characters c ON c.id=r.author_cid
        WHERE r.target_cid=? ORDER BY r.id DESC LIMIT 50]], { characterId }) or {}
    for _, row in ipairs(reports) do
        local evidenceOk, evidence = pcall(json.decode, row.evidence or '[]')
        row.evidence = evidenceOk and type(evidence) == 'table' and evidence or {}
        local officersOk, officers = pcall(json.decode, row.linked_officers or '[]')
        row.linkedOfficers = officersOk and type(officers) == 'table' and officers or {}
        row.linked_officers = nil
    end
    local warrants = MySQL.query.await([[SELECT w.id,w.organization_id,w.author_cid,w.reason,w.stars,w.status,w.created_at,w.closed_at,
        CONCAT(COALESCE(c.first_name,''),' ',COALESCE(c.last_name,'')) author_name
        FROM cm_legal_mdt_warrants w LEFT JOIN characters c ON c.id=w.author_cid
        WHERE w.target_cid=? ORDER BY w.id DESC LIMIT 50]], { characterId }) or {}
    local vehicles = {}
    pcall(function() vehicles = exports['cm-vehicles']:GetVehiclesByOwner(characterId) or {} end)
    local vehicleList = {}
    for _, vehicle in ipairs(vehicles) do
        vehicleList[#vehicleList + 1] = { vehicleId = tonumber(vehicle.id), plate = tostring(vehicle.plate or ''),
            model = tostring(vehicle.model or ''), label = tostring(vehicle.label or vehicle.model or ''),
            licenseNumber = vehicle.license_number and tostring(vehicle.license_number) or nil }
    end
    return { ok = true, profile = {
        characterId = characterId, name = clean(('%s %s'):format(citizen.first_name or '', citizen.last_name or ''), 100),
        wanted = criminal and tonumber(criminal.wanted) == 1 or false, stars = criminal and tonumber(criminal.stars) or 0,
        wantedReason = criminal and criminal.wanted_reason or nil, photoUrl = criminal and criminal.photo_url or nil,
        licenses = licenses, licenseTypes = (PoliceConfig.Mdt or {}).LicenseTypes or {},
        bookings = bookings, legalBookings = legalBookings, citations = citations, notes = notes, reports = reports,
        warrants = warrants, vehicles = vehicleList,
    }, actor = { organizationId = member.organizationId, isLeader = member.isLeader } }
end)

lib.callback.register('cm-law:server:mdtVehicleSearch', function(src, plate)
    local member, _, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_vehicle', 500) then return { ok = false, error = 'Please wait.' } end
    plate = clean(plate, 16):gsub('%s+', ''):upper()
    if plate == '' then return { ok = false, error = 'Enter a plate.' } end
    local row
    pcall(function() row = exports['cm-vehicles']:GetVehicleByPlate(plate) end)
    if not row then return { ok = false, error = 'Vehicle not found.' } end
    local ownerCid = row.owner_character_id and tostring(row.owner_character_id) or nil
    local impound = safeRows([[SELECT fee,reason,impounded_at FROM cm_police_impounds
        WHERE vehicle_id=? AND released_at IS NULL ORDER BY id DESC LIMIT 1]], { row.id })[1]
    local bolo = type(LawActiveBoloForPlate) == 'function' and LawActiveBoloForPlate(row.plate or plate) or nil
    return { ok = true, vehicle = { vehicleId = tonumber(row.id), plate = tostring(row.plate or plate),
        model = tostring(row.model or ''), label = tostring(row.label or row.model or ''),
        ownerCid = ownerCid, ownerName = ownerCid and nameFor(ownerCid) or 'Unknown',
        licenseNumber = row.license_number and tostring(row.license_number) or nil,
        impound = impound and { fee = tonumber(impound.fee) or 0, reason = tostring(impound.reason or ''),
            impoundedAt = tostring(impound.impounded_at or '') } or nil,
        bolo = bolo } }
end)

-- License status was previously police-only write access (cm_police_licenses,
-- embedded/police/server/mdt.lua's mdtSetLicenseStatus) even though the
-- shared MDT already reads it for every citizen profile. Writing directly to
-- that same table is consistent with how the read already works (embedded
-- police is part of this same resource, not a separate one -- see
-- server/records.lua's comment on why a genuinely separate resource gets an
-- export instead). Purely a record flag: per the original callback's own
-- comment, nothing in this codebase enforces driving/carrying without a
-- license, so this can't break existing gameplay.
lib.callback.register('cm-law:server:mdtSetLicenseStatus', function(src, characterId, licenseType, status, reason)
    local member, actorCid, reasonError = authorized(src)
    if not member then return { ok = false, error = reasonError } end
    if not rateLimit(src, 'law_mdt_license', 800) then return { ok = false, error = 'Please wait.' } end
    characterId = tostring(characterId or '')
    local validType = false
    for _, t in ipairs((PoliceConfig.Mdt or {}).LicenseTypes or {}) do if t == licenseType then validType = true break end end
    if not citizenExists(characterId) or not validType then return { ok = false, error = 'Invalid citizen or license type.' } end
    if status ~= 'active' and status ~= 'revoked' then return { ok = false, error = 'Invalid license status.' } end
    local cleanReason = clean(reason, 160)
    MySQL.insert.await(
        'INSERT INTO cm_police_licenses (character_id, license_type, status, set_by, reason) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE status = VALUES(status), set_by = VALUES(set_by), reason = VALUES(reason)',
        { characterId, licenseType, status, actorCid, cleanReason ~= '' and cleanReason or nil }
    )
    logActivity(member.organizationId, actorCid, 'mdt_license_set', { targetCid = characterId, licenseType = licenseType, status = status })
    return { ok = true, message = ('%s license %s.'):format(licenseType, status) }
end)

lib.callback.register('cm-law:server:mdtCapturePhoto', function(src, characterId)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_photo', 4000) then return { ok = false, error = 'Please wait before capturing another photo.' } end
    characterId = tostring(characterId or '')
    if not citizenExists(characterId) then return { ok = false, error = 'Citizen not found.' } end
    local targetSrc = sourceFor(characterId)
    if not targetSrc then return { ok = false, error = 'That citizen is not currently online.' } end
    local officerPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
    if officerPed == 0 or targetPed == 0 then return { ok = false, error = 'Citizen is unavailable.' } end
    if #(GetEntityCoords(officerPed) - GetEntityCoords(targetPed)) > 5.0 then return { ok = false, error = 'Move closer to the citizen to take a photo.' } end
    local photoUrl = LawCapturePhoto(targetSrc, 'citizens', characterId)
    if not photoUrl then return { ok = false, error = 'Photo capture failed. Is screenshot-basic running?' } end
    MySQL.insert.await([[INSERT INTO cm_police_criminal_status (character_id, photo_url, set_by)
        VALUES (?, ?, NULL) ON DUPLICATE KEY UPDATE photo_url = VALUES(photo_url)]], { characterId, photoUrl })
    logActivity(member.organizationId, actorCid, 'mdt_citizen_photo_captured', { targetCid = characterId })
    return { ok = true, message = 'Citizen photo captured.', photoUrl = photoUrl }
end)

lib.callback.register('cm-law:server:mdtAddNote', function(src, characterId, note)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_note', 700) then return { ok = false, error = 'Please wait.' } end
    characterId, note = tostring(characterId or ''), clean(note, 1000)
    if not citizenExists(characterId) or #note < 3 then return { ok = false, error = 'Enter a valid note.' } end
    MySQL.insert.await('INSERT INTO cm_legal_mdt_notes (target_cid,organization_id,author_cid,note) VALUES (?,?,?,?)',
        { characterId, member.organizationId, actorCid, note })
    logActivity(member.organizationId, actorCid, 'mdt_note_added', { targetCid = characterId })
    return { ok = true, message = 'Shared MDT note added.' }
end)

-- Case-file access for the actions below: the original author, any leader,
-- or anyone already linked to the case as an involved officer -- matches how
-- warrants let "the issuing agency or a leader" act on a shared record.
local function reportCaseAccess(reportId, member, actorCid)
    local row = MySQL.single.await('SELECT id,author_cid,linked_officers FROM cm_legal_mdt_reports WHERE id=? LIMIT 1', { reportId })
    if not row then return nil, 'That report no longer exists.' end
    if member.isLeader or tostring(row.author_cid) == tostring(actorCid) then return row end
    local ok, linked = pcall(json.decode, row.linked_officers or '[]')
    if ok and type(linked) == 'table' then
        for _, officer in ipairs(linked) do
            if tostring(officer.characterId or '') == tostring(actorCid) then return row end
        end
    end
    return nil, 'Only the report author, a linked officer, or a leader can update this case.'
end

lib.callback.register('cm-law:server:mdtCreateReport', function(src, data)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_report', 900) then return { ok = false, error = 'Please wait.' } end
    data = type(data) == 'table' and data or {}
    local targetCid, title, narrative = tostring(data.characterId or ''), clean(data.title, 120), clean(data.narrative, 6000)
    local summary = clean(data.summary, 300)
    if not citizenExists(targetCid) or #title < 3 or #narrative < 10 then return { ok = false, error = 'Citizen, title, and detailed narrative are required.' } end
    local id = MySQL.insert.await([[INSERT INTO cm_legal_mdt_reports
        (target_cid,organization_id,author_cid,title,narrative,summary,status,evidence,linked_officers)
        VALUES (?,?,?,?,?,?,'open','[]','[]')]],
        { targetCid, member.organizationId, actorCid, title, narrative, summary ~= '' and summary or nil })
    logActivity(member.organizationId, actorCid, 'mdt_report_created', { targetCid = targetCid, reportId = id })
    return { ok = true, message = ('Shared report #%s created.'):format(id) }
end)

lib.callback.register('cm-law:server:mdtSetReportStatus', function(src, reportId, status)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    reportId = tonumber(reportId)
    status = tostring(status or '')
    if status ~= 'open' and status ~= 'under_review' and status ~= 'closed' then return { ok = false, error = 'Invalid case status.' } end
    local row, accessError = reportId and reportCaseAccess(reportId, member, actorCid)
    if not row then return { ok = false, error = accessError } end
    MySQL.update.await('UPDATE cm_legal_mdt_reports SET status=? WHERE id=?', { status, reportId })
    logActivity(member.organizationId, actorCid, 'mdt_report_status_changed', { reportId = reportId, status = status })
    return { ok = true, message = ('Case marked %s.'):format(status:gsub('_', ' ')) }
end)

lib.callback.register('cm-law:server:mdtAddReportEvidence', function(src, reportId, label, note)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_report_evidence', 700) then return { ok = false, error = 'Please wait.' } end
    reportId = tonumber(reportId)
    label, note = clean(label, 80), clean(note, 400)
    if label == '' then return { ok = false, error = 'Enter an evidence label.' } end
    local row, accessError = reportId and reportCaseAccess(reportId, member, actorCid)
    if not row then return { ok = false, error = accessError } end
    local current = MySQL.scalar.await('SELECT evidence FROM cm_legal_mdt_reports WHERE id=?', { reportId })
    local ok, list = pcall(json.decode, current or '[]')
    list = ok and type(list) == 'table' and list or {}
    if #list >= 30 then return { ok = false, error = 'This case already has the maximum amount of evidence logged.' } end
    list[#list + 1] = { label = label, note = note, loggedBy = nameFor(actorCid), loggedAt = os.date('%Y-%m-%d %H:%M:%S') }
    MySQL.update.await('UPDATE cm_legal_mdt_reports SET evidence=? WHERE id=?', { json.encode(list), reportId })
    logActivity(member.organizationId, actorCid, 'mdt_report_evidence_added', { reportId = reportId, label = label })
    return { ok = true, message = 'Evidence logged.' }
end)

lib.callback.register('cm-law:server:mdtLinkReportOfficer', function(src, reportId, officerCid)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_report_link', 700) then return { ok = false, error = 'Please wait.' } end
    reportId = tonumber(reportId)
    officerCid = clean(officerCid, 64)
    if officerCid == '' then return { ok = false, error = 'Enter an officer character ID.' } end
    local isMember = MySQL.scalar.await('SELECT character_id FROM cm_legal_members WHERE character_id=? LIMIT 1', { officerCid })
    if not isMember then
        isMember = MySQL.scalar.await('SELECT character_id FROM cm_police_members WHERE character_id=? LIMIT 1', { officerCid })
    end
    if not isMember then
        return { ok = false, error = 'That character is not a member of a legal organization.' }
    end
    local row, accessError = reportId and reportCaseAccess(reportId, member, actorCid)
    if not row then return { ok = false, error = accessError } end
    local current = MySQL.scalar.await('SELECT linked_officers FROM cm_legal_mdt_reports WHERE id=?', { reportId })
    local ok, list = pcall(json.decode, current or '[]')
    list = ok and type(list) == 'table' and list or {}
    for _, officer in ipairs(list) do
        if tostring(officer.characterId or '') == officerCid then return { ok = false, error = 'That officer is already linked to this case.' } end
    end
    if #list >= 15 then return { ok = false, error = 'This case already has the maximum number of linked officers.' } end
    list[#list + 1] = { characterId = officerCid, name = nameFor(officerCid) }
    MySQL.update.await('UPDATE cm_legal_mdt_reports SET linked_officers=? WHERE id=?', { json.encode(list), reportId })
    logActivity(member.organizationId, actorCid, 'mdt_report_officer_linked', { reportId = reportId, officerCid = officerCid })
    return { ok = true, message = 'Officer linked to case.' }
end)

lib.callback.register('cm-law:server:mdtCaptureReportPhoto', function(src, reportId)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_report_photo', 4000) then return { ok = false, error = 'Please wait before capturing another photo.' } end
    reportId = tonumber(reportId)
    local row, accessError = reportId and reportCaseAccess(reportId, member, actorCid)
    if not row then return { ok = false, error = accessError } end
    local photoUrl = LawCapturePhoto(src, 'reports', ('report_%d'):format(reportId))
    if not photoUrl then return { ok = false, error = 'Photo capture failed. Is screenshot-basic running?' } end
    MySQL.update.await('UPDATE cm_legal_mdt_reports SET photo_url=? WHERE id=?', { photoUrl, reportId })
    logActivity(member.organizationId, actorCid, 'mdt_report_photo_captured', { reportId = reportId })
    return { ok = true, message = 'Scene photo attached to case.', photoUrl = photoUrl }
end)

local function setLiveWanted(characterId, stars)
    local online = sourceFor(characterId)
    if online then pcall(function() exports[Config.PlayerDataResource]:SetWantedStars(online, stars) end) end
end

lib.callback.register('cm-law:server:mdtSetWanted', function(src, characterId, stars, reasonText)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_wanted', 900) then return { ok = false, error = 'Please wait.' } end
    characterId, stars = tostring(characterId or ''), math.max(0, math.min(5, math.floor(tonumber(stars) or 0)))
    reasonText = clean(reasonText, 160)
    if not citizenExists(characterId) then return { ok = false, error = 'Citizen not found.' } end
    if stars > 0 and #reasonText < 3 then return { ok = false, error = 'A wanted reason is required.' } end
    local ok = pcall(function()
        MySQL.insert.await([[INSERT INTO cm_police_criminal_status (character_id,stars,wanted,wanted_reason,set_by)
            VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE stars=VALUES(stars),wanted=VALUES(wanted),wanted_reason=VALUES(wanted_reason),set_by=VALUES(set_by)]],
            { characterId, stars, stars > 0 and 1 or 0, stars > 0 and reasonText or nil, actorCid })
    end)
    if not ok then return { ok = false, error = 'Wanted records are unavailable.' } end
    setLiveWanted(characterId, stars)
    logActivity(member.organizationId, actorCid, 'mdt_wanted_set', { targetCid = characterId, stars = stars, reason = reasonText })
    return { ok = true, message = stars > 0 and ('Wanted level set to %d stars.'):format(stars) or 'Wanted level cleared.' }
end)

lib.callback.register('cm-law:server:mdtCreateWarrant', function(src, data)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_warrant', 900) then return { ok = false, error = 'Please wait.' } end
    data = type(data) == 'table' and data or {}
    local targetCid, stars, warrantReason = tostring(data.characterId or ''), math.max(1, math.min(5, math.floor(tonumber(data.stars) or 1))), clean(data.reason, 1000)
    if not citizenExists(targetCid) or #warrantReason < 5 then return { ok = false, error = 'Citizen and warrant reason are required.' } end
    local id = MySQL.insert.await([[INSERT INTO cm_legal_mdt_warrants
        (target_cid,organization_id,author_cid,reason,stars,status) VALUES (?,?,?,?,?,'active')]],
        { targetCid, member.organizationId, actorCid, warrantReason, stars })
    pcall(function() MySQL.insert.await([[INSERT INTO cm_police_criminal_status (character_id,stars,wanted,wanted_reason,set_by)
        VALUES (?,?,1,?,?) ON DUPLICATE KEY UPDATE stars=GREATEST(stars,VALUES(stars)),wanted=1,wanted_reason=VALUES(wanted_reason),set_by=VALUES(set_by)]],
        { targetCid, stars, warrantReason:sub(1, 160), actorCid }) end)
    setLiveWanted(targetCid, stars)
    logActivity(member.organizationId, actorCid, 'mdt_warrant_created', { targetCid = targetCid, warrantId = id, stars = stars })
    return { ok = true, message = ('Shared warrant #%s issued.'):format(id) }
end)

lib.callback.register('cm-law:server:mdtCloseWarrant', function(src, warrantId)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    warrantId = tonumber(warrantId)
    local row = warrantId and MySQL.single.await('SELECT id,organization_id,target_cid,status FROM cm_legal_mdt_warrants WHERE id=? LIMIT 1', { warrantId })
    if not row or row.status ~= 'active' then return { ok = false, error = 'Active warrant not found.' } end
    if not member.isLeader and row.organization_id ~= member.organizationId then return { ok = false, error = 'Only the issuing agency or a leader can close this warrant.' } end
    MySQL.update.await("UPDATE cm_legal_mdt_warrants SET status='closed',closed_by=?,closed_at=NOW() WHERE id=? AND status='active'", { actorCid, warrantId })
    logActivity(member.organizationId, actorCid, 'mdt_warrant_closed', { targetCid = row.target_cid, warrantId = warrantId })
    return { ok = true, message = 'Warrant closed. Review the wanted level separately.' }
end)

-- Single "front page" summary for the MDT idle view: active warrants, active
-- BOLOs, recent incidents and simple custody/dispatch stats. Each section is
-- pcall-wrapped so one bad query (e.g. a table not yet created on a fresh
-- install) blanks only that section instead of the whole dashboard.
local function dashboardSection(fn)
    local ok, result = pcall(fn)
    return ok and result or {}
end

lib.callback.register('cm-law:server:mdtDashboard', function(src)
    local member, _, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    local warrants = dashboardSection(function()
        return MySQL.query.await([[SELECT w.id,w.organization_id,w.target_cid,w.reason,w.stars,w.created_at,
            CONCAT(COALESCE(c.first_name,''),' ',COALESCE(c.last_name,'')) target_name
            FROM cm_legal_mdt_warrants w LEFT JOIN characters c ON c.id=w.target_cid
            WHERE w.status='active' ORDER BY w.id DESC LIMIT 15]]) or {}
    end)
    local bolos = dashboardSection(function()
        return MySQL.query.await("SELECT id,plate,description,organization_id,created_at FROM cm_legal_bolos WHERE status='active' ORDER BY id DESC LIMIT 15") or {}
    end)
    local incidents = dashboardSection(function()
        return MySQL.query.await([[SELECT id,caller_name,details,location,status,created_at
            FROM cm_legal_incidents ORDER BY id DESC LIMIT 10]]) or {}
    end)
    local stats = dashboardSection(function()
        return {
            activeWarrants = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cm_legal_mdt_warrants WHERE status='active'")) or 0,
            activeBolos = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cm_legal_bolos WHERE status='active'")) or 0,
            activeCalls = type(LawActiveCallCount) == 'function' and LawActiveCallCount() or 0,
        }
    end)
    return { ok = true, warrants = warrants, bolos = bolos, incidents = incidents, stats = stats }
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_mdt_notes (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,target_cid VARCHAR(64) NOT NULL,organization_id VARCHAR(32) NOT NULL,
        author_cid VARCHAR(64) NOT NULL,note TEXT NOT NULL,created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY(id),KEY idx_cm_legal_mdt_notes_target(target_cid,created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_mdt_reports (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,target_cid VARCHAR(64) NOT NULL,organization_id VARCHAR(32) NOT NULL,
        author_cid VARCHAR(64) NOT NULL,title VARCHAR(120) NOT NULL,narrative TEXT NOT NULL,
        status ENUM('open','under_review','closed') NOT NULL DEFAULT 'open',created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY(id),KEY idx_cm_legal_mdt_reports_target(target_cid,created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- Case-file fields added after the original notes/reports/warrants design
    -- (Pluto-style detailed case files: summary, evidence log, linked
    -- officers, scene photo, and a third "under review" status between
    -- open/closed). ALTER + pcall matches the ADD COLUMN convention used
    -- throughout this resource; MODIFY COLUMN is safe to rerun unconditionally.
    pcall(function() MySQL.query.await("ALTER TABLE cm_legal_mdt_reports MODIFY COLUMN status ENUM('open','under_review','closed') NOT NULL DEFAULT 'open'") end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_mdt_reports ADD COLUMN summary VARCHAR(300) NULL') end)
    -- Nullable rather than a LONGTEXT column default (MySQL only supports
    -- expression defaults on TEXT/BLOB types from 8.0.13+, not guaranteed) --
    -- every read already treats a NULL/missing value as '[]' (see
    -- mdtCitizenProfile's decode loop and reportCaseAccess/evidence/link
    -- callbacks below), so an unmigrated NULL row behaves identically to an
    -- explicit empty array.
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_mdt_reports ADD COLUMN evidence LONGTEXT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_mdt_reports ADD COLUMN linked_officers LONGTEXT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_legal_mdt_reports ADD COLUMN photo_url VARCHAR(300) NULL') end)
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_mdt_warrants (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,target_cid VARCHAR(64) NOT NULL,organization_id VARCHAR(32) NOT NULL,
        author_cid VARCHAR(64) NOT NULL,reason TEXT NOT NULL,stars TINYINT UNSIGNED NOT NULL DEFAULT 1,
        status ENUM('active','closed') NOT NULL DEFAULT 'active',closed_by VARCHAR(64) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,closed_at TIMESTAMP NULL,
        PRIMARY KEY(id),KEY idx_cm_legal_mdt_warrants_target(target_cid,status,created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MdtReady = true
end)
