local RESOURCE = GetCurrentResourceName()
local PLAYERDATA = 'cm-playerdata'
local chatCooldowns = {}
local sourceCharacters = {}
local cleanText
local contactRuntimeSeed = os.time()
local selectedContacts = {}

local function contactFor(gangId, configuredModel, kind)
    kind = tostring(kind or 'main')
    local cacheKey = ('%s:%s'):format(gangId, kind)
    if selectedContacts[cacheKey] then return selectedContacts[cacheKey] end
    local pool = Config.ContactNpcs and Config.ContactNpcs[gangId]
    if type(pool) ~= 'table' then return nil end
    local seed = contactRuntimeSeed
    local identityKey = gangId .. ':' .. kind
    for index = 1, #identityKey do seed = seed + (identityKey:byte(index) * index) end
    local function pick(values, offset)
        return type(values) == 'table' and #values > 0 and values[((seed + offset) % #values) + 1] or nil
    end
    local model = Config.NpcModels[tostring(configuredModel or '')] and configuredModel or pick(pool.models, 7)
    if not Config.NpcModels[tostring(model or '')] then return nil end
    selectedContacts[cacheKey] = {
        model = model,
        name = cleanText(pick(pool.names, 13) or 'Gang Contact', 64),
        nickname = cleanText(pick(pool.nicknames, 23) or 'Contact', 32),
        outfit = pick(pool.outfits, 31),
        greeting = cleanText(pick(Config.ContactGreetings, 41) or 'What do you need?', 96),
        refusal = cleanText(pool.refusals and pool.refusals[kind] or 'You are not one of us. These services are not available to you.', 180),
    }
    return selectedContacts[cacheKey]
end

local function characterIdForSource(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local ok, value = pcall(function() return exports[PLAYERDATA]:GetCharacterId(src) end)
    value = ok and tostring(value or '') or ''
    local characterId = value:match('^%d+$') and value or nil
    if characterId then sourceCharacters[src] = characterId end
    return characterId
end

cleanText = function(value, maximum)
    local text = tostring(value or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return text:sub(1, maximum)
end

local function safeAsset(value, catalog)
    value = type(value) == 'string' and value or nil
    return value and catalog[value] == true and value or nil
end

local function getMembership(src)
    local characterId = characterIdForSource(src)
    if not characterId then return nil, 'character_not_loaded' end
    local membership = exports[RESOURCE]:GetGangForCharacter(characterId)
    if type(membership) ~= 'table' or membership.enabled ~= true then return nil, 'not_in_enabled_gang' end
    return membership, nil, characterId
end

local function publicFacilities(gangId)
    local rows = MySQL.query.await([[
        SELECT facility_type, enabled, npc_model, display_name, role_label,
               x, y, z, heading, routing_bucket
        FROM cm_gang_facilities WHERE gang_id = ?
    ]], { gangId }) or {}
    local result = {}
    for _, row in ipairs(rows) do
        if Config.FacilityTypes[row.facility_type] then
            result[row.facility_type] = {
                type = row.facility_type,
                enabled = CMGangDbTrue(row.enabled),
                npcModel = Config.NpcModels[tostring(row.npc_model or '')] and row.npc_model or nil,
                displayName = cleanText(row.display_name or '', 64),
                roleLabel = cleanText(row.role_label or '', 64),
                x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
                heading = tonumber(row.heading) or 0.0,
                routingBucket = tonumber(row.routing_bucket) or 0,
            }
        end
    end
    return result
end

local function dashboardPayload(src)
    local membership, reason, characterId = getMembership(src)
    if not membership then return nil, reason end
    local gang = exports[RESOURCE]:GetGang(membership.gangId)
    if type(gang) ~= 'table' then return nil, 'gang_unavailable' end
    local permissions = {}
    for _, definition in ipairs(Config.Permissions or {}) do
        if exports[RESOURCE]:HasPermission(characterId, definition.key) then permissions[#permissions + 1] = definition.key end
    end
    local memberCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_gang_members WHERE gang_id = ?', { membership.gangId })) or 0
    local members = {}
    local ranks = exports[RESOURCE]:GetGangRanks(characterId) or {}
    local vehicleRanks = {}
    if membership.isLeader == true or exports[RESOURCE]:HasPermission(characterId, 'gang.manage_vehicles') then
        local rows = MySQL.query.await([[SELECT id,tier,name,is_leader_rank FROM cm_gang_ranks
            WHERE gang_id=? ORDER BY tier DESC]], { membership.gangId }) or {}
        for _, rank in ipairs(rows) do
            vehicleRanks[#vehicleRanks + 1] = {
                id=tonumber(rank.id), tier=tonumber(rank.tier) or 1,
                name=cleanText(rank.name, 48), isLeaderRank=CMGangDbTrue(rank.is_leader_rank)
            }
        end
    end
    local canViewMembers = membership.isLeader == true
        or exports[RESOURCE]:HasPermission(characterId, 'gang.view_members')
        or exports[RESOURCE]:HasPermission(characterId, 'gang.manage_members')
    if canViewMembers then
        local rows = MySQL.query.await([[
            SELECT m.character_id, m.rank_id, m.is_leader, r.name rank_name, r.tier,
                   CONCAT(c.first_name, ' ', c.last_name) character_name
            FROM cm_gang_members m
            JOIN cm_gang_ranks r ON r.id = m.rank_id AND r.gang_id = m.gang_id
            LEFT JOIN characters c ON c.id = m.character_id
            WHERE m.gang_id = ? ORDER BY r.tier DESC, m.character_id
        ]], { membership.gangId }) or {}
        for _, row in ipairs(rows) do
            local onlineSource
            do
                local ok, value = pcall(function() return exports[PLAYERDATA]:GetSourceByCharId(tostring(row.character_id)) end)
                onlineSource = ok and tonumber(value) or nil
            end
            members[#members + 1] = {
                characterId = tostring(row.character_id), name = cleanText(row.character_name or 'Unknown character', 96),
                rankId = tonumber(row.rank_id), rankName = cleanText(row.rank_name, 48), tier = tonumber(row.tier) or 0,
                isLeader = CMGangDbTrue(row.is_leader),
                online = onlineSource ~= nil and GetPlayerName(onlineSource) ~= nil,
            }
        end
    end
    local leaderName = MySQL.scalar.await([[
        SELECT CONCAT(c.first_name, ' ', c.last_name)
        FROM cm_gangs g LEFT JOIN characters c ON c.id = g.leader_character_id
        WHERE g.gang_id = ? LIMIT 1
    ]], { membership.gangId })
    local activity = {}
    if exports[RESOURCE]:HasPermission(characterId, 'gang.view_logs') then
        local rows = MySQL.query.await([[
            SELECT a.action, a.actor_character_id, a.target_character_id, a.created_at,
                   TRIM(CONCAT(COALESCE(ac.first_name,''),' ',COALESCE(ac.last_name,''))) actor_name,
                   TRIM(CONCAT(COALESCE(tc.first_name,''),' ',COALESCE(tc.last_name,''))) target_name
            FROM cm_gang_activity a
            LEFT JOIN characters ac ON ac.id = a.actor_character_id
            LEFT JOIN characters tc ON tc.id = a.target_character_id
            WHERE a.gang_id = ? ORDER BY a.id DESC LIMIT 20
        ]], { membership.gangId }) or {}
        for _, row in ipairs(rows) do
            activity[#activity + 1] = {
                action = cleanText(row.action, 64), actorCharacterId = tostring(row.actor_character_id or ''),
                targetCharacterId = row.target_character_id and tostring(row.target_character_id) or nil,
                actorName = cleanText(row.actor_name ~= '' and row.actor_name or (row.actor_character_id and ('CID ' .. tostring(row.actor_character_id)) or 'System'), 96),
                targetName = row.target_character_id and cleanText(row.target_name ~= '' and row.target_name or ('CID ' .. tostring(row.target_character_id)), 96) or nil,
                createdAt = tostring(row.created_at or ''),
            }
        end
    end
    local availableVehicles = tonumber(MySQL.scalar.await(
        [[SELECT COUNT(*) FROM cm_gang_fleet_vehicles
          WHERE gang_id = ? AND enabled = 1 AND minimum_tier <= ?
            AND vehicle_id IS NOT NULL AND x IS NOT NULL AND y IS NOT NULL AND z IS NOT NULL]],
        { membership.gangId, membership.tier })) or 0
    local onlineMembers = 0
    for _, member in ipairs(members) do if member.online then onlineMembers = onlineMembers + 1 end end
    local armoryStock = tonumber(MySQL.scalar.await(
        'SELECT COALESCE(SUM(stock_quantity),0) FROM cm_gang_armory_config WHERE gang_id=? AND enabled=1',
        { membership.gangId })) or 0
    local profit = MySQL.single.await(
        'SELECT activity_score,pending_amount,last_tick_at,last_collected_at FROM cm_gang_profit WHERE gang_id=?',
        { membership.gangId }) or {}
    return {
        gang = {
            id = gang.id, displayName = gang.displayName, shortTag = gang.shortTag, color = gang.color,
            logoAsset = safeAsset(gang.logoAsset, Config.AssetKeys.logos),
            artAsset = safeAsset(gang.artAsset, Config.AssetKeys.artwork),
        },
        member = { characterId = characterId, rankName = membership.rankName, tier = membership.tier, isLeader = membership.isLeader },
        leaderName = cleanText(leaderName or 'Unassigned', 96), memberCount = memberCount,
        onlineMembers = onlineMembers, offlineMembers = math.max(0, memberCount - onlineMembers),
        availableVehicles = availableVehicles, permissions = permissions, permissionCatalog = Config.Permissions,
        armoryStock = armoryStock,
        profit = { activityScore=tonumber(profit.activity_score) or 0, pendingAmount=tonumber(profit.pending_amount) or 0,
            lastTickAt=profit.last_tick_at and tostring(profit.last_tick_at) or nil,
            lastCollectedAt=profit.last_collected_at and tostring(profit.last_collected_at) or nil },
        canViewMembers = canViewMembers,
        activity = activity, facilities = publicFacilities(membership.gangId), members = members, ranks = ranks,
        vehicleRanks = vehicleRanks,
        canIssueBonus = membership.isLeader == true or exports[RESOURCE]:HasPermission(characterId, 'gang.issue_bonus'),
    }
end

lib.callback.register('cm-gang:server:getDashboard', function(source)
    local payload, reason = dashboardPayload(source)
    return { ok = payload ~= nil, reason = reason, data = payload }
end)

lib.callback.register('cm-gang:server:getHeadquarters', function(source)
    local membership = getMembership(source)
    if membership and not Config.IsFixedGangId(membership.gangId) then membership = nil end
    local ownGangId = membership and membership.gangId or nil
    local contacts, ownContacts = {}, {}
    local playerBucket = GetPlayerRoutingBucket(tonumber(source))
    for _, gangId in ipairs(Config.GangIds) do
        local gang = exports[RESOURCE]:GetGang(gangId)
        local facilities = publicFacilities(gangId)
        for _, definition in ipairs({
            { kind='main', facility='headquarters', role='Gang Contact' },
            { kind='vehicle', facility='fleet', role='Vehicle Coordinator' },
            { kind='profit', facility='profit', role='Profit Manager' },
        }) do
            local facility=facilities[definition.facility]
            if facility and facility.enabled and facility.x and facility.y and facility.z
                and playerBucket==facility.routingBucket then
                local contact=contactFor(gangId,facility.npcModel,definition.kind)
                if contact then
                    facility.npcModel=contact.model
                    facility.displayName=facility.displayName~='' and facility.displayName or contact.name
                    facility.roleLabel=facility.roleLabel~='' and facility.roleLabel or definition.role
                    contact.role=facility.roleLabel
                    contact.kind=definition.kind
                    contact.modelCandidates={contact.model}
                    for _,model in ipairs((Config.ContactNpcs[gangId] or {}).models or {}) do
                        if Config.NpcModels[model] and model~=contact.model then contact.modelCandidates[#contact.modelCandidates+1]=model end
                    end
                    local entry={kind=definition.kind,facility=facility,contact=contact,gangId=gangId,
                        gangName=gang and gang.displayName or gangId,isOwn=gangId==ownGangId}
                    contacts[#contacts+1]=entry
                    if entry.isOwn then ownContacts[#ownContacts+1]=entry end
                end
            end
        end
    end
    if #contacts==0 then return nil,'contact_not_configured' end
    return { gangId=ownGangId,gangName=membership and membership.displayName or 'Unaffiliated',color=membership and membership.color or '#31e6ff',contacts=contacts,
        facility=ownContacts[1] and ownContacts[1].facility or nil,contact=ownContacts[1] and ownContacts[1].contact or nil }
end)

lib.callback.register('cm-gang:server:validateContactService',function(source,service)
    local permissionByService={vehicles='gang.vehicle',weapons='gang.armory',storage='gang.stash',profit='gang.collect_profit',turf='gang.collect_profit',deposit='gang.stash'}
    local kindByService={vehicles='fleet',weapons='headquarters',storage='headquarters',profit='profit',turf='profit',deposit='headquarters'}
    local permission=permissionByService[tostring(service or '')]
    if not permission then return {ok=false,reason='invalid_service'} end
    local membership,reason,characterId=getMembership(source)
    if not membership then return {ok=false,reason=reason} end
    if not Config.IsFixedGangId(membership.gangId) then return {ok=false,reason='legacy_gang_not_supported'} end
    if not exports[RESOURCE]:HasPermission(characterId,permission) then return {ok=false,reason='no_permission'} end
    local facility=publicFacilities(membership.gangId)[kindByService[tostring(service or '')]]
    if not facility or not facility.enabled or not facility.x or not facility.y or not facility.z then return {ok=false,reason='contact_not_configured'} end
    if GetPlayerRoutingBucket(tonumber(source))~=(tonumber(facility.routingBucket) or 0) then return {ok=false,reason='wrong_routing_bucket'} end
    local ped=GetPlayerPed(tonumber(source))
    if not ped or ped==0 or not DoesEntityExist(ped) then return {ok=false,reason='player_entity_unavailable'} end
    if #(GetEntityCoords(ped)-vector3(facility.x,facility.y,facility.z))>(Config.ContactStreaming.interactionDistance or 2.5)+0.75 then
        return {ok=false,reason='too_far_away'}
    end
    return {ok=true,gangId=membership.gangId,service=service}
end)

lib.callback.register('cm-gang:server:getProfitFacility', function(source)
    local membership = getMembership(source)
    if not membership then return nil end
    local facility = publicFacilities(membership.gangId).profit
    if not facility or not facility.enabled or not facility.npcModel or not facility.x or not facility.y or not facility.z then return nil end
    if GetPlayerRoutingBucket(tonumber(source)) ~= facility.routingBucket then return nil end
    return { gangId=membership.gangId, gangName=membership.displayName, color=membership.color, facility=facility }
end)

lib.callback.register('cm-gang:server:dashboardMemberAction', function(source, request)
    request = type(request) == 'table' and request or {}
    local _, reason, characterId = getMembership(source)
    if not characterId then return { ok = false, reason = reason } end
    local action = tostring(request.action or '')
    local ok, result
    if action == 'assign_rank' then
        ok, result = exports[RESOURCE]:AssignMemberRank(characterId, request.targetCharacterId, request.rankId)
    elseif action == 'remove' then
        ok, result = exports[RESOURCE]:RemoveMember(characterId, request.targetCharacterId)
    else
        return { ok = false, reason = 'invalid_action' }
    end
    return { ok = ok == true, reason = ok == true and nil or result }
end)

lib.callback.register('cm-gang:server:dashboardRankAction', function(source, request)
    request = type(request) == 'table' and request or {}
    local _, reason, characterId = getMembership(source)
    if not characterId then return { ok = false, reason = reason } end
    local action = tostring(request.action or '')
    local ok, result
    if action == 'create' then
        local level = tonumber(request.level)
        if not level or level % 1 ~= 0 or level < 1 or level > 9 then
            return { ok = false, reason = 'invalid_rank_level' }
        end
        ok, result = exports[RESOURCE]:CreateRank(characterId, request.name, level * 10, request.permissions)
    elseif action == 'update' then
        local level = tonumber(request.level)
        if not level or level % 1 ~= 0 or level < 1 or level > 9 then
            return { ok = false, reason = 'invalid_rank_level' }
        end
        ok, result = exports[RESOURCE]:UpdateRank(characterId, request.rankId, request.name, level * 10, request.permissions)
    elseif action == 'delete' then
        ok, result = exports[RESOURCE]:DeleteRank(characterId, request.rankId)
    else
        return { ok = false, reason = 'invalid_action' }
    end
    return { ok = ok == true, reason = ok == true and nil or result, rankId = ok == true and result or nil }
end)

exports('SendGangChat', function(src, rawMessage, requestedMode)
    src = tonumber(src)
    local membership, reason, characterId = getMembership(src)
    if not membership then return false, reason end
    if not exports[RESOURCE]:HasPermission(characterId, 'gang.chat') then return false, 'no_permission' end
    local message = cleanText(rawMessage, Config.Chat.maximumLength or 180)
    if message == '' then return false, 'empty_message' end
    local now = GetGameTimer()
    if (chatCooldowns[characterId] or 0) > now then return false, 'rate_limited' end
    chatCooldowns[characterId] = now + ((Config.Chat.cooldownSeconds or 2) * 1000)
    if GetResourceState('cm-chat') ~= 'started' then return false, 'chat_unavailable' end
    local okName, name = pcall(function() return exports[PLAYERDATA]:GetCharacterFullName(src) end)
    name = okName and name and tostring(name) or 'Unknown'
    local mode = requestedMode == 'rp' and 'rp' or 'nonrp'
    TriggerEvent('cm-chat:server:gangMessage', {
        source = src, characterId = characterId, gangId = membership.gangId,
        gangName = membership.displayName, tag = membership.shortTag, color = membership.color,
        rankName = membership.rankName, name = name, message = message, mode = mode,
    })
    return true
end)

RegisterCommand(Config.Commands.chat, function(source, args)
    if source <= 0 then return end
    local ok, reason = exports[RESOURCE]:SendGangChat(source, table.concat(args, ' '))
    if not ok then TriggerClientEvent('cm-gang:client:notify', source, tostring(reason):gsub('_', ' '), 'error') end
end, false)

RegisterCommand(Config.Commands.chatRp, function(source, args)
    if source <= 0 then return end
    local ok, reason = exports[RESOURCE]:SendGangChat(source, table.concat(args, ' '), 'rp')
    if not ok then TriggerClientEvent('cm-gang:client:notify', source, tostring(reason):gsub('_', ' '), 'error') end
end, false)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    local characterId = data and tostring(data.charId or data.characterId or '') or ''
    if characterId:match('^%d+$') then sourceCharacters[tonumber(src)] = characterId end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    local characterId = sourceCharacters[src] or characterIdForSource(src)
    sourceCharacters[src] = nil
    if characterId then chatCooldowns[characterId] = nil end
end)

AddEventHandler('onResourceStop', function(name)
    if name == RESOURCE then chatCooldowns, sourceCharacters, selectedContacts = {}, {}, {} end
end)
