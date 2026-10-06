-- cm-gang V1 storage integration.
--
-- Shared stash access belongs to cm-inventory. Weapon issuance is deliberately
-- unavailable until cm-weapons exposes a faction-authorized server path. This
-- resource must not route gang armory requests through cm-law or create a
-- parallel weapon/inventory authority.

local RESOURCE, PLAYERDATA, INVENTORY = GetCurrentResourceName(), 'cm-playerdata', 'cm-inventory'
local ARMORY_UNAVAILABLE = 'weapon_owner_faction_api_missing'

local function characterIdForSource(src)
    local ok, value = pcall(function()
        return exports[PLAYERDATA]:GetCharacterId(tonumber(src))
    end)
    value = ok and tostring(value or '') or ''
    return value:match('^%d+$') and value or nil
end

local function memberContext(src, permission)
    local characterId = characterIdForSource(src)
    if not characterId then return nil, 'character_not_loaded' end
    local member = exports[RESOURCE]:GetGangForCharacter(characterId)
    if type(member) ~= 'table' or member.enabled ~= true then return nil, 'not_in_enabled_gang' end
    if not Config.IsFixedGangId(member.gangId) then return nil, 'legacy_gang_not_supported' end
    if not exports[RESOURCE]:HasPermission(characterId, permission) then return nil, 'no_permission' end
    return { source = tonumber(src), characterId = characterId, member = member }
end

local function facilityFor(context)
    local row = MySQL.single.await([[SELECT enabled,x,y,z,routing_bucket,display_name,role_label
        FROM cm_gang_facilities WHERE gang_id=? AND facility_type='headquarters' LIMIT 1]],
        { context.member.gangId })
    if not row or not CMGangDbTrue(row.enabled) then return nil, 'facility_disabled' end
    local x, y, z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
    if not x or not y or not z then return nil, 'facility_not_configured' end
    if GetPlayerRoutingBucket(context.source) ~= (tonumber(row.routing_bucket) or 0) then
        return nil, 'wrong_routing_bucket'
    end
    local ped = GetPlayerPed(context.source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil, 'player_entity_unavailable' end
    if IsEntityDead(ped) or (GetEntityHealth(ped) or 0) <= 0 then return nil, 'player_not_alive' end
    local allowedDistance = tonumber(Config.Headquarters and Config.Headquarters.interactionDistance)
        or tonumber(Config.Storage and Config.Storage.facilityDistance) or 3.0
    if #(GetEntityCoords(ped) - vector3(x, y, z)) > allowedDistance + 0.35 then
        return nil, 'too_far_away'
    end
    return row
end

local function logActivity(context, action, detail)
    MySQL.insert.await([[INSERT INTO cm_gang_activity
        (event_uid,gang_id,action,actor_character_id,detail) VALUES (?,?,?,?,?)]], {
        ('%s:%s:%d:%d'):format(RESOURCE, action, os.time(), math.random(100000, 999999)),
        context.member.gangId, action, context.characterId, json.encode(detail or {}),
    })
end

exports('ValidateGangStashAccess', function(src, ownerType, ownerId)
    local context, reason = memberContext(src, 'gang.stash')
    if not context then return false, reason end
    if tostring(ownerType) ~= 'gang_stash' or tostring(ownerId) ~= context.member.gangId then
        return false, 'stash_identity_mismatch'
    end
    if not facilityFor(context) then return false, 'stash_facility_unavailable' end
    return true
end)

exports('RecordGangStashMovement', function(src, ownerType, ownerId, movement, itemId, quantity)
    local context = memberContext(src, 'gang.stash')
    if not context or tostring(ownerType) ~= 'gang_stash' or tostring(ownerId) ~= context.member.gangId then return false end
    if not facilityFor(context) then return false end
    movement = movement == 'deposit' and 'stash_deposit' or movement == 'withdraw' and 'stash_withdraw' or nil
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    itemId = tostring(itemId or ''):lower():sub(1, 96)
    if not movement or itemId == '' then return false end
    logActivity(context, movement, { itemId = itemId, quantity = quantity })
    return true
end)

lib.callback.register('cm-gang:server:openStash', function(src)
    local context, reason = memberContext(src, 'gang.stash')
    if not context then return { ok = false, reason = reason } end
    local facility, facilityReason = facilityFor(context)
    if not facility then return { ok = false, reason = facilityReason } end
    if GetResourceState(INVENTORY) ~= 'started' then return { ok = false, reason = 'inventory_unavailable' } end
    local ok, opened, openReason = pcall(function()
        return exports[INVENTORY]:OpenExternalInventory(src, {
            ownerType = 'gang_stash', ownerId = context.member.gangId,
            slots = math.min(30, tonumber(Config.Storage.stashSlots) or 30),
            displaySlots = 30, slotPrefix = 'gang-',
            label = tostring(facility.display_name or context.member.displayName) .. ' Stash',
            subtitle = tostring(facility.role_label or 'Shared gang storage'), kind = 'gang_stash',
            accessExport = 'ValidateGangStashAccess', data = { gangId = context.member.gangId },
            activityExport = 'RecordGangStashMovement',
        })
    end)
    if not ok or opened ~= true then return { ok = false, reason = openReason or 'stash_open_failed' } end
    return { ok = true }
end)

local function armoryUnavailable()
    return { ok = false, reason = ARMORY_UNAVAILABLE }
end

lib.callback.register('cm-gang:server:getArmory', armoryUnavailable)
lib.callback.register('cm-gang:server:saveArmorySettings', armoryUnavailable)
lib.callback.register('cm-gang:server:armoryCheckout', armoryUnavailable)
lib.callback.register('cm-gang:server:getArmoryReturnOptions', armoryUnavailable)
lib.callback.register('cm-gang:server:armoryDeposit', armoryUnavailable)

exports('AddGangArmoryStock', function()
    return false, ARMORY_UNAVAILABLE
end)

exports('AdminGetArmory', function()
    return { ok = false, error = ARMORY_UNAVAILABLE }
end)

exports('AdminConfigureArmory', function()
    return false, ARMORY_UNAVAILABLE
end)

