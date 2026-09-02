local RESOURCE, PLAYERDATA = GetCurrentResourceName(), 'cm-playerdata'
local saveCooldowns = {}

local function characterIdForSource(src)
    local ok, value = pcall(function() return exports[PLAYERDATA]:GetCharacterId(tonumber(src)) end)
    value = ok and tostring(value or '') or ''
    return value:match('^%d+$') and value or nil
end

local function memberContext(src, permission)
    local characterId = characterIdForSource(src)
    if not characterId then return nil, 'character_not_loaded' end
    local member = exports[RESOURCE]:GetGangForCharacter(characterId)
    if type(member) ~= 'table' or member.enabled ~= true then return nil, 'not_in_enabled_gang' end
    if not exports[RESOURCE]:HasPermission(characterId, permission) then return nil, 'no_permission' end
    return { source = tonumber(src), characterId = characterId, member = member }
end

local function facilityFor(context, facilityType)
    local row = MySQL.single.await([[SELECT enabled,x,y,z,routing_bucket FROM cm_gang_facilities
        WHERE gang_id=? AND facility_type=? LIMIT 1]], { context.member.gangId, facilityType })
    if not row or not CMGangDbTrue(row.enabled) then return nil, 'facility_disabled' end
    local x, y, z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
    if not x or not y or not z then return nil, 'facility_not_configured' end
    if GetPlayerRoutingBucket(context.source) ~= (tonumber(row.routing_bucket) or 0) then return nil, 'wrong_routing_bucket' end
    local ped = GetPlayerPed(context.source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil, 'player_entity_unavailable' end
    if #(GetEntityCoords(ped) - vector3(x, y, z)) > (Config.Storage.facilityDistance or 3.0) then return nil, 'too_far_away' end
    return row
end

local function sanitizeComponents(raw)
    if type(raw) ~= 'table' then return nil end
    local clean = { components = {}, props = {} }
    for key, value in pairs(raw.components or {}) do
        local index = tonumber(key)
        if index and index >= 0 and index <= 11 and type(value) == 'table' then
            local drawable = math.floor(tonumber(value.drawable) or -1)
            local texture = math.floor(tonumber(value.texture) or -1)
            local palette = math.floor(tonumber(value.palette) or 0)
            if drawable >= 0 and drawable <= 1000 and texture >= 0 and texture <= 1000 and palette >= 0 and palette <= 3 then
                clean.components[tostring(index)] = { drawable = drawable, texture = texture, palette = palette }
            end
        end
    end
    for key, value in pairs(raw.props or {}) do
        local index = tonumber(key)
        if index and index >= 0 and index <= 7 and type(value) == 'table' then
            local drawable = math.floor(tonumber(value.drawable) or -1)
            local texture = math.floor(tonumber(value.texture) or 0)
            if drawable >= -1 and drawable <= 1000 and texture >= 0 and texture <= 1000 then
                clean.props[tostring(index)] = { drawable = drawable, texture = texture }
            end
        end
    end
    if next(clean.components) == nil then return nil end
    return clean
end

local function cleanName(value)
    local name = tostring(value or ''):gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
    if #name < 2 or #name > 64 then return nil end
    return name
end

local function logActivity(context, action, detail)
    MySQL.insert.await([[INSERT INTO cm_gang_activity
        (event_uid,gang_id,action,actor_character_id,detail) VALUES (?,?,?,?,?)]], {
        ('%s:%s:%d:%d'):format(RESOURCE, action, os.time(), math.random(100000, 999999)),
        context.member.gangId, action, context.characterId, json.encode(detail or {}),
    })
end

lib.callback.register('cm-gang:server:getWardrobeCatalog', function(src, sex)
    local context, reason = memberContext(src, 'gang.wardrobe')
    if not context then return { ok = false, reason = reason } end
    local _, facilityReason = facilityFor(context, 'headquarters')
    if facilityReason then return { ok = false, reason = facilityReason } end
    sex = sex == 'female' and 'female' or 'male'
    local rows = MySQL.query.await([[SELECT id,name,minimum_tier FROM cm_gang_wardrobe_outfits
        WHERE gang_id=? AND sex=? AND minimum_tier<=? ORDER BY name]],
        { context.member.gangId, sex, context.member.isLeader and 100 or context.member.tier }) or {}
    local outfits = {}
    for _, row in ipairs(rows) do
        outfits[#outfits + 1] = { id = tonumber(row.id), name = tostring(row.name), minimumTier = tonumber(row.minimum_tier) or 1 }
    end
    return { ok = true, outfits = outfits }
end)

lib.callback.register('cm-gang:server:applyWardrobeOutfit', function(src, outfitId)
    local context, reason = memberContext(src, 'gang.wardrobe')
    if not context then return { ok = false, reason = reason } end
    local _, facilityReason = facilityFor(context, 'headquarters')
    if facilityReason then return { ok = false, reason = facilityReason } end
    local row = MySQL.single.await('SELECT components,minimum_tier FROM cm_gang_wardrobe_outfits WHERE id=? AND gang_id=? LIMIT 1',
        { tonumber(outfitId), context.member.gangId })
    if not row then return { ok = false, reason = 'outfit_not_found' } end
    if not context.member.isLeader and context.member.tier < (tonumber(row.minimum_tier) or 1) then
        return { ok = false, reason = 'rank_denied' }
    end
    local ok, components = pcall(json.decode, row.components)
    if not ok or type(components) ~= 'table' then return { ok = false, reason = 'outfit_corrupted' } end
    return { ok = true, components = components }
end)

-- Gang wardrobe curation reuses gang.manage_armory (same NPC/service group
-- as the armory) rather than a new permission the spec doesn't request.
lib.callback.register('cm-gang:server:saveWardrobeOutfit', function(src, request)
    request = type(request) == 'table' and request or {}
    local context, reason = memberContext(src, 'gang.manage_armory')
    if not context then return { ok = false, reason = reason } end
    local _, facilityReason = facilityFor(context, 'headquarters')
    if facilityReason then return { ok = false, reason = facilityReason } end
    local now = GetGameTimer()
    if (saveCooldowns[context.characterId] or 0) > now then return { ok = false, reason = 'rate_limited' } end
    saveCooldowns[context.characterId] = now + ((Config.Security.wardrobeCooldownSeconds or 2) * 1000)
    local name = cleanName(request.name)
    local sex = request.sex == 'female' and 'female' or 'male'
    local components = sanitizeComponents(request.components)
    local minimumTier = math.max(1, math.min(99, math.floor(tonumber(request.minimumTier) or 1)))
    if not name or not components then return { ok = false, reason = 'invalid_outfit' } end
    local id = MySQL.insert.await([[INSERT INTO cm_gang_wardrobe_outfits
        (gang_id,name,sex,components,minimum_tier,created_by) VALUES (?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE components=VALUES(components),minimum_tier=VALUES(minimum_tier),created_by=VALUES(created_by)]],
        { context.member.gangId, name, sex, json.encode(components), minimumTier, context.characterId })
    logActivity(context, 'wardrobe_outfit_saved', { name = name, sex = sex })
    return { ok = id ~= nil or true }
end)

lib.callback.register('cm-gang:server:deleteWardrobeOutfit', function(src, outfitId)
    local context, reason = memberContext(src, 'gang.manage_armory')
    if not context then return { ok = false, reason = reason } end
    local changed = MySQL.update.await('DELETE FROM cm_gang_wardrobe_outfits WHERE id=? AND gang_id=?',
        { tonumber(outfitId), context.member.gangId })
    if tonumber(changed) ~= 1 then return { ok = false, reason = 'outfit_not_found' } end
    logActivity(context, 'wardrobe_outfit_deleted', { outfitId = tonumber(outfitId) })
    return { ok = true }
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    local characterId = characterIdForSource(src)
    if characterId then saveCooldowns[characterId] = nil end
end)

AddEventHandler('onResourceStop', function(name)
    if name == RESOURCE then saveCooldowns = {} end
end)
