-- Server-authoritative physical gang headquarters access.
--
-- Facility locations and labels belong to cm_gang_facilities and are edited
-- through cm-admin. This file only validates access and never creates or
-- mutates facility, membership, stash, vehicle, or chat authority.

local RESOURCE = GetCurrentResourceName()
local PLAYERDATA = 'cm-playerdata'
local COOLDOWN_MS = 750
local actionCooldowns = {}

local function characterIdForSource(src)
    src = tonumber(src)
    if not src or src <= 0 or GetResourceState(PLAYERDATA) ~= 'started' then return nil end
    local ok, value = pcall(function()
        return exports[PLAYERDATA]:GetCharacterId(src)
    end)
    value = ok and tostring(value or '') or ''
    return value:match('^%d+$') and value or nil
end

local function fail(reason)
    return { ok = false, reason = reason }
end

local function validCoordinates(row)
    return tonumber(row and row.x) ~= nil
        and tonumber(row and row.y) ~= nil
        and tonumber(row and row.z) ~= nil
end

local function validContactModel(gangId, row)
    local configured = tostring(row and row.npc_model or '')
    if Config.NpcModels[configured] == true then return true end
    local pool = Config.ContactNpcs and Config.ContactNpcs[gangId]
    for _, model in ipairs(type(pool) == 'table' and pool.models or {}) do
        if Config.NpcModels[tostring(model)] == true then return true end
    end
    return false
end

local function clearSourceCooldown(src)
    src = tonumber(src)
    if src then actionCooldowns[src] = nil end
end

local function validateHeadquarters(src, request)
    request = type(request) == 'table' and request or {}
    src = tonumber(src)
    if not src or src <= 0 then return nil, 'invalid_source' end

    local action = tostring(request.action or '')
    if action ~= 'dashboard' and action ~= 'stash' then return nil, 'invalid_action' end

    local requestedGangId = tostring(request.gangId or '')
    if not Config.IsFixedGangId(requestedGangId) then return nil, 'invalid_gang' end

    local characterId = characterIdForSource(src)
    if not characterId then return nil, 'character_not_loaded' end
    local membership = exports[RESOURCE]:GetGangForCharacter(characterId)
    if type(membership) ~= 'table' or membership.enabled ~= true then
        return nil, 'not_in_enabled_gang'
    end
    if tostring(membership.gangId or '') ~= requestedGangId then
        return nil, 'gang_membership_mismatch'
    end
    if not Config.IsFixedGangId(membership.gangId) then return nil, 'legacy_gang_not_supported' end
    if action == 'stash' and not exports[RESOURCE]:HasPermission(characterId, 'gang.stash') then
        return nil, 'no_permission'
    end

    local now = GetGameTimer()
    local last = actionCooldowns[src]
    if last and now - last < COOLDOWN_MS then return nil, 'interaction_rate_limited' end

    local row = MySQL.single.await([[SELECT enabled,x,y,z,heading,routing_bucket,display_name,role_label,npc_model
        FROM cm_gang_facilities WHERE gang_id=? AND facility_type='headquarters' LIMIT 1]], { requestedGangId })
    if not row or not CMGangDbTrue(row.enabled) then return nil, 'facility_disabled' end
    if not validCoordinates(row) then return nil, 'facility_not_configured' end
    if not validContactModel(requestedGangId, row) then return nil, 'facility_npc_unavailable' end

    if GetPlayerRoutingBucket(src) ~= (tonumber(row.routing_bucket) or 0) then
        return nil, 'wrong_routing_bucket'
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil, 'player_entity_unavailable' end
    if IsEntityDead(ped) or (GetEntityHealth(ped) or 0) <= 0 then return nil, 'player_not_alive' end

    local distance = #(GetEntityCoords(ped) - vector3(tonumber(row.x), tonumber(row.y), tonumber(row.z)))
    local allowedDistance = tonumber(Config.Headquarters and Config.Headquarters.interactionDistance)
        or tonumber(Config.ContactStreaming and Config.ContactStreaming.interactionDistance)
        or 2.5
    if distance > allowedDistance + 0.35 then return nil, 'too_far_away' end

    actionCooldowns[src] = now
    return {
        source = src,
        characterId = characterId,
        membership = membership,
        facility = row,
        action = action,
    }
end

function CMGangValidateHeadquarters(src, request)
    local context, reason = validateHeadquarters(src, request)
    if not context then return nil, reason end
    return context
end

lib.callback.register('cm-gang:server:authorizeHeadquarters', function(source, request)
    local context, reason = validateHeadquarters(source, request)
    if not context then return fail(reason) end
    return {
        ok = true,
        action = context.action,
        gangId = context.membership.gangId,
    }
end)

AddEventHandler('playerDropped', function()
    clearSourceCooldown(source)
end)
