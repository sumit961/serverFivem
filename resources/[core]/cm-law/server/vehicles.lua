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
local vehicleHasOccupant
local mergedRow
local persistentFleetRow
local recallFleetVehicleCore

-- A character is only ever an active member of one organization, so every
-- fleet action derives its org from the caller instead of trusting a
-- client-supplied orgId.
local function actorFor(src)
    local member, characterId = activeMemberForSource(src)
    if not member then return nil, characterId, 'You are not a member of a legal organization.' end
    if member.suspended then return nil, characterId, 'Your organization access is suspended.' end
    if not LawCapabilityEnabled(member.organizationId, 'fleet') then return nil, characterId, 'Fleet is disabled for this organization.' end
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

-- Tag-agnostic fallback: a vehicle granted straight to an organization via
-- rn-vehicleshop's "Give to organization" is never toggled through that
-- org's catalog status (that would silently pull it out of the public
-- Store/Server catalog, or hand it to a different org, which a grant must
-- never do), so it will never appear in getOrgCatalog(orgId) above. This
-- looks up plain appearance (label/category/image/mods) for any catalog
-- vehicle regardless of status, used only when the model isn't tag-matched.
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

-- Prefer the org-tagged catalog row (keeps the existing appearance
-- customization workflow for anyone still using /vehicleadmin's tag), fall
-- back to the plain lookup for a grant-linked vehicle that was never tagged.
local function resolveCatalogRow(orgId, model)
    return findCatalogRow(getOrgCatalog(orgId), model) or getVehicleCatalogInfo(model)
end

local function fleetSettingsByModel(orgId)
    local rows = MySQL.query.await('SELECT * FROM cm_legal_fleet_vehicles WHERE organization_id = ?', { orgId }) or {}
    local byModel = {}
    for _, row in ipairs(rows) do byModel[tostring(row.model):lower()] = row end
    return byModel
end

local function adminFleetRows(orgId)
    orgId = validOrgId(orgId)
    if not orgId then return { ok = false, error = 'Unknown organization.' } end
    local settings, out, seen = fleetSettingsByModel(orgId), {}, {}
    local function consider(catalogRow, row)
        local merged = mergedRow and mergedRow(catalogRow, row) or {
            model = catalogRow.model, label = catalogRow.label, category = catalogRow.category,
            enabled = row and dbBoolean(row.enabled) or false,
            minTier = row and tonumber(row.min_tier) or 0,
            configured = row and row.vehicle_id ~= nil and dbBoolean(row.location_configured) or false,
        }
        merged.savedLocation = row and row.spawn_x and { x = row.spawn_x, y = row.spawn_y, z = row.spawn_z, heading = row.spawn_h } or nil
        out[#out + 1] = merged
    end
    for _, catalogRow in ipairs(getOrgCatalog(orgId)) do
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
    return { ok = true, organizationId = orgId, vehicles = out }
end

exports('GetVehicleAccessDecision', function(characterId, vehicleId, action)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'not_legal_fleet_vehicle' end
    local settings = MySQL.single.await([[SELECT organization_id, min_tier FROM cm_legal_fleet_vehicles
        WHERE vehicle_id = ? AND enabled = 1 LIMIT 1]], { vehicleId })
    if not settings then
        if type(PoliceLegacyVehicleAccessDecision) == 'function' then
            return PoliceLegacyVehicleAccessDecision(characterId, vehicleId, action)
        end
        return false, 'not_legal_fleet_vehicle'
    end
    local orgId = validOrgId(settings.organization_id)
    local member = orgId and memberFor(tostring(characterId or ''), orgId) or nil
    if not member then return false, 'not_organization_member' end
    local required = tonumber(settings.min_tier) or 0
    local ok, reason = FleetVehicleAccessDecision(member, required, action, {
        protected = 'legal_fleet_protected', notOnDuty = 'organization_not_on_duty',
        rankTooLow = 'organization_rank_too_low', ok = 'legal_fleet',
    })
    if not ok then return false, reason end
    return true, reason, { organization = orgId, vehicleId = vehicleId, requiredTier = required }
end)

exports('CanUseOrganizationVehicle', function(src, vehicleId, action)
    local characterId = characterIdFor(tonumber(src))
    if not characterId then return false, 'character_not_loaded' end
    return exports[GetCurrentResourceName()]:GetVehicleAccessDecision(characterId, vehicleId, action)
end)
exports('CanUseOrganisationVehicle', function(src, vehicleId, action)
    return exports[GetCurrentResourceName()]:CanUseOrganizationVehicle(src, vehicleId, action)
end)

mergedRow = function(catalogRow, settingsRow)
    local orgId = settingsRow and tostring(settingsRow.organization_id or '') or ''
    local key = orgId .. ':' .. tostring(catalogRow.model):lower()
    local merged = {
        model = catalogRow.model,
        label = catalogRow.label,
        category = catalogRow.category,
        image = catalogRow.image,
        vehicleId = settingsRow and tonumber(settingsRow.vehicle_id) or nil,
        minTier = settingsRow and math.floor(tonumber(settingsRow.min_tier) or 0) or 0,
        enabled = settingsRow and dbBoolean(settingsRow.enabled) or false,
        configured = settingsRow ~= nil and settingsRow.vehicle_id ~= nil and dbBoolean(settingsRow.location_configured),
    }
    local vehicleId = settingsRow and tonumber(settingsRow.vehicle_id)
    local active, info = false, nil
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

exports('AdminGetFleet', function(src, orgId)
    if not adminAllowed(tonumber(src)) then return { ok = false, error = 'Permission denied.' } end
    return adminFleetRows(orgId)
end)

exports('AdminConfigureFleetVehicle', function(src, orgId, data)
    src, orgId, data = tonumber(src), validOrgId(orgId), type(data) == 'table' and data or {}
    if not adminAllowed(src) then return false, 'Permission denied.' end
    local model = tostring(data.model or ''):lower()
    if not orgId or not resolveCatalogRow(orgId, model) then return false, 'Unknown organization vehicle.' end
    local tier = math.max(0, math.min(100, math.floor(tonumber(data.minTier) or 0)))
    local existing = MySQL.single.await('SELECT model,vehicle_id,location_configured FROM cm_legal_fleet_vehicles WHERE organization_id=? AND model=?', { orgId, model })
    if not existing or not dbBoolean(existing.location_configured) then return false, 'Set the vehicle location before enabling it.' end
    if data.enabled ~= true and tonumber(existing.vehicle_id) then
        local active, info = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(tonumber(existing.vehicle_id))
        if active and vehicleHasOccupant(info and info.entity) then return false, 'Vehicle is currently occupied.' end
        if active then
            local removed, why = exports[VEHICLES_RESOURCE]:DeleteSpawnedVehicle(tonumber(existing.vehicle_id))
            if removed ~= true then return false, tostring(why or 'Could not safely disable the fleet vehicle.') end
        end
    end
    MySQL.update.await('UPDATE cm_legal_fleet_vehicles SET enabled=?, min_tier=?, updated_by=? WHERE organization_id=? AND model=?',
        { data.enabled == true and 1 or 0, tier, characterIdFor(src), orgId, model })
    return true, 'Fleet vehicle configuration saved.'
end)

exports('AdminResetFleetLocation', function(src, orgId, model)
    src, orgId, model = tonumber(src), validOrgId(orgId), tostring(model or ''):lower()
    if not adminAllowed(src) then return false, 'Permission denied.' end
    if not orgId or model == '' then return false, 'Invalid vehicle.' end
    local row = MySQL.single.await('SELECT vehicle_id FROM cm_legal_fleet_vehicles WHERE organization_id=? AND model=?', { orgId, model })
    if not row then return true, 'Fleet location was already reset.' end
    if tonumber(row.vehicle_id) then pcall(function() exports[VEHICLES_RESOURCE]:DeleteSpawnedVehicle(tonumber(row.vehicle_id)) end) end
    MySQL.update.await([[UPDATE cm_legal_fleet_vehicles SET enabled=0, location_configured=0, spawn_x=NULL,spawn_y=NULL,spawn_z=NULL,spawn_h=0
        WHERE organization_id=? AND model=?]], { orgId, model })
    return true, 'Fleet location reset; persistent vehicle identity was preserved.'
end)

-- Admin-only bridge for rn-vehicleshop's /managevehicle "Give to organization"
-- button, generalized across every non-Police cm-law organization (Army,
-- Sheriff, SAHP, FIB, ...): lets an admin drop a freshly granted persistent
-- vehicle straight into that organization's Motor Pool (skipping the manual
-- spawn+drive+H flow) at the admin's current position. Mirrors
-- cm-gang:LinkGrantedOrganizationVehicle's contract and the Police-specific
-- LinkGrantedPoliceFleetVehicle in embedded/police/server/vehicles.lua
-- (kept as a separate export name so the two don't silently overwrite each
-- other in this resource's shared export table). No matching rollback exists
-- here either -- cm-vehicles' DeleteOrganizationVehicle is cm-gang-only --
-- so a failure just leaves the vehicle un-linked (still a normal org-owned
-- vehicle) rather than deleted; rn-vehicleshop reports that as a partial
-- success, never a hard failure, since the grant itself already succeeded.
exports('LinkGrantedFleetVehicle', function(src, orgId, model, vehicleId, minTier)
    if GetInvokingResource() ~= 'rn-vehicleshop' then return false, 'untrusted_caller' end
    src, vehicleId = tonumber(src), tonumber(vehicleId)
    orgId = validOrgId(orgId)
    model = tostring(model or ''):lower()
    if not src or src <= 0 or not vehicleId or not orgId or model == '' then return false, 'invalid_request' end
    if not adminAllowed(src) then return false, 'permission_denied' end
    if not resolveCatalogRow(orgId, model) then return false, 'model_unknown' end

    local lockKey = orgId .. ':' .. model
    if FleetLocationBusy[lockKey] then return false, 'fleet_slot_busy' end
    FleetLocationBusy[lockKey] = true
    local existing = MySQL.single.await('SELECT location_configured FROM cm_legal_fleet_vehicles WHERE organization_id = ? AND model = ? LIMIT 1', { orgId, model })
    if existing and dbBoolean(existing.location_configured) then
        FleetLocationBusy[lockKey] = nil
        return false, 'model_already_configured'
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then FleetLocationBusy[lockKey] = nil; return false, 'admin_not_loaded' end
    local coords, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local okClass, classId = pcall(GetVehicleClassFromName, GetHashKey(model))
    local kind = okClass and classId == 15 and 'helicopter' or 'car'
    minTier = math.max(0, math.min(100, math.floor(tonumber(minTier) or 0)))

    if exports[VEHICLES_RESOURCE]:EnsureOrganizationOwnership(vehicleId, orgId) ~= true then
        FleetLocationBusy[lockKey] = nil
        return false, 'ownership_assign_failed'
    end
    MySQL.insert.await([[
        INSERT INTO cm_legal_fleet_vehicles (organization_id, model, vehicle_id, kind, min_tier, enabled, location_configured, spawn_x, spawn_y, spawn_z, spawn_h, updated_by)
        VALUES (?, ?, ?, ?, ?, 1, 1, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            vehicle_id = VALUES(vehicle_id), kind = VALUES(kind), min_tier = VALUES(min_tier), enabled = 1,
            location_configured = 1, spawn_x = VALUES(spawn_x), spawn_y = VALUES(spawn_y),
            spawn_z = VALUES(spawn_z), spawn_h = VALUES(spawn_h), updated_by = VALUES(updated_by)
    ]], { orgId, model, vehicleId, kind, minTier, coords.x, coords.y, coords.z, heading, characterIdFor(src) })
    FleetLocationBusy[lockKey] = nil

    exports[VEHICLES_RESOURCE]:TransitionVehicleLocation(vehicleId, 'JOB_GARAGE', { ref = 'law', reason = 'law_fleet_vehicle_granted', actorCharacterId = characterIdFor(src) })
    logActivity(orgId, characterIdFor(src), 'fleet_vehicle_granted_linked', { model = model, vehicleId = vehicleId, minTier = minTier })
    return true, 'linked'
end)

lib.callback.register('cm-law:server:fleetCatalog', function(src)
    local actor = select(1, actorFor(src))
    if not actor then return nil end
    local manage = actor.isLeader or actor.permissions['law.fleet'] == true
    local spawn = actor.isLeader or actor.permissions['law.vehicle'] == true
    if not manage and not spawn then return { vehicles = {}, canManage = false } end

    local catalog = getOrgCatalog(actor.organizationId)
    local settings = fleetSettingsByModel(actor.organizationId)
    local tier = math.floor(tonumber(actor.tier) or 0)

    local out = {}
    local seen = {}
    local function consider(catalogRow, settingsRow)
        local merged = mergedRow(catalogRow, settingsRow)
        if manage then
            out[#out + 1] = merged
        elseif merged.configured and merged.enabled and (actor.isLeader or tier >= merged.minTier) then
            out[#out + 1] = merged
        end
    end
    for _, catalogRow in ipairs(catalog) do
        local modelKey = tostring(catalogRow.model):lower()
        seen[modelKey] = true
        consider(catalogRow, settings[modelKey])
    end
    -- Vehicles linked via a "Give to organization" grant are never tagged in
    -- the shared catalog (see resolveCatalogRow above), so include them here
    -- from their own settings row.
    for modelKey, settingsRow in pairs(settings) do
        if not seen[modelKey] then
            local info = getVehicleCatalogInfo(modelKey) or { model = modelKey, label = modelKey, category = 'Fleet' }
            consider(info, settingsRow)
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return { vehicles = out, canManage = manage }
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

local function beginFleetLocationEdit(src, model, adminOrgId)
    local actor, actorCid, err = actorFor(src)
    local admin = adminOrgId ~= nil and adminAllowed(src)
    if admin then actor = { organizationId = validOrgId(adminOrgId), isLeader = true, permissions = {} }; actorCid = characterIdFor(src) end
    if not actor or not actor.organizationId or not (actor.isLeader or actor.permissions['law.fleet'] == true) then return false, err or 'Your rank cannot manage this organization\'s fleet.' end
    model = tostring(model or ''):lower()
    local catalogRow = resolveCatalogRow(actor.organizationId, model)
    local settings = MySQL.single.await('SELECT vehicle_id FROM cm_legal_fleet_vehicles WHERE organization_id = ? AND model = ? AND enabled = 1 AND location_configured = 1 LIMIT 1', { actor.organizationId, model })
    local vehicleId = settings and tonumber(settings.vehicle_id)
    if not catalogRow or not vehicleId then return false, 'Link this persistent vehicle through Manage Vehicle first.' end
    local ped = GetPlayerPed(src)
    local vehicle = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= ped then return false, 'Sit in the configured fleet vehicle as its driver first.' end
    if GetHashKey(catalogRow.model) ~= GetEntityModel(vehicle) or tonumber(Entity(vehicle).state.cmVehicleId) ~= vehicleId then return false, 'This is not the configured persistent fleet vehicle.' end
    local active, info = exports[VEHICLES_RESOURCE]:GetSpawnedVehicleInfo(vehicleId)
    if active ~= true or type(info) ~= 'table' or tonumber(info.entity) ~= tonumber(vehicle) then return false, 'The persistent vehicle registry does not match this entity.' end
    if GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(src) then return false, 'Vehicle routing context does not match.' end
    if not rateLimit(src, 'law_fleet_edit', 1500) then return false, 'Please wait.' end
    local coords, heading = GetEntityCoords(vehicle), GetEntityHeading(vehicle)
    if math.abs(coords.x) > 20000 or math.abs(coords.y) > 20000 or coords.z < -500 or coords.z > 5000 or heading < 0 or heading >= 360 then return false, 'Vehicle location is outside supported world bounds.' end
    local changed = MySQL.update.await([[UPDATE cm_legal_fleet_vehicles SET spawn_x=?,spawn_y=?,spawn_z=?,spawn_h=?,updated_by=?
        WHERE organization_id=? AND model=? AND vehicle_id=? AND enabled=1 AND location_configured=1]],
        { coords.x, coords.y, coords.z, heading, actorCid, actor.organizationId, model, vehicleId })
    if not tonumber(changed) or tonumber(changed) <= 0 then return false, 'Fleet configuration changed; location was not saved.' end
    logActivity(actor.organizationId, actorCid, 'fleet_vehicle_location_saved', { model = model, label = catalogRow.label, vehicleId = vehicleId })
    return true, ('%s location saved for permanent vehicle #%d.'):format(catalogRow.label, vehicleId)
end

lib.callback.register('cm-law:server:beginFleetLocationEdit', function(src, model)
    return beginFleetLocationEdit(src, model, nil)
end)

exports('AdminBeginFleetPlacement', function(src, orgId, model)
    src, orgId = tonumber(src), validOrgId(orgId)
    if not adminAllowed(src) or not orgId then return false, 'Permission denied.' end
    local ok, result = beginFleetLocationEdit(src, model, orgId)
    if ok and type(result) == 'table' then TriggerClientEvent('cm-law:client:adminFleetPlacement', src, result) end
    return ok, type(result) == 'table' and result.message or result
end)

lib.callback.register('cm-law:server:cancelFleetLocationEdit', function(src)
    local placement = FleetPlacementBySource[src]
    if not placement then return false, 'No legal fleet placement is active.' end
    FleetPlacementBySource[src] = nil
    pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end)
    return true, 'Fleet placement cancelled.'
end)

-- Location save/update: the player must be DRIVING the exact dummy being
-- saved, so the location that gets stored is always where the car genuinely
-- is right now (triggered by the H keybind, never by the NUI, and
-- coordinates always come from the server's own view of the vehicle).
lib.callback.register('cm-law:server:saveFleetVehicleLocation', function(src, model, kind)
    local actor, actorCid, err = actorFor(src)
    local placement = FleetPlacementBySource[src]
    if placement and tonumber(placement.expiresAt) and os.time() >= tonumber(placement.expiresAt) then
        FleetPlacementBySource[src] = nil
        pcall(function() exports[VEHICLES_RESOURCE]:DeleteAdminVehicle(placement.plate) end)
        return false, 'That fleet placement expired. Start it again.'
    end
    if placement and placement.admin == true and adminAllowed(src) then
        actor = { organizationId = validOrgId(placement.organizationId), isLeader = true, permissions = {} }
        actorCid = characterIdFor(src)
    end
    if not actor or not (actor.isLeader or actor.permissions['law.fleet'] == true) then
        return false, err or 'Your rank cannot manage this organization\'s fleet.'
    end
    if not rateLimit(src, 'law_fleet_save', 2000) then return false, 'Please wait.' end

    model = tostring(model or ''):lower()
    local catalogRow = resolveCatalogRow(actor.organizationId, model)
    if not catalogRow then return false, 'Unknown vehicle model.' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Character is not loaded.' end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false, 'Get in the fleet vehicle first.' end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return false, 'Only the driver can save this vehicle\'s location.' end
    if GetHashKey(catalogRow.model) ~= GetEntityModel(vehicle) then return false, 'You are not driving that vehicle.' end
    placement = FleetPlacementBySource[src]
    if not placement or placement.model ~= model or placement.organizationId ~= actor.organizationId or tonumber(placement.entity) ~= tonumber(vehicle) then
        return false, 'This is not your active fleet location dummy.'
    end

    local coords = GetEntityCoords(vehicle)
    local heading = GetEntityHeading(vehicle)
    kind = placement.kind == 'helicopter' and 'helicopter' or 'car'

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
        INSERT INTO cm_legal_fleet_vehicles (organization_id, model, vehicle_id, kind, min_tier, enabled, location_configured, spawn_x, spawn_y, spawn_z, spawn_h, updated_by)
        VALUES (?, ?, ?, ?, 0, 1, 1, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            vehicle_id = VALUES(vehicle_id), kind = VALUES(kind), location_configured = 1,
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

persistentFleetRow = function(orgId, model)
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
recallFleetVehicleCore = function(src, actorCid, orgId, model, settings, repair)
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
    if active == true and vehicleHasOccupant(activeInfo and activeInfo.entity) then
        return false, 'Vehicle is currently occupied.'
    end

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
    local catalogRow = resolveCatalogRow(orgId, model)
    if type(info) == 'table' and catalogRow then TriggerClientEvent('cm-law:client:applyFleetMods', src, info.netId, catalogRow.mods) end
    return true, ('%s recalled (vehicle #%d).'):format(row.label or model, vehicleId)
end

local function spawnPersistent(src, actor, actorCid, model, repair)
    local settings = persistentFleetRow(actor.organizationId, model)
    if not settings or not tonumber(settings.vehicle_id) then return false, 'Set this vehicle\'s location first.' end
    if not dbBoolean(settings.enabled) then return false, 'That fleet vehicle is disabled.' end
    if not actor.isLeader and (tonumber(actor.tier) or 0) < (tonumber(settings.min_tier) or 0) then return false, 'Your rank cannot use this vehicle.' end
    return recallFleetVehicleCore(src, actorCid, actor.organizationId, model, settings, repair)
end

lib.callback.register('cm-law:server:spawnFleetVehicle', function(src, model)
    return false, 'Fleet vehicles are already parked at their configured locations.'
end)

exports('AdminRecallFleetVehicle', function(src, orgId, model)
    src, orgId, model = tonumber(src), validOrgId(orgId), tostring(model or ''):lower()
    if not adminAllowed(src) then return false, 'Permission denied.' end
    if not orgId or model == '' then return false, 'Invalid fleet vehicle.' end
    local settings = persistentFleetRow(orgId, model)
    if not settings or not dbBoolean(settings.enabled) or not tonumber(settings.vehicle_id) then return false, 'Fleet vehicle is not enabled or configured.' end
    if fleetOperationBusy[orgId] then return false, 'Another fleet recall is already running.' end
    fleetOperationBusy[orgId] = true
    local ok, message = recallFleetVehicleCore(src, characterIdFor(src), orgId, model, settings, true)
    fleetOperationBusy[orgId] = nil
    return ok, message
end)

exports('AdminRecallAllFleetVehicles', function(src, orgId)
    src, orgId = tonumber(src), validOrgId(orgId)
    if not adminAllowed(src) then return false, 'Permission denied.' end
    if not orgId then return false, 'Unknown organization.' end
    if fleetOperationBusy[orgId] then return false, 'Another fleet recall is already running.' end
    fleetOperationBusy[orgId] = true
    local rows = MySQL.query.await('SELECT model FROM cm_legal_fleet_vehicles WHERE organization_id=? AND enabled=1 AND location_configured=1 AND vehicle_id IS NOT NULL ORDER BY model', { orgId }) or {}
    local recalled, failed = 0, 0
    for _, row in ipairs(rows) do
        local settings = persistentFleetRow(orgId, row.model)
        local ok = settings and recallFleetVehicleCore(src, characterIdFor(src), orgId, row.model, settings, true)
        if ok then recalled = recalled + 1 else failed = failed + 1 end
        Wait(0)
    end
    fleetOperationBusy[orgId] = nil
    return failed == 0, ('Recalled %d vehicles for %s; %d could not be moved safely.'):format(recalled, orgId, failed)
end)

exports('AdminTuneFleetVehicle', function(src, orgId, model)
    src, orgId, model = tonumber(src), validOrgId(orgId), tostring(model or ''):lower()
    if not adminAllowed(src) then return false, 'Permission denied.' end
    local settings = orgId and model ~= '' and persistentFleetRow(orgId, model) or nil
    if not settings or not dbBoolean(settings.enabled) or not tonumber(settings.vehicle_id) then return false, 'Fleet vehicle is not enabled or configured.' end
    if GetResourceState(SHOP_RESOURCE) ~= 'started' then return false, 'Manage Vehicle is unavailable.' end
    TriggerClientEvent('rn-vehicleshop:client:requestAdmin', src, 'manage', model)
    return true, 'Manage Vehicle opened for this fleet model. Saved appearance changes will update its persistent fleet record.'
end)

exports('SyncFleetCatalogMods', function(src, model, mods)
    if GetInvokingResource() ~= SHOP_RESOURCE then return false, 'untrusted_caller' end
    src, model = tonumber(src), tostring(model or ''):lower()
    if not adminAllowed(src) or model == '' or type(mods) ~= 'table' then return false, 'invalid_request' end
    if GetResourceState(VEHICLES_RESOURCE) ~= 'started' then return false, 'cm-vehicles is unavailable.' end
    local rows = MySQL.query.await([[SELECT organization_id, vehicle_id FROM cm_legal_fleet_vehicles
        WHERE model=? AND enabled=1 AND location_configured=1 AND vehicle_id IS NOT NULL]], { model }) or {}
    for _, row in ipairs(MySQL.query.await([[SELECT 'police' AS organization_id, vehicle_id FROM cm_police_fleet_vehicles
        WHERE model=? AND enabled=1 AND location_configured=1 AND vehicle_id IS NOT NULL]], { model }) or {}) do
        rows[#rows + 1] = row
    end
    local saved, failed = 0, 0
    for _, row in ipairs(rows) do
        local ok = exports[VEHICLES_RESOURCE]:SaveOrganizationFleetMods(src, tonumber(row.vehicle_id), tostring(row.organization_id), model, mods)
        if ok == true then saved = saved + 1 else failed = failed + 1 end
    end
    if failed > 0 then return false, ('Catalog saved; persistent modifications updated for %d vehicle(s), %d failed.'):format(saved, failed) end
    return true, ('Persistent modifications saved for %d configured fleet vehicle(s).'):format(saved)
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

lib.callback.register('cm-law:server:recallFleetVehicle', function(src, model)
    local actor, actorCid, err = actorFor(src)
    if not actor or not (actor.isLeader or actor.permissions['law.fleet'] == true) then
        return false, err or 'Your rank cannot recall this organization\'s fleet.'
    end
    model = tostring(model or ''):lower()
    local settings = model ~= '' and persistentFleetRow(actor.organizationId, model) or nil
    if not settings or not dbBoolean(settings.enabled) or not tonumber(settings.vehicle_id) then return false, 'Fleet vehicle is not enabled or configured.' end
    if fleetOperationBusy[actor.organizationId] then return false, 'Another fleet recall is already running.' end
    fleetOperationBusy[actor.organizationId] = true
    local ok, message = recallFleetVehicleCore(src, actorCid, actor.organizationId, model, settings, true)
    fleetOperationBusy[actor.organizationId] = nil
    if ok then logActivity(actor.organizationId, actorCid, 'fleet_vehicle_recalled', { model = model, vehicleId = tonumber(settings.vehicle_id) }) end
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
local fleetAutoRespawnRunning = false

local function fleetRecoverySource(preferred)
    preferred = tonumber(preferred)
    if preferred and GetPlayerName(preferred) and GetPlayerRoutingBucket(preferred) == 0 then return preferred end
    for _, rawSrc in ipairs(GetPlayers() or {}) do
        local src = tonumber(rawSrc)
        if src and GetPlayerRoutingBucket(src) == 0 then return src end
    end
end

local function autoRespawnFleet(triggerSrc)
    if fleetAutoRespawnRunning then return end
    triggerSrc = fleetRecoverySource(triggerSrc)
    if not triggerSrc or triggerSrc <= 0 or not GetPlayerName(triggerSrc) then return end
    fleetAutoRespawnRunning = true

    CreateThread(function()
        local deadline = GetGameTimer() + 30000
        while GetResourceState(VEHICLES_RESOURCE) ~= 'started' and GetGameTimer() < deadline do Wait(500) end
        if GetResourceState(VEHICLES_RESOURCE) ~= 'started' then fleetAutoRespawnRunning = false; return end
        Wait(2000) -- let cm-vehicles rebuild its vehicle_id registry before recovery
        local rows = MySQL.query.await('SELECT organization_id, model FROM cm_legal_fleet_vehicles WHERE enabled = 1 AND location_configured = 1 AND vehicle_id IS NOT NULL ORDER BY organization_id, model') or {}
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
        fleetAutoRespawnRunning = false
    end)
end

AddEventHandler('cm-playerdata:server:characterLoaded', function(src)
    autoRespawnFleet(src)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() and resource ~= VEHICLES_RESOURCE then return end
    CreateThread(function()
        Wait(2500)
        local players = GetPlayers()
        if players and players[1] then autoRespawnFleet() end
    end)
end)

CreateThread(function()
    while true do
        Wait(60000)
        local players = GetPlayers()
        if players and players[1] then autoRespawnFleet() end
    end
end)
