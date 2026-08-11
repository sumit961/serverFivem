-- Cross-agency charge-based booking. cm-law owns the booking journal and
-- custody transition; cm-prison remains authoritative for confinement.

local BookingBusy = {}

local function bookingNotify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function clean(value, limit)
    return tostring(value or ''):gsub('[%c]+', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, limit)
end

local SharedJailSpawns, SharedJailRelease = {}, nil

local function decodeLocation(value)
    local ok, decoded = pcall(json.decode, value or '')
    if not ok or type(decoded) ~= 'table' then return nil end
    local x, y, z = tonumber(decoded.x), tonumber(decoded.y), tonumber(decoded.z)
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z, heading = tonumber(decoded.heading) or 0.0,
        bucket = tonumber(decoded.bucket) or 0, name = clean(decoded.name, 64) }
end

local function saveJailSetting(key, value, actorCid)
    MySQL.insert.await([[INSERT INTO cm_legal_jail_settings(setting_key,setting_value,updated_by) VALUES(?,?,?)
        ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value),updated_by=VALUES(updated_by)]],
        { key, json.encode(value), actorCid })
end

function LawAdminSetSharedJail(src, settingType, reset)
    if not adminAllowed(src) then return false, 'Permission denied.' end
    local actorCid = characterIdFor(src) or 'admin'
    if settingType == 'jail_spawns' then
        if not reset then return false, 'Use Add Spawn to add a jail spawn.' end
        SharedJailSpawns = {}
        MySQL.update.await("DELETE FROM cm_legal_jail_settings WHERE setting_key='jail_spawns'")
        logActivity('shared', actorCid, 'shared_jail_spawns_reset', {})
        return true, 'All shared jail spawns reset.'
    end
    if settingType ~= 'jail_spawn' and settingType ~= 'jail_release' then return false, 'Unknown shared jail setting.' end
    if reset then
        if settingType == 'jail_release' then
            SharedJailRelease = nil
            MySQL.update.await("DELETE FROM cm_legal_jail_settings WHERE setting_key='jail_release'")
            logActivity('shared', actorCid, 'shared_jail_release_reset', {})
            return true, 'Shared jail release point reset.'
        end
        return false, 'Use Shared jail: all spawns to reset the spawn pool.'
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Player entity unavailable.' end
    local coords, heading = GetEntityCoords(ped), 0.0
    pcall(function() heading = tonumber(GetEntityHeading(ped)) or 0.0 end)
    local location = { x = coords.x, y = coords.y, z = coords.z, heading = heading,
        bucket = GetPlayerRoutingBucket(src), name = settingType == 'jail_spawn' and 'Shared Jail Spawn' or 'Shared Jail Release' }
    if settingType == 'jail_spawn' then
        SharedJailSpawns[#SharedJailSpawns + 1] = location
        saveJailSetting('jail_spawns', SharedJailSpawns, actorCid)
        logActivity('shared', actorCid, 'shared_jail_spawn_added', { index = #SharedJailSpawns, bucket = location.bucket })
        return true, ('Shared jail spawn %d saved (capacity %d).'):format(#SharedJailSpawns, tonumber(Config.Custody.SpawnCapacity) or 2)
    end
    SharedJailRelease = location
    saveJailSetting('jail_release', location, actorCid)
    logActivity('shared', actorCid, 'shared_jail_release_set', { bucket = location.bucket })
    return true, 'Shared jail release point saved.'
end

exports('GetSharedJailConfiguration', function()
    return { spawns = SharedJailSpawns, release = SharedJailRelease,
        capacityPerSpawn = tonumber(Config.Custody.SpawnCapacity) or 2 }
end)

local function chargeCatalog()
    local list, byId = {}, {}
    for _, configured in ipairs(Config.Custody.Charges or {}) do
        local id, label = clean(configured.id, 48), clean(configured.label, 96)
        local minutes = math.max(0, math.floor(tonumber(configured.jailMinutes) or 0))
        if id ~= '' and label ~= '' and not byId[id] then
            local charge = { id = id, label = label, jailMinutes = minutes }
            byId[id], list[#list + 1] = charge, charge
        end
    end
    return list, byId
end

local function bookingAuthority(src, targetSrc)
    src, targetSrc = tonumber(src), tonumber(targetSrc)
    if not src or not targetSrc or src == targetSrc then return nil, 'Invalid suspect.' end
    local actor, actorCid = activeMemberForSource(src)
    if not actor or actor.suspended or not actor.onDuty or not (actor.isLeader or actor.permissions['law.cuff'] == true) then
        return nil, 'You must be an on-duty member with cuffing permission.'
    end
    local targetCid = characterIdFor(targetSrc)
    local officerPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
    if not targetCid or not officerPed or officerPed == 0 or not targetPed or targetPed == 0 then return nil, 'The suspect is unavailable.' end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc) then return nil, 'The suspect is not in your routing instance.' end
    if Player(targetSrc).state.cmCuffed ~= true then return nil, 'The suspect must be cuffed first.' end
    local intake = type(LawFacilityLocation) == 'function' and LawFacilityLocation(actor.organizationId, 'intake') or nil
    if not intake then return nil, 'Your organization prison intake NPC is not configured.' end
    local intakeRadius = tonumber(Config.Custody.IntakeRadius) or 8.0
    if GetPlayerRoutingBucket(src) ~= (tonumber(intake.bucket) or 0) then return nil, 'Move to your organization prison intake.' end
    local intakeCoords = vector3(intake.x, intake.y, intake.z)
    if #(GetEntityCoords(officerPed) - intakeCoords) > intakeRadius or #(GetEntityCoords(targetPed) - intakeCoords) > intakeRadius then
        return nil, 'Bring the cuffed suspect to your organization prison intake NPC.'
    end
    if #(GetEntityCoords(officerPed) - GetEntityCoords(targetPed)) > 3.0 then return nil, 'Move closer to the suspect.' end
    if #SharedJailSpawns < 1 then return nil, 'No shared jail spawn locations are configured.' end
    if not SharedJailRelease then return nil, 'The shared jail release point is not configured.' end
    return { actor = actor, actorCid = tostring(actorCid), targetCid = tostring(targetCid), targetSrc = targetSrc }
end

function LawBookingActionIds()
    return {} -- legacy fixed-duration server actions were removed
end

lib.callback.register('cm-law:server:bookingPreview', function(src, targetSrc)
    local booking, why = bookingAuthority(src, targetSrc)
    if not booking then return { ok = false, error = why } end
    local charges = chargeCatalog()
    return { ok = true, suspectName = nameFor(booking.targetCid), characterId = booking.targetCid, charges = charges,
        maxCharges = tonumber(Config.Custody.MaxCharges) or 10,
        maxSentenceMinutes = tonumber(Config.Custody.MaxSentenceMinutes) or 180 }
end)

lib.callback.register('cm-law:server:bookSuspect', function(src, data)
    if not rateLimit(src, 'law_booking_action', 1500) then return { ok = false, error = 'Please wait.' } end
    data = type(data) == 'table' and data or {}
    local booking, why = bookingAuthority(src, data.targetServerId)
    if not booking then return { ok = false, error = why } end
    if BookingBusy[booking.targetCid] then return { ok = false, error = 'This suspect is already being processed.' } end

    local reason = clean(data.reason, 500)
    if #reason < 5 then return { ok = false, error = 'Enter a clear arrest reason.' } end
    if type(data.chargeIds) ~= 'table' then return { ok = false, error = 'Select at least one charge.' } end
    local _, byId = chargeCatalog()
    local selected, seen, minutes = {}, {}, 0
    local maxCharges = math.max(1, tonumber(Config.Custody.MaxCharges) or 10)
    if #data.chargeIds < 1 or #data.chargeIds > maxCharges then
        return { ok = false, error = ('Select between 1 and %d charges.'):format(maxCharges) }
    end
    for _, suppliedId in ipairs(data.chargeIds) do
        local id, charge = clean(suppliedId, 48), nil
        charge = byId[id]
        if not charge then return { ok = false, error = 'An invalid charge was selected.' } end
        if seen[id] then return { ok = false, error = 'Duplicate charges are not allowed.' } end
        seen[id] = true
        selected[#selected + 1] = { id = charge.id, label = charge.label, jailMinutes = charge.jailMinutes }
        minutes = minutes + charge.jailMinutes
    end
    minutes = math.min(minutes, math.max(1, tonumber(Config.Custody.MaxSentenceMinutes) or 180))
    if minutes < 1 then return { ok = false, error = 'The selected charges do not carry jail time.' } end

    BookingBusy[booking.targetCid] = tonumber(src)
    local bookingId
    local journalOk, journalError = pcall(function()
        bookingId = MySQL.insert.await([[INSERT INTO cm_legal_bookings
            (organization_id,character_id,officer_cid,reason,charges,sentence_minutes,handoff_status)
            VALUES (?,?,?,?,?,?,'processing')]],
            { booking.actor.organizationId, booking.targetCid, booking.actorCid, reason, json.encode(selected), minutes })
        if not bookingId then error('booking insert failed') end
        local affected = MySQL.update.await([[UPDATE cm_legal_custody SET status='processing',officer_cid=?,booking_minutes=?,updated_at=NOW()
            WHERE character_id=? AND status='cuffed']], { booking.actorCid, minutes, booking.targetCid })
        if tonumber(affected) ~= 1 then error('custody transition failed') end
    end)
    if not journalOk then
        BookingBusy[booking.targetCid] = nil
        if bookingId then MySQL.update.await("UPDATE cm_legal_bookings SET handoff_status='failed',failure_reason='journal_error' WHERE id=?", { bookingId }) end
        return { ok = false, error = 'Could not safely journal the booking.' }
    end

    local jailed, jailFailure = false, 'bridge_error'
    local bridgeOk, bridgeError = pcall(function()
        jailed, jailFailure = exports['cm-prison']:JailSuspect(src, booking.targetSrc, minutes, 10000, {
            spawns = SharedJailSpawns, release = SharedJailRelease, reason = reason,
            arrestedBy = nameFor(booking.actorCid), charges = selected, bookingId = bookingId,
        })
    end)
    if not jailed then
        if not bridgeOk then print(('[cm-law] cm-prison handoff failed: %s'):format(tostring(bridgeError))) end
        MySQL.transaction.await({
            { query = "UPDATE cm_legal_custody SET status='cuffed',updated_at=NOW() WHERE character_id=? AND status='processing'", values = { booking.targetCid } },
            { query = "UPDATE cm_legal_bookings SET handoff_status='failed',failure_reason=? WHERE id=? AND handoff_status='processing'", values = { clean(jailFailure, 64), bookingId } },
        })
        BookingBusy[booking.targetCid] = nil
        local failures = { prison_full = 'All jail spawn slots are occupied.', database_error = 'Prison could not save the sentence.',
            target_disconnected = 'The suspect disconnected during processing.', prison_unavailable = 'Prison is not ready.' }
        return { ok = false, error = failures[jailFailure] or 'Prison could not confirm custody. The suspect remains cuffed.' }
    end

    MySQL.transaction.await({
        { query = "UPDATE cm_legal_custody SET status='jailed',updated_at=NOW() WHERE character_id=? AND status='processing'", values = { booking.targetCid } },
        { query = "UPDATE cm_legal_bookings SET handoff_status='confirmed',confirmed_at=NOW(),release_at=DATE_ADD(NOW(),INTERVAL ? MINUTE) WHERE id=?", values = { minutes, bookingId } },
    })
    BookingBusy[booking.targetCid] = nil
    clearAll(booking.targetSrc, true)
    logActivity(booking.actor.organizationId, booking.actorCid, 'suspect_booked', {
        targetCid = booking.targetCid, minutes = minutes, bookingId = bookingId, charges = selected, reason = reason })
    bookingNotify(src, ('Suspect booked on %d charge%s for %d minutes.'):format(#selected, #selected == 1 and '' or 's', minutes), 'success')
    return { ok = true, message = 'Booking confirmed.', bookingId = bookingId, minutes = minutes }
end)

AddEventHandler('cm-prison:server:released', function(characterId)
    characterId = tostring(characterId)
    MySQL.transaction.await({
        { query = "UPDATE cm_legal_custody SET status='released',updated_at=NOW() WHERE character_id=? AND status='jailed'", values = { characterId } },
        { query = "UPDATE cm_legal_bookings SET handoff_status='released',released_at=NOW() WHERE character_id=? AND handoff_status='confirmed'", values = { characterId } },
    })
end)

AddEventHandler('playerDropped', function()
    local dropped = tonumber(source)
    for characterId, busy in pairs(BookingBusy) do
        if busy == dropped then BookingBusy[characterId] = nil end
    end
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_jail_settings (
        setting_key VARCHAR(32) NOT NULL,setting_value LONGTEXT NOT NULL,updated_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY(setting_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_legal_bookings (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,organization_id VARCHAR(32) NOT NULL,
        character_id VARCHAR(64) NOT NULL,officer_cid VARCHAR(64) NOT NULL,reason VARCHAR(500) NOT NULL,
        charges LONGTEXT NOT NULL,sentence_minutes INT UNSIGNED NOT NULL,handoff_status VARCHAR(24) NOT NULL DEFAULT 'processing',
        failure_reason VARCHAR(64) NULL,booked_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        confirmed_at TIMESTAMP NULL,release_at TIMESTAMP NULL,released_at TIMESTAMP NULL,
        PRIMARY KEY(id),KEY idx_cm_legal_bookings_character(character_id,booked_at),
        KEY idx_cm_legal_bookings_status(handoff_status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    local rows = MySQL.query.await("SELECT setting_key,setting_value FROM cm_legal_jail_settings WHERE setting_key IN ('jail_spawns','jail_release')") or {}
    for _, row in ipairs(rows) do
        if row.setting_key == 'jail_release' then
            SharedJailRelease = decodeLocation(row.setting_value)
        elseif row.setting_key == 'jail_spawns' then
            local ok, decoded = pcall(json.decode, row.setting_value or '[]')
            if ok and type(decoded) == 'table' then
                SharedJailSpawns = {}
                for _, stored in ipairs(decoded) do
                    local location = decodeLocation(json.encode(stored))
                    if location then SharedJailSpawns[#SharedJailSpawns + 1] = location end
                end
            end
        end
    end
end)
