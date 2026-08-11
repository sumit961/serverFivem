-- cm-law fleet vehicles. Mirrors cm-police/server/vehicles.lua's persistent,
-- garage-quality fleet system closely (recall/spawn one shared instance per
-- model, fully serviced/repaired on recall, "Recall All" for managers) --
-- generalized to whichever org the calling member actually belongs to,
-- instead of one hardcoded organization, since cm-law covers all four.
--
-- Appearance (model, label, category, image, paint/livery/wheels/etc) is
-- configured in rn-vehicleshop's /vehicleadmin (an organization's own
-- catalog status, e.g. "SAHP fleet vehicle") and read here live via its
-- generic GetOrgCatalog(organizationId) export -- cm-law never stores its
-- own copy, so re-customizing a vehicle there takes effect on the next
-- spawn with no separate sync step.
--
-- cm-law only owns what's org-specific: where each vehicle spawns, whether
-- it's a car or helicopter (auto-detected, not admin-picked), the minimum
-- rank tier required to spawn/drive it, and whether it's enabled.
--
-- Reuses (never duplicates), same pattern as cm-police/cm-ems:
--   rn-vehicleshop  GetOrgCatalog(organizationId) -- the org-tagged catalog.
--   cm-vehicles     SpawnAdminVehicle/DeleteAdminVehicle -- for the
--                   throwaway location-setting dummy only.
--   cm-vehicles     CreateOwnedVehicle/EnsureOrganizationOwnership/
--                   GetVehicleById/RecallWorldVehicle/CreateGarageVehicle/
--                   PromoteHouseGarageVehicle/TransitionVehicleLocation/
--                   ServiceVehicle/GetSpawnedVehicleInfo/
--                   GetSpawnedVehicleCondition/DeleteSpawnedVehicle -- the
--                   actual persistent vehicle lifecycle. cm-vehicles trusts
--                   organization = 'sahp'/'sheriff'/'fib'/'army' only when
--                   the invoking resource is 'cm-law' (server/main.lua's
--                   TRUSTED_ORGANIZATIONS table) -- added alongside
--                   'police'/'ems' rather than duplicated per org.

local VEHICLES_RESOURCE = 'cm-vehicles'
local SHOP_RESOURCE = 'rn-vehicleshop'

local FleetPlacementBySource = {} -- [src] = { model, kind, plate, netId, entity, organizationId }
local FleetLocationBusy = {} -- [orgId .. ':' .. model] = true
local FleetAssignments = {} -- [orgId .. ':' .. model] = { characterId, name }
local vehicleHasOccupant

-- A character is only ever an active member of one organization, so every
-- fleet action derives its org from the caller instead of trusting a
-- client-supplied orgId.
local function actorFor(src)
    local member, characterId = activeMemberForSource(src)
    if not member then return nil, characterId, 'You are not a member of a legal organization.' end
    return member, characterId, nil
end

-- Spawning a car exactly at the manager's own coordinates places it inside
-- their collision capsule, which is unreliable and can leave CreateVehicle's
-- entity stuck mid-registration. Reused verbatim from cm-police/cm-ems so
-- all three resources agree on what "clear" means.
local function offsetSpawnCoords(x, y, z, heading, kind)
    if kind == 'helicopter' then
        return x, y, z + 1.0
    end
    local rad = math.rad(heading)
    return x - math.sin(rad) * 3.5, y + math.cos(rad) * 3.5, z + 0.25
end

local function getOrgCatalog(orgId)
    local ok, rows = pcall(function() return exports[SHOP_RESOURCE]:GetOrgCatalog(orgId) end)
    return (ok and type(rows) == 'table') and rows or {}
end

local function findCatalogRow(catalog, model)
    model = tostring(model or ''):lower()
    for _, row in ipairs(catalog) do
        if tostring(row.model):lower() == model then return row end
    end
    return nil
end

local function fleetSettingsByModel(orgId)
    local rows = MySQL.query.await('SELECT * FROM cm_legal_fleet_vehicles WHERE organization_id = ?', { orgId }) or {}
    local byModel = {}
    for _, row in ipairs(rows) do byModel[tostring(row.model):lower()] = row end
    return byModel
end

exports('GetVehicleAccessDecision', function(characterId, vehicleId, action)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'not_legal_fleet_vehicle' end
    local settings = MySQL.single.await([[SELECT organization_id, min_tier FROM cm_legal_fleet_vehicles
        WHERE vehicle_id = ? AND enabled = 1 LIMIT 1]], { vehicleId })
    if not settings then return false, 'not_legal_fleet_vehicle' end
    local orgId = validOrgId(settings.organization_id)
    local member = orgId and memberFor(tostring(characterId or ''), orgId) or nil
    if not member then return false, 'not_organization_member' end
    action = tostring(action or 'vehicle.drive')
    if action == 'vehicle.sell' or action == 'vehicle.delete' or action == 'vehicle.keys.manage'
        or action == 'vehicle.family.share' then return false, 'legal_fleet_protected' end
    if member.suspended or member.onDuty ~= true then return false, 'organization_not_on_duty' end
    local required = tonumber(settings.min_tier) or 0
    if not member.isLeader and (tonumber(member.tier) or 0) < required then return false, 'organization_rank_too_low' end
    return true, 'legal_fleet', { organization = orgId, vehicleId = vehicleId, requiredTier = required }
end)

local function mergedRow(catalogRow, settingsRow)
    local orgId = settingsRow and tostring(settingsRow.organization_id or '') or ''
    local key = orgId .. ':' .. tostring(catalogRow.model):lower()
    local merged = {
        model = catalogRow.model,
        label = catalogRow.label,
        category = catalogRow.category,
        minTier = settingsRow and math.floor(tonumber(settingsRow.min_tier) or 0) or 0,
        enabled = settingsRow and dbBoolean(settingsRow.enabled) or false,
        configured = settingsRow ~= nil and settingsRow.vehicle_id ~= nil,
        assignedOfficer = FleetAssignments[key] and FleetAssignments[key].name or nil,
    }
    local vehicleId = settingsRow and tonumber(settingsRow.vehicle_id)
    local active, info = false, nil
    if vehicleId then active, info = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId) end
    local entity = active == true and type(info) == 'table' and tonumber(info.entity) or 0
    if entity ~= 0 and DoesEntityExist(entity) then
        merged.status = vehicleHasOccupant and vehicleHasOccupant(entity) and 'occupied' or 'deployed'
        merged.engineHealth = math.floor(math.max(0, GetVehicleEngineHealth(entity)))
        merged.bodyHealth = math.floor(math.max(0, GetVehicleBodyHealth(entity)))
        merged.fuel = math.floor(math.max(0, GetVehicleFuelLevel(entity)))
        local coords = GetEntityCoords(entity)
        merged.location = { x = math.floor(coords.x), y = math.floor(coords.y), z = math.floor(coords.z) }
    else
        merged.status = merged.configured and 'available' or 'not_configured'
    end
    return merged
end

lib.callback.register('cm-law:server:fleetCatalog', function(src)
    local actor = select(1, actorFor(src))
    if not actor then return nil end
    local manage = actor.isLeader or actor.permissions['law.fleet'] == true
    local spawn = actor.isLeader or actor.permissions['law.vehicle'] == true
    if not manage and not spawn then return {} end

    local catalog = getOrgCatalog(actor.organizationId)
    local settings = fleetSettingsByModel(actor.organizationId)
    local tier = math.floor(tonumber(actor.tier) or 0)

    local out = {}
    for _, catalogRow in ipairs(catalog) do
        local settingsRow = settings[tostring(catalogRow.model):lower()]
        local merged = mergedRow(catalogRow, settingsRow)
        if manage then
            out[#out + 1] = merged
        elseif merged.configured and merged.enabled and (actor.isLeader or tier >= merged.minTier) then
            out[#out + 1] = merged
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

-- Rank gate only -- never touches location/kind. Bound to the inline number
-- input in the NUI, separate from the H-key location save below.
lib.callback.register('cm-law:server:setFleetVehicleMinTier', function(src, model, minTier)
    local actor, actorCid = actorFor(src)
    if not actor or not (actor.isLeader or actor.permissions['law.fleet'] == true) then
        return false, 'Your rank cannot manage this organization\'s fleet.'
    end
    model = tostring(model or ''):lower()
    if model == '' then return false, 'Invalid model.' end
    minTier = math.max(0, math.min(100, math.floor(tonumber(minTier) or 0)))
    local changed = MySQL.update.await('UPDATE cm_legal_fleet_vehicles SET min_tier = ? WHERE organization_id = ? AND model = ?', { minTier, actor.organizationId, model })
    if not tonumber(changed) or tonumber(changed) <= 0 then
        return false, 'Set this vehicle\'s location first (Set location, then drive it and press H).'
    end
    logActivity(actor.organizationId, actorCid, 'fleet_vehicle_min_tier_set', { model = model, minTier = minTier })
    return true
end)

lib.callback.register('cm-law:server:beginFleetLocationEdit', function(src, model)
    local actor, _, err = actorFor(src)
    if not actor or not (actor.isLeader or actor.permissions['law.fleet'] == true) then
        return false, err or 'Your rank cannot manage this organization\'s fleet.'
    end
    if not rateLimit(src, 'law_fleet_edit', 1500) then return false, 'Please wait.' end
    model = tostring(model or ''):lower()
    local catalogRow = findCatalogRow(getOrgCatalog(actor.organizationId), model)
    if not catalogRow then return false, 'That vehicle is not tagged for this organization in /vehicleadmin.' end
    local previous = FleetPlacementBySource[src]
    if previous then pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(previous.plate) end) end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Character is not loaded.' end
    local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local okClass, classId = pcall(GetVehicleClassFromName, GetHashKey(model))
    local kind = okClass and classId == 15 and 'helicopter' or 'car'
    local x, y, z = offsetSpawnCoords(coords.x, coords.y, coords.z, heading, kind)
    local result = exports[VEHICLES_RESOURCE]:SpawnAdminVehicle(src, model, { x = x, y = y, z = z, h = heading }, {
        label = ('Fleet location dummy: %s'):format(catalogRow.label), placementKind = kind, engineOn = true,
    })
    if type(result) ~= 'table' or result.ok ~= true then return false, tostring(result and result.error or 'Could not create the location dummy.') end
    FleetPlacementBySource[src] = { model = model, kind = kind, plate = result.plate, netId = result.netId, entity = result.entity, organizationId = actor.organizationId }
    if result.entity and DoesEntityExist(result.entity) then Entity(result.entity).state:set('cmLegalFleet', { model = model, organizationId = actor.organizationId, placement = true }, true) end
    return true, { netId = result.netId, model = model, message = 'Drive the dummy to the vehicle location and press H to save.' }
end)

-- Location save/update: the player must be DRIVING the exact dummy being
-- saved, so the location that gets stored is always where the car genuinely
-- is right now (triggered by the H keybind, never by the NUI, and
-- coordinates always come from the server's own view of the vehicle).
lib.callback.register('cm-law:server:saveFleetVehicleLocation', function(src, model, kind)
    local actor, actorCid, err = actorFor(src)
    if not actor or not (actor.isLeader or actor.permissions['law.fleet'] == true) then
        return false, err or 'Your rank cannot manage this organization\'s fleet.'
    end
    if not rateLimit(src, 'law_fleet_save', 2000) then return false, 'Please wait.' end

    model = tostring(model or ''):lower()
    local catalogRow = findCatalogRow(getOrgCatalog(actor.organizationId), model)
    if not catalogRow then return false, 'That vehicle is not tagged for this organization in /vehicleadmin.' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Character is not loaded.' end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false, 'Get in the fleet vehicle first.' end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return false, 'Only the driver can save this vehicle\'s location.' end
    if GetHashKey(catalogRow.model) ~= GetEntityModel(vehicle) then return false, 'You are not driving that vehicle.' end
    local placement = FleetPlacementBySource[src]
    if not placement or placement.model ~= model or placement.organizationId ~= actor.organizationId or tonumber(placement.entity) ~= tonumber(vehicle) then
        return false, 'This is not your active fleet location dummy.'
    end

    local coords = GetEntityCoords(vehicle)
    local heading = GetEntityHeading(vehicle)
    kind = kind == 'helicopter' and 'helicopter' or 'car'

    local settings = MySQL.single.await('SELECT * FROM cm_legal_fleet_vehicles WHERE organization_id = ? AND model = ? LIMIT 1', { actor.organizationId, model })
    local vehicleId = settings and tonumber(settings.vehicle_id) or nil
    local heldLocationLock = false
    local lockKey = actor.organizationId .. ':' .. model
    if not vehicleId then
        if FleetLocationBusy[lockKey] then return false, 'Another manager is saving this vehicle location.' end
        FleetLocationBusy[lockKey] = true
        heldLocationLock = true
        settings = MySQL.single.await('SELECT vehicle_id FROM cm_legal_fleet_vehicles WHERE organization_id = ? AND model = ? LIMIT 1', { actor.organizationId, model })
        vehicleId = settings and tonumber(settings.vehicle_id) or nil
        if not vehicleId then
            local org = Config.Organizations[actor.organizationId]
            local called, created, permanent = pcall(function()
                return exports[VEHICLES_RESOURCE]:CreateOwnedVehicle(src, model, catalogRow.label, 1, {
                    ownerClass = actor.organizationId, organization = actor.organizationId,
                    ownerName = org.shortLabel, catalogMods = catalogRow.mods,
                })
            end)
            if not called or created ~= true or type(permanent) ~= 'table' or not tonumber(permanent.id) then
                FleetLocationBusy[lockKey] = nil
                return false, tostring(permanent or 'Could not create the persistent fleet vehicle.')
            end
            vehicleId = tonumber(permanent.id)
        end
    end
    if exports[VEHICLES_RESOURCE]:EnsureOrganizationOwnership(vehicleId, actor.organizationId) ~= true then
        if heldLocationLock then FleetLocationBusy[lockKey] = nil end
        return false, 'Could not assign the persistent vehicle to this organization.'
    end
    MySQL.insert.await([[
        INSERT INTO cm_legal_fleet_vehicles (organization_id, model, vehicle_id, kind, min_tier, enabled, spawn_x, spawn_y, spawn_z, spawn_h, updated_by)
        VALUES (?, ?, ?, ?, 0, 1, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            vehicle_id = VALUES(vehicle_id), kind = VALUES(kind),
            spawn_x = VALUES(spawn_x), spawn_y = VALUES(spawn_y), spawn_z = VALUES(spawn_z), spawn_h = VALUES(spawn_h),
            updated_by = VALUES(updated_by)
    ]], { actor.organizationId, model, vehicleId, kind, coords.x, coords.y, coords.z, heading, actorCid })
    if heldLocationLock then FleetLocationBusy[lockKey] = nil end

    exports[VEHICLES_RESOURCE]:TransitionVehicleLocation(vehicleId, 'JOB_GARAGE', { ref = 'law', reason = 'law_dummy_location_saved', actorCharacterId = actorCid })
    FleetPlacementBySource[src] = nil
    pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end)
    logActivity(actor.organizationId, actorCid, 'fleet_vehicle_location_saved', { model = model, label = catalogRow.label, kind = kind, vehicleId = vehicleId })
    return true, ('%s location saved for permanent vehicle #%d. The dummy was removed.'):format(catalogRow.label, vehicleId)
end)

local fleetOperationBusy = {} -- [orgId] = true

local function persistentFleetRow(orgId, model)
    return MySQL.single.await('SELECT * FROM cm_legal_fleet_vehicles WHERE organization_id = ? AND model = ? LIMIT 1', { orgId, tostring(model):lower() })
end

vehicleHasOccupant = function(entity)
    entity = tonumber(entity) or 0
    if entity == 0 or not DoesEntityExist(entity) then return false end
    local seats = 0
    pcall(function() seats = tonumber(GetVehicleMaxNumberOfPassengers(entity)) or 0 end)
    for seat = -1, seats - 1 do
        local ped = 0
        pcall(function() ped = GetPedInVehicleSeat(entity, seat) end)
        if ped and ped ~= 0 then return true end
    end
    return false
end

-- The recall/create/service mechanics themselves (no rank/tier gating -- that
-- is the caller's job). Used both by player-initiated spawn/recall callbacks
-- and by the unattended startup auto-respawn below, which has no "actor" to
-- check a rank against.
local function recallFleetVehicleCore(src, actorCid, orgId, model, settings, repair)
    local vehicleId = tonumber(settings.vehicle_id)
    if exports[VEHICLES_RESOURCE]:EnsureOrganizationOwnership(vehicleId, orgId) ~= true then
        return false, 'The vehicle could not be assigned to this organization.'
    end
    local servicePatch = {
        fuel = 100, engineHealth = 1000, bodyHealth = 1000,
        tankHealth = 1000, dirtLevel = 0,
        conditionState = {}, clearVisualDamage = true,
    }
    local row = exports[VEHICLES_RESOURCE]:GetVehicleById(vehicleId)
    if not row then return false, 'The persistent fleet vehicle record is missing. Use recovery before recreating it.' end
    local spawn = { x = tonumber(settings.spawn_x), y = tonumber(settings.spawn_y), z = tonumber(settings.spawn_z), h = tonumber(settings.spawn_h) or 0 }
    local active, activeInfo = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId)

    -- Recover vehicles left quarantined by an earlier ad-hoc path. House
    -- garages do the same thing when their registered display entity is
    -- unusable: remove only the physical copy, retain the database vehicle
    -- ID, and rebuild it through the client-assisted garage creator below.
    if active == true then
        local gotCondition, condition = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleCondition(vehicleId, row)
        if gotCondition == true and type(condition) == 'table' and condition.conditionReady ~= true then
            if vehicleHasOccupant(activeInfo and activeInfo.entity) then
                return false, 'That fleet vehicle is occupied and cannot be recovered yet.'
            end
            local deleted, deleteWhy = exports[VEHICLES_RESOURCE]:DeleteSpawnedVehicle(vehicleId)
            if deleted ~= true then return false, tostring(deleteWhy or 'The protected fleet vehicle could not be cleared.') end
            active, activeInfo = false, nil
        end
    end

    if active ~= true then
        -- The house-style creator reads its bootstrap condition from this row,
        -- so persist and reload the clean baseline before creating it.
        if exports[VEHICLES_RESOURCE]:ServiceVehicle(row.plate, servicePatch, src) ~= true then
            return false, 'The fleet vehicle could not be serviced before recall.'
        end
        row = exports[VEHICLES_RESOURCE]:GetVehicleById(vehicleId) or row
        row.fuel = 100
        row.engine_health, row.body_health, row.tank_health = 1000, 1000, 1000
        row.dirt_level, row.condition_state, row.conditionState = 0, {}, {}
    end

    local ok, result
    if active == true then
        -- Preserve the same live entity and network identity, matching a house
        -- garage recall when its vehicle is already active.
        ok, result = exports[VEHICLES_RESOURCE]:RecallWorldVehicle(vehicleId, src, spawn)
    else
        -- Match cm-house for a missing persistent entity: let the requesting
        -- client create and verify the network vehicle, then promote that SAME
        -- registered entity from its protected garage bootstrap into the world.
        local created, createResult = exports[VEHICLES_RESOURCE]:CreateGarageVehicle(src, row, spawn, {
            bucket = GetPlayerRoutingBucket(src),
        })
        if created == true and type(createResult) == 'table' then
            ok, result = exports[VEHICLES_RESOURCE]:PromoteHouseGarageVehicle(vehicleId, src, spawn)
            if ok ~= true then exports[VEHICLES_RESOURCE]:DeleteSpawnedVehicle(vehicleId) end
        else
            ok, result = false, createResult
        end
    end
    if ok ~= true then return false, tostring(result or 'The fleet vehicle could not be recalled.') end
    -- Broadcast (no targetSrc) rather than aiming only at the recalling
    -- member: the vehicle's saved spawn point is very often far from
    -- wherever they opened the fleet menu, so only that one client may never
    -- have it streamed in to physically apply the repair. Any currently-nearby
    -- client can pick this up instead; cm-vehicles also retries this patch
    -- for whoever streams the entity in later (cmPendingServicePatch).
    if exports[VEHICLES_RESOURCE]:ServiceVehicle(row.plate, servicePatch, nil) ~= true then
        return false, 'The fleet vehicle could not finish its service.'
    end
    exports[VEHICLES_RESOURCE]:TransitionVehicleLocation(vehicleId, 'JOB_GARAGE', { ref = 'law', reason = repair and 'law_recall_all' or 'law_vehicle_call', actorCharacterId = actorCid })
    local _, info = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId)
    if type(info) == 'table' and tonumber(info.entity) and DoesEntityExist(tonumber(info.entity)) then
        local entity = tonumber(info.entity)
        local state = Entity(entity).state
        state:set('cmLegalFleet', { model = model, organizationId = orgId, vehicleId = vehicleId, minTier = tonumber(settings.min_tier) or 0, ready = false }, true)
        local deadline = GetGameTimer() + 15000
        while DoesEntityExist(entity) and state.cmConditionReady ~= true and GetGameTimer() < deadline do Wait(200) end
        if not DoesEntityExist(entity) or state.cmConditionReady ~= true then
            return false, 'The fleet vehicle was recalled but its repaired condition did not finish loading.'
        end
        state:set('cmLegalFleet', { model = model, organizationId = orgId, vehicleId = vehicleId, minTier = tonumber(settings.min_tier) or 0, ready = true }, true)
    end
    local catalogRow = findCatalogRow(getOrgCatalog(orgId), model)
    if type(info) == 'table' and catalogRow then TriggerClientEvent('cm-law:client:applyFleetMods', src, info.netId, catalogRow.mods) end
    return true, ('%s recalled (vehicle #%d).'):format(row.label or model, vehicleId)
end

local function spawnPersistent(src, actor, actorCid, model, repair)
    local settings = persistentFleetRow(actor.organizationId, model)
    if not settings or not tonumber(settings.vehicle_id) then return false, 'Set this vehicle\'s location first.' end
    if not dbBoolean(settings.enabled) then return false, 'That fleet vehicle is disabled.' end
    if not actor.isLeader and (tonumber(actor.tier) or 0) < (tonumber(settings.min_tier) or 0) then return false, 'Your rank cannot use this vehicle.' end
    local ok, message = recallFleetVehicleCore(src, actorCid, actor.organizationId, model, settings, repair)
    local key = actor.organizationId .. ':' .. model
    if ok and actorCid and not repair then FleetAssignments[key] = { characterId = tostring(actorCid), name = nameFor(actorCid) } end
    if ok and repair then FleetAssignments[key] = nil end
    return ok, message
end

AddEventHandler('cm-law:server:memberWentOffDuty', function(src, characterId, orgId)
    src, characterId, orgId = tonumber(src), tostring(characterId or ''), tostring(orgId or '')
    if not src or not GetPlayerName(src) then src = tonumber((GetPlayers() or {})[1]) end
    for key, assignment in pairs(FleetAssignments) do
        if assignment.characterId == characterId and key:sub(1, #orgId + 1) == orgId .. ':' then
            local model = key:sub(#orgId + 2)
            local settings = persistentFleetRow(orgId, model)
            if src and GetPlayerName(src) and settings then recallFleetVehicleCore(src, characterId, orgId, model, settings, true) end
            FleetAssignments[key] = nil
        end
    end
end)

lib.callback.register('cm-law:server:spawnFleetVehicle', function(src, model)
    return false, 'Individual vehicle recall is disabled. Collect vehicles from organization parking or use Recall All.'
end)

lib.callback.register('cm-law:server:recallAllFleetVehicles', function(src)
    local actor, actorCid, err = actorFor(src)
    if not actor or not (actor.isLeader or actor.permissions['law.fleet'] == true) then
        return false, err or 'Your rank cannot recall this organization\'s fleet.'
    end
    local orgId = actor.organizationId
    if fleetOperationBusy[orgId] then return false, 'Another fleet recall is already running.' end
    fleetOperationBusy[orgId] = true
    local rows = MySQL.query.await('SELECT model FROM cm_legal_fleet_vehicles WHERE organization_id = ? AND enabled = 1 AND vehicle_id IS NOT NULL ORDER BY model', { orgId }) or {}
    local recalled, failed = 0, 0
    for _, row in ipairs(rows) do
        local settings = persistentFleetRow(orgId, row.model)
        local ok = settings and recallFleetVehicleCore(src, actorCid, orgId, row.model, settings, true)
        if ok then recalled = recalled + 1 else failed = failed + 1 end
        Wait(0)
    end
    fleetOperationBusy[orgId] = nil
    logActivity(orgId, actorCid, 'fleet_recalled_all', { recalled = recalled, failed = failed })
    return failed == 0, ('Recalled %d fleet vehicles clean, fully repaired and refuelled; %d failed safely.'):format(recalled, failed)
end)

AddEventHandler('playerDropped', function()
    local placement = FleetPlacementBySource[source]
    FleetPlacementBySource[source] = nil
    if placement then pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end) end
end)

-- ── Auto-respawn on server (re)start ─────────────────────────────────────
-- A resource restart wipes cm-vehicles' in-memory spawn registry, so every
-- configured fleet vehicle looks "not active" again even though its
-- persistent vehicle_id record is untouched. Rather than leaving every
-- org's fleet empty until a manager remembers to open the menu and click
-- Recall, bring it all back automatically the moment there is a real
-- connected player whose client can do the client-assisted creation. Runs
-- once per resource lifetime, across all four organizations in one pass;
-- not gated by rank/tier/on-duty since nobody is "requesting" this, the
-- server is just restoring its own fleet.
local fleetAutoRespawnStarted = false

local function autoRespawnFleet(triggerSrc)
    if fleetAutoRespawnStarted then return end
    triggerSrc = tonumber(triggerSrc)
    if not triggerSrc or triggerSrc <= 0 or not GetPlayerName(triggerSrc) then return end
    fleetAutoRespawnStarted = true

    CreateThread(function()
        local rows = MySQL.query.await('SELECT organization_id, model FROM cm_legal_fleet_vehicles WHERE enabled = 1 AND vehicle_id IS NOT NULL ORDER BY organization_id, model') or {}
        local respawned, skipped = 0, 0
        for _, row in ipairs(rows) do
            if not fleetOperationBusy[row.organization_id] then
                local settings = persistentFleetRow(row.organization_id, row.model)
                local vehicleId = settings and tonumber(settings.vehicle_id)
                local alreadyActive = vehicleId and exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId)
                if settings and not alreadyActive then
                    local ok = recallFleetVehicleCore(triggerSrc, nil, row.organization_id, row.model, settings, true)
                    if ok then respawned = respawned + 1 else skipped = skipped + 1 end
                end
            end
            Wait(0)
        end
        if respawned > 0 or skipped > 0 then
            print(('[cm-law] fleet auto-respawn: %d respawned, %d skipped'):format(respawned, skipped))
        end
    end)
end

AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    autoRespawnFleet(src)
end)
