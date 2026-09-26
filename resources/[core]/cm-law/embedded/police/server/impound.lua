-- Shared Law vehicle impound and tow authority. The existing Police resource
-- contracts and callbacks remain as compatibility wrappers, while J-menu
-- actions call the shared client functions directly. Public release remains
-- available to any owner, independent of Law membership or capability state.
--
-- The configured kiosk also anchors the physical tow drop-off. Only a
-- server-verified tow session delivered into that zone can impound. Paying
-- to release flips cm-vehicles' location state back to
-- STORED -- cm-police never spawns anything back itself, it only ever
-- flips a DB flag cm-vehicles already understands.

-- Network IDs identify the current transport entity only. Persistent vehicle
-- identity and active world registration are checked through cm-vehicles.
local KioskLocations = {} -- unlimited admin-configured operator/drop-off locations
local ReleaseLocks = {} -- [vehicleId] = source; prevents duplicate concurrent payment/release attempts
local TowSessions = {} -- [source] = actor/org + persistent tow/target IDs and transient net IDs
local ImpoundLocks = {} -- [vehicleId] = source; serializes location and ledger mutation
local TowSessionTtl = 1200

local function clearTowSession(src)
    local session = TowSessions[src]
    TowSessions[src] = nil
    if session and session.vehicleId and ImpoundLocks[session.vehicleId] == src then
        ImpoundLocks[session.vehicleId] = nil
    end
    if session and session.evidenceId then
        pcall(function()
            MySQL.update.await('UPDATE cm_police_impound_evidence SET locked_at = NULL WHERE id = ? AND used_at IS NULL', { session.evidenceId })
        end)
    end
end

local function rowOccupied(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return true end
    for seat = -1, (GetVehicleMaxNumberOfPassengers(vehicle) or 0) - 1 do
        local occupant = GetPedInVehicleSeat(vehicle, seat)
        if occupant and occupant ~= 0 then return true end
    end
    return false
end

local function findVehicleEntity(vehicleId)
    for _, entity in ipairs(GetAllVehicles()) do
        if DoesEntityExist(entity) then
            local stateId
            pcall(function() stateId = tonumber(Entity(entity).state.cmVehicleId) end)
            if stateId == tonumber(vehicleId) then return entity end
        end
    end
end

local function lawImpoundLocations()
    local rows = {}
    if GetResourceState('cm-law') ~= 'started' then return rows end
    for orgId in pairs(Config.Organizations or {}) do
        local ok, location = pcall(function() return exports['cm-law']:GetFacilityLocation(orgId, 'impound') end)
        if ok and type(location) == 'table' then rows[#rows + 1] = location end
    end
    return rows
end

local function allImpoundLocations()
    local rows, seen = {}, {}
    for _, sourceRows in ipairs({ KioskLocations, lawImpoundLocations() }) do
        for _, location in ipairs(sourceRows) do
            local key = ('%s:%.2f:%.2f:%.2f'):format(tostring(location.organizationId or 'police'),
                tonumber(location.x) or 0, tonumber(location.y) or 0, tonumber(location.z) or 0)
            if not seen[key] then seen[key] = true; rows[#rows + 1] = location end
        end
    end
    return rows
end

local function enforcementLog(actorCid, organizationId, action, detail)
    local context = { characterId = tostring(actorCid), organizationId = tostring(organizationId) }
    pcall(function() exports['cm-law']:LogEnforcementAction(context, action, detail or {}) end)
end

local function captureImpoundPhoto(src, vehicleId, targetNetId, plate, actorCid, organizationId, message)
    if GetResourceState('screenshot-basic') ~= 'started' then
        return false, 'Vehicle documentation service is unavailable.'
    end
    local filename = ('impound_%s_%d_%06d.jpg'):format(tostring(vehicleId), os.time(), math.random(0, 999999))
    local relativePath = 'html/police/img/bodycam/' .. filename
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
    enforcementLog(actorCid, organizationId, 'vehicle_impound_evidence_captured', { vehicleId = vehicleId, plate = plate, evidenceId = evidenceId })
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
    KioskLocations[#KioskLocations + 1] = { x = x, y = y, z = z, heading = heading, bucket = GetPlayerRoutingBucket(src), organizationId = 'police', policeOperator = true }
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
        if location.organizationId == nil and KioskLocations then location.organizationId = 'police' end
        if bucket == (tonumber(location.bucket) or 0)
            and #(coords - vector3(location.x, location.y, location.z)) <= (PoliceConfig.Impound.KioskRadius or 2.5) then return true end
    end
    return false
end

local function nearDropoff(entity, organizationId)
    local coords, bucket = GetEntityCoords(entity), GetEntityRoutingBucket(entity)
    for _, location in ipairs(allImpoundLocations()) do
        if organizationId and tostring(location.organizationId or '') == tostring(organizationId)
            and bucket == (tonumber(location.bucket) or 0)
            and #(coords - vector3(location.x, location.y, location.z)) <= (PoliceConfig.Impound.DropoffRadius or 18.0) then return true end
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
    if #(GetEntityCoords(officerPed) - GetEntityCoords(veh)) > (PoliceConfig.Impound.MaxDistance or 8.0) then
        return nil, nil, 'You are too far from the vehicle.'
    end
    if GetEntityType(veh) ~= 2 then return nil, nil, 'Select a valid vehicle.' end
    local stateVehicleId
    pcall(function() stateVehicleId = tonumber(Entity(veh).state.cmVehicleId) end)
    if not stateVehicleId or stateVehicleId <= 0 then return nil, nil, 'This vehicle has no persistent ownership record.' end
    local row = exports[PoliceConfig.VehiclesResource]:GetVehicleById(stateVehicleId)
    if not row or tonumber(row.id) ~= stateVehicleId then return nil, nil, 'This vehicle has no persistent ownership record.' end
    local spawnedOk, spawned = pcall(function() return exports[PoliceConfig.VehiclesResource]:GetSpawnedVehicleInfo(stateVehicleId) end)
    if not spawnedOk or type(spawned) ~= 'table' or tonumber(spawned.entity) ~= veh then
        return nil, nil, 'Vehicle identity could not be verified.'
    end
    local fleet = Entity(veh).state.cmPoliceFleet or Entity(veh).state.cmLegalFleet or Entity(veh).state.cmEmsFleet
    if fleet or tostring(row.owner_type or ''):lower() == 'organization' then
        return nil, nil, 'Organization fleet vehicles cannot be impounded through this service.'
    end
    if tostring(row.location_state or '') == 'IMPOUND' then return nil, nil, 'This vehicle is already impounded.' end
    return veh, row, nil
end

local function towAuthority(src)
    local ok, context, failure = pcall(function() return exports['cm-law']:AuthorizeEnforcement(src, 'impound', 'law.impound') end)
    if ok and type(context) == 'table' then return context.characterId, context.member, nil, context.organizationId end
    return nil, nil, failure or 'You must be an on-duty legal officer with impound permission.'
end

lib.callback.register('cm-police:server:captureImpoundEvidence', function(src, netId, requestedPlate, message)
    if TowSessions[src] then return false, 'The evidence file is locked because towing has already begun.' end
    if not PoliceLegacyRateLimit(src, 'police_impound_evidence', 2500) then return false, 'Please wait before taking another photo.' end
    local actorCid, _, failure, organizationId = towAuthority(src)
    if not actorCid then return false, failure end
    message = tostring(message or ''):gsub('[%c]', ' '):gsub('%s+', ' '):sub(1, 500)
    if #message < 5 then return false, 'Write an impound reason of at least 5 characters.' end
    local vehicle, row, resolveFailure = resolveNearbyVehicle(src, netId)
    if resolveFailure then return false, resolveFailure end
    if not vehicle or not row or not tonumber(row.id) then return false, 'This vehicle has no persistent ownership record.' end
    local plate = tostring((row and row.plate) or ''):gsub('%s+', ''):upper()
    if plate == '' then
        pcall(function() plate = tostring(Entity(vehicle).state.cmPlate or ''):gsub('%s+', ''):upper() end)
    end
    local submittedPlate = tostring(requestedPlate or ''):gsub('%s+', ''):upper()
    if plate == '' then return false, 'Vehicle identity could not be verified.' end
    if submittedPlate ~= '' and plate ~= submittedPlate then
        return false, 'The photographed vehicle does not match the MDT plate record.'
    end
    local ok, result = captureImpoundPhoto(src, row and tonumber(row.id) or nil, tonumber(netId), plate, actorCid, organizationId, message)
    return ok, result
end)

lib.callback.register('cm-police:server:beginTow', function(src, towNetId, targetNetId)
    if not PoliceLegacyRateLimit(src, 'police_begin_tow', 800) then return false, 'Please wait.' end
    local actorCid, _, failure, organizationId = towAuthority(src)
    if not actorCid then return false, failure end
    if TowSessions[src] then return false, 'You already have an active tow session.' end
    local towTruck = NetworkGetEntityFromNetworkId(tonumber(towNetId) or 0)
    local target = NetworkGetEntityFromNetworkId(tonumber(targetNetId) or 0)
    local ped = GetPlayerPed(src)
    if towTruck == 0 or target == 0 or towTruck == target or not DoesEntityExist(towTruck) or not DoesEntityExist(target) then
        return false, 'Tow truck or target vehicle is unavailable.'
    end
    local allowed = false
    for _, name in ipairs(PoliceConfig.Impound.TowModels or {}) do if GetEntityModel(towTruck) == GetHashKey(name) then allowed = true break end end
    local fleet = Entity(towTruck).state.cmPoliceFleet or Entity(towTruck).state.cmLegalFleet
    local fleetModel = type(fleet) == 'table' and tostring(fleet.model or ''):lower() or ''
    if not allowed and fleetModel:find('tow', 1, true) and GetEntityModel(towTruck) == GetHashKey(fleetModel) then allowed = true end
    if GetVehiclePedIsIn(ped, false) ~= towTruck then return false, 'You are not inside the submitted tow truck.' end
    if GetPedInVehicleSeat(towTruck, -1) ~= ped then return false, 'You must be in the tow truck driver seat.' end
    if not allowed or type(fleet) ~= 'table' then return false, 'That vehicle is not an authorized organization tow truck.' end
    local towVehicleId = tonumber(fleet.vehicleId or fleet.vehicle_id or Entity(towTruck).state.cmVehicleId)
    local towRow = towVehicleId and exports[PoliceConfig.VehiclesResource]:GetVehicleById(towVehicleId)
    local fleetOrg = tostring(fleet.organizationId or fleet.organization_id or '')
    if not towRow or tonumber(Entity(towTruck).state.cmVehicleId) ~= towVehicleId
        or tostring(towRow.owner_type or ''):lower() ~= 'organization'
        or tostring(towRow.owner_id or towRow.organization_id or ''):lower() ~= tostring(organizationId):lower()
        or (fleetOrg ~= '' and fleetOrg:lower() ~= tostring(organizationId):lower()) then
        return false, 'You do not have access to this tow vehicle.'
    end
    local spawnedOk, spawned = pcall(function() return exports[PoliceConfig.VehiclesResource]:GetSpawnedVehicleInfo(towVehicleId) end)
    if not spawnedOk or type(spawned) ~= 'table' or tonumber(spawned.entity) ~= towTruck then
        return false, 'Tow vehicle identity could not be verified.'
    end
    local accessOk, hasAccess = pcall(function() return exports[PoliceConfig.VehiclesResource]:CanUseVehicle(src, towVehicleId, 'vehicle.drive') end)
    if not accessOk or hasAccess ~= true then return false, 'You do not have access to this tow vehicle.' end
    if GetEntityRoutingBucket(towTruck) ~= GetEntityRoutingBucket(target)
        or #(GetEntityCoords(towTruck) - GetEntityCoords(target)) > (PoliceConfig.Impound.TowAttachDistance or 10.0) then
        return false, 'The target vehicle is too far away or in another routing instance.'
    end
    local _, targetRow, targetFailure = resolveNearbyVehicle(src, targetNetId)
    if targetFailure then return false, targetFailure end
    if targetRow and tonumber(targetRow.id) then
        if rowOccupied(target) then return false, 'Vehicle must be empty before it can be towed.' end
        if ImpoundLocks[tonumber(targetRow.id)] then return false, 'That vehicle is already being impounded.' end
        ImpoundLocks[tonumber(targetRow.id)] = src
        local activeOk, active = pcall(function()
            return MySQL.scalar.await('SELECT id FROM cm_police_impounds WHERE vehicle_id = ? AND released_at IS NULL LIMIT 1', { targetRow.id })
        end)
        if not activeOk then ImpoundLocks[tonumber(targetRow.id)] = nil; return false, 'Impound services are unavailable. Try again.' end
        if active then ImpoundLocks[tonumber(targetRow.id)] = nil; return false, 'This vehicle is already impounded.' end
        local evidenceOk, evidence = pcall(function() return MySQL.single.await([[SELECT id FROM cm_police_impound_evidence
            WHERE vehicle_id = ? AND officer_cid = ? AND organization_id = ? AND used_at IS NULL AND locked_at IS NULL
              AND captured_at >= DATE_SUB(NOW(), INTERVAL 30 MINUTE)
            ORDER BY id DESC LIMIT 1]], { targetRow.id, actorCid, organizationId or 'police' }) end)
        if not evidenceOk then ImpoundLocks[tonumber(targetRow.id)] = nil; return false, 'Impound services are unavailable. Try again.' end
        if not evidence then
            ImpoundLocks[tonumber(targetRow.id)] = nil
            return false, 'Use the MDT Vehicle Registry to photograph this vehicle and write an impound report before lifting it.'
        end
        local latestCid, _, _, latestOrg = towAuthority(src)
        if not GetPlayerName(src) or latestCid ~= actorCid or latestOrg ~= organizationId
            or ImpoundLocks[tonumber(targetRow.id)] ~= src then
            ImpoundLocks[tonumber(targetRow.id)] = nil
            return false, 'Tow authorization ended. Try again.'
        end
        TowSessions[src] = { actorCid = actorCid, organizationId = organizationId, towVehicleId = towVehicleId,
            towEntity = towTruck, targetEntity = target, towNetId = tonumber(towNetId), targetNetId = tonumber(targetNetId), vehicleId = tonumber(targetRow.id),
            evidenceId = tonumber(evidence.id), started = os.time() }
        local lockOk, locked = pcall(function()
            return MySQL.update.await('UPDATE cm_police_impound_evidence SET locked_at = NOW() WHERE id = ? AND used_at IS NULL AND locked_at IS NULL', { evidence.id })
        end)
        if not lockOk or tonumber(locked) ~= 1 then clearTowSession(src); return false, 'Impound evidence is already in use. Take a new photo.' end
        if TowSessions[src] == nil then
            pcall(function() MySQL.update.await('UPDATE cm_police_impound_evidence SET locked_at = NULL WHERE id = ? AND used_at IS NULL', { evidence.id }) end)
            return false, 'Tow authorization ended. Try again.'
        end
    else return false, 'This vehicle has no persistent ownership record.' end
    enforcementLog(actorCid, organizationId, 'vehicle_tow_started', { organizationId = organizationId })
    return true, 'Tow authorized.'
end)

lib.callback.register('cm-police:server:impoundVehicle', function(src, netId)
    if not PoliceLegacyRateLimit(src, 'police_impound', 1000) then return false, 'Please wait.' end
    local actorCid, _, authorityFailure, organizationId = towAuthority(src)
    if not actorCid then return false, authorityFailure end
    local session = TowSessions[src]
    if not session or session.actorCid ~= actorCid or session.organizationId ~= organizationId
        or os.time() - session.started > TowSessionTtl then clearTowSession(src); return false, 'Tow authorization expired. Attach the vehicle again.' end
    local veh, row, err = resolveNearbyVehicle(src, netId)
    if err then return false, err end
    local towTruck = NetworkGetEntityFromNetworkId(session.towNetId or 0)
    if towTruck == 0 or not DoesEntityExist(towTruck)
        or tonumber(Entity(towTruck).state.cmVehicleId) ~= session.towVehicleId then
        towTruck = findVehicleEntity(session.towVehicleId)
        if towTruck and towTruck ~= 0 then session.towNetId = NetworkGetNetworkIdFromEntity(towTruck) end
    end
    if not row or tonumber(row.id) ~= session.vehicleId or tonumber(Entity(veh).state.cmVehicleId) ~= session.vehicleId
        or towTruck == 0 or not DoesEntityExist(towTruck)
        or tonumber(Entity(towTruck).state.cmVehicleId) ~= session.towVehicleId
        or GetVehiclePedIsIn(GetPlayerPed(src), false) ~= towTruck
        or GetPedInVehicleSeat(towTruck, -1) ~= GetPlayerPed(src)
        or #allImpoundLocations() == 0 or not nearDropoff(veh, organizationId) or not nearDropoff(towTruck, organizationId) then
        return false, 'Deliver both the tow truck and vehicle to the configured impound drop-off.'
    end
    local towOk, towInfo = pcall(function() return exports[PoliceConfig.VehiclesResource]:GetSpawnedVehicleInfo(session.towVehicleId) end)
    local targetOk, targetInfo = pcall(function() return exports[PoliceConfig.VehiclesResource]:GetSpawnedVehicleInfo(session.vehicleId) end)
    if not towOk or type(towInfo) ~= 'table' or tonumber(towInfo.entity) ~= towTruck or towTruck ~= session.towEntity
        or not targetOk or type(targetInfo) ~= 'table' or tonumber(targetInfo.entity) ~= veh or veh ~= session.targetEntity then
        clearTowSession(src)
        return false, 'Tow authorization expired. Reattach the vehicle and try again.'
    end
    if rowOccupied(veh) then return false, 'Vehicle must be empty before it can be impounded.' end
    if ImpoundLocks[session.vehicleId] and ImpoundLocks[session.vehicleId] ~= src then return false, 'That vehicle is already being impounded.' end
    ImpoundLocks[session.vehicleId] = src
    local active = MySQL.scalar.await('SELECT id FROM cm_police_impounds WHERE vehicle_id = ? AND released_at IS NULL LIMIT 1', { session.vehicleId })
    if active then clearTowSession(src); return false, 'This vehicle is already impounded.' end
    local latestCid, _, _, latestOrg = towAuthority(src)
    if not GetPlayerName(src) or latestCid ~= actorCid or latestOrg ~= organizationId or TowSessions[src] ~= session then
        clearTowSession(src)
        return false, 'Tow authorization ended. Reattach the vehicle before continuing.'
    end

    -- Resolve the authoritative ID again before mutation. GetVehicleByPlate
    -- can return a synthetic row for temporary/admin vehicles, while a real
    -- player-owned vehicle must also exist by persistent vehicle_id.
    local authoritative = exports[PoliceConfig.VehiclesResource]:GetVehicleById(row.id)
    if not authoritative then
        clearTowSession(src)
        return false, 'That vehicle has no persistent ownership record and cannot be impounded.'
    end

    local called, ok, transitionReason = pcall(function()
        return exports[PoliceConfig.VehiclesResource]:TransitionVehicleLocation(row.id, 'IMPOUND', {
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
    exports[PoliceConfig.VehiclesResource]:DeleteSpawnedVehicle(row.id)
    local ownerCid = row.owner_character_id and tostring(row.owner_character_id) or nil
    local insertOk, impoundId = pcall(function()
        return MySQL.insert.await([[INSERT INTO cm_police_impounds
            (vehicle_id, organization_id, plate, owner_cid, officer_cid, fee, cinematic_status, completed_at) VALUES (?, ?, ?, ?, ?, ?, 'server_completed', NOW())]],
            { row.id, organizationId, row.plate, ownerCid, actorCid, PoliceConfig.Impound.Fee })
    end)
    if not insertOk or not impoundId then
        local reverted = false
        pcall(function() reverted = exports[PoliceConfig.VehiclesResource]:TransitionVehicleLocation(row.id, 'STORED', {
            reason = 'legal_impound_ledger_failed', actorCharacterId = actorCid,
        }) == true end)
        clearTowSession(src)
        if not reverted then print(('[cm-law] CRITICAL impound ledger failure could not restore vehicle_id %s'):format(tostring(row.id))) end
        return false, 'Impound could not be recorded safely. No vehicle was removed.'
    end
    if session.evidenceId then
        MySQL.update.await([[UPDATE cm_police_impound_evidence SET used_at = NOW(), impound_id = ?
            WHERE id = ? AND vehicle_id = ? AND officer_cid = ? AND used_at IS NULL]],
            { impoundId, session.evidenceId, row.id, actorCid })
    end
    local evidence = session.evidenceId and MySQL.single.await(
        'SELECT image_url, message FROM cm_police_impound_evidence WHERE id = ? LIMIT 1', { session.evidenceId }) or nil
    TowSessions[src] = nil
    ImpoundLocks[session.vehicleId] = nil
    enforcementLog(actorCid, organizationId, 'vehicle_impounded', { vehicleId = row.id, plate = row.plate, ownerCid = ownerCid, fee = PoliceConfig.Impound.Fee, organizationId = organizationId })
    return true, ('Impounded %s. A $%d release fee applies.'):format(row.plate, PoliceConfig.Impound.Fee), {
        plate = tostring(row.plate or ''), fee = tonumber(PoliceConfig.Impound.Fee) or 0,
        officerName = PoliceLegacyNameFor(actorCid), imageUrl = evidence and tostring(evidence.image_url or '') or '',
        reason = evidence and tostring(evidence.message or '') or 'Police impound',
        model = tostring(row.model or 'Unknown vehicle'),
        ownerName = ownerCid and PoliceLegacyNameFor(ownerCid) or 'Unregistered owner',
        completedAt = os.date('%Y-%m-%d %H:%M:%S'),
    }
end)

AddEventHandler('playerDropped', function() clearTowSession(source) end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() and resource ~= PoliceConfig.VehiclesResource then return end
    for src in pairs(TowSessions) do
        TriggerClientEvent('cm-law:client:impoundSessionEnded', src, 'Tow authorization ended. Reattach the vehicle before continuing.')
        clearTowSession(src)
    end
    ImpoundLocks = {}
end)

lib.callback.register('cm-police:server:cancelTow', function(src)
    local actorCid, _, failure, organizationId = towAuthority(src)
    if not actorCid then return false, failure end
    local session = TowSessions[src]
    if not session or session.actorCid ~= actorCid or session.organizationId ~= organizationId then
        return false, 'No active tow session was found.'
    end
    clearTowSession(src)
    enforcementLog(actorCid, organizationId, 'vehicle_tow_cancelled', { vehicleId = session.vehicleId, organizationId = organizationId })
    return true, 'Tow detached.'
end)

CreateThread(function()
    while true do
        Wait(5000)
        for src, session in pairs(TowSessions) do
            local actorCid, _, _, organizationId = towAuthority(src)
            local tow = NetworkGetEntityFromNetworkId(session.towNetId or 0)
            if tow == 0 or not DoesEntityExist(tow) or tonumber(Entity(tow).state.cmVehicleId) ~= session.towVehicleId then
                tow = findVehicleEntity(session.towVehicleId)
                if tow and tow ~= 0 then session.towNetId = NetworkGetNetworkIdFromEntity(tow) end
            end
            local target = NetworkGetEntityFromNetworkId(session.targetNetId or 0)
            if target == 0 or not DoesEntityExist(target) or tonumber(Entity(target).state.cmVehicleId) ~= session.vehicleId then
                target = findVehicleEntity(session.vehicleId)
                if target and target ~= 0 then session.targetNetId = NetworkGetNetworkIdFromEntity(target) end
            end
            if not actorCid or actorCid ~= session.actorCid or organizationId ~= session.organizationId
                or os.time() - session.started > TowSessionTtl
                or not tow or tow == 0 or not DoesEntityExist(tow)
                or not target or target == 0 or not DoesEntityExist(target)
                or tow ~= session.towEntity or target ~= session.targetEntity then
                clearTowSession(src)
                TriggerClientEvent('cm-law:client:impoundSessionEnded', src, 'Tow authorization ended. Reattach the vehicle before continuing.')
            end
        end
    end
end)

lib.callback.register('cm-police:server:listImpoundedVehicles', function(src)
    if not PoliceLegacyRateLimit(src, 'police_list_impounds', 500) then return {} end
    if not PoliceDatabaseReady() then return {} end
    local characterId = cid(src)
    if not characterId then return {} end
    if #allImpoundLocations() == 0 then return {} end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not nearKiosk(ped) then return {} end
    local owned = exports[PoliceConfig.VehiclesResource]:GetVehiclesByOwner(characterId) or {}
    local list = {}
    for _, row in ipairs(owned) do
        if tostring(row.location_state or '') == 'IMPOUND' then
            local impound = MySQL.single.await([[SELECT i.id, i.fee, i.organization_id, i.impounded_at, i.officer_cid,
                    e.image_url, e.message
                FROM cm_police_impounds i
                LEFT JOIN cm_police_impound_evidence e ON e.impound_id = i.id
                WHERE i.vehicle_id = ? AND i.released_at IS NULL
                ORDER BY i.id DESC, e.id DESC LIMIT 1]], { row.id })
            if impound then
                list[#list + 1] = {
                    vehicleId = tonumber(row.id), plate = row.plate,
                    model = tostring(row.model or ''), fee = tonumber(impound.fee) or PoliceConfig.Impound.Fee,
                    organizationId = tostring(impound.organization_id or 'police'),
                    organization = tostring(impound.organization_id or 'police') == 'police' and 'Police Department'
                        or ((Config.Organizations[tostring(impound.organization_id)] or {}).label or tostring(impound.organization_id)),
                    imageUrl = tostring(impound.image_url or ''),
                    reason = tostring(impound.message or 'No officer report was attached.'),
                    officerName = impound.officer_cid and PoliceLegacyNameFor(tostring(impound.officer_cid)) or 'Police Department',
                    impoundedAt = tostring(impound.impounded_at or ''),
                }
            end
        end
    end
    return list
end)

lib.callback.register('cm-police:server:payImpound', function(src, vehicleId)
    if not PoliceDatabaseReady() then return false, 'Police services are still starting. Try again shortly.' end
    if not PoliceLegacyRateLimit(src, 'police_pay_impound', 1000) then return false, 'Please wait.' end
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

    local row = exports[PoliceConfig.VehiclesResource]:GetVehicleById(vehicleId)
    if not row or tostring(row.owner_character_id) ~= tostring(characterId) then return finish(false, 'You do not own that vehicle.') end
    if tostring(row.location_state or '') ~= 'IMPOUND' then return finish(false, 'That vehicle is not impounded.') end
    local impound = MySQL.single.await('SELECT id, fee FROM cm_police_impounds WHERE vehicle_id = ? AND released_at IS NULL ORDER BY id DESC LIMIT 1', { vehicleId })
    if not impound then return finish(false, 'No impound record was found for that vehicle. Contact an admin.') end
    local fee = tonumber(impound.fee) or PoliceConfig.Impound.Fee
    local operationId = BeginPoliceOperation('impound_release', characterId, vehicleId, fee, { impoundId = impound.id })
    if not operationId then return finish(false, 'Could not start the release operation.') end

    local removed = exports[PoliceConfig.PlayerDataResource]:RemoveMoney(src, 'bank', fee, 'vehicle_impound_release', { vehicleId = vehicleId })
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
    local ok = exports[PoliceConfig.VehiclesResource]:TransitionVehicleLocation(vehicleId, 'STORED', { reason = 'impound_paid', actorCharacterId = characterId })
    if not ok then
        local refunded = false
        pcall(function() refunded = exports[PoliceConfig.PlayerDataResource]:AddMoney(src, 'bank', fee, 'vehicle_impound_release_refund', { vehicleId = vehicleId }) == true end)
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
        local reverted = exports[PoliceConfig.VehiclesResource]:TransitionVehicleLocation(vehicleId, 'IMPOUND', { reason = 'impound_release_rollback', actorCharacterId = characterId }) == true
        local refunded = exports[PoliceConfig.PlayerDataResource]:AddMoney(src, 'bank', fee, 'vehicle_impound_release_refund', { vehicleId = vehicleId }) == true
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
    -- In-memory tow sessions do not survive a resource restart, so release
    -- any evidence locks left behind by the previous cm-law execution.
    MySQL.update.await('UPDATE cm_police_impound_evidence SET locked_at = NULL WHERE used_at IS NULL AND locked_at IS NOT NULL')
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
        legacy.organizationId, legacy.policeOperator = 'police', true
        KioskLocations = { legacy }
        MySQL.insert.await([[INSERT INTO cm_police_settings (setting_key, setting_value, updated_by) VALUES ('impound_kiosks', ?, NULL)
            ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value)]], { json.encode(KioskLocations) })
    end
    for _, location in ipairs(KioskLocations) do
        if location.organizationId == nil then location.organizationId = 'police' end
        if location.organizationId == 'police' then location.policeOperator = true end
    end
    PoliceSchemaMarkReady('impound')
end)
