-- cm-ems fleet vehicles.
--
-- Appearance (model, label, category, image, paint/livery/wheels/etc) is
-- configured in rn-vehicleshop's /vehicleadmin ("EMS fleet vehicle" catalog
-- status) and read here live via its GetEmsCatalog export -- cm-ems never
-- stores its own copy, so re-customizing a vehicle there takes effect on the
-- next spawn with no separate sync step.
--
-- cm-ems only owns what's EMS-specific: where each vehicle spawns, whether
-- it's a car or helicopter (auto-detected, not admin-picked), the minimum EMS
-- rank tier required to spawn/drive it, and whether it's enabled.
--
-- Reuses (never duplicates):
--   rn-vehicleshop  GetEmsCatalog -- the EMS-tagged catalog (model/image/mods).
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
local FleetAssignments = {}

local function actorFor(src)
    local characterId = cid(src)
    if not characterId then return nil, nil, 'Character is not loaded.' end
    local member = memberFor(characterId)
    if not member then return nil, characterId, 'You are not an EMS member.' end
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

local function getEmsCatalog()
    local ok, rows = pcall(function() return exports[SHOP_RESOURCE]:GetEmsCatalog() end)
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
    local rows = MySQL.query.await('SELECT * FROM cm_ems_fleet_vehicles') or {}
    local byModel = {}
    for _, row in ipairs(rows) do byModel[tostring(row.model):lower()] = row end
    return byModel
end

local function mergedRow(catalogRow, settingsRow)
    return {
        model = catalogRow.model,
        label = catalogRow.label,
        category = catalogRow.category,
        image = catalogRow.image,
        minTier = settingsRow and math.floor(tonumber(settingsRow.min_tier) or 0) or 0,
        enabled = settingsRow and dbBoolean(settingsRow.enabled) or false,
        configured = settingsRow ~= nil and dbBoolean(settingsRow.location_configured),
        assignedOfficer = FleetAssignments[tostring(catalogRow.model):lower()] and FleetAssignments[tostring(catalogRow.model):lower()].name or nil,
    }
end

local function removeActiveInstance(model)
    local previous = ActiveFleetVehicles[model]
    if not previous then return end
    ActiveFleetVehicles[model] = nil
    pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(previous.plate) end)
end

lib.callback.register('cm-ems:server:fleetCatalog', function(src)
    local actor = select(1, actorFor(src))
    if not actor then return nil end
    local manage = has(actor, 'ems.manage_vehicles')
    local spawn = has(actor, 'ems.spawn_vehicles')
    if not manage and not spawn then return {} end

    local catalog = getEmsCatalog()
    local settings = fleetSettingsByModel()
    local tier = math.floor(tonumber(actor.tier) or 0)
    local isLeader = dbBoolean(actor.is_leader)

    local out = {}
    for _, catalogRow in ipairs(catalog) do
        local settingsRow = settings[tostring(catalogRow.model):lower()]
        local merged = mergedRow(catalogRow, settingsRow)
        local active = ActiveFleetVehicles[tostring(catalogRow.model):lower()]
        local entity = active and active.netId and NetworkGetEntityFromNetworkId(tonumber(active.netId)) or 0
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            local occupied = false
            for seat = -1, GetVehicleMaxNumberOfPassengers(entity) - 1 do
                if GetPedInVehicleSeat(entity, seat) ~= 0 then occupied = true; break end
            end
            merged.status = occupied and 'occupied' or 'deployed'
            merged.occupied = occupied
            merged.engineHealth = math.floor(math.max(0, GetVehicleEngineHealth(entity)))
            merged.bodyHealth = math.floor(math.max(0, GetVehicleBodyHealth(entity)))
            merged.fuel = math.floor(math.max(0, GetVehicleFuelLevel(entity)))
            local coords = GetEntityCoords(entity)
            merged.location = { x = math.floor(coords.x), y = math.floor(coords.y), z = math.floor(coords.z) }
        else
            merged.status = merged.configured and 'available' or 'not_configured'
        end
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
lib.callback.register('cm-ems:server:setFleetVehicleMinTier', function(src, model, minTier)
    local actor, actorCid = actorFor(src)
    if not actor or not has(actor, 'ems.manage_vehicles') then return false, 'Your rank cannot manage EMS vehicles.' end
    model = tostring(model or ''):lower()
    if model == '' then return false, 'Invalid model.' end
    minTier = math.max(0, math.min(100, math.floor(tonumber(minTier) or 0)))
    local changed = MySQL.update.await('UPDATE cm_ems_fleet_vehicles SET min_tier = ? WHERE model = ?', { minTier, model })
    if not tonumber(changed) or tonumber(changed) <= 0 then
        return false, 'Spawn this vehicle and press H inside it first, to give it a location.'
    end
    log(actorCid, 'fleet_vehicle_min_tier_set', { model = model, minTier = minTier })
    return true
end)

local function beginFleetLocationEdit(src, model, adminStarted)
    local actor, _, err = actorFor(src)
    local admin = false
    if adminStarted == true then pcall(function() admin = exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true end) end
    if not admin and (not actor or not has(actor, 'ems.manage_vehicles')) then return false, err or 'Your rank cannot manage EMS vehicles.' end
    if not rateLimit(src, 'ems_fleet_edit', 1500) then return false, 'Please wait.' end
    model = tostring(model or ''):lower()
    local catalogRow = findCatalogRow(getEmsCatalog(), model)
    if not catalogRow then return false, 'That vehicle is not tagged as an EMS vehicle.' end
    local previous = FleetPlacementBySource[src]
    if previous then pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(previous.plate) end) end
    FleetPlacementBySource[src] = nil
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Character is not loaded.' end
    local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local okClass, classId = pcall(GetVehicleClassFromName, GetHashKey(model))
    local kind = okClass and classId == 15 and 'helicopter' or 'car'
    local x, y, z = offsetSpawnCoords(coords.x, coords.y, coords.z, heading, kind)
    local result = exports[VEHICLES_RESOURCE]:SpawnAdminVehicle(src, model, { x = x, y = y, z = z, h = heading }, {
        label = ('EMS location dummy: %s'):format(catalogRow.label), placementKind = kind, engineOn = true,
    })
    if type(result) ~= 'table' or result.ok ~= true then return false, tostring(result and result.error or 'Could not create the location dummy.') end
    FleetPlacementBySource[src] = { model = model, kind = kind, plate = result.plate, netId = result.netId, entity = result.entity, admin = admin, expiresAt = os.time() + 300 }
    if result.entity and DoesEntityExist(result.entity) then Entity(result.entity).state:set('cmEmsFleet', { model = model, placement = true }, true) end
    return true, { netId = result.netId, model = model, message = 'Drive to the location. Press H to save or Backspace to cancel.' }
end
lib.callback.register('cm-ems:server:beginFleetLocationEdit', function(src, model) return beginFleetLocationEdit(src, model, false) end)

lib.callback.register('cm-ems:server:cancelFleetLocationEdit', function(src)
    local placement = FleetPlacementBySource[src]
    if not placement then return false, 'No EMS fleet placement is active.' end
    FleetPlacementBySource[src] = nil
    pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end)
    return true, 'EMS fleet placement cancelled.'
end)

-- Location save/update: the player must be DRIVING the exact EMS dummy
-- being saved, so the location that gets stored is always where the car
-- genuinely is right now (triggered by the in-game H keybind, never by the
-- NUI, and coordinates always come from the server's own view of the vehicle
-- -- never trusted from the client).
lib.callback.register('cm-ems:server:saveFleetVehicleLocation', function(src, model, kind)
    local actor, actorCid, err = actorFor(src)
    local placement = FleetPlacementBySource[src]
    if placement and tonumber(placement.expiresAt) and os.time() >= tonumber(placement.expiresAt) then
        FleetPlacementBySource[src] = nil
        pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end)
        return false, 'That EMS fleet placement expired. Start it again.'
    end
    local admin = placement and placement.admin == true and exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) == true
    if not admin and (not actor or not has(actor, 'ems.manage_vehicles')) then return false, err or 'Your rank cannot manage EMS vehicles.' end
    if not rateLimit(src, 'ems_fleet_save', 2000) then return false, 'Please wait.' end

    model = tostring(model or ''):lower()
    local catalogRow = findCatalogRow(getEmsCatalog(), model)
    if not catalogRow then return false, 'That vehicle is not tagged as an EMS vehicle in /vehicleadmin.' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Character is not loaded.' end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false, 'Get in the EMS vehicle first.' end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return false, 'Only the driver can save this vehicle\'s location.' end
    if GetHashKey(catalogRow.model) ~= GetEntityModel(vehicle) then return false, 'You are not driving that vehicle.' end
    placement = FleetPlacementBySource[src]
    if not placement or placement.model ~= model or tonumber(placement.entity) ~= tonumber(vehicle) then return false, 'This is not your active EMS location dummy.' end

    local coords = GetEntityCoords(vehicle)
    local heading = GetEntityHeading(vehicle)
    kind = placement.kind == 'helicopter' and 'helicopter' or 'car'

    local settings = MySQL.single.await('SELECT * FROM cm_ems_fleet_vehicles WHERE model = ? LIMIT 1', { model })
    local vehicleId = settings and tonumber(settings.vehicle_id) or nil
    local heldLocationLock = false
    if not vehicleId then
        if FleetLocationBusy[model] then return false, 'Another manager is saving this vehicle location.' end
        FleetLocationBusy[model] = true
        heldLocationLock = true
        settings = MySQL.single.await('SELECT vehicle_id FROM cm_ems_fleet_vehicles WHERE model = ? LIMIT 1', { model })
        vehicleId = settings and tonumber(settings.vehicle_id) or nil
        if not vehicleId then
            local called, created, permanent = pcall(function()
                return exports[VEHICLES_RESOURCE]:CreateOwnedVehicle(src, model, catalogRow.label, 1, { ownerClass = 'ems', organization = 'ems', ownerName = 'EMS', catalogMods = catalogRow.mods })
            end)
            if not called or created ~= true or type(permanent) ~= 'table' or not tonumber(permanent.id) then FleetLocationBusy[model] = nil; return false, tostring(permanent or 'Could not create the persistent EMS vehicle.') end
            vehicleId = tonumber(permanent.id)
        end
    end
    if exports[VEHICLES_RESOURCE]:EnsureOrganizationOwnership(vehicleId, 'ems') ~= true then
        if heldLocationLock then FleetLocationBusy[model] = nil end
        return false, 'Could not assign the persistent vehicle to EMS ownership.'
    end
    MySQL.insert.await([[
        INSERT INTO cm_ems_fleet_vehicles (model, vehicle_id, kind, min_tier, enabled, location_configured, spawn_x, spawn_y, spawn_z, spawn_h, updated_by)
        VALUES (?, ?, ?, 0, 1, 1, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            vehicle_id = VALUES(vehicle_id), kind = VALUES(kind), location_configured = 1,
            spawn_x = VALUES(spawn_x), spawn_y = VALUES(spawn_y), spawn_z = VALUES(spawn_z), spawn_h = VALUES(spawn_h),
            updated_by = VALUES(updated_by)
    ]], { model, vehicleId, kind, coords.x, coords.y, coords.z, heading, actorCid })
    if heldLocationLock then FleetLocationBusy[model] = nil end

    exports[VEHICLES_RESOURCE]:TransitionVehicleLocation(vehicleId, 'JOB_GARAGE', { ref = 'ems', reason = 'ems_dummy_location_saved', actorCharacterId = actorCid })
    FleetPlacementBySource[src] = nil
    pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end)
    log(actorCid, 'fleet_vehicle_location_saved', { model = model, label = catalogRow.label, kind = kind, vehicleId = vehicleId })
    return true, ('%s location saved for permanent vehicle #%d. The dummy was removed.'):format(catalogRow.label, vehicleId)
end)

-- Keyed by model (not src): two different on-duty members clicking spawn on
-- the same model at nearly the same moment would otherwise both pass the
-- per-src rateLimit check below (it's keyed by src, not model) and each get
-- their own copy, leaving whichever finishes first orphaned out of
-- ActiveFleetVehicles[model] and never recalled again.
local legacySpawnBusy = {}

local function spawnFleetVehicleLegacyImpl(src, model)
    local actor, actorCid, err = actorFor(src)
    if not actor then return false, err end
    local manage = has(actor, 'ems.manage_vehicles')
    if not manage and not has(actor, 'ems.spawn_vehicles') then return false, 'Your rank cannot spawn EMS vehicles.' end
    if not dbBoolean(actor.on_duty) then return false, 'Go on duty before spawning an EMS vehicle.' end
    local cooldown = (Config.VehicleFleet and Config.VehicleFleet.spawnCooldownMs) or 15000
    if not rateLimit(src, 'ems_veh_spawn', cooldown) then return false, 'Please wait before spawning another vehicle.' end

    model = tostring(model or ''):lower()
    local catalogRow = findCatalogRow(getEmsCatalog(), model)
    if not catalogRow then return false, 'That vehicle is not tagged as an EMS vehicle in /vehicleadmin.' end

    local settingsRow = MySQL.single.await('SELECT * FROM cm_ems_fleet_vehicles WHERE model = ? LIMIT 1', { model })

    local coords, heading, kind, minTier
    if settingsRow then
        if not dbBoolean(settingsRow.enabled) then return false, 'That EMS vehicle is not available.' end
        minTier = math.floor(tonumber(settingsRow.min_tier) or 0)
        local tier = math.floor(tonumber(actor.tier) or 0)
        if not manage and not dbBoolean(actor.is_leader) and tier < minTier then
            return false, 'Your rank is not authorized to spawn this vehicle.'
        end
        coords = { x = tonumber(settingsRow.spawn_x), y = tonumber(settingsRow.spawn_y), z = tonumber(settingsRow.spawn_z) }
        heading = tonumber(settingsRow.spawn_h) or 0.0
        kind = settingsRow.kind == 'helicopter' and 'helicopter' or 'car'
    else
        -- No saved location yet -- only a manager can bootstrap it, spawning
        -- at their own position so they can drive it into place and press H.
        if not manage then return false, 'This EMS vehicle has no spawn location yet. Ask an EMS manager to set one.' end
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return false, 'Character is not loaded.' end
        local pcoords = GetEntityCoords(ped)
        heading = GetEntityHeading(ped)
        -- Auto-detect car vs helicopter here too (same convention as the H-key
        -- save), instead of always assuming 'car'. A hardcoded 'car' offset
        -- (only +0.25m vertical clearance) previously left a bootstrap-spawned
        -- helicopter embedded in the ground/player collision, so it "spawned"
        -- (CreateVehicle succeeded server-side) but never appeared drivable.
        local okClass, classId = pcall(GetVehicleClassFromName, GetHashKey(catalogRow.model))
        kind = (okClass and classId == 15) and 'helicopter' or 'car' -- 15 = GTA's Helicopters class
        local sx, sy, sz = offsetSpawnCoords(pcoords.x, pcoords.y, pcoords.z, heading, kind)
        coords = { x = sx, y = sy, z = sz }
        minTier = 0
    end

    -- Recall: replace any previous live instance of this exact model instead
    -- of letting duplicates pile up.
    removeActiveInstance(model)

    local result = exports[VEHICLES_RESOURCE]:SpawnAdminVehicle(src, catalogRow.model, {
        x = coords.x, y = coords.y, z = coords.z, h = heading,
    }, {
        label = catalogRow.label,
        placementKind = kind,
        engineOn = true,
    })
    if not result or not result.ok then
        print(('[cm-ems] fleet spawn FAILED model=%s error=%s'):format(model, tostring(result and result.error)))
        return false, (result and result.error) or 'Could not spawn that vehicle right now.'
    end

    ActiveFleetVehicles[model] = { plate = result.plate, netId = result.netId }

    -- Replicated to every client so client/vehicles.lua can lock the doors
    -- for anyone who does not currently qualify to drive this vehicle.
    if result.entity and DoesEntityExist(result.entity) then
        Entity(result.entity).state:set('cmEmsFleet', { model = catalogRow.model, minTier = minTier }, true)
    end

    TriggerClientEvent('cm-ems:client:applyFleetMods', src, result.netId, decode(catalogRow.mods))
    log(actorCid, 'fleet_vehicle_spawned', { model = catalogRow.model, label = catalogRow.label, plate = result.plate, hasLocation = settingsRow ~= nil })
    return true, settingsRow
        and ('%s spawned.'):format(catalogRow.label)
        or ('%s spawned at your position. Drive it to where it should live, then press H to save that as its spawn point.'):format(catalogRow.label)
end

lib.callback.register('cm-ems:server:spawnFleetVehicleLegacy', function(src, model)
    model = tostring(model or ''):lower()
    if legacySpawnBusy[model] then return false, 'Someone else is already spawning that vehicle.' end
    legacySpawnBusy[model] = true
    local ok, resultA, resultB = pcall(spawnFleetVehicleLegacyImpl, src, model)
    legacySpawnBusy[model] = nil
    if not ok then
        print(('[cm-ems] fleet spawn (legacy) errored model=%s error=%s'):format(model, tostring(resultA)))
        return false, 'Could not spawn that vehicle right now.'
    end
    return resultA, resultB
end)

local fleetOperationBusy = false

local function persistentFleetRow(model)
    return MySQL.single.await('SELECT * FROM cm_ems_fleet_vehicles WHERE model = ? LIMIT 1', { tostring(model):lower() })
end

local function vehicleHasOccupant(entity)
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

-- Location edit mode records the manager's current position. It deliberately
-- does not create a physical placement vehicle.
lib.callback.register('cm-ems:server:setFleetVehicleLocation', function(src, model)
    local actor, actorCid, err = actorFor(src)
    if not actor or not has(actor, 'ems.manage_vehicles') then return false, err or 'Your rank cannot manage EMS vehicles.' end
    if not rateLimit(src, 'ems_fleet_location', 1500) then return false, 'Please wait.' end
    model = tostring(model or ''):lower()
    local catalogRow = findCatalogRow(getEmsCatalog(), model)
    if not catalogRow then return false, 'That model is not tagged as an EMS fleet vehicle.' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Character is not loaded.' end
    local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local okClass, classId = pcall(GetVehicleClassFromName, GetHashKey(model))
    local kind = okClass and classId == 15 and 'helicopter' or 'car'
    local settings = persistentFleetRow(model)
    local vehicleId = settings and tonumber(settings.vehicle_id) or nil
    if not vehicleId then
        local created, vehicle = exports[VEHICLES_RESOURCE]:CreateOwnedVehicle(src, model, catalogRow.label, 1, {
            ownerClass = 'ems', organization = 'ems', ownerName = 'EMS', catalogMods = catalogRow.mods,
        })
        if created ~= true or type(vehicle) ~= 'table' or not tonumber(vehicle.id) then return false, tostring(vehicle or 'Could not create persistent EMS vehicle.') end
        vehicleId = tonumber(vehicle.id)
    end
    if exports[VEHICLES_RESOURCE]:EnsureOrganizationOwnership(vehicleId, 'ems') ~= true then
        return false, 'Could not assign the persistent vehicle to EMS ownership.'
    end
    MySQL.insert.await([[INSERT INTO cm_ems_fleet_vehicles
        (model, vehicle_id, kind, min_tier, enabled, spawn_x, spawn_y, spawn_z, spawn_h, updated_by)
        VALUES (?, ?, ?, 0, 1, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE vehicle_id = VALUES(vehicle_id), kind = VALUES(kind),
        spawn_x = VALUES(spawn_x), spawn_y = VALUES(spawn_y), spawn_z = VALUES(spawn_z), spawn_h = VALUES(spawn_h), updated_by = VALUES(updated_by)]],
        { model, vehicleId, kind, coords.x, coords.y, coords.z, heading, actorCid })
    exports[VEHICLES_RESOURCE]:TransitionVehicleLocation(vehicleId, 'JOB_GARAGE', { ref = 'ems', reason = 'ems_location_set', actorCharacterId = actorCid })
    log(actorCid, 'fleet_vehicle_location_saved', { model = model, vehicleId = vehicleId })
    return true, ('%s location saved without spawning a vehicle. Permanent vehicle ID: %d.'):format(catalogRow.label, vehicleId)
end)

-- The recall/create/service mechanics themselves (no rank/tier gating -- that
-- is the caller's job). Used both by player-initiated spawn/recall callbacks
-- and by the unattended startup auto-respawn below, which has no "actor" to
-- check a rank against.
local function recallFleetVehicleCore(src, actorCid, model, settings, repair)
    local vehicleId = tonumber(settings.vehicle_id)
    if exports[VEHICLES_RESOURCE]:EnsureOrganizationOwnership(vehicleId, 'ems') ~= true then
        return false, 'The vehicle could not be assigned to EMS ownership.'
    end
    local servicePatch = {
        fuel = 100, engineHealth = 1000, bodyHealth = 1000,
        tankHealth = 1000, dirtLevel = 0,
        conditionState = {}, clearVisualDamage = true,
    }
    local row = exports[VEHICLES_RESOURCE]:GetVehicleById(vehicleId)
    if not row then return false, 'The persistent EMS vehicle record is missing. Use recovery before recreating it.' end
    local spawn = { x = tonumber(settings.spawn_x), y = tonumber(settings.spawn_y), z = tonumber(settings.spawn_z), h = tonumber(settings.spawn_h) or 0 }
    local active, activeInfo = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId)

    -- Recover vehicles left quarantined by the old server-created EMS path.
    -- House garages do the same thing when their registered display entity is
    -- unusable: remove only the physical copy, retain the database vehicle ID,
    -- and rebuild it through the client-assisted garage creator below.
    if active == true then
        local gotCondition, condition = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleCondition(vehicleId, row)
        if gotCondition == true and type(condition) == 'table' and condition.conditionReady ~= true then
            if vehicleHasOccupant(activeInfo and activeInfo.entity) then
                return false, 'That EMS vehicle is occupied and cannot be recovered yet.'
            end
            local deleted, deleteWhy = exports[VEHICLES_RESOURCE]:DeleteSpawnedVehicle(vehicleId)
            if deleted ~= true then return false, tostring(deleteWhy or 'The protected EMS vehicle could not be cleared.') end
            active, activeInfo = false, nil
        end
    end

    if active ~= true then
        -- The house-style creator reads its bootstrap condition from this row,
        -- so persist and reload the clean EMS baseline before creating it.
        if exports[VEHICLES_RESOURCE]:ServiceVehicle(row.plate, servicePatch, src) ~= true then
            return false, 'The EMS vehicle could not be serviced before recall.'
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
    if ok ~= true then return false, tostring(result or 'EMS vehicle could not be recalled.') end
    -- Broadcast (no targetSrc) rather than aiming only at the recalling admin:
    -- the vehicle's saved spawn point is very often far from wherever the
    -- admin opened the fleet menu, so only that one client may never have it
    -- streamed in to physically apply the repair. Any currently-nearby client
    -- can pick this up instead; cm-vehicles also now retries this patch for
    -- whichever client streams the entity in later (cmPendingServicePatch).
    if exports[VEHICLES_RESOURCE]:ServiceVehicle(row.plate, servicePatch, nil) ~= true then
        return false, 'The EMS vehicle could not finish its service.'
    end
    exports[VEHICLES_RESOURCE]:TransitionVehicleLocation(tonumber(settings.vehicle_id), 'JOB_GARAGE', { ref = 'ems', reason = repair and 'ems_recall_all' or 'ems_vehicle_call', actorCharacterId = actorCid })
    local _, info = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(tonumber(settings.vehicle_id))
    if type(info) == 'table' and tonumber(info.entity) and DoesEntityExist(tonumber(info.entity)) then
        local entity = tonumber(info.entity)
        local state = Entity(entity).state
        state:set('cmEmsFleet', { model = model, vehicleId = vehicleId, minTier = tonumber(settings.min_tier) or 0, ready = false }, true)
        local deadline = GetGameTimer() + 15000
        while DoesEntityExist(entity) and state.cmConditionReady ~= true and GetGameTimer() < deadline do Wait(200) end
        if not DoesEntityExist(entity) or state.cmConditionReady ~= true then
            return false, 'The EMS vehicle was recalled but its repaired condition did not finish loading.'
        end
        state:set('cmEmsFleet', { model = model, vehicleId = vehicleId, minTier = tonumber(settings.min_tier) or 0, ready = true }, true)
    end
    local catalogRow = findCatalogRow(getEmsCatalog(), model)
    if type(info) == 'table' and catalogRow then TriggerClientEvent('cm-ems:client:applyFleetMods', src, info.netId, decode(catalogRow.mods)) end
    return true, ('%s recalled (vehicle #%d).'):format(row.label or model, tonumber(settings.vehicle_id))
end

local function spawnPersistent(src, actor, actorCid, model, repair)
    local settings = persistentFleetRow(model)
    if not settings or not tonumber(settings.vehicle_id) then return false, 'Set this vehicle location first.' end
    if not dbBoolean(settings.enabled) then return false, 'That EMS vehicle is disabled.' end
    if not dbBoolean(actor.is_leader) and (tonumber(actor.tier) or 0) < (tonumber(settings.min_tier) or 0) then return false, 'Your rank cannot use this vehicle.' end
    local ok, message = recallFleetVehicleCore(src, actorCid, model, settings, repair)
    if ok and actorCid and not repair then FleetAssignments[model] = { characterId = tostring(actorCid), name = nameFor(actorCid) } end
    if ok and repair then FleetAssignments[model] = nil end
    return ok, message
end

AddEventHandler('cm-ems:server:memberWentOffDuty', function(src, characterId)
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

lib.callback.register('cm-ems:server:spawnFleetVehicle', function(src, model)
    local actor, actorCid, err = actorFor(src)
    if not actor then return false, err end
    if not has(actor, 'ems.manage_vehicles') and not has(actor, 'ems.spawn_vehicles') then return false, 'Your rank cannot call EMS vehicles.' end
    if not dbBoolean(actor.on_duty) then return false, 'Go on duty first.' end
    return spawnPersistent(src, actor, actorCid, tostring(model or ''):lower(), false)
end)

lib.callback.register('cm-ems:server:recallAllFleetVehicles', function(src)
    local actor, actorCid, err = actorFor(src)
    if not actor or not has(actor, 'ems.manage_vehicles') then return false, err or 'Your rank cannot recall the EMS fleet.' end
    if fleetOperationBusy then return false, 'Another fleet recall is running.' end
    fleetOperationBusy = true
    local rows = MySQL.query.await('SELECT model FROM cm_ems_fleet_vehicles WHERE enabled = 1 AND vehicle_id IS NOT NULL ORDER BY model') or {}
    local recalled, failed = 0, 0
    for _, row in ipairs(rows) do
        local ok = spawnPersistent(src, actor, actorCid, row.model, true)
        if ok then recalled = recalled + 1 else failed = failed + 1 end
        Wait(0)
    end
    fleetOperationBusy = false
    log(actorCid, 'fleet_recalled_all', { recalled = recalled, failed = failed })
    return failed == 0, ('Recalled %d persistent EMS vehicles clean, fully repaired and refuelled; %d failed safely.'):format(recalled, failed)
end)

AddEventHandler('playerDropped', function()
    local placement = FleetPlacementBySource[source]
    FleetPlacementBySource[source] = nil
    if placement then pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end) end
end)

CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        for src, placement in pairs(FleetPlacementBySource) do
            if tonumber(placement.expiresAt) and now >= tonumber(placement.expiresAt) then
                FleetPlacementBySource[src] = nil
                pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for src, placement in pairs(FleetPlacementBySource) do
        FleetPlacementBySource[src] = nil
        pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end)
    end
end)

local function emsAdmin(src)
    local ok, allowed = pcall(function() return exports[Config.AdminResource]:HasPermission(src, Config.AdminPermission) end)
    return ok and allowed == true
end

exports('AdminGetFleet', function(src)
    if not emsAdmin(tonumber(src)) then return { ok = false, error = 'Permission denied.' } end
    local settings, vehicles = fleetSettingsByModel(), {}
    for _, row in ipairs(getEmsCatalog()) do vehicles[#vehicles + 1] = mergedRow(row, settings[tostring(row.model):lower()]) end
    return { ok = true, vehicles = vehicles }
end)

exports('AdminConfigureFleetVehicle', function(src, _, data)
    src, data = tonumber(src), type(data) == 'table' and data or {}
    if not emsAdmin(src) then return false, 'Permission denied.' end
    local model = tostring(data.model or ''):lower()
    if not findCatalogRow(getEmsCatalog(), model) then return false, 'That model is not in the EMS catalog.' end
    local row = MySQL.single.await('SELECT model,location_configured FROM cm_ems_fleet_vehicles WHERE model = ? LIMIT 1', { model })
    if not row or not dbBoolean(row.location_configured) then return false, 'Set this vehicle location before enabling it.' end
    local tier = math.max(0, math.min(100, math.floor(tonumber(data.minTier) or 0)))
    MySQL.update.await('UPDATE cm_ems_fleet_vehicles SET enabled = ?, min_tier = ?, updated_by = ? WHERE model = ?',
        { data.enabled == true and 1 or 0, tier, tostring(cid(src) or 'admin'), model })
    return true, 'EMS fleet vehicle configuration saved.'
end)

exports('AdminBeginFleetPlacement', function(src, _, model)
    local ok, result = beginFleetLocationEdit(tonumber(src), model, true)
    if ok and type(result) == 'table' then TriggerClientEvent('cm-ems:client:adminFleetPlacement', tonumber(src), result) end
    return ok, type(result) == 'table' and result.message or result
end)

exports('AdminResetFleetLocation', function(src, _, model)
    src, model = tonumber(src), tostring(model or ''):lower()
    if not emsAdmin(src) then return false, 'Permission denied.' end
    local changed = MySQL.update.await('UPDATE cm_ems_fleet_vehicles SET enabled = 0, location_configured = 0, updated_by = ? WHERE model = ?', { tostring(cid(src) or 'admin'), model })
    if tonumber(changed) == 0 then return false, 'That EMS vehicle has no saved location.' end
    removeActiveInstance(model)
    return true, 'EMS fleet location disabled; persistent vehicle identity was preserved. Set a new location to reactivate it.'
end)

-- ── Auto-respawn on server (re)start ─────────────────────────────────────
-- A resource restart wipes cm-vehicles' in-memory spawn registry, so every
-- configured fleet vehicle looks "not active" again even though its
-- persistent vehicle_id record is untouched. Rather than leaving the fleet
-- empty until an EMS manager remembers to open the menu and click Recall,
-- bring it back automatically the moment there is a real connected player
-- whose client can do the client-assisted creation (there is no client to
-- spawn anything with at the instant this resource starts -- 0 players may
-- be online yet). Runs once per resource lifetime; not gated by rank/tier/
-- on-duty since nobody is "requesting" this, the server is just restoring
-- its own fleet. Vehicles that are actually far from whoever triggers this
-- still finish repairing safely later via cmPendingServicePatch/the pooled
-- vehicle scan in cm-vehicles once any player streams them in.
local fleetAutoRespawnStarted = false

local function autoRespawnFleet(triggerSrc)
    if fleetAutoRespawnStarted then return end
    triggerSrc = tonumber(triggerSrc)
    if not triggerSrc or triggerSrc <= 0 or not GetPlayerName(triggerSrc) then return end
    fleetAutoRespawnStarted = true

    CreateThread(function()
        if fleetOperationBusy then return end
        fleetOperationBusy = true
        local rows = MySQL.query.await('SELECT model FROM cm_ems_fleet_vehicles WHERE enabled = 1 AND vehicle_id IS NOT NULL ORDER BY model') or {}
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
