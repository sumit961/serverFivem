-- cm-law cuffing & escort. Server-authoritative, transient (session-only)
-- state, mirroring cm-police/server/cuffs.lua's proven shape -- state bags
-- (cmCuffed/cmEscortedBy) are plain FiveM state bags, not cm-police-specific,
-- so the client-side follow/drag mechanic is reused as-is (client/cuffs.lua).
--
-- No bodycam-evidence capture here (cm-police's version captures a
-- screenshot into an MDT-viewable evidence table) -- cm-law has no MDT yet
-- to show that evidence in, so capturing it now would just be dead weight.
-- Revisit once MDT exists.

local Cuffed = {}   -- [targetSrc] = { officerSrc, officerCid, targetCid, organizationId }
local Escorted = {} -- [targetSrc] = officerSrc
local PendingVehicleSeats = {}
local vehicleSeatSequence = 0

local function cuffNotify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function authorized(src)
    local member, characterId = activeMemberForSource(src)
    if not member or member.suspended or not member.onDuty
        or not (member.isLeader or member.permissions['law.cuff'] == true) then
        return nil, characterId
    end
    return member, characterId
end

local function setEscorted(targetSrc, officerSrc)
    Escorted[targetSrc] = officerSrc or nil
    if GetPlayerName(targetSrc) then
        Player(targetSrc).state:set('cmEscortedBy', officerSrc or false, true)
    end
end

local function persistCuffed(orgId, targetCid, officerCid)
    MySQL.query.await([[
        INSERT INTO cm_legal_custody (organization_id, character_id, officer_cid, status, created_at, updated_at)
        VALUES (?, ?, ?, 'cuffed', NOW(), NOW())
        ON DUPLICATE KEY UPDATE organization_id = VALUES(organization_id), officer_cid = VALUES(officer_cid),
            status = 'cuffed', reason = NULL, booking_minutes = NULL, updated_at = NOW()
    ]], { orgId, targetCid, officerCid })
end

local function releaseCustody(targetCid)
    if targetCid then
        MySQL.update.await("UPDATE cm_legal_custody SET status = 'released', updated_at = NOW() WHERE character_id = ?", { targetCid })
    end
end

-- Bare global: server/booking.lua calls this once a booking successfully
-- hands a suspect off to cm-prison, so this restraint bookkeeping doesn't
-- linger once cm-prison becomes responsible for containing them.
function clearAll(targetSrc, preserveCustody)
    local restraint = Cuffed[targetSrc]
    Cuffed[targetSrc] = nil
    setEscorted(targetSrc, nil)
    if GetPlayerName(targetSrc) then
        Player(targetSrc).state:set('cmCuffed', false, true)
    end
    if not preserveCustody and restraint then releaseCustody(restraint.targetCid) end
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

AddEventHandler('cm-law:server:cuffAction', function(src, targetSrc, action, payload)
    src, targetSrc = tonumber(src), tonumber(targetSrc)
    if not src or not targetSrc or src == targetSrc then return end
    if Cuffed[src] then return cuffNotify(src, 'You cannot do that while cuffed.', 'error') end
    if not rateLimit(src, 'law_cuff_action', 700) then return cuffNotify(src, 'Please wait.', 'error') end
    local actor, actorCid = authorized(src)
    if not actor then return cuffNotify(src, 'You must be an on-duty member with cuffing permission.', 'error') end
    local targetCid = characterIdFor(targetSrc)
    if not targetCid then return end

    if action == 'law_cuff' then
        if Cuffed[targetSrc] then return cuffNotify(src, 'That player is already cuffed.', 'error') end
        Cuffed[targetSrc] = { officerSrc = src, officerCid = actorCid, targetCid = targetCid, organizationId = actor.organizationId }
        Player(targetSrc).state:set('cmCuffed', true, true)
        persistCuffed(actor.organizationId, targetCid, actorCid)
        logActivity(actor.organizationId, actorCid, 'suspect_cuffed', { targetCid = targetCid })
        cuffNotify(src, 'Suspect cuffed.', 'success')
        cuffNotify(targetSrc, 'You have been cuffed.', 'error')
    elseif action == 'law_uncuff' then
        if not Cuffed[targetSrc] then return cuffNotify(src, 'That player is not cuffed.', 'error') end
        clearAll(targetSrc)
        logActivity(actor.organizationId, actorCid, 'suspect_uncuffed', { targetCid = targetCid })
        cuffNotify(src, 'Suspect uncuffed.', 'success')
        cuffNotify(targetSrc, 'You have been uncuffed.', 'success')
    elseif action == 'law_escort_grab' then
        if not Cuffed[targetSrc] then return cuffNotify(src, 'That player is not cuffed.', 'error') end
        local officerPed = GetPlayerPed(src)
        if officerPed == 0 or GetVehiclePedIsIn(officerPed, false) ~= 0 then
            return cuffNotify(src, 'Exit the vehicle before grabbing a suspect.', 'error')
        end
        if Escorted[targetSrc] and Escorted[targetSrc] ~= src and GetPlayerName(Escorted[targetSrc]) then
            return cuffNotify(src, 'Another member is already escorting that suspect.', 'error')
        end
        setEscorted(targetSrc, src)
        cuffNotify(src, 'Escorting suspect.', 'success')
    elseif action == 'law_escort_release' then
        if Escorted[targetSrc] ~= src then return cuffNotify(src, 'You are not escorting that suspect.', 'error') end
        setEscorted(targetSrc, nil)
        cuffNotify(src, 'Suspect released.', 'success')
    elseif action == 'law_put_in_vehicle' then
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
            vehicle = nearbyFreeSeatVehicle(GetEntityCoords(officerPed), Config.Cuffs.VehicleSeatDistance or 6.0, GetPlayerRoutingBucket(src))
        end
        if not vehicle then return cuffNotify(src, 'No nearby vehicle was found.', 'error') end
        local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
        if not vehicleNetId or vehicleNetId == 0 then return cuffNotify(src, 'That vehicle is not network-ready.', 'error') end
        setEscorted(targetSrc, nil)
        vehicleSeatSequence = vehicleSeatSequence + 1
        local token = ('%d:%d:%d:%d'):format(src, targetSrc, os.time(), vehicleSeatSequence)
        PendingVehicleSeats[token] = {
            officerSrc = src, targetSrc = targetSrc, actorCid = actorCid,
            targetCid = targetCid, vehicleNetId = vehicleNetId, expires = GetGameTimer() + 6500,
        }
        TriggerClientEvent('cm-law:client:placeInVehicle', targetSrc, vehicleNetId, token)
        SetTimeout(6500, function()
            local pending = PendingVehicleSeats[token]
            if not pending then return end
            PendingVehicleSeats[token] = nil
            if GetPlayerName(pending.targetSrc) and GetPlayerName(pending.officerSrc) and Cuffed[pending.targetSrc] then
                setEscorted(pending.targetSrc, pending.officerSrc)
                cuffNotify(pending.officerSrc, 'Could not confirm the suspect entered the vehicle.', 'error')
            end
        end)
    elseif action == 'law_take_out_vehicle' then
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
        TriggerClientEvent('cm-law:client:removeFromVehicle', targetSrc, vehicleNetId)
        setEscorted(targetSrc, src)
        logActivity(actor.organizationId, actorCid, 'suspect_removed_from_vehicle', { targetCid = targetCid })
        cuffNotify(src, 'Suspect removed from the vehicle.', 'success')
    end
end)

RegisterNetEvent('cm-law:server:vehicleSeatResult', function(token, clientSucceeded)
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
    for targetSrc, officerSrc in pairs(Escorted) do
        if officerSrc == src then setEscorted(targetSrc, nil) end
    end
    for token, pending in pairs(PendingVehicleSeats) do
        if pending.targetSrc == src or pending.officerSrc == src then PendingVehicleSeats[token] = nil end
    end
end)

local function restoreCustody(src)
    src = tonumber(src)
    local targetCid = src and characterIdFor(src)
    if not targetCid or Cuffed[src] then return end
    local row = MySQL.single.await([[
        SELECT organization_id, officer_cid, status FROM cm_legal_custody
        WHERE character_id = ? AND status IN ('cuffed', 'processing') LIMIT 1
    ]], { targetCid })
    if not row then return end
    local officerCid = row.officer_cid and tostring(row.officer_cid) or nil
    Cuffed[src] = { officerSrc = officerCid and sourceFor(officerCid) or nil, officerCid = officerCid,
        targetCid = tostring(targetCid), organizationId = row.organization_id }
    Player(src).state:set('cmCuffed', true, true)
    Player(src).state:set('cmEscortedBy', false, true)
    cuffNotify(src, 'Your existing custody has been restored.', 'error')
end

AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    CreateThread(function()
        while not LawIsReady() do Wait(500) end
        restoreCustody(src)
    end)
end)

CreateThread(function()
    while not LawIsReady() do Wait(500) end
    for _, playerSrc in ipairs(GetPlayers()) do restoreCustody(tonumber(playerSrc)) end
end)
