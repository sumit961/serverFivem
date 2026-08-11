-- cm-police fleet vehicles.
--
-- Appearance (model, label, category, image, paint/livery/wheels/etc) is
-- configured in rn-vehicleshop's /vehicleadmin ("Police fleet vehicle"
-- catalog status) and read here live via its GetPoliceCatalog export --
-- cm-police never stores its own copy, so re-customizing a vehicle there
-- takes effect on the next spawn with no separate sync step.
--
-- cm-police only owns what's Police-specific: where each vehicle spawns,
-- whether it's a car or helicopter (auto-detected, not admin-picked), the
-- minimum Police rank tier required to spawn/drive it, and whether it's
-- enabled.
--
-- Reuses (never duplicates), same pattern as cm-ems:
--   rn-vehicleshop  GetPoliceCatalog -- the Police-tagged catalog (model/image/mods).
--   cm-vehicles     SpawnAdminVehicle / DeleteAdminVehicle -- the same
--                   trusted, restart-safe spawn path cm-house uses for
--                   garage placement.
--   cm-vehicles     client ApplyVehicleMods -- the same native calls that
--                   apply cosmetic mods to any owned vehicle.

local VEHICLES_RESOURCE = 'cm-vehicles'
local SHOP_RESOURCE = 'rn-vehicleshop'

-- [model] = { plate, netId } -- the currently-live instance of each fleet
-- vehicle, if any. Spawning again deletes this first ("recall"), so there is
-- always at most one live copy of each fleet vehicle instead of duplicates
-- piling up every time someone presses Spawn.
local ActiveFleetVehicles = {}
local FleetPlacementBySource = {}
local FleetLocationBusy = {}
local FleetAssignments = {} -- [model] = { characterId, name }
local vehicleHasOccupant

local function actorFor(src)
    local characterId = cid(src)
    if not characterId then return nil, nil, 'Character is not loaded.' end
    local member = memberFor(characterId)
    if not member then
        local isAdmin = false
        pcall(function() isAdmin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end)
        if isAdmin then return { tier = 101, is_leader = 1, permissions = '{}' }, characterId, nil end
        return nil, characterId, 'You are not a Police member.'
    end
    return member, characterId, nil
end

-- Spawning a car exactly at the admin's own coordinates places it inside
-- their collision capsule, which is unreliable and can leave CreateVehicle's
-- entity stuck mid-registration ("The vehicle failed to spawn."). cm-house
-- hits the same issue for its garage/interior placement vehicles and fixes it
-- with this exact forward+up offset (server/sv_create.lua) -- reused here
-- rather than re-derived, so both resources agree on what "clear" means.
local function offsetSpawnCoords(x, y, z, heading, kind)
    if kind == 'helicopter' then
        return x, y, z + 1.0
    end
    local rad = math.rad(heading)
    return x - math.sin(rad) * 3.5, y + math.cos(rad) * 3.5, z + 0.25
end

local function getPoliceCatalog()
    local ok, rows = pcall(function() return exports[SHOP_RESOURCE]:GetPoliceCatalog() end)
    return (ok and type(rows) == 'table') and rows or {}
end

local function findCatalogRow(catalog, model)
    model = tostring(model or ''):lower()
    for _, row in ipairs(catalog) do
        if tostring(row.model):lower() == model then return row end
    end
    return nil
end

local function fleetSettingsByModel()
    local rows = MySQL.query.await('SELECT * FROM cm_police_fleet_vehicles') or {}
    local byModel = {}
    for _, row in ipairs(rows) do byModel[tostring(row.model):lower()] = row end
    return byModel
end

exports('GetVehicleAccessDecision', function(characterId, vehicleId, action)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'not_police_fleet_vehicle' end
    local settings = MySQL.single.await([[SELECT min_tier FROM cm_police_fleet_vehicles
        WHERE vehicle_id = ? AND enabled = 1 LIMIT 1]], { vehicleId })
    if not settings then return false, 'not_police_fleet_vehicle' end
    local member = characterId and memberFor(tostring(characterId)) or nil
    if not member then return false, 'not_police_member' end
    action = tostring(action or 'vehicle.drive')
    if action == 'vehicle.sell' or action == 'vehicle.delete' or action == 'vehicle.keys.manage'
        or action == 'vehicle.family.share' then return false, 'police_fleet_protected' end
    if dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) then return false, 'police_not_on_duty' end
    local required = tonumber(settings.min_tier) or 0
    if not dbBoolean(member.is_leader) and (tonumber(member.tier) or 0) < required then return false, 'police_rank_too_low' end
    return true, 'police_fleet', { organization = 'police', vehicleId = vehicleId, requiredTier = required }
end)

local function mergedRow(catalogRow, settingsRow)
    local merged = {
        model = catalogRow.model,
        label = catalogRow.label,
        category = catalogRow.category,
        image = catalogRow.image,
        minTier = settingsRow and math.floor(tonumber(settingsRow.min_tier) or 0) or 0,
        enabled = settingsRow and dbBoolean(settingsRow.enabled) or false,
        configured = settingsRow ~= nil,
        assignedOfficer = FleetAssignments[tostring(catalogRow.model):lower()] and FleetAssignments[tostring(catalogRow.model):lower()].name or nil,
    }
    local vehicleId = settingsRow and tonumber(settingsRow.vehicle_id)
    local active, info = vehicleId and exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId) or false, nil
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

local function removeActiveInstance(model)
    local previous = ActiveFleetVehicles[model]
    if not previous then return end
    ActiveFleetVehicles[model] = nil
    pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(previous.plate) end)
end

lib.callback.register('cm-police:server:fleetCatalog', function(src)
    local actor = select(1, actorFor(src))
    if not actor then return nil end
    local manage = has(actor, 'police.manage_vehicles')
    local spawn = has(actor, 'police.spawn_vehicles')
    if not manage and not spawn then return {} end

    local catalog = getPoliceCatalog()
    local settings = fleetSettingsByModel()
    local tier = math.floor(tonumber(actor.tier) or 0)
    local isLeader = dbBoolean(actor.is_leader)

    local out = {}
    for _, catalogRow in ipairs(catalog) do
        local settingsRow = settings[tostring(catalogRow.model):lower()]
        local merged = mergedRow(catalogRow, settingsRow)
        if manage then
            out[#out + 1] = merged
        elseif merged.configured and merged.enabled and (isLeader or tier >= merged.minTier) then
            out[#out + 1] = merged
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

-- Rank gate only -- never touches location/kind. Bound to the inline number
-- input in the NUI, separate from the H-key location save below.
lib.callback.register('cm-police:server:setFleetVehicleMinTier', function(src, model, minTier)
    local actor, actorCid = actorFor(src)
    if not actor or not has(actor, 'police.manage_vehicles') then return false, 'Your rank cannot manage Police vehicles.' end
    model = tostring(model or ''):lower()
    if model == '' then return false, 'Invalid model.' end
    minTier = math.max(0, math.min(100, math.floor(tonumber(minTier) or 0)))
    local changed = MySQL.update.await('UPDATE cm_police_fleet_vehicles SET min_tier = ? WHERE model = ?', { minTier, model })
    if not tonumber(changed) or tonumber(changed) <= 0 then
        return false, 'Spawn this vehicle and press H inside it first, to give it a location.'
    end
    log(actorCid, 'fleet_vehicle_min_tier_set', { model = model, minTier = minTier })
    return true
end)

lib.callback.register('cm-police:server:beginFleetLocationEdit', function(src, model)
    local actor, _, err = actorFor(src)
    if not actor or not has(actor, 'police.manage_vehicles') then return false, err or 'Your rank cannot manage Police vehicles.' end
    if not rateLimit(src, 'police_fleet_edit', 1500) then return false, 'Please wait.' end
    model = tostring(model or ''):lower()
    local catalogRow = findCatalogRow(getPoliceCatalog(), model)
    if not catalogRow then return false, 'That vehicle is not tagged as a Police vehicle.' end
    local previous = FleetPlacementBySource[src]
    if previous then pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(previous.plate) end) end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Character is not loaded.' end
    local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local okClass, classId = pcall(GetVehicleClassFromName, GetHashKey(model))
    local kind = okClass and classId == 15 and 'helicopter' or 'car'
    local x, y, z = offsetSpawnCoords(coords.x, coords.y, coords.z, heading, kind)
    local result = exports[VEHICLES_RESOURCE]:SpawnAdminVehicle(src, model, { x = x, y = y, z = z, h = heading }, {
        label = ('Police location dummy: %s'):format(catalogRow.label), placementKind = kind, engineOn = true,
    })
    if type(result) ~= 'table' or result.ok ~= true then return false, tostring(result and result.error or 'Could not create the location dummy.') end
    FleetPlacementBySource[src] = { model = model, kind = kind, plate = result.plate, netId = result.netId, entity = result.entity }
    if result.entity and DoesEntityExist(result.entity) then Entity(result.entity).state:set('cmPoliceFleet', { model = model, placement = true }, true) end
    return true, { netId = result.netId, model = model, message = 'Drive the dummy to the vehicle location and press H to save.' }
end)

-- Location save/update: the player must be DRIVING the exact Police dummy
-- being saved, so the location that gets stored is always where the car
-- genuinely is right now (triggered by the in-game H keybind, never by the
-- NUI, and coordinates always come from the server's own view of the vehicle
-- -- never trusted from the client).
lib.callback.register('cm-police:server:saveFleetVehicleLocation', function(src, model, kind)
    local actor, actorCid, err = actorFor(src)
    if not actor or not has(actor, 'police.manage_vehicles') then return false, err or 'Your rank cannot manage Police vehicles.' end
    if not rateLimit(src, 'police_fleet_save', 2000) then return false, 'Please wait.' end

    model = tostring(model or ''):lower()
    local catalogRow = findCatalogRow(getPoliceCatalog(), model)
    if not catalogRow then return false, 'That vehicle is not tagged as a Police vehicle in /vehicleadmin.' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Character is not loaded.' end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false, 'Get in the Police vehicle first.' end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return false, 'Only the driver can save this vehicle\'s location.' end
    if GetHashKey(catalogRow.model) ~= GetEntityModel(vehicle) then return false, 'You are not driving that vehicle.' end
    local placement = FleetPlacementBySource[src]
    if not placement or placement.model ~= model or tonumber(placement.entity) ~= tonumber(vehicle) then return false, 'This is not your active Police location dummy.' end

    local coords = GetEntityCoords(vehicle)
    local heading = GetEntityHeading(vehicle)
    kind = kind == 'helicopter' and 'helicopter' or 'car'

    local settings = MySQL.single.await('SELECT * FROM cm_police_fleet_vehicles WHERE model = ? LIMIT 1', { model })
    local vehicleId = settings and tonumber(settings.vehicle_id) or nil
    local heldLocationLock = false
    if not vehicleId then
        if FleetLocationBusy[model] then return false, 'Another manager is saving this vehicle location.' end
        FleetLocationBusy[model] = true
        heldLocationLock = true
        settings = MySQL.single.await('SELECT vehicle_id FROM cm_police_fleet_vehicles WHERE model = ? LIMIT 1', { model })
        vehicleId = settings and tonumber(settings.vehicle_id) or nil
        if not vehicleId then
            local called, created, permanent = pcall(function()
                return exports[VEHICLES_RESOURCE]:CreateOwnedVehicle(src, model, catalogRow.label, 1, { ownerClass = 'police', organization = 'police', ownerName = 'Police', catalogMods = catalogRow.mods })
            end)
            if not called or created ~= true or type(permanent) ~= 'table' or not tonumber(permanent.id) then FleetLocationBusy[model] = nil; return false, tostring(permanent or 'Could not create the persistent Police vehicle.') end
            vehicleId = tonumber(permanent.id)
        end
    end
    if exports[VEHICLES_RESOURCE]:EnsureOrganizationOwnership(vehicleId, 'police') ~= true then
        if heldLocationLock then FleetLocationBusy[model] = nil end
        return false, 'Could not assign the persistent vehicle to Police ownership.'
    end
    MySQL.insert.await([[
        INSERT INTO cm_police_fleet_vehicles (model, vehicle_id, kind, min_tier, enabled, spawn_x, spawn_y, spawn_z, spawn_h, updated_by)
        VALUES (?, ?, ?, 0, 1, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            vehicle_id = VALUES(vehicle_id), kind = VALUES(kind),
            spawn_x = VALUES(spawn_x), spawn_y = VALUES(spawn_y), spawn_z = VALUES(spawn_z), spawn_h = VALUES(spawn_h),
            updated_by = VALUES(updated_by)
    ]], { model, vehicleId, kind, coords.x, coords.y, coords.z, heading, actorCid })
    if heldLocationLock then FleetLocationBusy[model] = nil end

    exports[VEHICLES_RESOURCE]:TransitionVehicleLocation(vehicleId, 'JOB_GARAGE', { ref = 'police', reason = 'police_dummy_location_saved', actorCharacterId = actorCid })
    FleetPlacementBySource[src] = nil
    pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end)
    log(actorCid, 'fleet_vehicle_location_saved', { model = model, label = catalogRow.label, kind = kind, vehicleId = vehicleId })
    return true, ('%s location saved for permanent vehicle #%d. The dummy was removed.'):format(catalogRow.label, vehicleId)
end)

-- Note: an earlier `cm-police:server:spawnFleetVehicleLegacy` callback and
-- its ad-hoc SpawnAdminVehicle-based spawn path used to live here. It was
-- never called by any client file (client/vehicles.lua only ever calls
-- spawnFleetVehicle/beginFleetLocationEdit) and duplicated logic the live
-- recall/create path below already owns with better guards (e.g. the
-- FleetLocationBusy lock) -- removed rather than left as dead, divergent
-- code a future change could mistakenly call again.

local fleetOperationBusy = false

local function persistentFleetRow(model)
    return MySQL.single.await('SELECT * FROM cm_police_fleet_vehicles WHERE model = ? LIMIT 1', { tostring(model):lower() })
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

-- Note: an earlier `cm-police:server:setFleetVehicleLocation` callback used
-- to live here (a second, unguarded way to save a fleet vehicle's spawn
-- location). Never called by any client file (client/vehicles.lua only
-- calls beginFleetLocationEdit/the save flow above), and it was missing the
-- FleetLocationBusy lock the live save path above has -- removed rather
-- than left as a latent footgun.

-- The recall/create/service mechanics themselves (no rank/tier gating -- that
-- is the caller's job). Used both by player-initiated spawn/recall callbacks
-- and by the unattended startup auto-respawn below, which has no "actor" to
-- check a rank against.
local function recallFleetVehicleCore(src, actorCid, model, settings, repair)
    local vehicleId = tonumber(settings.vehicle_id)
    if exports[VEHICLES_RESOURCE]:EnsureOrganizationOwnership(vehicleId, 'police') ~= true then
        return false, 'The vehicle could not be assigned to Police ownership.'
    end
    local servicePatch = {
        fuel = 100, engineHealth = 1000, bodyHealth = 1000,
        tankHealth = 1000, dirtLevel = 0,
        conditionState = {}, clearVisualDamage = true,
    }
    local row = exports[VEHICLES_RESOURCE]:GetVehicleById(vehicleId)
    if not row then return false, 'The persistent Police vehicle record is missing. Use recovery before recreating it.' end
    local spawn = { x = tonumber(settings.spawn_x), y = tonumber(settings.spawn_y), z = tonumber(settings.spawn_z), h = tonumber(settings.spawn_h) or 0 }
    local active, activeInfo = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId)

    -- Recover vehicles left quarantined by the old server-created path.
    -- House garages do the same thing when their registered display entity is
    -- unusable: remove only the physical copy, retain the database vehicle ID,
    -- and rebuild it through the client-assisted garage creator below.
    if active == true then
        local gotCondition, condition = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleCondition(vehicleId, row)
        if gotCondition == true and type(condition) == 'table' and condition.conditionReady ~= true then
            if vehicleHasOccupant(activeInfo and activeInfo.entity) then
                return false, 'That Police vehicle is occupied and cannot be recovered yet.'
            end
            local deleted, deleteWhy = exports[VEHICLES_RESOURCE]:DeleteSpawnedVehicle(vehicleId)
            if deleted ~= true then return false, tostring(deleteWhy or 'The protected Police vehicle could not be cleared.') end
            active, activeInfo = false, nil
        end
    end

    if active ~= true then
        -- The house-style creator reads its bootstrap condition from this row,
        -- so persist and reload the clean Police baseline before creating it.
        if exports[VEHICLES_RESOURCE]:ServiceVehicle(row.plate, servicePatch, src) ~= true then
            return false, 'The Police vehicle could not be serviced before recall.'
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
    if ok ~= true then return false, tostring(result or 'Police vehicle could not be recalled.') end
    -- Broadcast (no targetSrc) rather than aiming only at the recalling admin:
    -- the vehicle's saved spawn point is very often far from wherever the
    -- admin opened the fleet menu, so only that one client may never have it
    -- streamed in to physically apply the repair. Any currently-nearby client
    -- can pick this up instead; cm-vehicles also now retries this patch for
    -- whichever client streams the entity in later (cmPendingServicePatch).
    if exports[VEHICLES_RESOURCE]:ServiceVehicle(row.plate, servicePatch, nil) ~= true then
        return false, 'The Police vehicle could not finish its service.'
    end
    exports[VEHICLES_RESOURCE]:TransitionVehicleLocation(tonumber(settings.vehicle_id), 'JOB_GARAGE', { ref = 'police', reason = repair and 'police_recall_all' or 'police_vehicle_call', actorCharacterId = actorCid })
    local _, info = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(tonumber(settings.vehicle_id))
    if type(info) == 'table' and tonumber(info.entity) and DoesEntityExist(tonumber(info.entity)) then
        local entity = tonumber(info.entity)
        local state = Entity(entity).state
        state:set('cmPoliceFleet', { model = model, vehicleId = vehicleId, minTier = tonumber(settings.min_tier) or 0, ready = false }, true)
        local deadline = GetGameTimer() + 15000
        while DoesEntityExist(entity) and state.cmConditionReady ~= true and GetGameTimer() < deadline do Wait(200) end
        if not DoesEntityExist(entity) or state.cmConditionReady ~= true then
            return false, 'The Police vehicle was recalled but its repaired condition did not finish loading.'
        end
        state:set('cmPoliceFleet', { model = model, vehicleId = vehicleId, minTier = tonumber(settings.min_tier) or 0, ready = true }, true)
    end
    local catalogRow = findCatalogRow(getPoliceCatalog(), model)
    if type(info) == 'table' and catalogRow then TriggerClientEvent('cm-police:client:applyFleetMods', src, info.netId, decode(catalogRow.mods)) end
    return true, ('%s recalled (vehicle #%d).'):format(row.label or model, tonumber(settings.vehicle_id))
end

local function spawnPersistent(src, actor, actorCid, model, repair)
    local settings = persistentFleetRow(model)
    if not settings or not tonumber(settings.vehicle_id) then return false, 'Set this vehicle location first.' end
    if not dbBoolean(settings.enabled) then return false, 'That Police vehicle is disabled.' end
    if not dbBoolean(actor.is_leader) and (tonumber(actor.tier) or 0) < (tonumber(settings.min_tier) or 0) then return false, 'Your rank cannot use this vehicle.' end
    local ok, message = recallFleetVehicleCore(src, actorCid, model, settings, repair)
    if ok and actorCid and not repair then FleetAssignments[model] = { characterId = tostring(actorCid), name = nameFor(actorCid) } end
    if ok and repair then FleetAssignments[model] = nil end
    return ok, message
end

AddEventHandler('cm-police:server:memberWentOffDuty', function(src, characterId)
    src, characterId = tonumber(src), tostring(characterId or '')
    if not src or not GetPlayerName(src) then src = tonumber((GetPlayers() or {})[1]) end
    for model, assignment in pairs(FleetAssignments) do
        if assignment.characterId == characterId then
            local settings = persistentFleetRow(model)
            if src and GetPlayerName(src) and settings then recallFleetVehicleCore(src, characterId, model, settings, true) end
            FleetAssignments[model] = nil
        end
    end
end)

lib.callback.register('cm-police:server:spawnFleetVehicle', function(src, model)
    local actor, actorCid, err = actorFor(src)
    if not actor then return false, err end
    if not has(actor, 'police.manage_vehicles') and not has(actor, 'police.spawn_vehicles') then return false, 'Your rank cannot call Police vehicles.' end
    if not dbBoolean(actor.on_duty) then return false, 'Go on duty first.' end
    return spawnPersistent(src, actor, actorCid, tostring(model or ''):lower(), false)
end)

lib.callback.register('cm-police:server:recallAllFleetVehicles', function(src)
    local actor, actorCid, err = actorFor(src)
    if not actor or not has(actor, 'police.manage_vehicles') then return false, err or 'Your rank cannot recall the Police fleet.' end
    if fleetOperationBusy then return false, 'Another fleet recall is running.' end
    fleetOperationBusy = true
    local rows = MySQL.query.await('SELECT model FROM cm_police_fleet_vehicles WHERE enabled = 1 AND vehicle_id IS NOT NULL ORDER BY model') or {}
    local recalled, failed = 0, 0
    for _, row in ipairs(rows) do
        local ok = spawnPersistent(src, actor, actorCid, row.model, true)
        if ok then recalled = recalled + 1 else failed = failed + 1 end
        Wait(0)
    end
    fleetOperationBusy = false
    log(actorCid, 'fleet_recalled_all', { recalled = recalled, failed = failed })
    return failed == 0, ('Recalled %d persistent Police vehicles clean, fully repaired and refuelled; %d failed safely.'):format(recalled, failed)
end)

AddEventHandler('playerDropped', function()
    local placement = FleetPlacementBySource[source]
    FleetPlacementBySource[source] = nil
    if placement then pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end) end
end)

-- ── Auto-respawn on server (re)start ─────────────────────────────────────
-- A resource restart wipes cm-vehicles' in-memory spawn registry, so every
-- configured fleet vehicle looks "not active" again even though its
-- persistent vehicle_id record is untouched. Rather than leaving the fleet
-- empty until a Police manager remembers to open the menu and click Recall,
-- bring it back automatically the moment there is a real connected player
-- whose client can do the client-assisted creation. Runs once per resource
-- lifetime; not gated by rank/tier/on-duty since nobody is "requesting" this,
-- the server is just restoring its own fleet.
local fleetAutoRespawnStarted = false

local function autoRespawnFleet(triggerSrc)
    if fleetAutoRespawnStarted then return end
    triggerSrc = tonumber(triggerSrc)
    if not triggerSrc or triggerSrc <= 0 or not GetPlayerName(triggerSrc) then return end
    fleetAutoRespawnStarted = true

    CreateThread(function()
        if fleetOperationBusy then return end
        fleetOperationBusy = true
        local rows = MySQL.query.await('SELECT model FROM cm_police_fleet_vehicles WHERE enabled = 1 AND vehicle_id IS NOT NULL ORDER BY model') or {}
        local respawned, skipped = 0, 0
        for _, row in ipairs(rows) do
            local settings = persistentFleetRow(row.model)
            local vehicleId = settings and tonumber(settings.vehicle_id)
            local alreadyActive = vehicleId and exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId)
            if settings and not alreadyActive then
                local ok = recallFleetVehicleCore(triggerSrc, nil, row.model, settings, true)
                if ok then respawned = respawned + 1 else skipped = skipped + 1 end
            end
            Wait(0)
        end
        fleetOperationBusy = false
        if respawned > 0 or skipped > 0 then
            log(nil, 'fleet_auto_respawned', { respawned = respawned, skipped = skipped })
        end
    end)
end

AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    autoRespawnFleet(src)
end)
