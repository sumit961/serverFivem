-- ============================================================
--  cm-family | sv_vehicles.lua
--  Authoritative family vehicle sharing, rank access and session-key revocation.
--  Legal ownership remains in cm-vehicles; cm-family never changes owner_character_id.
-- ============================================================

local B = CMFamilyBridge
local KEYS = tostring(Config.VehicleKeysResource or 'cm-vehiclekeys')
local SHOP = tostring(Config.VehicleShopResource or 'rn-vehicleshop')

-- [familyId][vehicleId] = required tier.
local levelCache = {}
local imageCache = {}
-- [characterId][vehicleId] = unix time when another snapshot may be requested.
local trackCooldown = {}

local function revokeCharacterKeys(characterId, reason)
    if GetResourceState(KEYS) ~= 'started' then return 0 end
    local ok, removed = pcall(function()
        return exports[KEYS]:RevokeFamilyKeysForCharacter(tostring(characterId), reason or 'family-membership-changed')
    end)
    return ok and tonumber(removed) or 0
end

local function revokeVehicleKeys(vehicleId, familyId, reason)
    if GetResourceState(KEYS) ~= 'started' then return 0 end
    local ok, removed = pcall(function()
        return exports[KEYS]:RevokeFamilyKeysForVehicle(tonumber(vehicleId), tonumber(familyId), reason or 'family-vehicle-changed')
    end)
    return ok and tonumber(removed) or 0
end

local function revokeFamilyKeys(familyId, reason)
    if GetResourceState(KEYS) ~= 'started' then return 0 end
    local ok, removed = pcall(function()
        return exports[KEYS]:RevokeFamilyKeysForFamily(tonumber(familyId), reason or 'family-deleted')
    end)
    return ok and tonumber(removed) or 0
end

CMFamilyRevokeVehicleKeysForCharacter = revokeCharacterKeys
CMFamilyRevokeVehicleKeysForVehicle = revokeVehicleKeys
CMFamilyRevokeVehicleKeysForFamily = revokeFamilyKeys

local function ensureFamilyLoaded(familyId)
    familyId = tonumber(familyId)
    if not familyId then return end
    if levelCache[familyId] then return end
    levelCache[familyId] = {}
    for _, row in ipairs(MySQL.query.await(
        'SELECT vehicle_id, level FROM cm_family_vehicle_access WHERE family_id = ?', { familyId }) or {}) do
        local vehicleId = tonumber(row.vehicle_id)
        if vehicleId then
            levelCache[familyId][vehicleId] = tonumber(row.level) or Config.DefaultVehicleLevel
        end
    end
end

function GetVehicleLevel(familyId, vehicleId)
    familyId, vehicleId = tonumber(familyId), tonumber(vehicleId)
    if not familyId or not vehicleId then return Config.DefaultVehicleLevel end
    ensureFamilyLoaded(familyId)
    return levelCache[familyId][vehicleId] or Config.DefaultVehicleLevel
end
exports('GetFamilyVehicleLevel', GetVehicleLevel)

local function isSharedFamilyVehicle(familyId, vehicleId)
    familyId, vehicleId = tonumber(familyId), tonumber(vehicleId)
    if not familyId or not vehicleId then return false end

    for _, vehicle in ipairs(B.GetFamilyVehicles(familyId)) do
        if tonumber(vehicle.id or vehicle.vehicle_id) == vehicleId then return true end
    end

    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT 1 AS shared
            FROM cm_house_shared_vehicles sh
            JOIN cm_houses house ON house.id = sh.house_id
            WHERE sh.vehicle_id = ? AND house.family_id = ?
            LIMIT 1
        ]], { vehicleId, familyId })
    end)
    return ok and row ~= nil
end

local function catalogImage(model)
    model = tostring(model or ''):lower()
    if model == '' then return nil end
    if imageCache[model] ~= nil then
        return imageCache[model] ~= false and imageCache[model] or nil
    end

    if GetResourceState(SHOP) == 'started' then
        local ok, image = pcall(function()
            return exports[SHOP]:GetVehicleImage(model)
        end)
        if ok and image and tostring(image) ~= '' then
            imageCache[model] = tostring(image)
            return imageCache[model]
        end
    end

    local ok, image = pcall(function()
        return MySQL.scalar.await(
            'SELECT image FROM cm_vehicle_catalog WHERE LOWER(model) = ? LIMIT 1',
            { model })
    end)
    imageCache[model] = ok and image and tostring(image) ~= '' and tostring(image) or false
    return imageCache[model] ~= false and imageCache[model] or nil
end

function SetVehicleLevel(familyId, vehicleId, level, actorCid)
    familyId, vehicleId = tonumber(familyId), tonumber(vehicleId)
    level = math.max(1, math.min(Config.MaxRanks, math.floor(tonumber(level) or Config.DefaultVehicleLevel)))
    if not familyId or not vehicleId then return false, 'invalid_arguments' end
    if not isSharedFamilyVehicle(familyId, vehicleId) then
        return false, 'vehicle_is_not_shared_with_this_family'
    end

    MySQL.query.await([[
        INSERT INTO cm_family_vehicle_access (family_id, vehicle_id, level, updated_by)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE level = VALUES(level), updated_by = VALUES(updated_by)
    ]], { familyId, vehicleId, level, actorCid and tostring(actorCid) or nil })

    ensureFamilyLoaded(familyId)
    levelCache[familyId][vehicleId] = level

    -- A raised threshold can invalidate an already-issued key. Revoke all
    -- family keys for this car and let eligible members receive a fresh key
    -- on their next authorized take/engine/trunk action.
    revokeVehicleKeys(vehicleId, familyId, 'family-vehicle-tier-changed')
    LogFamily(familyId, actorCid, 'vehicle_level_set', { vehicleId = vehicleId, level = level })
    return true
end

exports('SetFamilyVehicleLevel', function(familyId, vehicleId, level, actorCid)
    local invoking = GetInvokingResource()
    if invoking and invoking ~= Config.HouseResource and invoking ~= 'cm-admin' then
        return false, 'resource_not_authorized'
    end
    return SetVehicleLevel(familyId, vehicleId, level, actorCid)
end)

function CMFamilyResolveVehicleId(action)
    if type(action) == 'table' then
        return tonumber(action.vehicleId or action.vehicle_id or action.vehicle)
    end
    if type(action) == 'string' then
        local id = action:match(':(%d+)$')
        if id then return tonumber(id) end
    end
    return nil
end

local function vehiclePermission(action)
    action = tostring(action or 'vehicle.drive')
    local map = {
        ['take'] = 'garage.take',
        ['call'] = 'garage.take',
        ['drive'] = 'garage.take',
        ['vehicle.drive'] = 'garage.take',
        ['vehicle.engine'] = 'garage.take',
        ['vehicle.lock'] = 'garage.take',
        ['vehicle.info'] = 'garage.take',
        ['vehicle.track'] = tostring(Config.Tracking and Config.Tracking.vehicles and Config.Tracking.vehicles.permission or 'vehicle.track'),
        ['vehicle.store'] = 'garage.store',
        ['store'] = 'garage.store',
        ['vehicle.trunk.open'] = 'trunk.access',
        ['vehicle.trunk.deposit'] = 'trunk.access',
        ['vehicle.trunk.withdraw'] = 'trunk.access',
        ['trunk'] = 'trunk.access',
        ['manage'] = 'garage.manage_shared',
        ['vehicle.manage'] = 'garage.manage_shared',
    }
    return map[action] or 'garage.take'
end

local function rankAllows(rank, permission)
    if not rank then return false end
    if rank.is_founder then return true end
    if RankHasPermission(rank, permission) then return true end
    -- Compatibility for ranks created before trunk.access existed.
    if permission == 'trunk.access' and RankHasPermission(rank, 'storage.access') then return true end
    return false
end

local function familyVehicleDecision(characterId, vehicleId, action)
    vehicleId = tonumber(vehicleId)
    characterId = tostring(characterId or '')
    if not vehicleId then return false, 'invalid_vehicle_id' end
    if characterId == '' then return false, 'invalid_character_id' end

    local membership = GetMembership(characterId)
        or (CMFamilyRefreshMembership and CMFamilyRefreshMembership(characterId))
    if not membership then return false, 'not_a_family_member' end

    local fam = GetFamilyById(membership.family_id)
    if not fam then return false, 'family_not_loaded' end
    if not isSharedFamilyVehicle(fam.id, vehicleId) then
        return false, 'vehicle_not_shared_with_family'
    end

    local rank = (CMFamilyResolveMembershipRank and CMFamilyResolveMembershipRank(fam, membership))
        or select(1, GetRankForCid(characterId))
    if CMFamilyEffectiveRank then
        rank = CMFamilyEffectiveRank(characterId, fam, rank)
    end
    local tier = rank and tonumber(rank.tier) or tonumber(membership.rank_tier) or 1
    local permission = vehiclePermission(action)

    -- Family vehicle actions are always rank-authorized. Basic house entry is
    -- intentionally broader, but driving, engine, lock, store and trunk use
    -- must respect the rank editor and the per-vehicle minimum tier.
    if not rankAllows(rank, permission) then
        return false, ('rank_missing_permission:%s'):format(permission)
    end

    local level = tonumber(GetVehicleLevel(fam.id, vehicleId)) or Config.DefaultVehicleLevel
    if tier < level then
        return false, ('vehicle_requires_tier:%s'):format(level)
    end

    return true, 'allowed', {
        familyId = tonumber(fam.id),
        familyName = tostring(fam.name or 'Family'),
        familyTag = tostring(fam.tag or ''),
        houseId = tonumber(fam.house_id),
        vehicleId = vehicleId,
        tier = tier,
        requiredTier = level,
        permission = permission,
        action = tostring(action or 'vehicle.drive'),
    }
end

local function vehicleTrackRemaining(characterId, vehicleId)
    characterId, vehicleId = tostring(characterId or ''), tonumber(vehicleId)
    if characterId == '' or not vehicleId then return 0 end
    local expires = trackCooldown[characterId] and tonumber(trackCooldown[characterId][vehicleId]) or 0
    return math.max(0, expires - os.time())
end

local function requestVehicleTrack(characterId, vehicleId)
    if not (Config.Tracking and Config.Tracking.vehicles and Config.Tracking.vehicles.enabled ~= false) then
        return false, 'Vehicle tracking is disabled.'
    end
    characterId, vehicleId = tostring(characterId or ''), tonumber(vehicleId)
    local allowed, reason, context = familyVehicleDecision(characterId, vehicleId, 'vehicle.track')
    if not allowed then
        if tostring(reason):find('rank_missing_permission', 1, true) then
            return false, 'Your rank cannot track family vehicles.'
        elseif tostring(reason):find('vehicle_requires_tier', 1, true) then
            return false, 'Your rank is below this vehicle\'s required tier.'
        end
        return false, tostring(reason or 'Vehicle tracking denied.')
    end

    local remaining = vehicleTrackRemaining(characterId, vehicleId)
    if remaining > 0 then
        return false, ('This vehicle can be tracked again in %d:%02d.'):format(math.floor(remaining / 60), remaining % 60)
    end
    if GetResourceState(tostring(Config.VehiclesResource or 'cm-vehicles')) ~= 'started' then
        return false, 'Vehicle location service is unavailable.'
    end

    local ok, success, result = pcall(function()
        return exports[tostring(Config.VehiclesResource or 'cm-vehicles')]:GetTrackableVehicleLocation(vehicleId)
    end)
    if not ok or success ~= true or type(result) ~= 'table' then
        return false, type(result) == 'string' and result or 'The vehicle location could not be resolved.'
    end
    if not tonumber(result.x) or not tonumber(result.y) or not tonumber(result.z) then
        return false, tostring(result.message or 'The vehicle has no trackable location.')
    end

    local cooldown = math.max(60, tonumber(Config.Tracking.vehicles.cooldownSeconds) or 300)
    trackCooldown[characterId] = trackCooldown[characterId] or {}
    trackCooldown[characterId][vehicleId] = os.time() + cooldown

    local row = MySQL.single.await('SELECT plate, model FROM cm_owned_vehicles WHERE id = ? LIMIT 1', { vehicleId }) or {}
    result.vehicleId = vehicleId
    result.plate = tostring(result.plate or row.plate or '')
    result.label = tostring(result.label or row.model or result.plate or 'Family vehicle')
    result.familyId = tonumber(context and context.familyId)
    result.blipDurationSeconds = math.max(30, tonumber(Config.Tracking.vehicles.blipDurationSeconds) or 300)
    result.cooldownSeconds = cooldown
    result.message = tostring(result.message or ('%s location marked for five minutes.'):format(result.label))

    LogFamily(context.familyId, characterId, 'vehicle_tracked', {
        vehicleId = vehicleId,
        plate = result.plate,
        locationState = result.state,
        live = result.live == true,
        cooldownSeconds = cooldown,
    })
    return true, result
end

CMFamilyRequestVehicleTrack = requestVehicleTrack
exports('RequestFamilyVehicleTrack', requestVehicleTrack)

local function canUseFamilyVehicle(characterId, vehicleId, action)
    local allowed = familyVehicleDecision(characterId, vehicleId, action)
    return allowed == true
end
exports('CanUseFamilyVehicle', canUseFamilyVehicle)
exports('GetFamilyVehicleAccessDecision', familyVehicleDecision)

function GetFamilyVehiclesWithLevels(familyId, viewerCid)
    familyId = tonumber(familyId)
    if not familyId then return {} end
    ensureFamilyLoaded(familyId)

    local viewerRank, viewerFamily = viewerCid and GetRankForCid(viewerCid) or nil, nil
    if viewerCid then viewerRank, viewerFamily = GetRankForCid(viewerCid) end
    local canTrackRank = viewerRank and RankHasPermission(viewerRank,
        tostring(Config.Tracking and Config.Tracking.vehicles and Config.Tracking.vehicles.permission or 'vehicle.track')) or false

    local vehicles = B.GetFamilyVehicleManagementList(familyId, viewerCid)
    if #vehicles == 0 then vehicles = B.GetFamilyVehicles(familyId) end

    local out = {}
    for _, v in ipairs(vehicles) do
        local vehicleId = tonumber(v.id or v.vehicle_id)
        if vehicleId then
            local model = v.model or v.vehicle_model or v.display_name
            out[#out + 1] = {
                id = vehicleId,
                plate = v.plate,
                model = model,
                label = v.label or v.display_name or model,
                image = v.image or catalogImage(model),
                house_id = tonumber(v.house_id) or v.house_id,
                house_label = v.house_label,
                slot_index = tonumber(v.slot_index) or v.slot_index,
                level = levelCache[familyId][vehicleId] or Config.DefaultVehicleLevel,
                shared = v.shared == true or tonumber(v.shared) == 1 or tostring(v.owner_class) == 'family',
                owner_character_id = tostring(v.owner_character_id or ''),
                isOwner = viewerCid ~= nil and tostring(v.owner_character_id or '') == tostring(viewerCid),
                eligible = v.family_house_eligible == true or tonumber(v.family_house_eligible) == 1,
                canTrack = canTrackRank == true and (tonumber(viewerRank and viewerRank.tier) or 0) >= (levelCache[familyId][vehicleId] or Config.DefaultVehicleLevel),
                trackCooldownSeconds = viewerCid and vehicleTrackRemaining(viewerCid, vehicleId) or 0,
            }
        end
    end

    table.sort(out, function(a, b)
        if a.shared ~= b.shared then return a.shared == true end
        return tostring(a.plate or a.id) < tostring(b.plate or b.id)
    end)
    return out
end

function SetVehicleSharedAndLevel(actorCid, vehicleId, shared, level)
    local rank, fam = GetRankForCid(actorCid)
    if not rank or not fam then return false, 'not_in_family' end
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'invalid_vehicle_id' end

    local sharedOk, sharedErr = B.SetVehicleFamilyShared(vehicleId, shared == true, actorCid)
    if not sharedOk then return false, sharedErr or 'vehicle_share_failed' end

    if shared == true then
        local ok, why = SetVehicleLevel(fam.id, vehicleId, level, actorCid)
        if not ok then
            B.SetVehicleFamilyShared(vehicleId, false, actorCid)
            return false, why
        end
    else
        MySQL.update.await(
            'DELETE FROM cm_family_vehicle_access WHERE family_id = ? AND vehicle_id = ?',
            { fam.id, vehicleId })
        ensureFamilyLoaded(fam.id)
        levelCache[fam.id][vehicleId] = nil
        revokeVehicleKeys(vehicleId, fam.id, 'family-vehicle-unshared')
    end

    LogFamily(fam.id, actorCid, shared and 'vehicle_shared' or 'vehicle_unshared',
        { vehicleId = vehicleId, level = tonumber(level) })
    return true
end
exports('SetFamilyVehicleShared', SetVehicleSharedAndLevel)

function InvalidateVehicleCache(familyId)
    levelCache[tonumber(familyId)] = nil
end


AddEventHandler('cm-playerdata:server:characterUnloaded', function(_, data)
    local cid = type(data) == 'table' and (data.charId or data.characterId or data.id) or nil
    if cid then trackCooldown[tostring(cid)] = nil end
end)
