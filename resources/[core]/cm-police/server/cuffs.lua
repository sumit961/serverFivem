-- cm-police cuffing & arrest. Server-authoritative, transient (session-only)
-- state -- nothing here is persisted, matching cm-ems's stretcher.lua
-- convention for physically-owned, in-world state. No item/inventory
-- dependency: cuffing is gated purely by on-duty status + the police.cuff
-- permission.
--
-- A cuffed player is a REAL PLAYER, not an NPC ped like EMS's mission
-- patients -- so movement (escort) is driven by the CUFFED PLAYER'S OWN
-- CLIENT reading a replicated cmEscortedBy state bag and following the
-- officer's ped locally (client/cuffs.lua). The officer's client never
-- tasks another player's ped directly. Seating in/out of a vehicle IS done
-- server-side, since a player's ped has a real server-side entity handle
-- (GetPlayerPed), unlike an NPC ped created client-side.

local Cuffed = {}    -- [targetSrc] = { officerSrc, officerCid, targetCid }
local Escorted = {}  -- [targetSrc] = officerSrc
local PendingVehicleSeats = {} -- unguessable-enough, short-lived server challenges
local vehicleSeatSequence = 0

local function cuffNotify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function authorized(src)
    local characterId = cid(tonumber(src))
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) or not has(member, 'police.cuff') then
        return nil, characterId
    end
    return member, tostring(characterId)
end

local function setEscorted(targetSrc, officerSrc)
    Escorted[targetSrc] = officerSrc or nil
    if GetPlayerName(targetSrc) then
        Player(targetSrc).state:set('cmEscortedBy', officerSrc or false, true)
    end
end

-- Bare global (not local) -- server/booking.lua calls this the moment a
-- booking successfully hands a suspect off to cm-prison,
-- so cm-police's own restraint bookkeeping (Cuffed/Escorted/cmCuffed) is
-- fully released instead of left dangling once cm-prison becomes solely
-- responsible for containing them.
local function persistCuffed(targetCid, officerCid)
    MySQL.query.await([[
        INSERT INTO cm_police_custody (character_id, officer_cid, status, created_at, updated_at)
        VALUES (?, ?, 'cuffed', NOW(), NOW())
        ON DUPLICATE KEY UPDATE officer_cid = VALUES(officer_cid), status = 'cuffed',
            reason = NULL, charges = NULL, booking_minutes = NULL, custody_mode = 'arrest', updated_at = NOW()
    ]], { targetCid, officerCid })
end

local function releaseCustody(targetCid)
    if targetCid then
        MySQL.update.await("UPDATE cm_police_custody SET status = 'released', updated_at = NOW() WHERE character_id = ?", { targetCid })
    end
end

function clearAll(targetSrc, preserveCustody)
    local restraint = Cuffed[targetSrc]
    Cuffed[targetSrc] = nil
    setEscorted(targetSrc, nil)
    if GetPlayerName(targetSrc) then
        Player(targetSrc).state:set('cmCuffed', false, true)
    end
    if not preserveCustody and restraint then releaseCustody(restraint.targetCid) end
end

-- Real screenshot capture (the arresting officer's own current view -- POV
-- matches a real body-cam), same exports['screenshot-basic']:requestClientScreenshot
-- shape cm-house/server/sv_photo.lua's requestServerCapture already uses
-- for property photos, adapted to this resource's own image directory.
-- Falls back to a text-only system note (this feature's original scope)
-- if screenshot-basic isn't running or the capture fails/times out --
-- never blocks the cuff action itself either way.
local function captureBodycamEvidence(src, actorCid, targetCid)
    local officerPed = GetPlayerPed(src)
    local fallbackNote
    if officerPed and officerPed ~= 0 then
        local c = GetEntityCoords(officerPed)
        fallbackNote = ('BODY-CAM LOG: Cuffed by %s near %.0f, %.0f'):format(nameFor(actorCid), c.x, c.y)
    end

    if GetResourceState('screenshot-basic') ~= 'started' then
        if fallbackNote then
            MySQL.insert.await('INSERT INTO cm_police_notes (target_cid, author_cid, note) VALUES (?, ?, ?)', { targetCid, nil, fallbackNote })
        end
        return
    end

    local filename = ('bodycam_%d_%06d.jpg'):format(os.time(), math.random(0, 999999))
    local relativePath = 'html/img/bodycam/' .. filename
    local absolutePath = ('%s/%s'):format(GetResourcePath(GetCurrentResourceName()), relativePath)

    local promiseResult = promise.new()
    local resolved = false
    local function finish(ok) if not resolved then resolved = true; promiseResult:resolve(ok) end end

    local ok = pcall(function()
        exports['screenshot-basic']:requestClientScreenshot(src, {
            fileName = absolutePath,
            encoding = 'jpg',
            quality = 0.85,
          }, function(err) finish(err == nil or err == false) end)
    end)
    if not ok then
        if fallbackNote then
            MySQL.insert.await('INSERT INTO cm_police_notes (target_cid, author_cid, note) VALUES (?, ?, ?)', { targetCid, nil, fallbackNote })
        end
        return
    end
    SetTimeout(15000, function() finish(false) end)

    if Citizen.Await(promiseResult) then
        MySQL.insert.await('INSERT INTO cm_police_evidence (target_cid, author_cid, url, caption) VALUES (?, ?, ?, ?)',
            { targetCid, nil, 'img/bodycam/' .. filename, 'Body-cam capture' })
    elseif fallbackNote then
        MySQL.insert.await('INSERT INTO cm_police_notes (target_cid, author_cid, note) VALUES (?, ?, ?)', { targetCid, nil, fallbackNote })
    end
end

local function nearbyFreeSeatVehicle(officerCoords, maxDistance, routingBucket)
    local vehicle
    for _, candidate in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(candidate)
            and GetEntityRoutingBucket(candidate) == routingBucket
            and #(officerCoords - GetEntityCoords(candidate)) <= maxDistance then
            vehicle = candidate
            break
        end
    end
    return vehicle
end

AddEventHandler('cm-police:server:cuffAction', function(src, targetSrc, action, payload, context)
    src, targetSrc = tonumber(src), tonumber(targetSrc)
    if not src or not targetSrc or src == targetSrc then return end
    if Cuffed[src] then return cuffNotify(src, 'You cannot do that while cuffed.', 'error') end
    if not rateLimit(src, 'police_cuff_action', 700) then return cuffNotify(src, 'Please wait.', 'error') end
    local actor, actorCid = authorized(src)
    if not actor then return cuffNotify(src, 'You must be an on-duty officer with cuffing permission.', 'error') end
    local targetCid = context and context.targetCharacterId and tostring(context.targetCharacterId) or cid(targetSrc)
    if not targetCid then return end

    if action == 'police_cuff' then
        if Cuffed[targetSrc] then return cuffNotify(src, 'That player is already cuffed.', 'error') end
        Cuffed[targetSrc] = { officerSrc = src, officerCid = actorCid, targetCid = targetCid }
        Player(targetSrc).state:set('cmCuffed', true, true)
        persistCuffed(targetCid, actorCid)
        log(actorCid, 'suspect_cuffed', { targetCid = targetCid })
        -- Body-cam auto-evidence: a real screenshot from the arresting
        -- officer's own view when possible, same "author_cid = NULL renders
        -- as System" convention as auto-warrants -- falls back to a text
        -- note if screenshot-basic isn't available.
        captureBodycamEvidence(src, actorCid, targetCid)
        cuffNotify(src, 'Suspect cuffed.', 'success')
        cuffNotify(targetSrc, 'You have been cuffed.', 'error')
        -- Miranda rights -- a purely cosmetic roleplay prompt, admin-
        -- editable text (Config.Miranda), separate toast from the cuff
        -- notice above so it reads as its own moment.
        if Config.Miranda and Config.Miranda.Text then
            cuffNotify(targetSrc, Config.Miranda.Text, 'inform')
        end
    elseif action == 'police_uncuff' then
        if not Cuffed[targetSrc] then return cuffNotify(src, 'That player is not cuffed.', 'error') end
        clearAll(targetSrc)
        log(actorCid, 'suspect_uncuffed', { targetCid = targetCid })
        cuffNotify(src, 'Suspect uncuffed.', 'success')
        cuffNotify(targetSrc, 'You have been uncuffed.', 'success')
    elseif action == 'police_escort_grab' then
        if not Cuffed[targetSrc] then return cuffNotify(src, 'That player is not cuffed.', 'error') end
        local officerPed = GetPlayerPed(src)
        if officerPed == 0 or GetVehiclePedIsIn(officerPed, false) ~= 0 then
            return cuffNotify(src, 'Exit the vehicle before grabbing a suspect.', 'error')
        end
        if Escorted[targetSrc] and Escorted[targetSrc] ~= src and GetPlayerName(Escorted[targetSrc]) then
            return cuffNotify(src, 'Another officer is already escorting that suspect.', 'error')
        end
        setEscorted(targetSrc, src)
        cuffNotify(src, 'Escorting suspect.', 'success')
    elseif action == 'police_escort_release' then
        if Escorted[targetSrc] ~= src then return cuffNotify(src, 'You are not escorting that suspect.', 'error') end
        setEscorted(targetSrc, nil)
        cuffNotify(src, 'Suspect released.', 'success')
    elseif action == 'police_put_in_vehicle' then
        if not Cuffed[targetSrc] then return cuffNotify(src, 'That player is not cuffed.', 'error') end
        if Escorted[targetSrc] ~= src then return cuffNotify(src, 'Grab the suspect before putting them in a vehicle.', 'error') end
        local officerPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
        if not officerPed or officerPed == 0 or not targetPed or targetPed == 0 then return end
        payload = type(payload) == 'table' and payload or {}
        local vehicle
        local requestedNetId = tonumber(payload.vehicleNetId)
        if requestedNetId and requestedNetId > 0 then
            local requested = NetworkGetEntityFromNetworkId(requestedNetId)
            if requested and requested ~= 0 and DoesEntityExist(requested) and GetEntityType(requested) == 2
                and GetEntityRoutingBucket(requested) == GetPlayerRoutingBucket(src)
                and #(GetEntityCoords(officerPed) - GetEntityCoords(requested)) <= (Config.Cuffs.VehicleSeatDistance or 6.0) then
                vehicle = requested
            end
            if not vehicle then return cuffNotify(src, 'The selected vehicle is not available.', 'error') end
        else
            vehicle = nearbyFreeSeatVehicle(
                GetEntityCoords(officerPed),
                Config.Cuffs.VehicleSeatDistance or 6.0,
                GetPlayerRoutingBucket(src)
            )
        end
        if not vehicle then return cuffNotify(src, 'No nearby vehicle was found.', 'error') end
        local seat = 0 -- target client selects another passenger seat if needed
        local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
        if not vehicleNetId or vehicleNetId == 0 then return cuffNotify(src, 'That vehicle is not network-ready.', 'error') end
        -- The target player's client owns their ped. Keep selection, distance,
        -- cuff and free-seat checks authoritative here, then ask that owning
        -- client to execute the validated seat warp.
        setEscorted(targetSrc, nil)
        vehicleSeatSequence = vehicleSeatSequence + 1
        local token = ('%d:%d:%d:%d'):format(src, targetSrc, os.time(), vehicleSeatSequence)
        PendingVehicleSeats[token] = {
            officerSrc = src, targetSrc = targetSrc, actorCid = actorCid,
            targetCid = targetCid, vehicleNetId = vehicleNetId, seat = seat,
            expires = GetGameTimer() + 6500,
        }
        TriggerClientEvent('cm-police:client:placeInVehicle', targetSrc, vehicleNetId, seat, token)
        SetTimeout(6500, function()
            local pending = PendingVehicleSeats[token]
            if not pending then return end
            PendingVehicleSeats[token] = nil
            if GetPlayerName(pending.targetSrc) and GetPlayerName(pending.officerSrc) and Cuffed[pending.targetSrc] then
                setEscorted(pending.targetSrc, pending.officerSrc)
                cuffNotify(pending.officerSrc, 'Could not confirm the suspect entered the vehicle.', 'error')
            end
        end)
    elseif action == 'police_take_out_vehicle' then
        if not Cuffed[targetSrc] then return cuffNotify(src, 'That player is not cuffed.', 'error') end
        local officerPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
        if not officerPed or officerPed == 0 or not targetPed or targetPed == 0 then return end
        local vehicle = GetVehiclePedIsIn(targetPed, false)
        if vehicle == 0 or not DoesEntityExist(vehicle) then return cuffNotify(src, 'That suspect is not in a vehicle.', 'error') end
        if #(GetEntityCoords(officerPed) - GetEntityCoords(vehicle)) > (Config.Cuffs.VehicleSeatDistance or 6.0) then
            return cuffNotify(src, 'Move closer to the vehicle.', 'error')
        end
        local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
        if not vehicleNetId or vehicleNetId == 0 then return cuffNotify(src, 'That vehicle is not network-ready.', 'error') end
        TriggerClientEvent('cm-police:client:removeFromVehicle', targetSrc, vehicleNetId)
        setEscorted(targetSrc, src)
        log(actorCid, 'suspect_removed_from_vehicle', { targetCid = targetCid })
        cuffNotify(src, 'Suspect removed from the vehicle.', 'success')
    end
end)

RegisterNetEvent('cm-police:server:vehicleSeatResult', function(token, clientSucceeded)
    local targetSrc = tonumber(source)
    token = type(token) == 'string' and token:sub(1, 100) or nil
    local pending = token and PendingVehicleSeats[token]
    if not pending or pending.targetSrc ~= targetSrc then return end
    PendingVehicleSeats[token] = nil

    local officerPed, targetPed = GetPlayerPed(pending.officerSrc), GetPlayerPed(targetSrc)
    local vehicle = NetworkGetEntityFromNetworkId(pending.vehicleNetId)
    if clientSucceeded == true and targetPed and targetPed ~= 0 and vehicle and vehicle ~= 0 then
        local replicationDeadline = GetGameTimer() + 2000
        while GetGameTimer() < replicationDeadline and GetVehiclePedIsIn(targetPed, false) ~= vehicle do
            Wait(100)
        end
    end
    local valid = clientSucceeded == true and Cuffed[targetSrc] ~= nil
        and officerPed and officerPed ~= 0 and targetPed and targetPed ~= 0
        and vehicle and vehicle ~= 0 and DoesEntityExist(vehicle)
        and GetVehiclePedIsIn(targetPed, false) == vehicle
        and GetPlayerRoutingBucket(pending.officerSrc) == GetPlayerRoutingBucket(targetSrc)
        and #(GetEntityCoords(officerPed) - GetEntityCoords(vehicle)) <= (Config.Cuffs.VehicleSeatDistance or 6.0) + 2.0

    if valid then
        log(pending.actorCid, 'suspect_transported', {
            targetCid = pending.targetCid, vehicleNetId = pending.vehicleNetId, seat = pending.seat,
        })
        cuffNotify(pending.officerSrc, 'Suspect placed in the vehicle.', 'success')
    elseif GetPlayerName(pending.officerSrc) and GetPlayerName(targetSrc) and Cuffed[targetSrc] then
        setEscorted(targetSrc, pending.officerSrc)
        cuffNotify(pending.officerSrc, 'Could not confirm the suspect entered the vehicle.', 'error')
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Cuffed[src] then Cuffed[src] = nil end
    Escorted[src] = nil
    -- If the dropped player was escorting someone, release that suspect too.
    for targetSrc, officerSrc in pairs(Escorted) do
        if officerSrc == src then setEscorted(targetSrc, nil) end
    end
    for token, pending in pairs(PendingVehicleSeats) do
        if pending.targetSrc == src or pending.officerSrc == src then PendingVehicleSeats[token] = nil end
    end
end)

local function restoreCustody(src)
    src = tonumber(src)
    local targetCid = src and cid(src)
    if not targetCid or Cuffed[src] then return end
    local row = MySQL.single.await([[
        SELECT officer_cid, status, custody_mode FROM cm_police_custody
        WHERE character_id = ? AND status IN ('cuffed', 'processing') LIMIT 1
    ]], { targetCid })
    if not row then return end
    if row.status == 'processing' and row.custody_mode == 'surrender' then return end
    local officerCid = row.officer_cid and tostring(row.officer_cid) or nil
    Cuffed[src] = { officerSrc = officerCid and sourceFor(officerCid) or nil, officerCid = officerCid, targetCid = tostring(targetCid) }
    -- Keep a processing state intact across reconnect. The booking
    -- reconciler decides whether cm-prison accepted it; downgrading it here
    -- would erase the only durable evidence of an in-flight handoff.
    if row.status == 'cuffed' then
        MySQL.update.await("UPDATE cm_police_custody SET updated_at = NOW() WHERE character_id = ?", { targetCid })
    end
    Player(src).state:set('cmCuffed', true, true)
    Player(src).state:set('cmEscortedBy', false, true)
    cuffNotify(src, 'Your existing police custody has been restored.', 'error')
end

AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    CreateThread(function()
        if AwaitPoliceDatabase(15000) then restoreCustody(src) end
    end)
end)

CreateThread(function()
    if not AwaitPoliceDatabase(15000) then return end
    for _, playerSrc in ipairs(GetPlayers()) do restoreCustody(tonumber(playerSrc)) end
end)

-- Periodic sanity check: if an escorting officer wanders far from their
-- suspect (or either disconnects), drop the escort instead of leaving a
-- stale state bag pointed at someone who isn't nearby anymore. Mirrors
-- stretcher.lua's own periodic cleanup thread.
CreateThread(function()
    while true do
        Wait(3000)
        for targetSrc, officerSrc in pairs(Escorted) do
            local targetPed = GetPlayerName(targetSrc) and GetPlayerPed(targetSrc)
            local officerPed = GetPlayerName(officerSrc) and GetPlayerPed(officerSrc)
            if not targetPed or targetPed == 0 or not officerPed or officerPed == 0
                or #(GetEntityCoords(targetPed) - GetEntityCoords(officerPed)) > 15.0 then
                setEscorted(targetSrc, nil)
            end
        end
    end
end)
