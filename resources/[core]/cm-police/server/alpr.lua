-- cm-police ALPR (automatic license plate reader) cameras. Fixed
-- installations an admin places (Config.Permissions.police.manage_alpr) --
-- not officer-deployable, unlike spike strips. Reads the vehicle's
-- rendered plate text (police-issued license_number if registered, blank
-- otherwise -- see cm-vehicles' spawn code from this session's vehicle-
-- licensing work) and cross-references it against active BOLO plates
-- only. GetAllVehicles/GetVehicleNumberPlateText/GetEntityCoords are all
-- natively available server-side, so this needs zero changes to
-- cm-vehicles.

local CameraCache = {}
local BoloPlateCache = {}

local function reloadCameras()
    CameraCache = MySQL.query.await('SELECT id, label, x, y, z FROM cm_police_alpr_cameras ORDER BY id ASC') or {}
    for _, row in ipairs(CameraCache) do row.id = tonumber(row.id) end
end

function PoliceAlprRefreshBolos()
    local rows = MySQL.query.await("SELECT plate FROM cm_police_bolos WHERE status = 'active' AND plate IS NOT NULL AND plate <> ''") or {}
    local nextCache = {}
    for _, row in ipairs(rows) do nextCache[tostring(row.plate):gsub('%s+', ''):upper()] = true end
    BoloPlateCache = nextCache
end

local function authorizedManager(src)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not has(member, 'police.manage_alpr') then
        return nil, characterId
    end
    return member, characterId
end

lib.callback.register('cm-police:server:alprCameraList', function(src)
    local member = authorizedManager(src)
    if not member then return {} end
    local rows = {}
    for _, row in ipairs(CameraCache) do rows[#rows + 1] = { id = row.id, label = row.label, x = row.x, y = row.y, z = row.z } end
    return rows
end)

lib.callback.register('cm-police:server:addAlprCamera', function(src, label, x, y, z)
    local member, characterId = authorizedManager(src)
    if not member then return false, 'Your rank cannot manage ALPR cameras.' end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z or math.abs(x) > 10000 or math.abs(y) > 10000 or math.abs(z) > 2500 then return false, 'Could not resolve your location.' end
    local ped = GetPlayerPed(src)
    if ped == 0 or #(GetEntityCoords(ped) - vector3(x, y, z)) > 10.0 then return false, 'Camera location mismatch.' end
    local cleanLabel = tostring(label or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 64)
    if cleanLabel == '' then cleanLabel = ('Camera %s'):format(os.date('%H:%M:%S')) end
    MySQL.insert.await('INSERT INTO cm_police_alpr_cameras (label, x, y, z, created_by) VALUES (?, ?, ?, ?, ?)', { cleanLabel, x, y, z, characterId })
    reloadCameras()
    log(characterId, 'alpr_camera_added', { label = cleanLabel })
    return true, 'Camera added.'
end)

lib.callback.register('cm-police:server:removeAlprCamera', function(src, cameraId)
    local member, characterId = authorizedManager(src)
    if not member then return false, 'Your rank cannot manage ALPR cameras.' end
    cameraId = tonumber(cameraId)
    if not cameraId then return false, 'Invalid camera.' end
    MySQL.update.await('DELETE FROM cm_police_alpr_cameras WHERE id = ?', { cameraId })
    reloadCameras()
    log(characterId, 'alpr_camera_removed', { cameraId = cameraId })
    return true, 'Camera removed.'
end)

-- Per (camera, plate) alert cooldown -- in-memory only, resets on restart,
-- same acceptable tradeoff spike strips'/dispatch's own transient state
-- already accepts.
local RecentHits = {}

CreateThread(function()
    while true do
        Wait(Config.Alpr.CheckIntervalMs or 3000)
        if PoliceDatabaseReady() and #CameraCache > 0 then
            if next(BoloPlateCache) then
                local now = os.time()
                for _, vehicle in ipairs(GetAllVehicles()) do
                    if DoesEntityExist(vehicle) then
                        local plate = tostring(GetVehicleNumberPlateText(vehicle) or ''):gsub('%s+', ''):upper()
                        if plate ~= '' and BoloPlateCache[plate] then
                            local vCoords = GetEntityCoords(vehicle)
                            for _, camera in ipairs(CameraCache) do
                                local dist = #(vCoords - vector3(camera.x, camera.y, camera.z))
                                if dist <= (Config.Alpr.DetectionRadius or 20.0) then
                                    local key = tostring(camera.id) .. '|' .. plate
                                    if not RecentHits[key] or now - RecentHits[key] >= math.floor((Config.Alpr.AlertCooldownMs or 300000) / 1000) then
                                        RecentHits[key] = now
                                        log(nil, 'alpr_hit', { cameraId = tonumber(camera.id), cameraLabel = camera.label, plate = plate })
                                        for _, targetSrc in ipairs(recipients('police.receive_dispatch')) do
                                            TriggerClientEvent('cm-police:client:alprHit', targetSrc, plate, camera.label, { x = camera.x, y = camera.y, z = camera.z })
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_alpr_cameras (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        label VARCHAR(64) NOT NULL,
        x FLOAT NOT NULL, y FLOAT NOT NULL, z FLOAT NOT NULL,
        created_by VARCHAR(64) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    reloadCameras()
    PoliceAlprRefreshBolos()
    PoliceSchemaMarkReady('alpr')
end)
