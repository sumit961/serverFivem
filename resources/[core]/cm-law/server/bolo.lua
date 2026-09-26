-- Shared vehicle BOLO contracts. The legacy Police and generic Law boards
-- remain separate durable sources; this bounded cache unions their active
-- rows because the existing fixed ALPR implementation already shares hits
-- across Law organizations.

local BoloReady = false
local boloCache = { generic = {}, police = {} }

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

local function publicBolo(row, police)
    local organizationId = police and 'police' or tostring(row.organization_id or '')
    local organization = Config.Organizations[organizationId]
    return {
        plate = LawNormalizePlate(row.plate),
        description = clean(row.description, 200),
        reason = clean(row.description, 200),
        organizationId = organizationId,
        organizationLabel = organization and tostring(organization.label) or (police and 'Police Department' or organizationId:upper()),
        status = 'active',
        createdAt = tostring(row.created_at or ''),
    }
end

function LawRefreshActiveBoloCache()
    if not BoloReady then return false end
    local ok, rows = pcall(function()
        return MySQL.query.await("SELECT plate, description, organization_id, created_at FROM cm_legal_bolos WHERE status = 'active'") or {}
    end)
    if ok then
        local nextRows = {}
        for _, row in ipairs(rows) do
            local plate = LawNormalizePlate(row.plate)
            if plate then
                row.plate = plate
                nextRows[#nextRows + 1] = row
            end
        end
        boloCache.generic = nextRows
    else
        boloCache.generic = {}
    end
    -- cm_police_bolos is created by the embedded MDT startup path. A missing
    -- legacy table must not erase the last known Police cache or break Law.
    ok, rows = pcall(function()
        return MySQL.query.await("SELECT plate, description, officer_cid, created_at FROM cm_police_bolos WHERE status = 'active' AND plate IS NOT NULL") or {}
    end)
    if ok then
        local nextRows = {}
        for _, row in ipairs(rows) do
            local plate = LawNormalizePlate(row.plate)
            if plate then row.plate = plate; nextRows[#nextRows + 1] = row end
        end
        boloCache.police = nextRows
    else
        boloCache.police = {}
    end
    return true
end

function LawGetActiveBoloMatches(plate)
    plate = LawNormalizePlate(plate)
    if not plate or not BoloReady then return {} end
    local matches = {}
    for _, row in ipairs(boloCache.generic) do
        if row.plate == plate then matches[#matches + 1] = publicBolo(row, false) end
    end
    for _, row in ipairs(boloCache.police) do
        if row.plate == plate then matches[#matches + 1] = publicBolo(row, true) end
    end
    return matches
end

function LawGetActiveBoloPlateCache()
    local out = {}
    for _, row in ipairs(boloCache.generic) do
        if row.plate then out[row.plate] = out[row.plate] or {}; out[row.plate][#out[row.plate] + 1] = publicBolo(row, false) end
    end
    for _, row in ipairs(boloCache.police) do
        if row.plate then out[row.plate] = out[row.plate] or {}; out[row.plate][#out[row.plate] + 1] = publicBolo(row, true) end
    end
    return out
end

exports('GetActiveLawPlateAlerts', function(plate)
    local matches = LawGetActiveBoloMatches(plate)
    return { active = #matches > 0, plate = LawNormalizePlate(plate), entries = matches }
end)

lib.callback.register('cm-law:server:mdtIssueBolo', function(src, plate, description)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_bolo_issue', 1500) then return { ok = false, error = 'Please wait.' } end
    local cleanedPlate, cleanedDescription = LawNormalizePlate(plate), clean(description, 200)
    if not cleanedPlate then return { ok = false, error = 'Enter a valid plate.' } end
    if #cleanedDescription < 3 then return { ok = false, error = 'Enter a description.' } end
    local existing = MySQL.scalar.await("SELECT id FROM cm_legal_bolos WHERE plate = ? AND status = 'active' LIMIT 1", { cleanedPlate })
    if existing then return { ok = false, error = 'That plate already has an active BOLO.' } end
    local id = MySQL.insert.await([[INSERT INTO cm_legal_bolos
        (plate, description, organization_id, author_cid, status) VALUES (?, ?, ?, ?, 'active')]],
        { cleanedPlate, cleanedDescription, member.organizationId, actorCid })
    if not id then return { ok = false, error = 'BOLO storage failed.' } end
    LawRefreshActiveBoloCache()
    if type(PoliceAlprRefreshBolos) == 'function' then PoliceAlprRefreshBolos() end
    logActivity(member.organizationId, actorCid, 'mdt_bolo_issued', { boloId = id, plate = cleanedPlate })
    return { ok = true, message = ('BOLO issued for %s.'):format(cleanedPlate) }
end)

lib.callback.register('cm-law:server:mdtClearBolo', function(src, boloId)
    local member, actorCid, reason = authorized(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_mdt_bolo_clear', 750) then return { ok = false, error = 'Please wait.' } end
    boloId = tonumber(boloId)
    if not boloId then return { ok = false, error = 'Invalid BOLO.' } end
    local affected = MySQL.update.await(
        "UPDATE cm_legal_bolos SET status = 'cleared', cleared_by = ?, cleared_at = NOW() WHERE id = ? AND status = 'active'",
        { actorCid, boloId })
    if tonumber(affected) ~= 1 then return { ok = false, error = 'That BOLO is no longer active.' } end
    LawRefreshActiveBoloCache()
    if type(PoliceAlprRefreshBolos) == 'function' then PoliceAlprRefreshBolos() end
    logActivity(member.organizationId, actorCid, 'mdt_bolo_cleared', { boloId = boloId })
    return { ok = true, message = 'BOLO cleared.' }
end)

lib.callback.register('cm-law:server:mdtActiveBolos', function(src)
    local member = authorized(src)
    if not member then return {} end
    local rows = MySQL.query.await("SELECT * FROM cm_legal_bolos WHERE status = 'active' ORDER BY id DESC") or {}
    local list = {}
    for _, row in ipairs(rows) do
        local value = publicBolo(row, false)
        value.id, value.authorName = tonumber(row.id), row.author_cid and nameFor(row.author_cid) or 'Unknown'
        list[#list + 1] = value
    end
    return list
end)

lib.callback.register('cm-law:server:mdtBoloHistory', function(src)
    local member = authorized(src)
    if not member then return {} end
    local rows = MySQL.query.await("SELECT * FROM cm_legal_bolos WHERE status = 'cleared' ORDER BY id DESC LIMIT 50") or {}
    local list = {}
    for _, row in ipairs(rows) do list[#list + 1] = {
        id = tonumber(row.id), plate = LawNormalizePlate(row.plate), description = tostring(row.description or ''),
        organizationId = row.organization_id, authorName = row.author_cid and nameFor(row.author_cid) or 'Unknown',
        status = 'cleared', createdAt = tostring(row.created_at or ''), clearedAt = tostring(row.cleared_at or ''),
    } end
    return list
end)

local function fleetScannerAuthorized(src, patrol, context)
    local state = Entity(patrol).state
    local vehicleId = tonumber(state.cmVehicleId)
    if not vehicleId then return false end
    local fleet, fleetOrg
    if context.organizationId == 'police' then
        fleet, fleetOrg = state.cmPoliceFleet, 'police'
    else
        fleet, fleetOrg = state.cmLegalFleet, context.organizationId
    end
    if type(fleet) ~= 'table' or tonumber(fleet.vehicleId) ~= vehicleId
        or (fleet.organizationId and tostring(fleet.organizationId) ~= fleetOrg) then return false end
    local activeOk, active, info = pcall(function()
        return exports['cm-vehicles']:GetSpawnedVehicleInfo(vehicleId)
    end)
    if not activeOk or active ~= true or type(info) ~= 'table'
        or tonumber(info.entity) ~= patrol or tostring(info.context or '') ~= 'world' then return false end
    local rowOk, vehicleRow = pcall(function() return exports['cm-vehicles']:GetVehicleById(vehicleId) end)
    if not rowOk or type(vehicleRow) ~= 'table' or tostring(vehicleRow.owner_type or '') ~= 'organization'
        or tostring(vehicleRow.owner_id or ''):lower() ~= fleetOrg then return false end
    local ok, allowed = pcall(function()
        return exports['cm-vehicles']:CanUseVehicle(src, vehicleId, 'vehicle.drive')
    end)
    return ok and allowed == true
end

-- The client submits transient network IDs only. The server derives the
-- officer's org/duty/capability, fleet access, target entity and plate.
lib.callback.register('cm-law:server:scanVehiclePlates', function(src, candidateNetIds)
    local context = LawAuthorizeEnforcement(src, 'alpr', 'law.alpr')
    if not context then return {} end
    if not rateLimit(src, 'law_vehicle_scan', 2500) then return {} end
    if type(candidateNetIds) ~= 'table' then return {} end
    local ped = GetPlayerPed(src)
    local patrol = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if patrol == 0 or not DoesEntityExist(patrol) then return {} end
    local seatFound = GetPedInVehicleSeat(patrol, -1) == ped
    for seat = 0, GetVehicleModelNumberOfSeats(GetEntityModel(patrol)) - 2 do
        if GetPedInVehicleSeat(patrol, seat) == ped then seatFound = true; break end
    end
    if not seatFound or not fleetScannerAuthorized(src, patrol, context) then return {} end

    local candidates, seen = {}, {}
    for index = 1, math.min(#candidateNetIds, 8) do
        local netId = tonumber(candidateNetIds[index])
        if netId and netId > 0 and not seen[netId] then
            seen[netId] = true
            local vehicle = NetworkGetEntityFromNetworkId(netId)
            if vehicle ~= 0 and DoesEntityExist(vehicle) and GetEntityType(vehicle) == 2
                and GetEntityRoutingBucket(vehicle) == GetEntityRoutingBucket(patrol)
                and #(GetEntityCoords(patrol) - GetEntityCoords(vehicle)) <= 25.0 then
                local plate = LawNormalizePlate(GetVehicleNumberPlateText(vehicle))
                if plate then candidates[plate] = true end
            end
        end
    end
    local hits = {}
    for plate in pairs(candidates) do
        for _, bolo in ipairs(LawGetActiveBoloMatches(plate)) do
            local key = table.concat({ bolo.organizationId, bolo.plate, bolo.reason }, '|')
            hits[key] = { plate = bolo.plate, description = bolo.reason, organizationId = bolo.organizationId,
                organizationLabel = bolo.organizationLabel, createdAt = bolo.createdAt }
        end
    end
    local result = {}; for _, bolo in pairs(hits) do result[#result + 1] = bolo end
    return result
end)

function LawActiveBoloForPlate(plate)
    return LawGetActiveBoloMatches(plate)[1]
end

exports('GetVehicleBolo', function(plate) return LawActiveBoloForPlate(plate) end)
exports('HasActiveBolo', function(plate) return #LawGetActiveBoloMatches(plate) > 0 end)

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
    LawRefreshActiveBoloCache()
    if type(PoliceAlprRefreshBolos) == 'function' then PoliceAlprRefreshBolos() end
end)
