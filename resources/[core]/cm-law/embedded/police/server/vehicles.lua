-- cm-police fleet vehicles.
--
-- Appearance (model, label, category, image, paint/livery/wheels/etc) is
-- configured in rn-vehicleshop's /vehicleadmin ("Police fleet vehicle"
-- catalog status) and read here live via its GetPoliceCatalog export --
-- cm-police never stores its own copy, so re-customizing a vehicle there
-- takes effect on the next spawn with no separate sync step.
--
-- cm-police only owns what's Police-specific: each vehicle's saved parking place,
-- whether it's a car or helicopter (auto-detected, not admin-picked), the
-- minimum Police rank tier required to use it, and whether it's
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
local vehicleHasOccupant

local function actorFor(src)
    local characterId = cid(src)
    if not characterId then return nil, nil, 'Character is not loaded.' end
    local member = PoliceLegacyMemberFor(characterId)
    if not member then
        local isAdmin = false
        pcall(function() isAdmin = exports[PoliceConfig.AdminResource]:HasPermission(src, PoliceConfig.AdminPermission) == true end)
        if isAdmin then return { tier = 101, is_leader = 1, permissions = '{}' }, characterId, nil end
        return nil, characterId, 'You are not a Police member.'
    end
    return member, characterId, nil
end

local function canManagePoliceFleet(actor)
    return actor ~= nil and (PoliceLegacyDbBoolean(actor.is_leader) or has(actor, 'police.manage_vehicles'))
end

local function canUsePoliceFleet(actor)
    return actor ~= nil and (PoliceLegacyDbBoolean(actor.is_leader) or has(actor, 'police.spawn_vehicles'))
end

local function policeFleetRanks()
    local rows = MySQL.query.await('SELECT id, name, tier FROM cm_police_ranks ORDER BY tier ASC') or {}
    local ranks = {}
    for _, row in ipairs(rows) do
        ranks[#ranks + 1] = { id = tonumber(row.id), name = tostring(row.name or ''), tier = tonumber(row.tier) or 0 }
    end
    return ranks
end

local function rankLabelForTier(ranks, tier)
    tier = tonumber(tier) or 0
    for _, rank in ipairs(ranks or {}) do
        if tonumber(rank.tier) == tier then return rank.name end
    end
    return ('Tier %d'):format(math.floor(tier))
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

-- Tag-agnostic fallback: a vehicle granted straight to Police via
-- rn-vehicleshop's "Give to organization" is never toggled through the
-- "Police fleet vehicle" catalog status (that would silently pull it out of
-- the public Store/Server catalog, which a grant must never do), so it will
-- never appear in getPoliceCatalog() above. This looks up plain appearance
-- (label/category/image/mods) for any catalog vehicle regardless of status,
-- used only when the model isn't tag-matched.
local function getVehicleCatalogInfo(model)
    local ok, row = pcall(function() return exports[SHOP_RESOURCE]:GetVehicleCatalogInfo(model) end)
    return (ok and type(row) == 'table') and row or nil
end

local function findCatalogRow(catalog, model)
    model = tostring(model or ''):lower()
    for _, row in ipairs(catalog) do
        if tostring(row.model):lower() == model then return row end
    end
    return nil
end

-- Prefer the Police-tagged catalog row (keeps the existing appearance
-- customization workflow for anyone still using /vehicleadmin's tag), fall
-- back to the plain lookup for a grant-linked vehicle that was never tagged.
local function resolveCatalogRow(model)
    return findCatalogRow(getPoliceCatalog(), model) or getVehicleCatalogInfo(model)
end

local function fleetSettingsByModel()
    local rows = MySQL.query.await('SELECT * FROM cm_police_fleet_vehicles') or {}
    local byModel = {}
    for _, row in ipairs(rows) do byModel[tostring(row.model):lower()] = row end
    return byModel
end

function PoliceLegacyVehicleAccessDecision(characterId, vehicleId, action)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'not_police_fleet_vehicle' end
    local settings = MySQL.single.await([[SELECT min_tier FROM cm_police_fleet_vehicles
        WHERE vehicle_id = ? AND enabled = 1 LIMIT 1]], { vehicleId })
    if not settings then return false, 'not_police_fleet_vehicle' end
    local member = characterId and PoliceLegacyMemberFor(tostring(characterId)) or nil
    if not member then return false, 'not_police_member' end
    local required = tonumber(settings.min_tier) or 0
    local normalized = {
        suspended = PoliceLegacyDbBoolean(member.is_suspended), onDuty = PoliceLegacyDbBoolean(member.on_duty),
        isLeader = PoliceLegacyDbBoolean(member.is_leader), tier = member.tier,
    }
    local ok, reason = FleetVehicleAccessDecision(normalized, required, action, {
        protected = 'police_fleet_protected', notOnDuty = 'police_not_on_duty',
        rankTooLow = 'police_rank_too_low', ok = 'police_fleet',
    })
    if not ok then return false, reason end
    return true, reason, { organization = 'police', vehicleId = vehicleId, requiredTier = required }
end
exports('PoliceLegacyGetVehicleAccessDecision', PoliceLegacyVehicleAccessDecision)
exports('GetPoliceVehicleAccessDecision', PoliceLegacyVehicleAccessDecision)

local function mergedRow(catalogRow, settingsRow)
    local merged = {
        model = catalogRow.model,
        label = catalogRow.label,
        category = catalogRow.category,
        image = catalogRow.image,
        vehicleId = settingsRow and tonumber(settingsRow.vehicle_id) or nil,
        minTier = settingsRow and math.floor(tonumber(settingsRow.min_tier) or 0) or 0,
        enabled = settingsRow and PoliceLegacyDbBoolean(settingsRow.enabled) or false,
        configured = settingsRow ~= nil and PoliceLegacyDbBoolean(settingsRow.location_configured),
    }
    local vehicleId = settingsRow and tonumber(settingsRow.vehicle_id)
    local active, info = vehicleId and exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId) or false, nil
    if vehicleId then active, info = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId) end
    local entity = active == true and type(info) == 'table' and tonumber(info.entity) or 0
    if entity ~= 0 and DoesEntityExist(entity) then
        merged.status = vehicleHasOccupant and vehicleHasOccupant(entity) and 'in_use' or 'available'
        merged.engineHealth = math.floor(math.max(0, GetVehicleEngineHealth(entity)))
        merged.bodyHealth = math.floor(math.max(0, GetVehicleBodyHealth(entity)))
        local fuelOk, fuelLevel = pcall(GetVehicleFuelLevel, entity) -- server-side native availability is build-dependent; never let a read crash the listing
        merged.fuel = math.floor(math.max(0, fuelOk and fuelLevel or 0))
        local coords = GetEntityCoords(entity)
        merged.location = { x = math.floor(coords.x), y = math.floor(coords.y), z = math.floor(coords.z) }
    else
        merged.status = not merged.enabled and 'disabled' or (merged.configured and 'recovering' or 'not_configured')
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
    local manage = canManagePoliceFleet(actor)
    local use = canUsePoliceFleet(actor)
    if not manage and not use then return { vehicles = {}, ranks = {}, canManage = false, useVehicles = false } end

    local catalog = getPoliceCatalog()
    local settings = fleetSettingsByModel()
    local tier = math.floor(tonumber(actor.tier) or 0)
    local isLeader = PoliceLegacyDbBoolean(actor.is_leader)
    local ranks = policeFleetRanks()

    local out = {}
    local seen = {}
    local function consider(catalogRow, settingsRow)
        local merged = mergedRow(catalogRow, settingsRow)
        merged.minRankName = rankLabelForTier(ranks, merged.minTier)
        merged.vehicleId, merged.engineHealth, merged.bodyHealth, merged.fuel, merged.location = nil, nil, nil, nil, nil
        if manage then
            out[#out + 1] = merged
        elseif use and merged.configured and merged.enabled and (isLeader or tier >= merged.minTier) then
            out[#out + 1] = merged
        end
    end
    for _, catalogRow in ipairs(catalog) do
        local modelKey = tostring(catalogRow.model):lower()
        seen[modelKey] = true
        consider(catalogRow, settings[modelKey])
    end
    -- Vehicles linked via a "Give to organization" grant are never tagged in
    -- the shared catalog (see resolveCatalogRow above), so they never show up
    -- in the loop above -- include them here from their own settings row.
    for modelKey, settingsRow in pairs(settings) do
        if not seen[modelKey] then
            local info = getVehicleCatalogInfo(modelKey) or { model = modelKey, label = modelKey, category = 'Fleet' }
            consider(info, settingsRow)
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return { vehicles = out, ranks = ranks, canManage = manage, useVehicles = use, spawnVehicles = use }
end)

-- Rank gate only -- stores a tier from the authoritative Police rank table.
lib.callback.register('cm-police:server:setFleetVehicleMinTier', function(src, model, selectedTier)
    local actor, actorCid = actorFor(src)
    if not canManagePoliceFleet(actor) then return false, 'Your rank cannot manage Police vehicles.' end
    model = tostring(model or ''):lower()
    if model == '' then return false, 'Invalid model.' end
    local rankTier = tonumber(selectedTier)
    if not rankTier or rankTier % 1 ~= 0 then return false, 'Select a valid Police rank.' end
    local rank = MySQL.single.await('SELECT id, name, tier FROM cm_police_ranks WHERE tier = ? LIMIT 1', { rankTier })
    if not rank or tonumber(rank.tier) ~= rankTier then return false, 'That rank does not belong to Police.' end
    local catalogRow = resolveCatalogRow(model)
    local configured = MySQL.single.await('SELECT vehicle_id FROM cm_police_fleet_vehicles WHERE model = ? AND location_configured = 1 LIMIT 1', { model })
    if not catalogRow or not configured or not tonumber(configured.vehicle_id) then return false, 'Set this vehicle location first.' end
    local minTier = tonumber(rank.tier)
    local changed = MySQL.update.await('UPDATE cm_police_fleet_vehicles SET min_tier = ? WHERE model = ?', { minTier, model })
    if not tonumber(changed) or tonumber(changed) <= 0 then
        return false, 'Link this persistent vehicle through Manage Vehicle before setting its location.'
    end
    local active, info = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(tonumber(configured.vehicle_id))
    if active == true and type(info) == 'table' and tonumber(info.entity) and DoesEntityExist(tonumber(info.entity)) then
        pcall(function()
            local state = Entity(tonumber(info.entity)).state
            local fleet = state.cmPoliceFleet
            if type(fleet) ~= 'table' then fleet = { model = model, vehicleId = tonumber(configured.vehicle_id) } end
            fleet.minTier = minTier
            state:set('cmPoliceFleet', fleet, true)
        end)
    end
    log(actorCid, 'fleet_vehicle_min_tier_set', { model = model, minTier = minTier })
    return true, ('Required rank updated to %s.'):format(tostring(rank.name))
end)

local function beginFleetLocationEdit(src, model, adminStarted)
    local actor, actorCid, err = actorFor(src)
    local admin = false
    if adminStarted == true then pcall(function() admin = exports[PoliceConfig.AdminResource]:HasPermission(src, PoliceConfig.AdminPermission) == true end) end
    if not admin and not canManagePoliceFleet(actor) then return false, err or 'Your rank cannot manage Police vehicles.' end
    if admin then actorCid = cid(src) end
    model = tostring(model or ''):lower()
    local catalogRow = resolveCatalogRow(model)
    local settings = MySQL.single.await('SELECT vehicle_id FROM cm_police_fleet_vehicles WHERE model = ? AND enabled = 1 AND location_configured = 1 LIMIT 1', { model })
    local vehicleId = settings and tonumber(settings.vehicle_id)
    if not catalogRow or not vehicleId then return false, 'Link this persistent vehicle through Manage Vehicle first.' end
    local ped = GetPlayerPed(src)
    local vehicle = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= ped then return false, 'Sit in the configured Police vehicle as its driver first.' end
    if GetHashKey(catalogRow.model) ~= GetEntityModel(vehicle) or tonumber(Entity(vehicle).state.cmVehicleId) ~= vehicleId then return false, 'This is not the configured persistent Police vehicle.' end
    local active, info = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId)
    if active ~= true or type(info) ~= 'table' or tonumber(info.entity) ~= tonumber(vehicle) then return false, 'The persistent vehicle registry does not match this entity.' end
    if GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(src) then return false, 'Vehicle routing context does not match.' end
    if not PoliceLegacyRateLimit(src, 'police_fleet_edit', 1500) then return false, 'Please wait.' end
    local coords, heading = GetEntityCoords(vehicle), GetEntityHeading(vehicle)
    if math.abs(coords.x) > 20000 or math.abs(coords.y) > 20000 or coords.z < -500 or coords.z > 5000 or heading < 0 or heading >= 360 then return false, 'Vehicle location is outside supported world bounds.' end
    local kind = GetVehicleClass(vehicle) == 15 and 'helicopter' or 'car'
    local changed = MySQL.update.await([[UPDATE cm_police_fleet_vehicles SET kind=?,spawn_x=?,spawn_y=?,spawn_z=?,spawn_h=?,updated_by=?
        WHERE model=? AND vehicle_id=? AND enabled=1 AND location_configured=1]],
        { kind, coords.x, coords.y, coords.z, heading, actorCid, model, vehicleId })
    if not tonumber(changed) or tonumber(changed) <= 0 then return false, 'Fleet configuration changed; location was not saved.' end
    log(actorCid, 'fleet_vehicle_location_saved', { model = model, label = catalogRow.label, vehicleId = vehicleId })
    return true, ('%s parking location updated.'):format(catalogRow.label)
end
lib.callback.register('cm-police:server:beginFleetLocationEdit', function(src, model) return beginFleetLocationEdit(src, model, false) end)

lib.callback.register('cm-police:server:cancelFleetLocationEdit', function(src)
    local placement = FleetPlacementBySource[src]
    if not placement then return false, 'No Police fleet placement is active.' end
    FleetPlacementBySource[src] = nil
    pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end)
    return true, 'Police fleet placement cancelled.'
end)

-- Location save/update: the player must be DRIVING the exact Police dummy
-- being saved, so the location that gets stored is always where the car
-- genuinely is right now (triggered by the in-game H keybind, never by the
-- NUI, and coordinates always come from the server's own view of the vehicle
-- -- never trusted from the client).
lib.callback.register('cm-police:server:saveFleetVehicleLocation', function(src, model, kind)
    local actor, actorCid, err = actorFor(src)
    local placement = FleetPlacementBySource[src]
    if placement and tonumber(placement.expiresAt) and os.time() >= tonumber(placement.expiresAt) then
        FleetPlacementBySource[src] = nil
        pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end)
        return false, 'That Police fleet placement expired. Start it again.'
    end
    local admin = placement and placement.admin == true and exports[PoliceConfig.AdminResource]:HasPermission(src, PoliceConfig.AdminPermission) == true
    if not admin and not canManagePoliceFleet(actor) then return false, err or 'Your rank cannot manage Police vehicles.' end
    if not PoliceLegacyRateLimit(src, 'police_fleet_save', 2000) then return false, 'Please wait.' end

    model = tostring(model or ''):lower()
    local catalogRow = resolveCatalogRow(model)
    if not catalogRow then return false, 'Unknown vehicle model.' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Character is not loaded.' end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false, 'Get in the Police vehicle first.' end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return false, 'Only the driver can save this vehicle\'s location.' end
    if GetHashKey(catalogRow.model) ~= GetEntityModel(vehicle) then return false, 'You are not driving that vehicle.' end
    placement = FleetPlacementBySource[src]
    if not placement or placement.model ~= model or tonumber(placement.entity) ~= tonumber(vehicle) then return false, 'This is not your active Police location dummy.' end

    local coords = GetEntityCoords(vehicle)
    local heading = GetEntityHeading(vehicle)
    kind = placement.kind == 'helicopter' and 'helicopter' or 'car'

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
        INSERT INTO cm_police_fleet_vehicles (model, vehicle_id, kind, min_tier, enabled, location_configured, spawn_x, spawn_y, spawn_z, spawn_h, updated_by)
        VALUES (?, ?, ?, 0, 1, 1, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            vehicle_id = VALUES(vehicle_id), kind = VALUES(kind), location_configured = 1,
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

local FleetRecoveryLocks, FleetRecoveryFailureLogAt = {}, {}

local function isSuitableFleetRecoveryClient(src)
    src = tonumber(src)
    if not src or src <= 0 then return false end
    local okName, playerName = pcall(GetPlayerName, src)
    if not okName or not playerName then return false end
    local okBucket, bucket = pcall(GetPlayerRoutingBucket, src)
    return okBucket and tonumber(bucket) == 0
end

local function logFleetRecoveryFailure(vehicleId, reason)
    local key = ('%s:%s'):format(tostring(vehicleId or 0), tostring(reason or 'unknown'))
    local now = os.time()
    if FleetRecoveryFailureLogAt[key] and now - FleetRecoveryFailureLogAt[key] < 300 then return end
    FleetRecoveryFailureLogAt[key] = now
    print(('[cm-law:fleet] vehicle_id %s recovery: %s'):format(tostring(vehicleId or 'unknown'), tostring(reason or 'unknown')))
end

local function withFleetRecoveryLock(vehicleId, callback)
    vehicleId = tonumber(vehicleId)
    if not vehicleId or vehicleId <= 0 or type(callback) ~= 'function' then return false, 'invalid_vehicle_id' end
    if FleetRecoveryLocks[vehicleId] then return false, 'recovery_in_progress' end
    FleetRecoveryLocks[vehicleId] = true
    local results = table.pack(pcall(callback))
    FleetRecoveryLocks[vehicleId] = nil
    if not results[1] then
        logFleetRecoveryFailure(vehicleId, 'recovery_exception')
        return false, 'recovery_exception'
    end
    return table.unpack(results, 2, results.n)
end

local function recoverPersistentFleetVehicle(src, vehicleId, spawn)
    local response = exports[VEHICLES_RESOURCE]:RecoverPersistentWorldVehicle(src, vehicleId, spawn, {
        organizationId = 'police',
    })
    if type(response) ~= 'table' then return false, 'recovery_response_invalid' end
    if response.ok ~= true then return false, tostring(response.error or 'recovery_failed') end
    return true, response.vehicle, response.mode
end

local fleetOperationBusy = false

local function persistentFleetRow(model)
    return MySQL.single.await('SELECT * FROM cm_police_fleet_vehicles WHERE model = ? LIMIT 1', { tostring(model):lower() })
end

vehicleHasOccupant = function(entity)
    entity = tonumber(entity) or 0
    if entity == 0 then return false end
    local okExists, exists = pcall(DoesEntityExist, entity)
    if not okExists or not exists then return false end
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
local function recallPoliceFleetVehicleUnlocked(src, actorCid, model, settings, repair)
    local vehicleId = tonumber(settings.vehicle_id)
    local servicePatch = {
        fuel = 100, engineHealth = 1000, bodyHealth = 1000,
        tankHealth = 1000, dirtLevel = 0,
        conditionState = {}, clearVisualDamage = true,
    }
    local row = exports[VEHICLES_RESOURCE]:GetVehicleById(vehicleId)
    if not row then return false, 'The persistent Police vehicle record is missing. Use recovery before recreating it.' end
    if tostring(row.owner_type or ''):lower() ~= 'organization'
        or tostring(row.owner_id or ''):lower() ~= 'police' then
        return false, 'The persistent vehicle is not owned by Police.'
    end
    local spawn = { x = tonumber(settings.spawn_x), y = tonumber(settings.spawn_y), z = tonumber(settings.spawn_z), h = tonumber(settings.spawn_h) or 0 }
    local active, activeInfo = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId)
    if active == true and vehicleHasOccupant(activeInfo and activeInfo.entity) then
        return false, 'Vehicle is currently occupied.'
    end

    if active ~= true then
        -- Manual recall repairs and refuels; startup recovery preserves state.
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
        local createMode
        ok, result, createMode = recoverPersistentFleetVehicle(src, vehicleId, spawn)
        if ok and type(result) == 'table' and result.reused == true then
            ok, result = exports[VEHICLES_RESOURCE]:RecallWorldVehicle(vehicleId, src, spawn)
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
    if type(info) == 'table' and tonumber(info.entity) then
        local entity = tonumber(info.entity)
        pcall(function()
            if DoesEntityExist(entity) then
                local state = Entity(entity).state
                state:set('cmPoliceFleet', {
                    model = model, vehicleId = vehicleId,
                    minTier = tonumber(settings.min_tier) or 0,
                    ready = state.cmConditionReady == true,
                }, true)
            end
        end)
    end
    local catalogRow = resolveCatalogRow(model)
    if type(info) == 'table' and catalogRow then TriggerClientEvent('cm-police:client:applyFleetMods', src, info.netId, decode(catalogRow.mods)) end
    return true, ('%s returned to its assigned parking space.'):format(row.label or model)
end

local function recallFleetVehicleCore(src, actorCid, model, settings, repair)
    return withFleetRecoveryLock(tonumber(settings and settings.vehicle_id), function()
        return recallPoliceFleetVehicleUnlocked(src, actorCid, model, settings, repair)
    end)
end

local function spawnPersistent(src, actor, actorCid, model, repair)
    local settings = persistentFleetRow(model)
    if not settings or not tonumber(settings.vehicle_id) then return false, 'Set this vehicle location first.' end
    if not PoliceLegacyDbBoolean(settings.enabled) then return false, 'That Police vehicle is disabled.' end
    if not PoliceLegacyDbBoolean(actor.is_leader) and (tonumber(actor.tier) or 0) < (tonumber(settings.min_tier) or 0) then return false, 'Your rank cannot use this vehicle.' end
    return recallFleetVehicleCore(src, actorCid, model, settings, repair)
end

lib.callback.register('cm-police:server:spawnFleetVehicle', function(src, model)
    return false, 'Police fleet vehicles are already parked at their configured locations.'
end)

lib.callback.register('cm-police:server:recallAllFleetVehicles', function(src)
    local actor, actorCid, err = actorFor(src)
    if not canManagePoliceFleet(actor) then
        return false, err or 'Your rank cannot recall the Police fleet.'
    end
    if fleetOperationBusy then return false, 'Another fleet recall is running.' end
    fleetOperationBusy = true
    local rows = MySQL.query.await('SELECT model FROM cm_police_fleet_vehicles WHERE enabled = 1 AND vehicle_id IS NOT NULL ORDER BY model') or {}
    local recalled, occupied, failed = 0, 0, 0
    for _, row in ipairs(rows) do
        local ok, message = spawnPersistent(src, actor, actorCid, row.model, true)
        if ok then recalled = recalled + 1
        elseif tostring(message or ''):lower():find('occupied', 1, true) then occupied = occupied + 1
        else failed = failed + 1 end
        Wait(0)
    end
    fleetOperationBusy = false
    log(actorCid, 'fleet_recalled_all', { recalled = recalled, occupied = occupied, failed = failed })
    local summary = ('%d vehicles returned. %d occupied vehicles skipped.'):format(recalled, occupied)
    if failed > 0 then summary = summary .. (' %d could not be returned.'):format(failed) end
    return failed == 0, summary
end)

lib.callback.register('cm-police:server:recallFleetVehicle', function(src, model)
    local actor, actorCid, err = actorFor(src)
    if not canManagePoliceFleet(actor) then return false, err or 'Your rank cannot recall Police fleet vehicles.' end
    model = tostring(model or ''):lower()
    local settings = model ~= '' and persistentFleetRow(model) or nil
    if not settings or not PoliceLegacyDbBoolean(settings.enabled) or not tonumber(settings.vehicle_id) then return false, 'Police fleet vehicle is not enabled or configured.' end
    if fleetOperationBusy then return false, 'Another Police fleet recall is running.' end
    fleetOperationBusy = true
    local ok, message = recallFleetVehicleCore(src, actorCid, model, settings, true)
    fleetOperationBusy = false
    if ok then log(actorCid, 'fleet_vehicle_recalled', { model = model, vehicleId = tonumber(settings.vehicle_id) }) end
    return ok, message
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

local function policeAdmin(src)
    local ok, allowed = pcall(function() return exports[PoliceConfig.AdminResource]:HasPermission(src, PoliceConfig.AdminPermission) end)
    return ok and allowed == true
end

exports('PoliceLegacyAdminGetFleet', function(src)
    if not policeAdmin(tonumber(src)) then return { ok = false, error = 'Permission denied.' } end
    local settings, vehicles, seen = fleetSettingsByModel(), {}, {}
    for _, row in ipairs(getPoliceCatalog()) do
        seen[tostring(row.model):lower()] = true
        vehicles[#vehicles + 1] = mergedRow(row, settings[tostring(row.model):lower()])
    end
    for modelKey, settingsRow in pairs(settings) do
        if not seen[modelKey] then
            local info = getVehicleCatalogInfo(modelKey) or { model = modelKey, label = modelKey, category = 'Fleet' }
            vehicles[#vehicles + 1] = mergedRow(info, settingsRow)
        end
    end
    return { ok = true, vehicles = vehicles }
end)

exports('PoliceLegacyAdminConfigureFleetVehicle', function(src, _, data)
    src, data = tonumber(src), type(data) == 'table' and data or {}
    if not policeAdmin(src) then return false, 'Permission denied.' end
    local model = tostring(data.model or ''):lower()
    if not resolveCatalogRow(model) then return false, 'Unknown vehicle model.' end
    local row = MySQL.single.await('SELECT model,vehicle_id,location_configured FROM cm_police_fleet_vehicles WHERE model = ? LIMIT 1', { model })
    if not row or not PoliceLegacyDbBoolean(row.location_configured) then return false, 'Set this vehicle location before enabling it.' end
    if data.enabled ~= true and tonumber(row.vehicle_id) then
        local active, info = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(tonumber(row.vehicle_id))
        if active and vehicleHasOccupant(info and info.entity) then return false, 'Vehicle is currently occupied.' end
        if active then
            local removed, why = exports[VEHICLES_RESOURCE]:DeleteSpawnedVehicle(tonumber(row.vehicle_id))
            if removed ~= true then return false, tostring(why or 'Could not safely disable the Police vehicle.') end
        end
    end
    local tier = math.max(0, math.min(100, math.floor(tonumber(data.minTier) or 0)))
    MySQL.update.await('UPDATE cm_police_fleet_vehicles SET enabled = ?, min_tier = ?, updated_by = ? WHERE model = ?',
        { data.enabled == true and 1 or 0, tier, tostring(cid(src) or 'admin'), model })
    return true, 'Police fleet vehicle configuration saved.'
end)

-- Admin-only bridge for rn-vehicleshop's /managevehicle "Give to organization"
-- button: lets an admin drop a freshly granted persistent vehicle straight
-- into the Police Fleet (skipping the manual spawn+drive+H flow) at the
-- admin's current position. Mirrors cm-gang:LinkGrantedOrganizationVehicle's
-- contract, but there is no matching rollback here -- cm-vehicles'
-- DeleteOrganizationVehicle is cm-gang-only -- so a failure just leaves the
-- vehicle un-linked (still a normal Police-owned vehicle) rather than
-- deleted; rn-vehicleshop reports that as a partial success, never a hard
-- failure, since the grant itself already succeeded. Named distinctly from
-- server/vehicles.lua's generic LinkGrantedFleetVehicle (Army/Sheriff/SAHP/
-- FIB) -- both live in the cm-law resource's shared export table, so a
-- shared name would have the later-loaded one silently overwrite the other.
exports('LinkGrantedPoliceFleetVehicle', function(src, model, vehicleId, minTier)
    if GetInvokingResource() ~= 'rn-vehicleshop' then return false, 'untrusted_caller' end
    src, vehicleId = tonumber(src), tonumber(vehicleId)
    model = tostring(model or ''):lower()
    if not src or src <= 0 or not vehicleId or model == '' then return false, 'invalid_request' end
    if not policeAdmin(src) then return false, 'permission_denied' end
    if not resolveCatalogRow(model) then return false, 'model_unknown' end

    if FleetLocationBusy[model] then return false, 'fleet_slot_busy' end
    FleetLocationBusy[model] = true
    local existing = MySQL.single.await('SELECT location_configured FROM cm_police_fleet_vehicles WHERE model = ? LIMIT 1', { model })
    if existing and PoliceLegacyDbBoolean(existing.location_configured) then
        FleetLocationBusy[model] = nil
        return false, 'model_already_configured'
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then FleetLocationBusy[model] = nil; return false, 'admin_not_loaded' end
    local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local okClass, classId = pcall(GetVehicleClassFromName, GetHashKey(model))
    local kind = okClass and classId == 15 and 'helicopter' or 'car'
    minTier = math.max(0, math.min(100, math.floor(tonumber(minTier) or 0)))

    if exports[VEHICLES_RESOURCE]:EnsureOrganizationOwnership(vehicleId, 'police') ~= true then
        FleetLocationBusy[model] = nil
        return false, 'ownership_assign_failed'
    end
    MySQL.insert.await([[
        INSERT INTO cm_police_fleet_vehicles (model, vehicle_id, kind, min_tier, enabled, location_configured, spawn_x, spawn_y, spawn_z, spawn_h, updated_by)
        VALUES (?, ?, ?, ?, 1, 1, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            vehicle_id = VALUES(vehicle_id), kind = VALUES(kind), min_tier = VALUES(min_tier), enabled = 1,
            location_configured = 1, spawn_x = VALUES(spawn_x), spawn_y = VALUES(spawn_y),
            spawn_z = VALUES(spawn_z), spawn_h = VALUES(spawn_h), updated_by = VALUES(updated_by)
    ]], { model, vehicleId, kind, minTier, coords.x, coords.y, coords.z, heading, tostring(cid(src) or 'admin') })
    FleetLocationBusy[model] = nil

    exports[VEHICLES_RESOURCE]:TransitionVehicleLocation(vehicleId, 'JOB_GARAGE', { ref = 'police', reason = 'police_fleet_vehicle_granted', actorCharacterId = cid(src) })
    log(cid(src), 'fleet_vehicle_granted_linked', { model = model, vehicleId = vehicleId, minTier = minTier })
    return true, 'linked'
end)

exports('PoliceLegacyAdminBeginFleetPlacement', function(src, _, model)
    local ok, result = beginFleetLocationEdit(tonumber(src), model, true)
    return ok, result
end)

exports('PoliceLegacyAdminResetFleetLocation', function(src, _, model)
    src, model = tonumber(src), tostring(model or ''):lower()
    if not policeAdmin(src) then return false, 'Permission denied.' end
    local changed = MySQL.update.await('UPDATE cm_police_fleet_vehicles SET enabled = 0, location_configured = 0, updated_by = ? WHERE model = ?', { tostring(cid(src) or 'admin'), model })
    if tonumber(changed) == 0 then return false, 'That Police vehicle has no saved location.' end
    removeActiveInstance(model)
    return true, 'Police fleet location disabled; persistent vehicle identity was preserved. Set a new location to reactivate it.'
end)

-- ── Auto-respawn on server (re)start ─────────────────────────────────────
-- A resource restart wipes cm-vehicles' in-memory spawn registry, so each
-- enabled persistent fleet entry is reconciled automatically without requiring
-- a connected player. Unsupported streamed models wait for a suitable bucket-0
-- client. This is server restoration, not a rank/tier/on-duty-gated action.
local fleetAutoRespawnRunning = false
local queuedFleetRecoverySource = nil

local function stampPoliceFleet(vehicleId, model, settings)
    local okInfo, active, info = pcall(function()
        return exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId)
    end)
    if not okInfo or active ~= true or type(info) ~= 'table' then return false end
    local entity = tonumber(info.entity) or 0
    if entity == 0 then return false end
    local okState, exists, ready = pcall(function()
        if not DoesEntityExist(entity) then return false, false end
        local state = Entity(entity).state
        local conditionReady = state.cmConditionReady == true
        state:set('cmPoliceFleet', {
            model = model, vehicleId = vehicleId,
            minTier = tonumber(settings.min_tier) or 0,
            ready = conditionReady,
        }, true)
        return true, conditionReady
    end)
    return okState and exists == true, ready == true
end

local function reconcilePoliceFleetRow(src, model, settings)
    local vehicleId = tonumber(settings and settings.vehicle_id)
    if not vehicleId then return false, 'unconfigured' end
    local ok, result, mode = withFleetRecoveryLock(vehicleId, function()
        local latest = persistentFleetRow(model)
        if not latest or not PoliceLegacyDbBoolean(latest.enabled)
            or not PoliceLegacyDbBoolean(latest.location_configured)
            or tonumber(latest.vehicle_id) ~= vehicleId then return false, 'configuration_changed' end
        local row = exports[VEHICLES_RESOURCE]:GetVehicleById(vehicleId)
        if not row then return false, 'vehicle_not_found' end
        if tostring(row.owner_type or ''):lower() ~= 'organization'
            or tostring(row.owner_id or ''):lower() ~= 'police' then
            logFleetRecoveryFailure(vehicleId, 'organization_ownership_mismatch')
            return false, 'organization_ownership_mismatch'
        end

        local active, info = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId)
        if active == true and type(info) == 'table' then
            local stamped, ready = stampPoliceFleet(vehicleId, model, latest)
            return true, 'existing'
        end

        local spawn = {
            x = tonumber(latest.spawn_x), y = tonumber(latest.spawn_y),
            z = tonumber(latest.spawn_z), h = tonumber(latest.spawn_h) or 0,
        }
        local spawned, details, spawnMode = recoverPersistentFleetVehicle(src, vehicleId, spawn)
        if spawned then
            stampPoliceFleet(vehicleId, model, latest)
            return true, spawnMode or 'server'
        end
        return false, details
    end)
    return ok == true, result, mode
end

local function autoRespawnFleet(triggerSrc, reportSummary)
    triggerSrc = isSuitableFleetRecoveryClient(triggerSrc) and tonumber(triggerSrc) or nil
    if fleetAutoRespawnRunning then
        if triggerSrc then queuedFleetRecoverySource = triggerSrc end
        return
    end
    fleetAutoRespawnRunning = true

    CreateThread(function()
        local deadline = GetGameTimer() + 30000
        local function dependenciesReady()
            if GetResourceState(VEHICLES_RESOURCE) ~= 'started' then return false end
            if type(PoliceDatabaseReady) ~= 'function' then return false end
            local ok, ready = pcall(PoliceDatabaseReady)
            return ok and ready == true
        end
        while not dependenciesReady() and GetGameTimer() < deadline do Wait(500) end
        if not dependenciesReady() then
            fleetAutoRespawnRunning = false
            logFleetRecoveryFailure(0, 'police_fleet_dependencies_not_ready')
            return
        end
        -- cm-vehicles owns its one-time registry reconciliation. Both Law
        -- fleet scripts scanning globally here would race DeleteEntity during
        -- duplicate cleanup; per-vehicle recovery below also scans by ID.
        Wait(2000)
        local rows = MySQL.query.await([[SELECT model FROM cm_police_fleet_vehicles
            WHERE enabled = 1 AND location_configured = 1 AND vehicle_id IS NOT NULL ORDER BY model]]) or {}
        local existing, serverSpawned, clientSpawned, waiting, failed = 0, 0, 0, 0, 0
        for _, row in ipairs(rows) do
            local settings = persistentFleetRow(row.model)
            if settings then
                local ok, result = reconcilePoliceFleetRow(triggerSrc, row.model, settings)
                if ok then
                    if result == 'existing' then existing = existing + 1
                    elseif result == 'client' then clientSpawned = clientSpawned + 1
                    else serverSpawned = serverSpawned + 1 end
                elseif result == 'waiting_for_client' then waiting = waiting + 1
                elseif result ~= 'recovery_in_progress' and result ~= 'configuration_changed' then failed = failed + 1 end
            end
            Wait(0)
        end
        if reportSummary then
            print(('[cm-law:fleet] recovery complete police: %d existing, %d server-spawned, %d client-spawned, %d waiting, %d failed')
                :format(existing, serverSpawned, clientSpawned, waiting, failed))
        end
        fleetAutoRespawnRunning = false
        local queued = queuedFleetRecoverySource
        queuedFleetRecoverySource = nil
        if queued then autoRespawnFleet(queued, false) end
    end)
end

AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    autoRespawnFleet(src, false)
end)

exports('PoliceLegacyAdminRecallFleetVehicle', function(src, _, model)
    src, model = tonumber(src), tostring(model or ''):lower()
    if not policeAdmin(src) then return false, 'Permission denied.' end
    local settings = persistentFleetRow(model)
    if not settings or not PoliceLegacyDbBoolean(settings.enabled) or not tonumber(settings.vehicle_id) then return false, 'Police fleet vehicle is not enabled or configured.' end
    if fleetOperationBusy then return false, 'Another Police fleet recall is running.' end
    fleetOperationBusy = true
    local ok, message = recallFleetVehicleCore(src, tostring(cid(src) or 'admin'), model, settings, true)
    fleetOperationBusy = false
    return ok, message
end)

exports('PoliceLegacyAdminRecallAllFleetVehicles', function(src, _)
    src = tonumber(src)
    if not policeAdmin(src) then return false, 'Permission denied.' end
    if fleetOperationBusy then return false, 'Another Police fleet recall is running.' end
    fleetOperationBusy = true
    local rows = MySQL.query.await('SELECT model FROM cm_police_fleet_vehicles WHERE enabled=1 AND location_configured=1 AND vehicle_id IS NOT NULL ORDER BY model') or {}
    local recalled, failed = 0, 0
    for _, row in ipairs(rows) do
        local settings = persistentFleetRow(row.model)
        local ok = settings and recallFleetVehicleCore(src, tostring(cid(src) or 'admin'), row.model, settings, true)
        if ok then recalled = recalled + 1 else failed = failed + 1 end
        Wait(0)
    end
    fleetOperationBusy = false
    return failed == 0, ('Recalled %d Police vehicles; %d could not be moved safely.'):format(recalled, failed)
end)

exports('PoliceLegacyAdminTuneFleetVehicle', function(src, _, model)
    src, model = tonumber(src), tostring(model or ''):lower()
    if not policeAdmin(src) then return false, 'Permission denied.' end
    local settings = persistentFleetRow(model)
    if not settings or not PoliceLegacyDbBoolean(settings.enabled) or not tonumber(settings.vehicle_id) then return false, 'Police fleet vehicle is not enabled or configured.' end
    if GetResourceState(SHOP_RESOURCE) ~= 'started' then return false, 'Manage Vehicle is unavailable.' end
    TriggerClientEvent('rn-vehicleshop:client:requestAdmin', src, 'manage', model)
    return true, 'Manage Vehicle opened for this Police fleet model. Saved appearance changes will update its persistent fleet record.'
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() and resource ~= VEHICLES_RESOURCE then return end
    CreateThread(function()
        Wait(2500)
        autoRespawnFleet(nil, true)
    end)
end)

CreateThread(function()
    while true do
        Wait(60000)
        autoRespawnFleet(nil, false)
    end
end)
