-- cm-law/server/bolo.lua
-- Shared vehicle BOLO ("be on the lookout") board across all four cm-law
-- organizations (SAHP/Sheriff/FIB/Army). The embedded legacy Police module
-- already has its own BOLO board (embedded/police/server/mdt.lua,
-- cm_police_bolos) tied to its own ALPR system -- this mirrors that feature's
-- shape for the shared orgs without touching police's table, the same way
-- warrants were unified as cm_legal_mdt_warrants alongside cm-police's own
-- warrant-less "wanted" flag.

local BoloReady = false

local function authorized(src)
    if not BoloReady then return nil, nil, 'Shared MDT is still loading.' end
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

local function cleanPlate(value)
    return tostring(value or ''):gsub('%s+', ''):upper():sub(1, 16)
end

local function publicBolo(row)
    return {
        id = tonumber(row.id),
        plate = row.plate,
        description = tostring(row.description or ''),
        organizationId = row.organization_id,
        authorName = row.author_cid and nameFor(row.author_cid) or 'Unknown',
        status = tostring(row.status or 'active'),
        clearedByName = row.cleared_by and nameFor(row.cleared_by) or nil,
        createdAt = tostring(row.created_at or ''),
        clearedAt = row.cleared_at and tostring(row.cleared_at) or nil,
    }
end

lib.callback.register('cm-law:server:mdtIssueBolo', function(src, plate, description)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_bolo_issue', 1500) then return { ok = false, error = 'Please wait.' } end
    local cleanedPlate, cleanedDescription = cleanPlate(plate), clean(description, 200)
    if cleanedPlate == '' then return { ok = false, error = 'Enter a plate.' } end
    if #cleanedDescription < 3 then return { ok = false, error = 'Enter a description.' } end
    local existing = MySQL.scalar.await('SELECT id FROM cm_legal_bolos WHERE plate = ? AND status = ? LIMIT 1', { cleanedPlate, 'active' })
    if existing then return { ok = false, error = 'That plate already has an active BOLO.' } end
    local id = MySQL.insert.await([[INSERT INTO cm_legal_bolos
        (plate, description, organization_id, author_cid, status) VALUES (?, ?, ?, ?, 'active')]],
        { cleanedPlate, cleanedDescription, member.organizationId, actorCid })
    if not id then return { ok = false, error = 'BOLO storage failed.' } end
    if type(PoliceAlprRefreshBolos) == 'function' then PoliceAlprRefreshBolos() end
    logActivity(member.organizationId, actorCid, 'mdt_bolo_issued', { boloId = id, plate = cleanedPlate })
    return { ok = true, message = ('BOLO issued for %s.'):format(cleanedPlate) }
end)

lib.callback.register('cm-law:server:mdtClearBolo', function(src, boloId)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    boloId = tonumber(boloId)
    if not boloId then return { ok = false, error = 'Invalid BOLO.' } end
    local affected = MySQL.update.await(
        "UPDATE cm_legal_bolos SET status = 'cleared', cleared_by = ?, cleared_at = NOW() WHERE id = ? AND status = 'active'",
        { actorCid, boloId })
    if tonumber(affected) ~= 1 then return { ok = false, error = 'That BOLO is no longer active.' } end
    if type(PoliceAlprRefreshBolos) == 'function' then PoliceAlprRefreshBolos() end
    logActivity(member.organizationId, actorCid, 'mdt_bolo_cleared', { boloId = boloId })
    return { ok = true, message = 'BOLO cleared.' }
end)

lib.callback.register('cm-law:server:mdtActiveBolos', function(src)
    local member = authorized(src)
    if not member then return {} end
    local rows = MySQL.query.await("SELECT * FROM cm_legal_bolos WHERE status = 'active' ORDER BY id DESC") or {}
    local list = {}
    for _, row in ipairs(rows) do list[#list + 1] = publicBolo(row) end
    return list
end)

lib.callback.register('cm-law:server:mdtBoloHistory', function(src)
    local member = authorized(src)
    if not member then return {} end
    local rows = MySQL.query.await("SELECT * FROM cm_legal_bolos WHERE status = 'cleared' ORDER BY id DESC LIMIT 50") or {}
    local list = {}
    for _, row in ipairs(rows) do list[#list + 1] = publicBolo(row) end
    return list
end)

-- Patrol-car plate scanner (client/vehicle_scanner.lua): the client reads
-- plates off nearby vehicles while driving and batches them here rather than
-- exposing LawActiveBoloForPlate directly, so a modified client can't probe
-- the BOLO list at will without at least being on-duty with MDT/dispatch
-- access, and so a whole patrol's worth of plates is one round trip.
lib.callback.register('cm-law:server:scanVehiclePlates', function(src, plates)
    local member = authorized(src)
    if not member then return {} end
    if not rateLimit(src, 'law_vehicle_scan', 900) then return {} end
    if type(plates) ~= 'table' then return {} end
    local hits = {}
    for i = 1, math.min(#plates, 8) do
        local bolo = LawActiveBoloForPlate(plates[i])
        if bolo then hits[#hits + 1] = bolo end
    end
    return hits
end)

-- Server-internal lookup used by mdt.lua's vehicle search to surface an
-- active BOLO the moment a plate is looked up.
function LawActiveBoloForPlate(plate)
    plate = cleanPlate(plate)
    if plate == '' or not BoloReady then return nil end
    local row = MySQL.single.await("SELECT * FROM cm_legal_bolos WHERE plate = ? AND status = 'active' LIMIT 1", { plate })
    return row and publicBolo(row) or nil
end

-- Cross-resource read access, matching the pcall-wrapped export idiom used
-- throughout cm-law (e.g. server/records.lua's GetCitizenLegalRecords).
exports('GetVehicleBolo', function(plate)
    return LawActiveBoloForPlate(plate)
end)

exports('HasActiveBolo', function(plate)
    return LawActiveBoloForPlate(plate) ~= nil
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_bolos (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        plate VARCHAR(16) NOT NULL,
        description VARCHAR(200) NOT NULL,
        organization_id VARCHAR(32) NOT NULL,
        author_cid VARCHAR(64) NOT NULL,
        status ENUM('active','cleared') NOT NULL DEFAULT 'active',
        cleared_by VARCHAR(64) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        cleared_at TIMESTAMP NULL,
        PRIMARY KEY(id),
        KEY idx_cm_legal_bolos_plate(plate, status),
        KEY idx_cm_legal_bolos_status(status, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    BoloReady = true
end)
