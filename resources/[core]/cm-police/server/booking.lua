-- cm-police booking. Cuffing/escort stays here; once booking succeeds,
-- persistent sentence, cell assignment, confinement and release belong to
-- the CM-owned cm-prison resource.
--
-- clearAll (server/cuffs.lua, a bare global) is called on a successful
-- booking so cm-police's own restraint bookkeeping (Cuffed/Escorted/
-- cmCuffed) doesn't linger once cm-prison becomes responsible for containing
-- the suspect -- avoids any desync between the two resources.

local function bookingNotify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local BookingLocation
local JailLocation
local JailSpawns = {}
local ServiceNpcLocation
local BookingBusy = {}
local BookingReservations = {}
local BookingRules = {
    minutesPerStar = tonumber(Config.Booking.MinutesPerWantedStar) or 15,
    bookingRadius = tonumber(Config.Booking.BookingRadius) or 8.0,
    handoffTimeoutMs = tonumber(Config.Booking.HandoffTimeoutMs) or 10000,
}
local CinematicRules = {
    enabled = true, allowSkip = true, cameraCollision = true,
    sequenceSpeed = 1.0, cameraFov = 45.0, responseDurationMs = 2200,
    soundEnabled = true, soundVolume = 1.0,
}

-- All legal organizations share cm-law's jail spawn pool and release point.
-- Legacy Police values remain a safe fallback during migration/startup.
local function sharedPrisonConfig()
    if GetResourceState('cm-law') == 'started' then
        local ok, configured = pcall(function() return exports['cm-law']:GetSharedJailConfiguration() end)
        if ok and type(configured) == 'table' and type(configured.spawns) == 'table'
            and #configured.spawns > 0 and type(configured.release) == 'table' then
            return configured.spawns, configured.release
        end
    end
    return JailSpawns, JailLocation
end

local function cleanField(value)
    return tostring(value or ''):gsub('[%c]+', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 160)
end

local function captureBookingMugshot(targetSrc, targetCid, bookingId)
    if GetResourceState('screenshot-basic') ~= 'started' then return nil end
    local filename = ('booking_%s_%d_%06d.jpg'):format(tostring(targetCid):gsub('[^%w_-]', ''), os.time(), math.random(0, 999999))
    local relativeUrl = 'img/mugshots/' .. filename
    local absolutePath = ('%s/html/img/mugshots/%s'):format(GetResourcePath(GetCurrentResourceName()), filename)
    local result, resolved = promise.new(), false
    local function finish(ok) if not resolved then resolved = true; result:resolve(ok) end end
    TriggerClientEvent('cm-police:client:prepareBookingMugshot', targetSrc, 3500)
    Wait(700)
    local requested = pcall(function()
        exports['screenshot-basic']:requestClientScreenshot(targetSrc, {
            fileName = absolutePath, encoding = 'jpg', quality = 0.9,
        }, function(err) finish(err == nil or err == false) end)
    end)
    if not requested then TriggerClientEvent('cm-police:client:endBookingMugshot', targetSrc); return nil end
    SetTimeout(5000, function() finish(false) end)
    local captured = Citizen.Await(result)
    TriggerClientEvent('cm-police:client:endBookingMugshot', targetSrc)
    Wait(200)
    if not captured then return nil end
    MySQL.update.await('UPDATE cm_police_bookings SET mugshot_url = ? WHERE id = ?', { relativeUrl, bookingId })
    MySQL.insert.await([[INSERT INTO cm_police_criminal_status (character_id, photo_url, set_by)
        VALUES (?, ?, NULL) ON DUPLICATE KEY UPDATE photo_url = VALUES(photo_url)]], { targetCid, relativeUrl })
    return relativeUrl
end

local function bookingAuthority(src, targetSrc)
    src, targetSrc = tonumber(src), tonumber(targetSrc)
    if not src or not targetSrc or src == targetSrc then return nil, 'Invalid suspect.' end
    local actorCid = cid(src)
    local actor = actorCid and memberFor(actorCid)
    if not actor or dbBoolean(actor.is_suspended) or not dbBoolean(actor.on_duty) or not has(actor, 'police.book') then
        return nil, 'You must be an on-duty officer with booking permission.'
    end
    if isFtoRestricted(actor) then return nil, 'Cadets must be signed off by a training officer before booking suspects.' end
    local targetCid = cid(targetSrc)
    local officerPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
    if not targetCid or not officerPed or officerPed == 0 or not targetPed or targetPed == 0 then return nil, 'The suspect is unavailable.' end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc) then return nil, 'The suspect is not in your routing instance.' end
    if Player(targetSrc).state.cmCuffed ~= true then return nil, 'The suspect must be cuffed first.' end
    local sharedSpawns = select(1, sharedPrisonConfig())
    local intakeLocation = JailLocation or BookingLocation
    if not intakeLocation then return nil, 'The Prison Intake NPC has not been configured.' end
    if #sharedSpawns < 1 then return nil, 'No shared jail spawn locations have been configured.' end
    if GetPlayerRoutingBucket(src) ~= (tonumber(intakeLocation.bucket) or 0) then return nil, 'Move to the configured prison intake routing bucket.' end
    local radius = BookingRules.bookingRadius
    local bookingCoords = vector3(intakeLocation.x, intakeLocation.y, intakeLocation.z)
    if #(GetEntityCoords(officerPed) - bookingCoords) > radius or #(GetEntityCoords(targetPed) - bookingCoords) > radius then
        return nil, 'Bring the cuffed suspect to the Prison Intake NPC.'
    end
    if #(GetEntityCoords(officerPed) - GetEntityCoords(targetPed)) > radius then return nil, 'Move closer to the suspect.' end
    local status = MySQL.single.await('SELECT stars, wanted, wanted_reason FROM cm_police_criminal_status WHERE character_id = ? LIMIT 1', { tostring(targetCid) })
    local stars = status and math.max(0, math.min(6, math.floor(tonumber(status.stars) or 0))) or 0
    if stars < 1 or not dbBoolean(status and status.wanted) then
        return nil, 'Assign the suspect at least one active wanted star in the MDT before booking.'
    end
    return {
        actor = actor, actorCid = tostring(actorCid), targetCid = tostring(targetCid),
        stars = stars,
        minutes = stars * BookingRules.minutesPerStar,
        reason = cleanField(status.wanted_reason),
        officerPed = officerPed, targetPed = targetPed,
    }
end

lib.callback.register('cm-police:server:bookingPreview', function(src, targetSrc)
    local booking, why = bookingAuthority(src, targetSrc)
    if not booking then return false, why end
    local current = BookingReservations[booking.targetCid]
    if current and current.expiresAt > GetGameTimer() and current.src ~= tonumber(src) then
        return false, 'Another officer is already processing this suspect.'
    end
    local token = ('book:%s:%s:%d:%06d'):format(booking.targetCid, tostring(booking.actorCid), GetGameTimer(), math.random(0, 999999))
    BookingReservations[booking.targetCid] = { src = tonumber(src), targetSrc = tonumber(targetSrc), token = token, expiresAt = GetGameTimer() + 45000 }
    return true, { stars = booking.stars, minutes = booking.minutes, reason = booking.reason,
        suspectName = nameFor(booking.targetCid), characterId = booking.targetCid,
        officerName = nameFor(booking.actorCid), operationToken = token }
end)

lib.callback.register('cm-police:server:cancelBookingReservation', function(src, token)
    token = tostring(token or '')
    for characterId, reservation in pairs(BookingReservations) do
        if reservation.src == tonumber(src) and reservation.token == token then BookingReservations[characterId] = nil; return true end
    end
    return false
end)

local function policeAdmin(src)
    local ok, allowed = pcall(function()
        return exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission)
    end)
    return ok and allowed == true
end

local function locationPayload(location)
    if not location then return nil end
    return { x = location.x, y = location.y, z = location.z, heading = location.heading or 0.0,
        name = location.name, bucket = tonumber(location.bucket) or 0, warning = location.warning }
end

function GetPoliceServiceNpcLocation() return locationPayload(ServiceNpcLocation) end
function GetPoliceJailLocation() local _, release = sharedPrisonConfig(); return locationPayload(release) end
function GetPoliceJailSpawns() local spawns = sharedPrisonConfig(); return spawns end
-- Exported (not just a bare global) so cm-law's own booking can jail
-- suspects at this same physical prison instead of needing a second set
-- of admin-configured jail spawns for the one prison map in the game.
exports('GetJailSpawns', GetPoliceJailSpawns)
exports('GetJailLocation', GetPoliceJailLocation)
function GetPoliceBookingRules() return BookingRules end
function GetPoliceCinematicRules() return CinematicRules end
lib.callback.register('cm-police:server:cinematicRules', function() return CinematicRules end)
-- World NPC placement is not privileged information. Booking itself remains
-- fully server-authorized, but every client must be able to fetch the ped
-- location even while Police membership/state bags are still loading.
lib.callback.register('cm-police:server:jailNpcLocation', function()
    return locationPayload(JailLocation)
end)

local function prisonAreaWarning(coords)
    local area = Config.Booking.PrisonArea
    if type(area) ~= 'table' then return nil end
    local distance = #(coords - vector3(tonumber(area.X) or 0, tonumber(area.Y) or 0, tonumber(area.Z) or 0))
    if distance > (tonumber(area.Radius) or 180.0) then
        return ('Outside the configured %s prison area (%.0fm away).'):format(tostring(area.Label or 'CM'), distance)
    end
    return nil
end

local function saveSetting(key, value, actorCid)
    MySQL.insert.await([[INSERT INTO cm_police_settings (setting_key, setting_value, updated_by) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by)]],
        { key, json.encode(value), actorCid })
end

lib.callback.register('cm-police:server:adminConfig', function(src)
    if not policeAdmin(src) then return nil, 'Permission denied.' end
    local getFacility = type(GetPoliceFacilityNpcLocation) == 'function' and GetPoliceFacilityNpcLocation or function() return nil end
    local wardrobeStatus = type(GetWardrobeNpcStatus) == 'function' and GetWardrobeNpcStatus() or { set = false }
    return {
        bookingDesk = locationPayload(BookingLocation), jailIntake = locationPayload(JailLocation), jailSpawns = JailSpawns, serviceNpc = locationPayload(ServiceNpcLocation),
        armoryNpc = getFacility('armory_npc'), storageNpc = getFacility('storage_npc'),
        wardrobeNpc = wardrobeStatus,
        minutesPerStar = BookingRules.minutesPerStar, bookingRadius = BookingRules.bookingRadius,
        handoffTimeoutMs = BookingRules.handoffTimeoutMs,
        cinematicRules = CinematicRules,
    }
end)

lib.callback.register('cm-police:server:setAdminLocation', function(src, locationType, supplied)
    if not policeAdmin(src) or not rateLimit(src, 'police_admin_location', 800) then return false, 'Permission denied.' end
    if locationType ~= 'booking_desk' and locationType ~= 'jail_intake' and locationType ~= 'jail_spawn' and locationType ~= 'service_npc'
        and locationType ~= 'armory_npc' and locationType ~= 'storage_npc' then return false, 'Invalid location type.' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or type(supplied) ~= 'table' then return false, 'Location unavailable.' end
    local actual = GetEntityCoords(ped)
    local proposed = vector3(tonumber(supplied.x) or 0, tonumber(supplied.y) or 0, tonumber(supplied.z) or 0)
    if #(actual - proposed) > 5.0 then return false, 'Location verification failed.' end
    local locationName = cleanField(supplied.name)
    if locationName == '' then
        local defaults = { booking_desk = 'Police Booking Desk', jail_intake = 'Prison Intake NPC', jail_spawn = 'Jail Spawn', service_npc = 'Police Front Desk',
            armory_npc = 'Police Armory', storage_npc = 'Police Storage' }
        locationName = defaults[locationType]
    end
    local value = { x = actual.x, y = actual.y, z = actual.z, heading = GetEntityHeading(ped),
        name = locationName:sub(1, 48), bucket = GetPlayerRoutingBucket(src) }
    if locationType == 'jail_intake' then
        value.warning = prisonAreaWarning(actual)
        if value.bucket ~= 0 then
            value.warning = (value.warning and (value.warning .. ' ') or '') .. 'Jail intake is in a non-default routing bucket.'
        end
    end
    if locationType == 'booking_desk' then BookingLocation = value
    elseif locationType == 'jail_intake' then JailLocation = value
    elseif locationType == 'jail_spawn' then
        JailSpawns[#JailSpawns + 1] = value
        saveSetting('jail_spawns', JailSpawns, tostring(cid(src) or 'admin'))
    elseif locationType == 'service_npc' then ServiceNpcLocation = value
    elseif type(SetPoliceFacilityNpcLocation) == 'function' then SetPoliceFacilityNpcLocation(locationType, value)
    else return false, 'Police facility service is unavailable.' end
    local actorCid = tostring(cid(src) or 'admin')
    if locationType ~= 'jail_spawn' then saveSetting(locationType, value, actorCid) end
    local actionName = locationType .. '_set'
    log(actorCid, actionName, value)
    TriggerEvent('cm-admin:server:addLog', src, 'police_' .. actionName, { category = 'police' })
    if locationType == 'service_npc' then TriggerClientEvent('cm-police:client:serviceNpcUpdated', -1, locationPayload(value)) end
    if locationType == 'jail_intake' then TriggerClientEvent('cm-police:client:jailNpcUpdated', -1) end
    local messages = { booking_desk = 'Booking desk saved.', jail_intake = 'Prison intake NPC saved.', jail_spawn = ('Jail spawn %d saved (capacity 2).'):format(#JailSpawns), service_npc = 'Police service NPC saved.',
        armory_npc = 'Police armory NPC saved.', storage_npc = 'Police storage NPC saved.' }
    local message = messages[locationType]
    if value.warning then message = message .. ' WARNING: ' .. value.warning end
    return true, message, locationPayload(value)
end)

lib.callback.register('cm-police:server:resetAdminLocation', function(src, locationType)
    if not policeAdmin(src) or not rateLimit(src, 'police_admin_location_reset', 800) then return false, 'Permission denied.' end
    if locationType ~= 'booking_desk' and locationType ~= 'jail_intake' and locationType ~= 'jail_spawns' and locationType ~= 'service_npc'
        and locationType ~= 'armory_npc' and locationType ~= 'storage_npc' then return false, 'Invalid location type.' end
    if locationType == 'booking_desk' then BookingLocation = nil
    elseif locationType == 'jail_intake' then JailLocation = nil
    elseif locationType == 'jail_spawns' then JailSpawns = {}
    elseif locationType == 'service_npc' then ServiceNpcLocation = nil
    elseif type(SetPoliceFacilityNpcLocation) == 'function' then SetPoliceFacilityNpcLocation(locationType, nil)
    else return false, 'Police facility service is unavailable.' end
    MySQL.update.await('DELETE FROM cm_police_settings WHERE setting_key = ?', { locationType })
    local actorCid = tostring(cid(src) or 'admin')
    log(actorCid, locationType .. '_reset', {})
    TriggerEvent('cm-admin:server:addLog', src, 'police_' .. locationType .. '_reset', { category = 'police' })
    if locationType == 'service_npc' then TriggerClientEvent('cm-police:client:serviceNpcUpdated', -1, false) end
    if locationType == 'jail_intake' then TriggerClientEvent('cm-police:client:jailNpcUpdated', -1) end
    local messages = { booking_desk = 'Booking desk reset.', jail_intake = 'Prison intake NPC reset.', jail_spawns = 'All jail spawns reset.', service_npc = 'Police service NPC reset.',
        armory_npc = 'Police armory NPC reset.', storage_npc = 'Police storage NPC reset.' }
    return true, messages[locationType]
end)

lib.callback.register('cm-police:server:teleportAdminLocation', function(src, locationType)
    if not policeAdmin(src) or not rateLimit(src, 'police_admin_location_teleport', 1500) then return false, 'Permission denied.' end
    local facilityLocation = type(GetPoliceFacilityNpcLocation) == 'function' and GetPoliceFacilityNpcLocation(locationType) or nil
    local location = locationType == 'booking_desk' and BookingLocation or locationType == 'jail_intake' and JailLocation
        or locationType == 'service_npc' and ServiceNpcLocation or facilityLocation
    if not location then return false, 'That location is not configured.' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Player entity unavailable.' end
    SetPlayerRoutingBucket(src, tonumber(location.bucket) or 0)
    SetEntityCoords(ped, location.x, location.y, location.z, false, false, false, false)
    SetEntityHeading(ped, location.heading or 0.0)
    return true, ('Teleported to %s.'):format(location.name or 'configured location')
end)

lib.callback.register('cm-police:server:adminReleaseCustody', function(src, targetCid)
    if not policeAdmin(src) or not rateLimit(src, 'police_admin_release_custody', 1000) then return false, 'Permission denied.' end
    targetCid = tostring(targetCid or '')
    if targetCid == '' or #targetCid > 64 then return false, 'Enter a valid character ID.' end
    local changed = MySQL.update.await("UPDATE cm_police_custody SET status = 'released', updated_at = NOW() WHERE character_id = ? AND status IN ('cuffed', 'processing')", { targetCid })
    if (tonumber(changed) or 0) < 1 then return false, 'No cuffed or processing custody record was found.' end
    local targetSrc = sourceFor(targetCid)
    if targetSrc then clearAll(targetSrc, true) end
    local actorCid = tostring(cid(src) or 'admin')
    log(actorCid, 'custody_admin_released', { targetCid = targetCid })
    TriggerEvent('cm-admin:server:addLog', src, 'police_custody_admin_released', { category = 'police', characterId = targetCid })
    return true, ('Custody cleared for character %s.'):format(targetCid)
end)

lib.callback.register('cm-police:server:saveAdminRules', function(src, payload)
    if not policeAdmin(src) or not rateLimit(src, 'police_admin_rules', 800) then return false, 'Permission denied.' end
    payload = type(payload) == 'table' and payload or {}
    local minutes = math.floor(tonumber(payload.minutesPerStar) or 0)
    local radius = tonumber(payload.bookingRadius) or 0
    local timeout = math.floor(tonumber(payload.handoffTimeoutMs) or 0)
    if minutes < 1 or minutes > 120 then return false, 'Minutes per star must be between 1 and 120.' end
    if radius < 2.0 or radius > 25.0 then return false, 'Booking radius must be between 2 and 25 metres.' end
    if timeout < 2000 or timeout > 15000 then return false, 'Handoff timeout must be between 2000 and 15000 ms.' end
    local hasCinematicPayload = type(payload.cinematicRules) == 'table'
    local cinematic = hasCinematicPayload and payload.cinematicRules or CinematicRules
    local speed = tonumber(cinematic.sequenceSpeed) or CinematicRules.sequenceSpeed
    local fov = tonumber(cinematic.cameraFov) or CinematicRules.cameraFov
    local response = math.floor(tonumber(cinematic.responseDurationMs) or CinematicRules.responseDurationMs)
    local volume = tonumber(cinematic.soundVolume) or CinematicRules.soundVolume
    if speed < 0.5 or speed > 2.0 then return false, 'Cinematic speed must be between 0.5 and 2.0.' end
    if fov < 30 or fov > 70 then return false, 'Camera FOV must be between 30 and 70.' end
    if response < 1000 or response > 8000 then return false, 'Response duration must be between 1000 and 8000 ms.' end
    if volume < 0 or volume > 1 then return false, 'Sound volume must be between 0 and 1.' end
    BookingRules = { minutesPerStar = minutes, bookingRadius = radius, handoffTimeoutMs = timeout }
    if hasCinematicPayload then
        CinematicRules = { enabled = cinematic.enabled ~= false, allowSkip = cinematic.allowSkip ~= false,
            cameraCollision = cinematic.cameraCollision ~= false, sequenceSpeed = speed, cameraFov = fov,
            responseDurationMs = response, soundEnabled = cinematic.soundEnabled ~= false, soundVolume = volume }
    end
    local actorCid = tostring(cid(src) or 'admin')
    saveSetting('booking_rules', BookingRules, actorCid)
    if hasCinematicPayload then saveSetting('cinematic_rules', CinematicRules, actorCid) end
    log(actorCid, 'booking_rules_updated', BookingRules)
    TriggerEvent('cm-admin:server:addLog', src, 'police_booking_rules_updated', { category = 'police', minutesPerStar = minutes })
    TriggerClientEvent('cm-police:client:cinematicRulesUpdated', -1, CinematicRules)
    return true, 'Police booking and jail rules saved.'
end)

lib.callback.register('cm-police:server:adminPrisoners', function(src)
    if not policeAdmin(src) then return nil, 'Permission denied.' end
    if GetResourceState('cm-prison') ~= 'started' then return nil, 'Prison is unavailable.' end
    local ok, rows = pcall(function() return exports['cm-prison']:GetActiveSentences() end)
    if not ok or type(rows) ~= 'table' then return nil, 'Active sentences could not be loaded.' end
    for _, row in ipairs(rows) do row.character_name = nameFor(row.character_id) end
    return rows
end)

lib.callback.register('cm-police:server:adminPrisonAction', function(src, action, characterId, minutes)
    if not policeAdmin(src) or not rateLimit(src, 'police_admin_prison_action', 900) then return false, 'Permission denied.' end
    characterId = tostring(characterId or ''):gsub('[^%w_%-]', ''):sub(1, 64)
    if characterId == '' or GetResourceState('cm-prison') ~= 'started' then return false, 'Invalid prisoner or prison unavailable.' end
    local ok, changed, failure = pcall(function()
        if action == 'release' then return exports['cm-prison']:ReleasePrisoner(characterId) end
        if action == 'reduce' then return exports['cm-prison']:ReduceSentence(characterId, minutes) end
        return false, 'invalid_action'
    end)
    if not ok or changed ~= true then
        local messages = { not_imprisoned = 'That character has no active sentence.', invalid_reduction = 'Enter a reduction from 1 to 43,200 minutes.', prison_unavailable = 'Prison is unavailable.' }
        return false, messages[failure] or 'The sentence could not be changed.'
    end
    log(cid(src), action == 'release' and 'admin_prisoner_released' or 'admin_prison_sentence_reduced', {
        targetCid = characterId, minutes = action == 'reduce' and math.floor(tonumber(minutes) or 0) or nil,
    })
    return true, action == 'release' and 'Prisoner released.' or 'Sentence reduced.'
end)

RegisterCommand('setpolicebooking', function(src)
    src = tonumber(src)
    if not src or src <= 0 then return end
    local actorCid = cid(src)
    local actor = actorCid and memberFor(actorCid)
    if not actor or dbBoolean(actor.is_suspended) or not dbBoolean(actor.on_duty)
        or not has(actor, 'police.manage_booking') then
        return bookingNotify(src, 'You need Police booking-management permission.', 'error')
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)
    BookingLocation = { x = coords.x, y = coords.y, z = coords.z, heading = GetEntityHeading(ped) }
    MySQL.insert.await([[INSERT INTO cm_police_settings (setting_key, setting_value, updated_by) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by)]],
        { 'booking_desk', json.encode(BookingLocation), tostring(actorCid) })
    log(actorCid, 'holding_cell_set', BookingLocation)
    bookingNotify(src, 'Police booking desk location saved.', 'success')
end, false)

-- The G-menu exposes one booking action. Sentence length is derived from the
-- server-owned MDT wanted record, never selected or supplied by the client. No
-- police_release_booking entry anymore -- sentence release is owned by
-- cm-prison and the separate Police Admin prison controls.
function BookingActionIds()
    return { 'police_book' }
end

AddEventHandler('playerDropped', function()
    local dropped = source
    for characterId, reservation in pairs(BookingReservations) do
        if reservation.src == dropped or reservation.targetSrc == dropped then BookingReservations[characterId] = nil end
    end
end)

AddEventHandler('cm-police:server:bookingAction', function(src, targetSrc, action, payload, context)
    src, targetSrc = tonumber(src), tonumber(targetSrc)
    if not src or not targetSrc or src == targetSrc then return end
    if not rateLimit(src, 'police_booking_action', 700) then return bookingNotify(src, 'Please wait.', 'error') end
    if action ~= 'police_book' then return end
    local booking, why = bookingAuthority(src, targetSrc)
    if not booking then return bookingNotify(src, why, 'error') end
    local reservation = BookingReservations[booking.targetCid]
    local suppliedToken = type(payload) == 'table' and tostring(payload.operationToken or '') or ''
    if not reservation or reservation.src ~= src or reservation.targetSrc ~= targetSrc
        or reservation.token ~= suppliedToken or reservation.expiresAt <= GetGameTimer() then
        return bookingNotify(src, 'The booking reservation expired. Review the suspect again.', 'error')
    end
    BookingReservations[booking.targetCid] = nil
    if BookingBusy[booking.targetCid] then return bookingNotify(src, 'That suspect is already being processed.', 'error') end
    local reason, charges = cleanField(booking.reason), cleanField(booking.reason)
    if #reason < 3 then return bookingNotify(src, 'The wanted record has no reason. Update the MDT stars first.', 'error') end
    BookingBusy[booking.targetCid] = true
    SetTimeout(30000, function() BookingBusy[booking.targetCid] = nil end)
    local releaseEpoch = os.time() + booking.minutes * 60
    local bookingId
    local journalOk = pcall(function()
        bookingId = MySQL.insert.await([[INSERT INTO cm_police_bookings
            (character_id, officer_cid, reason, charges, wanted_stars, sentence_minutes, handoff_status, cinematic_status, operation_token, release_at)
            VALUES (?, ?, ?, ?, ?, ?, 'processing', ?, ?, FROM_UNIXTIME(?))]],
            { booking.targetCid, booking.actorCid, reason, charges, booking.stars, booking.minutes,
                payload.cinematicPlayed == true and 'played' or 'skipped_or_interrupted', suppliedToken, releaseEpoch })
        if not bookingId then error('booking journal insert failed') end
        local changed = MySQL.update.await([[UPDATE cm_police_custody SET status = 'processing', custody_mode = 'arrest', officer_cid = ?, reason = ?, charges = ?, booking_minutes = ?, updated_at = CURRENT_TIMESTAMP
            WHERE character_id = ? AND status IN ('cuffed', 'processing')]],
            { booking.actorCid, reason, charges, booking.minutes, booking.targetCid })
        if tonumber(changed) ~= 1 then error('custody transition failed') end
    end)
    if not journalOk then
        if bookingId then MySQL.update.await("UPDATE cm_police_bookings SET handoff_status = 'failed' WHERE id = ?", { bookingId }) end
        BookingBusy[booking.targetCid] = nil
        return bookingNotify(src, 'Booking could not be journaled safely. The suspect remains cuffed.', 'error')
    end

    local mugshotUrl = captureBookingMugshot(targetSrc, booking.targetCid, bookingId)

    local sharedSpawns, sharedRelease = sharedPrisonConfig()
    local jailed, jailFailure = false, 'bridge_error'
    local bridgeOk, bridgeError = pcall(function() jailed, jailFailure = exports['cm-prison']:JailSuspect(src, targetSrc, booking.minutes, BookingRules.handoffTimeoutMs, {
        spawns = sharedSpawns, release = sharedRelease, reason = reason, arrestedBy = nameFor(booking.actorCid),
    }) end)
    if not jailed then
        if not bridgeOk then
            print(('[cm-police] cm-prison handoff failed for booking %s: %s'):format(tostring(bookingId), tostring(bridgeError)))
            jailFailure = 'bridge_error'
        end
        if jailFailure == 'target_disconnected' or jailFailure == 'prison_unavailable' then
            BookingBusy[booking.targetCid] = nil
            return bookingNotify(src, jailFailure == 'prison_unavailable'
                and 'Prison is not ready. Check the cm-prison server log and restart cm-prison after oxmysql.'
                or 'The suspect disconnected during prison confirmation.', 'error')
        end
        MySQL.update.await([[UPDATE cm_police_custody SET status = 'cuffed', updated_at = CURRENT_TIMESTAMP
            WHERE character_id = ? AND status = 'processing']], { booking.targetCid })
        MySQL.update.await("UPDATE cm_police_bookings SET handoff_status = 'failed' WHERE id = ? AND handoff_status = 'processing'", { bookingId })
        BookingBusy[booking.targetCid] = nil
        local failures = {
            prison_full = 'All configured jail spawn slots are occupied (maximum two prisoners per spawn).',
            database_error = 'Prison could not save the sentence. Check the cm-prison server log.',
            bridge_error = 'cm-police could not contact cm-prison. Ensure cm-prison is started.',
        }
        return bookingNotify(src, failures[jailFailure] or ('Prison did not confirm custody (%s). The suspect remains cuffed.'):format(tostring(jailFailure)), 'error')
    end

    local finalized = false
    pcall(function()
        finalized = MySQL.transaction.await({
            { query = "UPDATE cm_police_bookings SET handoff_status = 'confirmed', completed_at = NOW() WHERE id = ? AND handoff_status = 'processing'", values = { bookingId } },
            { query = "UPDATE cm_police_custody SET status = 'jailed', booking_minutes = ?, updated_at = NOW() WHERE character_id = ? AND status = 'processing'", values = { booking.minutes, booking.targetCid } },
        })
    end)
    -- "Busted" (GTA5-style): clear cm-playerdata's own wanted-stars system
    -- on a successful booking. pcall-guarded like every other cross-resource
    -- call in this codebase, so a stopped/missing cm-playerdata never
    -- breaks booking itself.
    pcall(function() exports[Config.PlayerDataResource]:ClearWantedStars(targetSrc) end)
    clearAll(targetSrc, true)

    BookingBusy[booking.targetCid] = nil
    if not finalized then
        log(booking.actorCid, 'booking_reconciliation_required', { targetCid = booking.targetCid, bookingId = bookingId })
        return bookingNotify(src, 'Prison accepted custody; the Police record is queued for automatic reconciliation.', 'inform')
    end
    log(booking.actorCid, 'suspect_booked', { targetCid = booking.targetCid, stars = booking.stars, minutes = booking.minutes, reason = reason, charges = charges, handoff = 'confirmed' })
    TriggerClientEvent('cm-police:client:bookingCompleted', targetSrc, {
        stars = booking.stars, minutes = booking.minutes, reason = reason, mugshotUrl = mugshotUrl,
    })
    bookingNotify(src, ('Prison confirmed custody: %d minutes (%d wanted star%s).'):format(booking.minutes, booking.stars, booking.stars == 1 and '' or 's'), 'success')
end)

local function cmPrisoner(src)
    if GetResourceState('cm-prison') ~= 'started' then return nil end
    local ok, result = pcall(function() return exports['cm-prison']:IsPrisoner(src) end)
    if not ok then return nil end
    return result == true
end

local function reconcileReleased(characterId, bookingId, reason)
    MySQL.transaction.await({
        { query = "UPDATE cm_police_custody SET status = 'released', updated_at = NOW() WHERE character_id = ? AND status = 'jailed'", values = { characterId } },
        { query = "UPDATE cm_police_bookings SET released_at = COALESCE(released_at, NOW()), release_reason = COALESCE(release_reason, ?) WHERE id = ? AND handoff_status = 'confirmed'", values = { reason, bookingId } },
    })
    log(nil, 'prison_release_synchronized', { targetCid = characterId, bookingId = bookingId, reason = reason })
end

AddEventHandler('cm-prison:server:released', function(characterId, reason)
    local row = MySQL.single.await("SELECT id FROM cm_police_bookings WHERE character_id=? AND handoff_status='confirmed' AND released_at IS NULL ORDER BY id DESC LIMIT 1", { tostring(characterId) })
    if row then reconcileReleased(tostring(characterId), tonumber(row.id), tostring(reason or 'sentence_complete')) end
end)

local function reconcileBookings()
    if not PoliceDatabaseReady() or GetResourceState('cm-prison') ~= 'started' then return end
    local rows = MySQL.query.await([[
        SELECT c.character_id, c.status, c.custody_mode, TIMESTAMPDIFF(SECOND, c.updated_at, NOW()) AS age_seconds,
            b.id AS booking_id, b.handoff_status
        FROM cm_police_custody c
        LEFT JOIN cm_police_bookings b ON b.id = (
            SELECT MAX(b2.id) FROM cm_police_bookings b2 WHERE b2.character_id = c.character_id
        )
        WHERE c.status IN ('processing', 'jailed')
           OR (c.status = 'cuffed' AND b.handoff_status IN ('processing', 'failed'))
    ]]) or {}
    for _, row in ipairs(rows) do
        local characterId, bookingId = tostring(row.character_id), tonumber(row.booking_id)
        local onlineSrc = sourceFor(characterId)
        local prisoner = onlineSrc and cmPrisoner(onlineSrc) or nil
        if (row.status == 'processing' or row.status == 'cuffed') and bookingId then
            if prisoner == true then
                MySQL.transaction.await({
                    { query = "UPDATE cm_police_custody SET status = 'jailed', updated_at = NOW() WHERE character_id = ? AND status IN ('processing', 'cuffed')", values = { characterId } },
                    { query = "UPDATE cm_police_bookings SET handoff_status = 'confirmed' WHERE id = ? AND handoff_status IN ('processing', 'failed')", values = { bookingId } },
                })
                if onlineSrc then
                    pcall(function() exports[Config.PlayerDataResource]:ClearWantedStars(onlineSrc) end)
                    clearAll(onlineSrc, true)
                end
                log(nil, 'booking_reconciled_confirmed', { targetCid = characterId, bookingId = bookingId })
            elseif row.status == 'processing' and prisoner == false and (tonumber(row.age_seconds) or 0) >= 30 then
                MySQL.transaction.await({
                    { query = "UPDATE cm_police_custody SET status = IF(custody_mode = 'surrender', 'released', 'cuffed'), updated_at = NOW() WHERE character_id = ? AND status = 'processing'", values = { characterId } },
                    { query = "UPDATE cm_police_bookings SET handoff_status = 'failed' WHERE id = ? AND handoff_status = 'processing'", values = { bookingId } },
                })
            elseif row.status == 'processing' and not onlineSrc and (tonumber(row.age_seconds) or 0) >= 120 then
                MySQL.transaction.await({
                    { query = "UPDATE cm_police_custody SET status = IF(custody_mode = 'surrender', 'released', 'cuffed'), updated_at = NOW() WHERE character_id = ? AND status = 'processing'", values = { characterId } },
                    { query = "UPDATE cm_police_bookings SET handoff_status = 'failed' WHERE id = ? AND handoff_status = 'processing'", values = { bookingId } },
                })
            end
        elseif row.status == 'jailed' and bookingId then
            if prisoner == false then
                reconcileReleased(characterId, bookingId, 'cm_prison_confirmed')
            end
        end
    end
end

CreateThread(function()
    if not AwaitPoliceDatabase(30000) then return end
    while true do
        local ok, failure = xpcall(reconcileBookings, debug.traceback)
        if not ok then print(('[cm-police] booking reconciliation failed: %s'):format(tostring(failure))) end
        Wait(15000)
    end
end)

CreateThread(function()
    -- release_at needs an explicit DEFAULT even though the application
    -- always supplies a real value on INSERT -- MySQL 8's
    -- explicit_defaults_for_timestamp (on by default) rejects any
    -- NOT NULL TIMESTAMP column with no DEFAULT clause outright
    -- ("Invalid default value"), regardless of column order. Confirmed
    -- against this server's actual error output, not guessed. Kept purely
    -- as an audit/MDT-history record now -- no functional state is derived
    -- from this table anymore.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_bookings (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        character_id VARCHAR(64) NOT NULL,
        officer_cid VARCHAR(64) NULL,
        reason VARCHAR(255) NULL,
        charges VARCHAR(500) NULL,
        wanted_stars TINYINT UNSIGNED NOT NULL DEFAULT 0,
        sentence_minutes INT UNSIGNED NOT NULL DEFAULT 0,
        handoff_status VARCHAR(24) NOT NULL DEFAULT 'legacy',
        booked_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        release_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        released_at TIMESTAMP NULL,
        released_by VARCHAR(64) NULL,
        release_reason VARCHAR(64) NULL,
        mugshot_url VARCHAR(300) NULL,
        cinematic_status VARCHAR(32) NULL,
        operation_token VARCHAR(160) NULL,
        completed_at TIMESTAMP NULL,
        PRIMARY KEY (id),
        KEY idx_cm_police_booking_character (character_id),
        KEY idx_cm_police_booking_release (release_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_bookings ADD COLUMN charges VARCHAR(500) NULL') end)
    pcall(function() MySQL.query.await("ALTER TABLE cm_police_bookings ADD COLUMN wanted_stars TINYINT UNSIGNED NOT NULL DEFAULT 0") end)
    pcall(function() MySQL.query.await("ALTER TABLE cm_police_bookings ADD COLUMN sentence_minutes INT UNSIGNED NOT NULL DEFAULT 0") end)
    pcall(function() MySQL.query.await("ALTER TABLE cm_police_bookings ADD COLUMN handoff_status VARCHAR(24) NOT NULL DEFAULT 'legacy'") end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_bookings ADD COLUMN release_reason VARCHAR(64) NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_bookings ADD COLUMN mugshot_url VARCHAR(300) NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_bookings ADD COLUMN cinematic_status VARCHAR(32) NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_bookings ADD COLUMN operation_token VARCHAR(160) NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_bookings ADD COLUMN completed_at TIMESTAMP NULL') end)
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_settings (
        setting_key VARCHAR(64) NOT NULL, setting_value LONGTEXT NOT NULL, updated_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (setting_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_custody (
        character_id VARCHAR(64) NOT NULL, officer_cid VARCHAR(64) NULL,
        status VARCHAR(24) NOT NULL DEFAULT 'cuffed', custody_mode VARCHAR(24) NOT NULL DEFAULT 'arrest', reason VARCHAR(160) NULL, charges VARCHAR(160) NULL,
        booking_minutes INT UNSIGNED NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id), KEY idx_cm_police_custody_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    pcall(function() MySQL.query.await("ALTER TABLE cm_police_custody ADD COLUMN custody_mode VARCHAR(24) NOT NULL DEFAULT 'arrest' AFTER status") end)
    local settingsRows = MySQL.query.await("SELECT setting_key, setting_value FROM cm_police_settings WHERE setting_key IN ('booking_desk', 'jail_intake', 'jail_spawns', 'service_npc', 'booking_rules', 'cinematic_rules')") or {}
    for _, row in ipairs(settingsRows) do
        local ok, decoded = pcall(json.decode, row.setting_value)
        if ok and type(decoded) == 'table' then
            if row.setting_key == 'booking_desk' and tonumber(decoded.x) and tonumber(decoded.y) and tonumber(decoded.z) then BookingLocation = decoded end
            if row.setting_key == 'jail_intake' and tonumber(decoded.x) and tonumber(decoded.y) and tonumber(decoded.z) then JailLocation = decoded end
            if row.setting_key == 'jail_spawns' and type(decoded) == 'table' then JailSpawns = decoded end
            if row.setting_key == 'service_npc' and tonumber(decoded.x) and tonumber(decoded.y) and tonumber(decoded.z) then ServiceNpcLocation = decoded end
            if row.setting_key == 'booking_rules' then
                BookingRules.minutesPerStar = math.max(1, math.min(120, math.floor(tonumber(decoded.minutesPerStar) or BookingRules.minutesPerStar)))
                BookingRules.bookingRadius = math.max(2.0, math.min(25.0, tonumber(decoded.bookingRadius) or BookingRules.bookingRadius))
                BookingRules.handoffTimeoutMs = math.max(2000, math.min(15000, math.floor(tonumber(decoded.handoffTimeoutMs) or BookingRules.handoffTimeoutMs)))
            end
            if row.setting_key == 'cinematic_rules' then
                CinematicRules.enabled = decoded.enabled ~= false
                CinematicRules.allowSkip = decoded.allowSkip ~= false
                CinematicRules.cameraCollision = decoded.cameraCollision ~= false
                CinematicRules.sequenceSpeed = math.max(0.5, math.min(2.0, tonumber(decoded.sequenceSpeed) or 1.0))
                CinematicRules.cameraFov = math.max(30, math.min(70, tonumber(decoded.cameraFov) or 45))
                CinematicRules.responseDurationMs = math.max(1000, math.min(8000, math.floor(tonumber(decoded.responseDurationMs) or 2200)))
                CinematicRules.soundEnabled = decoded.soundEnabled ~= false
                CinematicRules.soundVolume = math.max(0, math.min(1, tonumber(decoded.soundVolume) or 1.0))
            end
        end
    end
    PoliceSchemaMarkReady('booking')
end)
