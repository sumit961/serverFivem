-- cm-police vehicle impound & tow. Unlike every other duty-tool feature
-- this session, the target here is a VEHICLE, not a player -- so this
-- can't go through cm-playerdata's player-only G-menu pipeline. Officer
-- actions are plain lib.callbacks triggered from a chat command
-- (client/impound.lua); the owner's "pay to release" side is a second,
-- unrestricted command usable by any player (this script runs for every
-- connected client regardless of Police membership, same as
-- cuffs.lua/booking.lua's client-side threads already do).
--
-- The configured kiosk also anchors the physical tow drop-off. Only a
-- server-verified tow session delivered into that zone can impound. Paying
-- to release flips cm-vehicles' location state back to
-- STORED -- cm-police never spawns anything back itself, it only ever
-- flips a DB flag cm-vehicles already understands.

-- Same distance + identity verification cm-vehicles' own (un-exported)
-- ResolveAndValidateVehicle does internally, rebuilt here from only the
-- public primitives available cross-resource: a live network id, the
-- cmPlate/cmVehicleId state bags cm-vehicles' own spawn code already sets
-- on every vehicle it manages, and the exported GetVehicleByPlate.
local KioskLocations = {} -- unlimited admin-configured operator/drop-off locations
local ReleaseLocks = {} -- [vehicleId] = source; prevents duplicate concurrent payment/release attempts
local TowSessions = {} -- [source] = { towNetId, targetNetId }; server-verified physical delivery

local function lawImpoundLocations()
    local rows = {}
    if GetResourceState('cm-law') ~= 'started' then return rows end
    for _, orgId in ipairs({ 'sahp', 'sheriff', 'fib', 'army' }) do
        local ok, location = pcall(function() return exports['cm-law']:GetFacilityLocation(orgId, 'impound') end)
        if ok and type(location) == 'table' then rows[#rows + 1] = location end
    end
    return rows
end

local function allImpoundLocations()
    local rows = {}
    for _, location in ipairs(KioskLocations) do rows[#rows + 1] = location end
    for _, location in ipairs(lawImpoundLocations()) do rows[#rows + 1] = location end
    return rows
end

local function enforcementLog(src, actorCid, action, detail)
    local ok, context = pcall(function() return exports['cm-law']:AuthorizeEnforcement(src, 'impound', 'law.impound') end)
    if ok and type(context) == 'table' then
        pcall(function() exports['cm-law']:LogEnforcementAction(context, action, detail or {}) end)
    else log(actorCid, action, detail or {}) end
end

local function captureImpoundPhoto(src, vehicleId, targetNetId, plate, actorCid, organizationId, message)
    if GetResourceState('screenshot-basic') ~= 'started' then
        return false, 'Vehicle photo service is unavailable. Start screenshot-basic and try again.'
    end
    local filename = ('impound_%s_%d_%06d.jpg'):format(tostring(vehicleId), os.time(), math.random(0, 999999))
    local relativePath = 'html/img/bodycam/' .. filename
    local absolutePath = ('%s/%s'):format(GetResourcePath(GetCurrentResourceName()), relativePath)
    local result, resolved = promise.new(), false
    local function finish(ok)
        if resolved then return end
        resolved = true
        result:resolve(ok)
    end
    local called = pcall(function()
        exports['screenshot-basic']:requestClientScreenshot(src, {
            fileName = absolutePath, encoding = 'jpg', quality = 0.88,
        }, function(err) finish(err == nil or err == false) end)
    end)
    if not called then return false, 'Vehicle photo could not be requested.' end
    SetTimeout(15000, function() finish(false) end)
    if not Citizen.Await(result) then return false, 'Vehicle photo timed out. Try again.' end
    local imageUrl = 'img/bodycam/' .. filename
    local evidenceId
    if vehicleId then
        evidenceId = MySQL.insert.await([[INSERT INTO cm_police_impound_evidence
            (vehicle_id, target_net_id, organization_id, plate, officer_cid, image_url, message) VALUES (?, ?, ?, ?, ?, ?, ?)]],
            { vehicleId, targetNetId, organizationId or 'police', plate, actorCid, imageUrl, message })
    else
        evidenceId = MySQL.insert.await([[INSERT INTO cm_police_impound_evidence
            (vehicle_id, target_net_id, organization_id, plate, officer_cid, image_url, message) VALUES (NULL, ?, ?, ?, ?, ?, ?)]],
            { targetNetId, organizationId or 'police', plate, actorCid, imageUrl, message })
    end
    if not evidenceId then return false, 'The photo was taken but its MDT record could not be saved.' end
    enforcementLog(src, actorCid, 'vehicle_impound_evidence_captured', { vehicleId = vehicleId, plate = plate, evidenceId = evidenceId })
    return true, 'Vehicle image and impound report saved. You may now attach it to the tow truck.'
end

function GetImpoundKioskStatus()
    return { set = #KioskLocations > 0, count = #KioskLocations }
end

-- Called from server/main.lua's action dispatcher (the 'set_impound_kiosk'
-- case) -- same anti-spoof shape as set_meeting's own "stand here" action,
-- but also broadcast live to every connected client, not just read back
-- through the F7 dashboard: unlike an officer-only setting, this location
-- matters to every player.
function SetImpoundKioskLocation(src, actor, payload)
    if not has(actor, 'police.manage_impound') then return false, 'Your rank cannot configure Impound Operators.' end
    local x, y, z = tonumber(payload.x), tonumber(payload.y), tonumber(payload.z)
    local heading = tonumber(payload.heading) or 0.0
    if not x or not y or not z or math.abs(x) > 10000.0 or math.abs(y) > 10000.0 or math.abs(z) > 2500.0 then
        return false, 'Invalid Impound Operator location.'
    end
    local ped = GetPlayerPed(src)
    if ped and ped > 0 then
        local serverCoords = GetEntityCoords(ped)
        if serverCoords and #(serverCoords - vector3(x, y, z)) > 25.0 then return false, 'Impound kiosk location mismatch.' end
    end
    KioskLocations[#KioskLocations + 1] = { x = x, y = y, z = z, heading = heading, bucket = GetPlayerRoutingBucket(src) }
    local actorCid = cid(src)
    MySQL.insert.await([[INSERT INTO cm_police_settings (setting_key, setting_value, updated_by) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by)]],
        { 'impound_kiosks', json.encode(KioskLocations), actorCid })
    log(actorCid, 'impound_operator_added', { x = x, y = y, z = z, heading = heading, count = #KioskLocations })
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent('cm-police:client:impoundKioskUpdated', tonumber(playerId), KioskLocations)
    end
    return true, ('Impound Operator %d added.'):format(#KioskLocations)
end

function ResetImpoundKioskLocations(src, actor)
    if not has(actor, 'police.manage_impound') then return false, 'Your rank cannot configure impound operators.' end
    KioskLocations = {}
    MySQL.insert.await([[INSERT INTO cm_police_settings (setting_key, setting_value, updated_by) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value), updated_by=VALUES(updated_by)]],
        { 'impound_kiosks', '[]', cid(src) })
    TriggerClientEvent('cm-police:client:impoundKioskUpdated', -1, KioskLocations)
    log(cid(src), 'impound_operators_reset', {})
    return true, 'All Impound Operators removed.'
end

local function nearKiosk(ped)
    local coords, bucket = GetEntityCoords(ped), GetEntityRoutingBucket(ped)
    for _, location in ipairs(allImpoundLocations()) do
        if bucket == (tonumber(location.bucket) or 0)
            and #(coords - vector3(location.x, location.y, location.z)) <= (Config.Impound.KioskRadius or 2.5) then return true end
    end
    return false
end

local function nearDropoff(entity, organizationId)
    local coords, bucket = GetEntityCoords(entity), GetEntityRoutingBucket(entity)
    for _, location in ipairs(allImpoundLocations()) do
        if not organizationId or not location.organizationId or location.organizationId == organizationId then
        if bucket == (tonumber(location.bucket) or 0)
            and #(coords - vector3(location.x, location.y, location.z)) <= (Config.Impound.DropoffRadius or 18.0) then return true end
        end
    end
    return false
end

-- Any player, no permission gate -- purely public info, same spirit as the
-- release flow itself (usable by any citizen, not just Police).
lib.callback.register('cm-police:server:impoundKioskLocation', function(src)
    return allImpoundLocations()
end)

local function resolveNearbyVehicle(src, netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return nil, nil, 'Vehicle could not be identified.' end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil, nil, 'That vehicle no longer exists.' end
    local officerPed = GetPlayerPed(src)
    if not officerPed or officerPed == 0 then return nil, nil, 'Officer not found.' end
    if GetEntityRoutingBucket(officerPed) ~= GetEntityRoutingBucket(veh) then
        return nil, nil, 'That vehicle is in another routing instance.'
    end
    if #(GetEntityCoords(officerPed) - GetEntityCoords(veh)) > (Config.Impound.MaxDistance or 8.0) then
        return nil, nil, 'You are too far from the vehicle.'
    end
    local plate
    pcall(function() plate = tostring(Entity(veh).state.cmPlate or ''):gsub('%s+$', '') end)
    if not plate or plate == '' then return veh, nil, nil end
    local row = exports[Config.VehiclesResource]:GetVehicleByPlate(plate)
    if not row then return veh, nil, nil end
    local stateVehicleId
    pcall(function() stateVehicleId = tonumber(Entity(veh).state.cmVehicleId) end)
    if stateVehicleId and tonumber(row.id) ~= stateVehicleId then return veh, nil, nil end
    return veh, row, nil
end

local function towAuthority(src)
    local actorCid = cid(src)
    local actor = actorCid and memberFor(actorCid)
    if actor and not dbBoolean(actor.is_suspended) and dbBoolean(actor.on_duty) and has(actor, 'police.impound') then
        if type(PoliceCapabilityEnabled)=='function' and not PoliceCapabilityEnabled('impound') then return nil,nil,'Police impound is disabled.' end
        if isFtoRestricted(actor) then return nil, nil, 'Cadets must be signed off before towing vehicles.' end
        return actorCid, actor, nil, 'police'
    end
    local ok, context, failure = pcall(function() return exports['cm-law']:AuthorizeEnforcement(src, 'impound', 'law.impound') end)
    if ok and type(context) == 'table' then return context.characterId, context.member, nil, context.organizationId end
    return nil, nil, failure or 'You must be an on-duty legal officer with impound permission.'
end

lib.callback.register('cm-police:server:captureImpoundEvidence', function(src, netId, requestedPlate, message)
    if TowSessions[src] then return false, 'The evidence file is locked because towing has already begun.' end
    if not rateLimit(src, 'police_impound_evidence', 2500) then return false, 'Please wait before taking another photo.' end
    local actorCid, _, failure, organizationId = towAuthority(src)
    if not actorCid then return false, failure end
    message = tostring(message or ''):gsub('[%c]', ' '):gsub('%s+', ' '):sub(1, 500)
    if #message < 5 then return false, 'Write an impound reason of at least 5 characters.' end
    local vehicle, row, resolveFailure = resolveNearbyVehicle(src, netId)
    if resolveFailure then return false, resolveFailure end
    if not vehicle then return false, 'No nearby vehicle was found.' end
    local plate = tostring((row and row.plate) or ''):gsub('%s+', ''):upper()
    if plate == '' then
        pcall(function() plate = tostring(Entity(vehicle).state.cmPlate or ''):gsub('%s+', ''):upper() end)
    end
    local submittedPlate = tostring(requestedPlate or ''):gsub('%s+', ''):upper()
    if plate == '' then plate = submittedPlate end
    if plate == '' then plate = ('NET%d'):format(tonumber(netId) or 0) end
    if submittedPlate ~= '' and plate ~= submittedPlate then
        return false, 'The photographed vehicle does not match the MDT plate record.'
    end
    local ok, result = captureImpoundPhoto(src, row and tonumber(row.id) or nil, tonumber(netId), plate, actorCid, organizationId, message)
    return ok, result
end)

lib.callback.register('cm-police:server:beginTow', function(src, towNetId, targetNetId)
    if not rateLimit(src, 'police_begin_tow', 800) then return false, 'Please wait.' end
    local actorCid, _, failure, organizationId = towAuthority(src)
    if not actorCid then return false, failure end
    local towTruck = NetworkGetEntityFromNetworkId(tonumber(towNetId) or 0)
    local target = NetworkGetEntityFromNetworkId(tonumber(targetNetId) or 0)
    local ped = GetPlayerPed(src)
    if towTruck == 0 or target == 0 or towTruck == target or not DoesEntityExist(towTruck) or not DoesEntityExist(target) then
        return false, 'Tow truck or target vehicle is unavailable.'
    end
    local allowed = false
    for _, name in ipairs(Config.Impound.TowModels or {}) do if GetEntityModel(towTruck) == GetHashKey(name) then allowed = true break end end
    local fleet = Entity(towTruck).state.cmPoliceFleet or Entity(towTruck).state.cmLegalFleet
    local fleetModel = type(fleet) == 'table' and tostring(fleet.model or ''):lower() or ''
    if not allowed and fleetModel:find('tow', 1, true) and GetEntityModel(towTruck) == GetHashKey(fleetModel) then allowed = true end
    if GetVehiclePedIsIn(ped, false) ~= towTruck then return false, 'You are not inside the submitted tow truck.' end
    if GetPedInVehicleSeat(towTruck, -1) ~= ped then return false, 'You must be in the tow truck driver seat.' end
    if not allowed then return false, 'That Police fleet model is not configured as a tow truck.' end
    if GetEntityRoutingBucket(towTruck) ~= GetEntityRoutingBucket(target)
        or #(GetEntityCoords(towTruck) - GetEntityCoords(target)) > (Config.Impound.TowAttachDistance or 10.0) then
        return false, 'The target vehicle is too far away or in another routing instance.'
    end
    local _, targetRow, targetFailure = resolveNearbyVehicle(src, targetNetId)
    if targetFailure then return false, targetFailure end
    if targetRow and tonumber(targetRow.id) then
        local evidence = MySQL.single.await([[SELECT id FROM cm_police_impound_evidence
            WHERE vehicle_id = ? AND officer_cid = ? AND organization_id = ? AND used_at IS NULL
              AND captured_at >= DATE_SUB(NOW(), INTERVAL 30 MINUTE)
            ORDER BY id DESC LIMIT 1]], { targetRow.id, actorCid, organizationId or 'police' })
        if not evidence then
            return false, 'Use the MDT Vehicle Registry to photograph this vehicle and write an impound report before lifting it.'
        end
        TowSessions[src] = { towNetId = tonumber(towNetId), targetNetId = tonumber(targetNetId), organizationId = organizationId,
            vehicleId = tonumber(targetRow.id), evidenceId = tonumber(evidence.id), started = os.time() }
        MySQL.update.await('UPDATE cm_police_impound_evidence SET locked_at = COALESCE(locked_at, NOW()) WHERE id = ? AND used_at IS NULL', { evidence.id })
    else
        local plate = ''
        pcall(function() plate = tostring(Entity(target).state.cmPlate or ''):gsub('%s+', ''):upper() end)
        local evidence = MySQL.single.await([[SELECT id FROM cm_police_impound_evidence
            WHERE target_net_id = ? AND officer_cid = ? AND organization_id = ? AND used_at IS NULL
              AND captured_at >= DATE_SUB(NOW(), INTERVAL 30 MINUTE)
            ORDER BY id DESC LIMIT 1]], { targetNetId, actorCid, organizationId or 'police' })
        if not evidence then
            return false, 'Use the MDT to photograph this vehicle and write an impound report before lifting it.'
        end
        TowSessions[src] = { towNetId = tonumber(towNetId), targetNetId = tonumber(targetNetId), organizationId = organizationId,
            evidenceId = tonumber(evidence.id), started = os.time() }
        MySQL.update.await('UPDATE cm_police_impound_evidence SET locked_at = COALESCE(locked_at, NOW()) WHERE id = ? AND used_at IS NULL', { evidence.id })
    end
    enforcementLog(src, actorCid, 'vehicle_tow_started', { organizationId = organizationId })
    return true, 'Tow authorized.'
end)

lib.callback.register('cm-police:server:impoundVehicle', function(src, netId)
    if not rateLimit(src, 'police_impound', 1000) then return false, 'Please wait.' end
    local actorCid, _, authorityFailure, organizationId = towAuthority(src)
    if not actorCid then return false, authorityFailure end
    local session = TowSessions[src]
    if not session or session.targetNetId ~= tonumber(netId) then return false, 'Tow this vehicle with a Police tow truck first.' end
    local veh, row, err = resolveNearbyVehicle(src, netId)
    if err then return false, err end
    local towTruck = NetworkGetEntityFromNetworkId(session.towNetId or 0)
    if #allImpoundLocations() == 0 or towTruck == 0 or not DoesEntityExist(towTruck)
        or not nearDropoff(veh, organizationId) or not nearDropoff(towTruck, organizationId) then
        return false, 'Deliver both the tow truck and vehicle to the configured impound drop-off.'
    end

    if not row then
        -- Untracked/ambient vehicle -- the "tow" half of this feature: just
        -- clear it, no fee, no database record.
        pcall(function() DeleteEntity(veh) end)
        if session.evidenceId then
            MySQL.update.await('UPDATE cm_police_impound_evidence SET used_at = NOW() WHERE id = ? AND officer_cid = ? AND used_at IS NULL',
                { session.evidenceId, actorCid })
        end
        TowSessions[src] = nil
        enforcementLog(src, actorCid, 'vehicle_towed', { organizationId = organizationId })
        return true, 'Untracked vehicle towed.', {
            plate = 'UNREGISTERED', fee = 0, officerName = nameFor(actorCid),
            reason = 'Untracked vehicle removed from the roadway.',
        }
    end

    if tostring(row.location_state or '') == 'IMPOUND' then
        return false, 'That vehicle is already impounded.'
    end

    -- Resolve the authoritative ID again before mutation. GetVehicleByPlate
    -- can return a synthetic row for temporary/admin vehicles, while a real
    -- player-owned vehicle must also exist by persistent vehicle_id.
    local authoritative = exports[Config.VehiclesResource]:GetVehicleById(row.id)
    if not authoritative then
        return false, 'That vehicle has no persistent ownership record and cannot be impounded.'
    end

    local called, ok, transitionReason = pcall(function()
        return exports[Config.VehiclesResource]:TransitionVehicleLocation(row.id, 'IMPOUND', {
            reason = 'legal_impound', actorCharacterId = actorCid,
        })
    end)
    if not called then
        print(('[cm-police] impound transition export failed for vehicle_id %s: %s'):format(tostring(row.id), tostring(ok)))
        return false, 'Vehicle services rejected the impound operation. Check the server console.'
    end
    if not ok then
        local reasons = {
            resource_not_authorized = 'cm-police is not authorized by cm-vehicles. Restart cm-vehicles, then cm-police.',
            vehicle_not_found = 'The owned vehicle record disappeared during impound. Try retrieving it again.',
            invalid_transition = 'The vehicle has an invalid location state and needs administrator reconciliation.',
        }
        local safeReason = tostring(transitionReason or 'unknown')
        print(('[cm-police] impound transition rejected vehicle_id %s: %s'):format(tostring(row.id), safeReason))
        return false, reasons[safeReason] or ('Vehicle location transition failed (%s).'):format(safeReason)
    end
    exports[Config.VehiclesResource]:DeleteSpawnedVehicle(row.id)
    local ownerCid = row.owner_character_id and tostring(row.owner_character_id) or nil
    local impoundId = MySQL.insert.await([[INSERT INTO cm_police_impounds
        (vehicle_id, organization_id, plate, owner_cid, officer_cid, fee, cinematic_status, completed_at) VALUES (?, ?, ?, ?, ?, ?, 'server_completed', NOW())]],
        { row.id, organizationId or 'police', row.plate, ownerCid, actorCid, Config.Impound.Fee })
    if session.evidenceId then
        MySQL.update.await([[UPDATE cm_police_impound_evidence SET used_at = NOW(), impound_id = ?
            WHERE id = ? AND vehicle_id = ? AND officer_cid = ? AND used_at IS NULL]],
            { impoundId, session.evidenceId, row.id, actorCid })
    end
    local evidence = session.evidenceId and MySQL.single.await(
        'SELECT image_url, message FROM cm_police_impound_evidence WHERE id = ? LIMIT 1', { session.evidenceId }) or nil
    TowSessions[src] = nil
    enforcementLog(src, actorCid, 'vehicle_impounded', { vehicleId = row.id, plate = row.plate, ownerCid = ownerCid, fee = Config.Impound.Fee, organizationId = organizationId })
    return true, ('Impounded %s. A $%d release fee applies.'):format(row.plate, Config.Impound.Fee), {
        plate = tostring(row.plate or ''), fee = tonumber(Config.Impound.Fee) or 0,
        officerName = nameFor(actorCid), imageUrl = evidence and tostring(evidence.image_url or '') or '',
        reason = evidence and tostring(evidence.message or '') or 'Police impound',
        model = tostring(row.model or 'Unknown vehicle'),
        ownerName = ownerCid and nameFor(ownerCid) or 'Unregistered owner',
        completedAt = os.date('%Y-%m-%d %H:%M:%S'),
    }
end)

AddEventHandler('playerDropped', function() TowSessions[source] = nil end)

lib.callback.register('cm-police:server:listImpoundedVehicles', function(src)
    if not PoliceDatabaseReady() then return {} end
    local characterId = cid(src)
    if not characterId then return {} end
    if #allImpoundLocations() == 0 then return {} end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not nearKiosk(ped) then return {} end
    local owned = exports[Config.VehiclesResource]:GetVehiclesByOwner(characterId) or {}
    local list = {}
    for _, row in ipairs(owned) do
        if tostring(row.location_state or '') == 'IMPOUND' then
            local impound = MySQL.single.await([[SELECT i.id, i.fee, i.impounded_at, i.officer_cid,
                    e.image_url, e.message
                FROM cm_police_impounds i
                LEFT JOIN cm_police_impound_evidence e ON e.impound_id = i.id
                WHERE i.vehicle_id = ? AND i.released_at IS NULL
                ORDER BY i.id DESC, e.id DESC LIMIT 1]], { row.id })
            if impound then
                list[#list + 1] = {
                    vehicleId = tonumber(row.id), plate = row.plate,
                    model = tostring(row.model or ''), fee = tonumber(impound.fee) or Config.Impound.Fee,
                    imageUrl = tostring(impound.image_url or ''),
                    reason = tostring(impound.message or 'No officer report was attached.'),
                    officerName = impound.officer_cid and nameFor(tostring(impound.officer_cid)) or 'Police Department',
                    impoundedAt = tostring(impound.impounded_at or ''),
                }
            end
        end
    end
    return list
end)

lib.callback.register('cm-police:server:payImpound', function(src, vehicleId)
    if not PoliceDatabaseReady() then return false, 'Police services are still starting. Try again shortly.' end
    if not rateLimit(src, 'police_pay_impound', 1000) then return false, 'Please wait.' end
    vehicleId = tonumber(vehicleId)
    local characterId = cid(src)
    if not vehicleId or not characterId then return false, 'Invalid request.' end
    if #allImpoundLocations() == 0 then return false, 'No Impound Operator has been configured.' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not nearKiosk(ped) then return false, 'You must be at the impound release kiosk to do this.' end
    if ReleaseLocks[vehicleId] then return false, 'That vehicle release is already being processed.' end
    ReleaseLocks[vehicleId] = src

    local function finish(ok, message)
        ReleaseLocks[vehicleId] = nil
        return ok, message
    end

    local row = exports[Config.VehiclesResource]:GetVehicleById(vehicleId)
    if not row or tostring(row.owner_character_id) ~= tostring(characterId) then return finish(false, 'You do not own that vehicle.') end
    if tostring(row.location_state or '') ~= 'IMPOUND' then return finish(false, 'That vehicle is not impounded.') end
    local impound = MySQL.single.await('SELECT id, fee FROM cm_police_impounds WHERE vehicle_id = ? AND released_at IS NULL ORDER BY id DESC LIMIT 1', { vehicleId })
    if not impound then return finish(false, 'No impound record was found for that vehicle. Contact an admin.') end
    local fee = tonumber(impound.fee) or Config.Impound.Fee
    local operationId = BeginPoliceOperation('impound_release', characterId, vehicleId, fee, { impoundId = impound.id })
    if not operationId then return finish(false, 'Could not start the release operation.') end

    local removed = exports[Config.PlayerDataResource]:RemoveMoney(src, 'bank', fee, 'vehicle_impound_release', { vehicleId = vehicleId })
    if not removed then
        FinishPoliceOperation(operationId, 'refunded', { reason = 'insufficient_funds', moneyRemoved = false })
        return finish(false, 'You do not have enough money in your bank account to pay this fee.')
    end

    -- Unlike the impound side (which already checks this at line 63-64
    -- above), this return value used to be discarded -- a player could pay
    -- the fee, have the vehicle-location transition silently fail (e.g.
    -- cm-vehicles rejects it, the row is locked/mid-mutation elsewhere),
    -- and still be told it was released while it stayed stuck in IMPOUND
    -- with no refund path. Refund and bail instead.
    local ok = exports[Config.VehiclesResource]:TransitionVehicleLocation(vehicleId, 'STORED', { reason = 'impound_paid', actorCharacterId = characterId })
    if not ok then
        local refunded = false
        pcall(function() refunded = exports[Config.PlayerDataResource]:AddMoney(src, 'bank', fee, 'vehicle_impound_release_refund', { vehicleId = vehicleId }) == true end)
        FinishPoliceOperation(operationId, refunded and 'refunded' or 'reconciliation_required', { reason = 'vehicle_transition_failed', refund = refunded })
        return finish(false, refunded and 'Could not release that vehicle. Your fee has been refunded.' or 'Release failed and requires administrator reconciliation.')
    end
    local detail = json.encode({ targetCid = characterId, plate = row.plate, fee = fee })
    local called, committed = pcall(function()
        return MySQL.transaction.await({
            { query = 'UPDATE cm_police_impounds SET released_at = NOW(), released_by = ? WHERE id = ? AND released_at IS NULL', values = { characterId, impound.id } },
            { query = 'UPDATE cm_police_organization SET fund_balance = fund_balance + ? WHERE id = 1', values = { fee } },
            { query = 'INSERT INTO cm_police_activity (actor_cid, action, detail) VALUES (?, ?, ?)', values = { false, 'vehicle_released_from_impound', detail } },
        })
    end)
    if not called or committed ~= true then
        local reverted = exports[Config.VehiclesResource]:TransitionVehicleLocation(vehicleId, 'IMPOUND', { reason = 'impound_release_rollback', actorCharacterId = characterId }) == true
        local refunded = exports[Config.PlayerDataResource]:AddMoney(src, 'bank', fee, 'vehicle_impound_release_refund', { vehicleId = vehicleId }) == true
        if not reverted or not refunded then
            FinishPoliceOperation(operationId, 'reconciliation_required', { reason = 'database_commit_failed', vehicleReverted = reverted, refund = refunded })
            print(('[cm-police] CRITICAL: impound release reconciliation failed for vehicle_id %s (vehicleReverted=%s refund=%s)'):format(vehicleId, tostring(reverted), tostring(refunded)))
            return finish(false, 'Release failed and requires administrator reconciliation.')
        end
        FinishPoliceOperation(operationId, 'refunded', { reason = 'database_commit_failed', vehicleReverted = true, refund = true })
        return finish(false, 'Release failed safely; the vehicle remains impounded and your fee was refunded.')
    end
    FinishPoliceOperation(operationId, 'completed', { impoundId = impound.id, vehicleReleased = true })
    return finish(true, ('%s has been released. It is now available from your normal garage.'):format(row.plate))
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_impounds (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        vehicle_id BIGINT UNSIGNED NOT NULL,
        organization_id VARCHAR(32) NOT NULL DEFAULT 'police',
        plate VARCHAR(12) NOT NULL,
        owner_cid VARCHAR(64) NULL,
        officer_cid VARCHAR(64) NULL,
        fee BIGINT NOT NULL,
        impounded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        released_at TIMESTAMP NULL,
        released_by VARCHAR(64) NULL,
        cinematic_status VARCHAR(32) NULL,
        completed_at TIMESTAMP NULL,
        PRIMARY KEY (id),
        KEY idx_cm_police_impound_vehicle (vehicle_id),
        KEY idx_cm_police_impound_owner (owner_cid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_impound_evidence (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        vehicle_id BIGINT UNSIGNED NULL,
        target_net_id INT UNSIGNED NULL,
        organization_id VARCHAR(32) NOT NULL DEFAULT 'police',
        plate VARCHAR(12) NOT NULL,
        officer_cid VARCHAR(64) NOT NULL,
        image_url VARCHAR(300) NOT NULL,
        message VARCHAR(500) NOT NULL,
        captured_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        used_at TIMESTAMP NULL,
        impound_id BIGINT UNSIGNED NULL,
        locked_at TIMESTAMP NULL,
        PRIMARY KEY (id),
        KEY idx_cm_police_impound_evidence_vehicle (vehicle_id, captured_at),
        KEY idx_cm_police_impound_evidence_entity (target_net_id, officer_cid, used_at, captured_at),
        KEY idx_cm_police_impound_evidence_ready (vehicle_id, officer_cid, used_at, captured_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_impound_evidence MODIFY COLUMN vehicle_id BIGINT UNSIGNED NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_impound_evidence ADD COLUMN target_net_id INT UNSIGNED NULL AFTER vehicle_id') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_impound_evidence ADD COLUMN locked_at TIMESTAMP NULL') end)
    pcall(function() MySQL.query.await("ALTER TABLE cm_police_impound_evidence ADD COLUMN organization_id VARCHAR(32) NOT NULL DEFAULT 'police' AFTER target_net_id") end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_impounds ADD COLUMN cinematic_status VARCHAR(32) NULL') end)
    pcall(function() MySQL.query.await("ALTER TABLE cm_police_impounds ADD COLUMN organization_id VARCHAR(32) NOT NULL DEFAULT 'police' AFTER vehicle_id") end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_impounds ADD COLUMN completed_at TIMESTAMP NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cm_police_impound_evidence ADD KEY idx_cm_police_impound_evidence_entity (target_net_id, officer_cid, used_at, captured_at)') end)
    -- Same generic key/value table server/booking.lua's own CreateThread
    -- already creates -- IF NOT EXISTS makes running it from both files safe
    -- regardless of which one's CreateThread actually finishes first.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_settings (
        setting_key VARCHAR(64) NOT NULL,
        setting_value LONGTEXT NOT NULL,
        updated_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (setting_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    local rows = MySQL.query.await("SELECT setting_key, setting_value FROM cm_police_settings WHERE setting_key IN ('impound_kiosks','impound_kiosk')") or {}
    local legacy
    for _, row in ipairs(rows) do
        local decoded = decode(row.setting_value)
        if row.setting_key == 'impound_kiosks' and type(decoded) == 'table' then KioskLocations = decoded
        elseif row.setting_key == 'impound_kiosk' and type(decoded) == 'table' and tonumber(decoded.x) then legacy = decoded end
    end
    if #KioskLocations == 0 and legacy then
        KioskLocations = { legacy }
        MySQL.insert.await([[INSERT INTO cm_police_settings (setting_key, setting_value, updated_by) VALUES ('impound_kiosks', ?, NULL)
            ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value)]], { json.encode(KioskLocations) })
    end
    PoliceSchemaMarkReady('impound')
end)
