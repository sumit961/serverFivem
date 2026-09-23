-- cm-law/server/dispatch_cameras.lua
-- Shared dispatch CCTV cameras across all four cm-law organizations. Distinct
-- from the embedded legacy Police module's ALPR system (plate-scanning
-- cameras) -- these are human-viewed CCTV feeds an on-duty dispatcher can aim
-- and watch. Placement/removal is config-driven permission
-- (law.manage_dispatch_cameras), not a hardcoded admin identity -- the
-- reference resource's own "vendor Discord ID as default camera admin" was
-- the flagged anti-pattern this deliberately avoids.

local CamerasReady = false

local function viewer(src)
    local member, characterId = activeMemberForSource(src)
    if not member or member.suspended or not member.onDuty
        or not LawCapabilityEnabled(member.organizationId, 'dispatch')
        or not (member.isLeader or member.permissions['law.receive_dispatch'] == true) then
        return nil, characterId, 'You must be on duty with dispatch access.'
    end
    return member, characterId
end

local function manager(src)
    local member, characterId, reason = viewer(src)
    if not member then return nil, characterId, reason end
    if not (member.isLeader or member.permissions['law.manage_dispatch_cameras'] == true) then
        return nil, characterId, 'Your rank cannot manage dispatch cameras.'
    end
    return member, characterId
end

local function clean(value, limit)
    return tostring(value or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, limit)
end

local function publicCamera(row)
    return {
        id = tonumber(row.id), label = tostring(row.label or 'Camera'), organizationId = row.organization_id,
        x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z), heading = tonumber(row.heading) or 0.0,
    }
end

lib.callback.register('cm-law:server:listDispatchCameras', function(src)
    local member = viewer(src)
    if not member or not CamerasReady then return {} end
    local rows = MySQL.query.await('SELECT * FROM cm_legal_dispatch_cameras ORDER BY label ASC') or {}
    local list = {}
    for _, row in ipairs(rows) do list[#list + 1] = publicCamera(row) end
    return list
end)

lib.callback.register('cm-law:server:createDispatchCamera', function(src, x, y, z, heading, label)
    local member, actorCid, reason = manager(src)
    if not member then return { ok = false, error = reason } end
    if not rateLimit(src, 'law_dispatch_camera_create', 1500) then return { ok = false, error = 'Please wait.' } end
    x, y, z, heading = tonumber(x), tonumber(y), tonumber(z), tonumber(heading) or 0.0
    if not x or not y or not z then return { ok = false, error = 'Invalid camera location.' } end
    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - vector3(x, y, z)) > 30.0 then return { ok = false, error = 'Camera location is too far away.' } end
    local cleanLabel = clean(label, 64)
    if cleanLabel == '' then cleanLabel = ('Camera %d'):format(MySQL.scalar.await('SELECT COUNT(*)+1 FROM cm_legal_dispatch_cameras') or 1) end
    local id = MySQL.insert.await([[INSERT INTO cm_legal_dispatch_cameras
        (organization_id, label, x, y, z, heading, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)]],
        { member.organizationId, cleanLabel, x, y, z, heading, actorCid })
    if not id then return { ok = false, error = 'Camera storage failed.' } end
    logActivity(member.organizationId, actorCid, 'dispatch_camera_placed', { cameraId = id, label = cleanLabel })
    return { ok = true, message = ('%s placed.'):format(cleanLabel), camera = { id = id, label = cleanLabel, organizationId = member.organizationId, x = x, y = y, z = z, heading = heading } }
end)

lib.callback.register('cm-law:server:deleteDispatchCamera', function(src, cameraId)
    local member, actorCid, reason = manager(src)
    if not member then return { ok = false, error = reason } end
    cameraId = tonumber(cameraId)
    if not cameraId then return { ok = false, error = 'Invalid camera.' } end
    local affected = MySQL.update.await('DELETE FROM cm_legal_dispatch_cameras WHERE id = ?', { cameraId })
    if tonumber(affected) ~= 1 then return { ok = false, error = 'That camera no longer exists.' } end
    logActivity(member.organizationId, actorCid, 'dispatch_camera_removed', { cameraId = cameraId })
    return { ok = true, message = 'Camera removed.' }
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_dispatch_cameras (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        organization_id VARCHAR(32) NOT NULL,
        label VARCHAR(64) NOT NULL,
        x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, heading FLOAT NOT NULL DEFAULT 0,
        created_by VARCHAR(64) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY(id),
        KEY idx_cm_legal_dispatch_cameras_org(organization_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    CamerasReady = true
end)
