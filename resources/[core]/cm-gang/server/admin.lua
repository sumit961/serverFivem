local RESOURCE = GetCurrentResourceName()
local ADMIN = 'cm-admin'
local leaderMutationLocks = {}

local function fixed(id) return Config.IsFixedGangId(tostring(id or '')) and tostring(id) or nil end
local function admin(src, permission)
    src = tonumber(src)
    if not src or GetInvokingResource() ~= ADMIN or GetResourceState(ADMIN) ~= 'started' then return nil end
    local ok, allowed = pcall(function() return exports[ADMIN]:HasPermission(src, permission or 'gang.admin.manage') end)
    if not ok or allowed ~= true then return nil end
    local cidOk, cid = pcall(function() return exports['cm-playerdata']:GetCharacterId(src) end)
    return cidOk and cid and tostring(cid) or nil
end
local function text(value, maximum, required)
    value = tostring(value or ''):gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if (required and value == '') or #value > maximum then return nil end
    return value
end
local function refreshGangHeadquarters(gangId)
    if GetResourceState('cm-playerdata') ~= 'started' then return end
    local rows = MySQL.query.await('SELECT character_id FROM cm_gang_members WHERE gang_id=?', { gangId }) or {}
    for _, row in ipairs(rows) do
        local ok, playerSrc = pcall(function() return exports['cm-playerdata']:GetSourceByCharId(tostring(row.character_id)) end)
        playerSrc = ok and tonumber(playerSrc) or nil
        if playerSrc and GetPlayerName(playerSrc) then TriggerClientEvent('cm-gang:client:refreshHeadquarters', playerSrc) end
    end
end

local function log(gangId, action, actorCid, targetCid, detail)
    MySQL.insert.await([[INSERT INTO cm_gang_activity
        (event_uid,gang_id,action,actor_character_id,target_character_id,detail) VALUES (?,?,?,?,?,?)]],
        { ('admin:%s:%s:%s'):format(action, os.time(), lib.string.random('Aa0', 10)), gangId, action,
          actorCid, targetCid, json.encode(detail or {}) })
end
local function reload(src)
    local ok, result, reason = pcall(function() return CMGangReloadDomainForAdmin(src) end)
    return ok and result == true, ok and reason or 'domain_reload_failed'
end

local function withAdminGangMutation(gangId, label, callback)
    if type(CMGangAcquireMutationLock) ~= 'function' or type(CMGangReleaseMutationLock) ~= 'function' then
        return false, 'domain_not_ready'
    end
    local token = ('admin:%s:%s:%d'):format(tostring(label or 'mutation'), gangId, GetGameTimer())
    if not CMGangAcquireMutationLock(gangId, token) then return false, 'operation_busy' end
    local ok, success, result, extra = xpcall(callback, debug.traceback)
    CMGangReleaseMutationLock(gangId, token)
    if not ok then
        print(('[cm-gang] admin %s failed: %s'):format(tostring(label or 'mutation'), tostring(success)))
        return false, 'internal_error'
    end
    return success, result, extra
end

exports('AdminGetGangManagement', function(src)
    if not admin(src, 'gang.admin.view') then return { ok=false, error='permission_denied' } end
    local gangs = MySQL.query.await([[SELECT gang_id,display_name,short_tag,color,logo_asset,art_asset,
        leader_character_id,enabled FROM cm_gangs ORDER BY gang_id]]) or {}
    local ranks = MySQL.query.await([[SELECT id,gang_id,tier,name,permissions,is_leader_rank
        FROM cm_gang_ranks ORDER BY gang_id,tier DESC]]) or {}
    local facilities = MySQL.query.await([[SELECT gang_id,facility_type,enabled,npc_model,display_name,
        role_label,x,y,z,heading,routing_bucket FROM cm_gang_facilities ORDER BY gang_id,facility_type]]) or {}
    local counts = MySQL.query.await('SELECT gang_id,COUNT(*) member_count FROM cm_gang_members GROUP BY gang_id') or {}
    local activity = MySQL.query.await([[SELECT gang_id,action,actor_character_id,target_character_id,vehicle_id,created_at
        FROM cm_gang_activity ORDER BY id DESC LIMIT 100]]) or {}
    -- Armory now lives in cm-law's shared cm_legal_armory_stock table
    -- (server/storage.lua migrated onto it), namespaced per gang as
    -- 'gang:<gangId>'. The old cm_gang_armory_config table is left in place
    -- unused rather than dropped, but is no longer read here.
    local armoryRows = MySQL.query.await([[SELECT organization_id,item_name AS item_id,enabled,
        min_tier AS minimum_tier,issue_amount AS issue_quantity,stock AS stock_quantity
        FROM cm_legal_armory_stock WHERE organization_id LIKE 'gang:%' ORDER BY organization_id,item_name]]) or {}
    local armory = {}
    for _, row in ipairs(armoryRows) do
        row.gang_id = tostring(row.organization_id):match('^gang:(.+)$')
        row.organization_id = nil
        row.issue_limit = 0
        if row.gang_id then armory[#armory + 1] = row end
    end
    local fleet = MySQL.query.await([[SELECT gang_id,catalog_id,vehicle_id,enabled,minimum_tier,trunk_minimum_tier,x,y,z
        FROM cm_gang_fleet_vehicles ORDER BY gang_id,catalog_id]]) or {}
    local profits=MySQL.query.await('SELECT gang_id,activity_score,pending_amount,last_tick_at,last_collected_at FROM cm_gang_profit') or {}
    local blacklists=MySQL.query.await('SELECT gang_id,character_id,character_name_snapshot,reason,created_at,expires_at FROM cm_gang_blacklist ORDER BY created_at DESC') or {}
    local wardrobes=MySQL.query.await('SELECT gang_id,id,name,sex,minimum_tier FROM cm_gang_wardrobe_outfits ORDER BY gang_id,name') or {}
    local staleInvites = MySQL.query.await([[SELECT gang_id,COUNT(*) count FROM cm_gang_invites
        WHERE status='pending' AND expires_at<=NOW() GROUP BY gang_id]]) or {}
    local leaderCounts = MySQL.query.await([[SELECT gang_id,COUNT(*) count FROM cm_gang_members
        WHERE is_leader=1 GROUP BY gang_id]]) or {}
    local byId = {}; for _, g in ipairs(gangs) do if fixed(g.gang_id) then g.enabled=CMGangDbTrue(g.enabled); g.ranks={}; g.facilities={}; g.armory={}; g.fleet={}; g.blacklist={}; g.wardrobe={}; g.profit={activity_score=0,pending_amount=0}; g.memberCount=0; g.activity={}; g.recovery={staleInvites=0,leaderMembers=0}; byId[g.gang_id]=g end end
    for _, r in ipairs(ranks) do local g=byId[r.gang_id]; if g then local ok,p=pcall(json.decode,r.permissions or '{}'); r.permissions=ok and p or {}; r.isLeaderRank=CMGangDbTrue(r.is_leader_rank); g.ranks[#g.ranks+1]=r end end
    for _, f in ipairs(facilities) do local g=byId[f.gang_id]; if g then f.enabled=CMGangDbTrue(f.enabled); g.facilities[#g.facilities+1]=f end end
    for _, c in ipairs(counts) do if byId[c.gang_id] then byId[c.gang_id].memberCount=tonumber(c.member_count) or 0 end end
    for _, a in ipairs(activity) do if byId[a.gang_id] and #byId[a.gang_id].activity < 15 then byId[a.gang_id].activity[#byId[a.gang_id].activity+1]=a end end
    for _, item in ipairs(armory) do local g=byId[item.gang_id]; if g then item.enabled=CMGangDbTrue(item.enabled); g.armory[#g.armory+1]=item end end
    for _, vehicle in ipairs(fleet) do local g=byId[vehicle.gang_id]; if g then vehicle.enabled=CMGangDbTrue(vehicle.enabled); vehicle.configured=vehicle.vehicle_id~=nil and vehicle.x~=nil and vehicle.y~=nil and vehicle.z~=nil; g.fleet[#g.fleet+1]=vehicle end end
    for _,row in ipairs(profits) do if byId[row.gang_id] then byId[row.gang_id].profit=row end end
    for _,row in ipairs(blacklists) do if byId[row.gang_id] then byId[row.gang_id].blacklist[#byId[row.gang_id].blacklist+1]=row end end
    for _,row in ipairs(wardrobes) do if byId[row.gang_id] then byId[row.gang_id].wardrobe[#byId[row.gang_id].wardrobe+1]=row end end
    for _, row in ipairs(staleInvites) do if byId[row.gang_id] then byId[row.gang_id].recovery.staleInvites=tonumber(row.count) or 0 end end
    for _, row in ipairs(leaderCounts) do if byId[row.gang_id] then byId[row.gang_id].recovery.leaderMembers=tonumber(row.count) or 0 end end
    local weaponCatalog={}
    if GetResourceState('cm-weapons')=='started' then
        local ok,weapons=pcall(function() return exports['cm-weapons']:GetAllWeapons(false) end)
        if ok and type(weapons)=='table' then for _,weapon in ipairs(weapons) do
            weaponCatalog[#weaponCatalog+1]={itemName=tostring(weapon.itemName or ''),label=tostring(weapon.label or weapon.itemName or ''),
                ammoItem=weapon.ammoItem and tostring(weapon.ammoItem) or nil,image=tostring(weapon.image or ''),group=tostring(weapon.group or 'weapon')}
        end end
    end
    local out={}; for _, id in ipairs(Config.GangIds) do if byId[id] then out[#out+1]=byId[id] end end
    return { ok=#out==#Config.GangIds, gangs=out, graffiti=type(CMGangGraffitiAdminList)=='function' and CMGangGraffitiAdminList() or {}, permissions=Config.Permissions, npcModels=Config.NpcModels, assetKeys=Config.AssetKeys,
        legacyGangIds=Config.LegacyGangIds,weaponCatalog=weaponCatalog }
end)

exports('AdminUpdateIdentity', function(src, gangId, data)
    local actor, id = admin(src), fixed(gangId); if not actor or not id or type(data)~='table' then return false,'invalid_request' end
    local name, tag = text(data.displayName,64,true), text(data.shortTag,12,true)
    local color=tostring(data.color or ''):lower(); if not color:match('^#%x%x%x%x%x%x$') then return false,'invalid_color' end
    local logo=text(data.logoAsset,96,false); local art=text(data.artAsset,96,false)
    if logo~='' and Config.AssetKeys.logos[logo]~=true then return false,'invalid_logo_asset' end
    if art~='' and Config.AssetKeys.artwork[art]~=true then return false,'invalid_art_asset' end
    if not name or not tag then return false,'invalid_identity' end
    MySQL.update.await([[UPDATE cm_gangs SET display_name=?,short_tag=?,color=?,logo_asset=NULLIF(?,''),
        art_asset=NULLIF(?,''),enabled=? WHERE gang_id=?]],{name,tag,color,logo,art,data.enabled==true and 1 or 0,id})
    log(id,'admin_identity_updated',actor,nil,{enabled=data.enabled==true})
    local refreshed, reason = reload(src); if not refreshed then return false, reason end
    return true,'Gang identity saved.'
end)

exports('AdminSetFacility', function(src, gangId, data)
    local actor,id=admin(src),fixed(gangId); if not actor or not id or type(data)~='table' or not Config.FacilityTypes[data.facilityType] then return false,'invalid_request' end
    local kind=data.facilityType
    if data.reset==true then
        MySQL.update.await([[UPDATE cm_gang_facilities SET enabled=0,npc_model=NULL,display_name=NULL,role_label=NULL,
            x=NULL,y=NULL,z=NULL,heading=NULL,routing_bucket=0,updated_by=? WHERE gang_id=? AND facility_type=?]],{actor,id,kind})
    else
        local ped=GetPlayerPed(src); if not ped or ped==0 or not DoesEntityExist(ped) then return false,'admin_entity_unavailable' end
        local c=GetEntityCoords(ped); local model=text(data.npcModel,64,false) or ''
        if (kind=='headquarters' or kind=='fleet' or kind=='profit') and model=='' then
            local pool=Config.ContactNpcs[id] and Config.ContactNpcs[id].models or {}
            model=tostring(pool[1] or '')
        end
        if (kind=='headquarters' or kind=='fleet' or kind=='profit') and model~='' and Config.NpcModels[model]~=true then return false,'invalid_npc_model' end
        local display=text(data.displayName,64,false); local role=text(data.roleLabel,64,false)
        if display==nil or role==nil then return false,'invalid_labels' end
        local changed=MySQL.update.await([[UPDATE cm_gang_facilities SET enabled=?,npc_model=NULLIF(?,''),display_name=NULLIF(?,''),
            role_label=NULLIF(?,''),x=?,y=?,z=?,heading=?,routing_bucket=?,updated_by=?
            WHERE gang_id=? AND facility_type=?]],{kind=='headquarters' and 1 or (data.enabled==true and 1 or 0),model,display,role,c.x,c.y,c.z,
            GetEntityHeading(ped),kind=='headquarters' and 0 or GetPlayerRoutingBucket(src),actor,id,kind})
        local saved=MySQL.single.await([[SELECT enabled,npc_model,x,y,z,heading,routing_bucket FROM cm_gang_facilities
            WHERE gang_id=? AND facility_type=? LIMIT 1]],{id,kind})
        if not saved or tonumber(saved.x)==nil or tonumber(saved.y)==nil or tonumber(saved.z)==nil then
            return false,'facility_row_not_updated'
        end
    end
    log(id,data.reset==true and 'admin_facility_reset' or 'admin_facility_updated',actor,nil,{facilityType=kind})
    if kind == 'headquarters' or kind == 'fleet' or kind == 'profit' then
        refreshGangHeadquarters(id)
        if GetConvar('cm_environment','production')=='development' then
            local row=MySQL.single.await([[SELECT enabled,npc_model,x,y,z,routing_bucket FROM cm_gang_facilities
                WHERE gang_id=? AND facility_type='headquarters' LIMIT 1]],{id})
            print(('[cm-gang] contact sync gang=%s enabled=%s model=%s configured=%s bucket=%s'):format(
                id,tostring(row and CMGangDbTrue(row.enabled) or false),tostring(row and row.npc_model or 'fallback'),
                tostring(row and tonumber(row.x)~=nil and tonumber(row.y)~=nil and tonumber(row.z)~=nil),tostring(row and row.routing_bucket or 0)))
        end
    end
    return true,data.reset==true and 'Facility reset.' or 'Facility saved at your current location.'
end)

local function dumpContactStatus()
    if GetConvar('cm_environment','production')~='development' then return end
    for _,gangId in ipairs(Config.GangIds or {}) do
        local row=MySQL.single.await([[SELECT g.enabled gang_enabled,f.enabled,f.npc_model,f.x,f.y,f.z,f.heading,f.routing_bucket
            FROM cm_gangs g LEFT JOIN cm_gang_facilities f ON f.gang_id=g.gang_id AND f.facility_type='headquarters'
            WHERE g.gang_id=? LIMIT 1]],{gangId})
        local online=0
        for _,member in ipairs(MySQL.query.await('SELECT character_id FROM cm_gang_members WHERE gang_id=?',{gangId}) or {}) do
            local ok,playerSrc=pcall(function() return exports['cm-playerdata']:GetSourceByCharId(tostring(member.character_id)) end)
            if ok and tonumber(playerSrc) and GetPlayerName(tonumber(playerSrc)) then online=online+1 end
        end
        print(('[cm-gang] contact status gang=%s gangEnabled=%s facilityEnabled=%s model=%s coords=%s heading=%s bucket=%s onlineMembers=%d'):format(
            gangId,tostring(row and CMGangDbTrue(row.gang_enabled) or false),tostring(row and CMGangDbTrue(row.enabled) or false),
            tostring(row and row.npc_model or 'fallback'),tostring(row and tonumber(row.x)~=nil and tonumber(row.y)~=nil and tonumber(row.z)~=nil),
            tostring(row and row.heading or 'nil'),tostring(row and row.routing_bucket or 'nil'),online))
    end
    for _,row in ipairs(MySQL.query.await([[SELECT gang_id,facility_type,enabled,x,y,z FROM cm_gang_facilities
        WHERE x IS NOT NULL OR y IS NOT NULL OR z IS NOT NULL ORDER BY gang_id,facility_type]]) or {}) do
        print(('[cm-gang] configured facility gang=%s type=%s enabled=%s coords=%s'):format(
            tostring(row.gang_id),tostring(row.facility_type),tostring(CMGangDbTrue(row.enabled)),
            tostring(tonumber(row.x)~=nil and tonumber(row.y)~=nil and tonumber(row.z)~=nil)))
    end
end

RegisterCommand('cm_gang_contact_status',function(source)
    if source==0 then dumpContactStatus() end
end,true)

CreateThread(function()
    while not CMGangDatabaseReady do
        if CMGangDatabaseError and CMGangDatabaseError~='initializing' then return end
        Wait(100)
    end
    dumpContactStatus()
end)

local function allGangPermissions()
    local permissions = {}
    for _, permission in ipairs(Config.Permissions or {}) do
        permissions[tostring(permission.key)] = true
    end
    return permissions
end

local function repairLeaderRankBaseline(gangId)
    local ranks = MySQL.query.await([[SELECT id,tier,name,is_leader_rank
        FROM cm_gang_ranks WHERE gang_id=? ORDER BY tier DESC,id ASC]], { gangId }) or {}
    local leaderRank
    local repaired = false
    for _, rank in ipairs(ranks) do
        if CMGangDbTrue(rank.is_leader_rank) then leaderRank = rank; break end
    end

    -- Never convert an existing member rank into the leader rank: that can
    -- grant leader permissions to every member currently assigned to it.
    -- Recovery instead reserves tier 100 and creates a dedicated leader row.
    if not leaderRank then
        local tier100
        local used = {}
        for _, rank in ipairs(ranks) do
            used[tonumber(rank.tier)] = true
            if tonumber(rank.tier) == 100 then tier100 = rank end
        end
        if tier100 then
            local replacementTier
            for tier = 99, 1, -1 do
                if not used[tier] then replacementTier = tier; break end
            end
            if not replacementTier then return nil, nil, false, 'rank_tiers_exhausted' end
            local moved = MySQL.update.await('UPDATE cm_gang_ranks SET tier=? WHERE id=? AND gang_id=? AND is_leader_rank=0',
                { replacementTier, tier100.id, gangId })
            if tonumber(moved) ~= 1 then return nil, nil, false, 'tier_100_recovery_failed' end
            tier100.tier = replacementTier
            used[100], used[replacementTier] = nil, true
        end
        local rankId = MySQL.insert.await([[INSERT INTO cm_gang_ranks
            (gang_id,tier,name,permissions,is_leader_rank) VALUES (?,100,'Leader',?,1)]],
            { gangId, json.encode(allGangPermissions()) })
        if not rankId then return nil, nil, false, 'leader_rank_create_failed' end
        leaderRank = { id = rankId, tier = 100, name = 'Leader', is_leader_rank = 1 }
        repaired = true
    else
        -- The dedicated leader rank is always tier 100 and always has every
        -- gang permission. If legacy data put a non-leader at tier 100, move
        -- that rank first instead of letting the unique tier constraint fail.
        if tonumber(leaderRank.tier) ~= 100 then
            local tier100, used = nil, {}
            for _, rank in ipairs(ranks) do
                used[tonumber(rank.tier)] = true
                if tonumber(rank.tier) == 100 and tonumber(rank.id) ~= tonumber(leaderRank.id) then tier100 = rank end
            end
            if tier100 then
                local replacementTier
                for tier = 99, 1, -1 do if not used[tier] then replacementTier = tier; break end end
                if not replacementTier then return nil, nil, false, 'rank_tiers_exhausted' end
                local moved = MySQL.update.await('UPDATE cm_gang_ranks SET tier=? WHERE id=? AND gang_id=? AND is_leader_rank=0',
                    { replacementTier, tier100.id, gangId })
                if tonumber(moved) ~= 1 then return nil, nil, false, 'tier_100_recovery_failed' end
                repaired = true
            end
        end
        local changed = MySQL.update.await([[UPDATE cm_gang_ranks SET tier=100,permissions=?
            WHERE id=? AND gang_id=? AND is_leader_rank=1]],
            { json.encode(allGangPermissions()), leaderRank.id, gangId })
        leaderRank.tier = 100
        if tonumber(changed) and tonumber(changed) > 0 then repaired = true end
    end

    local refreshedRanks = MySQL.query.await([[SELECT id,tier,name,is_leader_rank
        FROM cm_gang_ranks WHERE gang_id=? ORDER BY tier DESC,id ASC]], { gangId }) or {}
    local fallbackRank
    for _, rank in ipairs(refreshedRanks) do
        if not CMGangDbTrue(rank.is_leader_rank) then fallbackRank = rank; break end
    end

    if not fallbackRank then
        local used = { [100] = true }
        for _, rank in ipairs(refreshedRanks) do used[tonumber(rank.tier)] = true end
        local fallbackTier
        for _, tier in ipairs({ 80, 60, 40, 20, 1 }) do
            if not used[tier] then fallbackTier = tier; break end
        end
        if not fallbackTier then
            for tier = 99, 1, -1 do if not used[tier] then fallbackTier = tier; break end end
        end
        if not fallbackTier then return nil, nil, false, 'rank_tiers_exhausted' end
        local fallbackPermissions = { ['gang.view_members'] = true, ['gang.chat'] = true }
        local rankId = MySQL.insert.await([[INSERT INTO cm_gang_ranks
            (gang_id,tier,name,permissions,is_leader_rank) VALUES (?,?,'Member',?,0)]],
            { gangId, fallbackTier, json.encode(fallbackPermissions) })
        if not rankId then return nil, nil, false, 'fallback_rank_create_failed' end
        fallbackRank = { id = rankId, tier = fallbackTier, name = 'Member', is_leader_rank = 0 }
        repaired = true
    end

    -- A non-leader must never inherit the dedicated leader rank's complete
    -- permission set. Repair stale legacy assignments before returning.
    local reassigned = MySQL.update.await([[UPDATE cm_gang_members
        SET rank_id=? WHERE gang_id=? AND rank_id=? AND is_leader=0]],
        { fallbackRank.id, gangId, leaderRank.id })
    if tonumber(reassigned) and tonumber(reassigned) > 0 then repaired = true end

    return leaderRank, fallbackRank, repaired
end

exports('AdminAssignLeader', function(src, targetCid, gangId)
    local actor,id=admin(src),fixed(gangId); targetCid=tostring(targetCid or '')
    if not actor or not id or not targetCid:match('^%d+$') or #targetCid>64 then return false,'invalid_request' end
    local targetLockKey = 'target:' .. targetCid
    if leaderMutationLocks[targetLockKey] then return false, 'operation_busy' end
    leaderMutationLocks[targetLockKey] = true
    local gangToken = ('admin:leader_assign:%s:%s:%d'):format(id, targetCid, GetGameTimer())
    if type(CMGangAcquireMutationLock) ~= 'function' or not CMGangAcquireMutationLock(id, gangToken) then
        leaderMutationLocks[targetLockKey] = nil
        return false, 'operation_busy'
    end
    local ok, success, result = xpcall(function()
        local exists=MySQL.scalar.await('SELECT 1 FROM characters WHERE id=? LIMIT 1',{tonumber(targetCid)})
        if not exists then return false,'character_not_found' end
        local occupied=MySQL.single.await('SELECT gang_id FROM cm_gang_members WHERE character_id=? LIMIT 1',{targetCid})
        if occupied and occupied.gang_id~=id then return false,'character_in_another_gang' end
        local repairedOk, leaderRank, fallback, repaired, repairReason = pcall(repairLeaderRankBaseline, id)
        if not repairedOk then
            print(('[cm-gang] rank baseline repair failed for %s: %s'):format(id, tostring(leaderRank)))
            return false,'rank_configuration_repair_failed'
        end
        if not leaderRank or not fallback then return false,repairReason or 'rank_configuration_broken' end
        -- Recheck immediately before the transaction. Combined with the
        -- in-resource lock this prevents a concurrent leader assignment from
        -- using ON DUPLICATE KEY UPDATE to move a member out of another gang.
        occupied=MySQL.single.await('SELECT gang_id FROM cm_gang_members WHERE character_id=? LIMIT 1',{targetCid})
        if occupied and occupied.gang_id~=id then return false,'character_in_another_gang' end
        local old=MySQL.scalar.await('SELECT leader_character_id FROM cm_gangs WHERE gang_id=?',{id})
        local queries={
          {query=[[UPDATE cm_gang_members gm
            SET gm.is_leader=0, gm.rank_id=?
            WHERE gm.gang_id=? AND gm.is_leader=1
              AND NOT EXISTS (
                SELECT 1 FROM (SELECT gang_id,character_id FROM cm_gang_members) occupied
                WHERE occupied.character_id=? AND occupied.gang_id<>?
              )]],values={fallback.id,id,targetCid,id}},
          {query=[[INSERT INTO cm_gang_members (gang_id,character_id,rank_id,is_leader)
            SELECT ?,?,?,1 FROM DUAL
            WHERE NOT EXISTS (SELECT 1 FROM cm_gang_members WHERE character_id=? AND gang_id<>?)
            ON DUPLICATE KEY UPDATE
              rank_id=IF(gang_id=VALUES(gang_id),VALUES(rank_id),rank_id),
              is_leader=IF(gang_id=VALUES(gang_id),1,is_leader)]],values={id,targetCid,leaderRank.id,targetCid,id}},
          {query=[[UPDATE cm_gangs g
            INNER JOIN cm_gang_members m ON m.gang_id=g.gang_id AND m.character_id=? AND m.is_leader=1
            SET g.leader_character_id=? WHERE g.gang_id=?]],values={targetCid,targetCid,id}},
        }
        if not MySQL.transaction.await(queries) then return false,'transaction_failed' end
        local verified=MySQL.scalar.await('SELECT 1 FROM cm_gang_members WHERE gang_id=? AND character_id=? AND is_leader=1 LIMIT 1',{id,targetCid})
        if not verified then return false,'leader_assignment_race_rejected' end
        if repaired then log(id,'admin_rank_baseline_repaired',actor,nil,{}) end
        log(id,'admin_leader_assigned',actor,targetCid,{previousLeader=old})
        local refreshed, reason = reload(src); if not refreshed then return false, reason end
        return true,'Gang leader assigned.'
    end, debug.traceback)
    if type(CMGangReleaseMutationLock) == 'function' then CMGangReleaseMutationLock(id, gangToken) end
    leaderMutationLocks[targetLockKey] = nil
    if not ok then
        print(('[cm-gang] admin leader assignment failed: %s'):format(tostring(success)))
        return false, 'internal_error'
    end
    return success, result
end)

exports('AdminRemoveLeader', function(src, gangId)
    local actor,id=admin(src),fixed(gangId); if not actor or not id then return false,'invalid_request' end
    local gangToken = ('admin:leader_remove:%s:%d'):format(id, GetGameTimer())
    if type(CMGangAcquireMutationLock) ~= 'function' or not CMGangAcquireMutationLock(id, gangToken) then return false,'operation_busy' end
    local ok, success, result = xpcall(function()
        local pointer=MySQL.scalar.await('SELECT leader_character_id FROM cm_gangs WHERE gang_id=?',{id})
        local leaderMember=MySQL.scalar.await('SELECT character_id FROM cm_gang_members WHERE gang_id=? AND is_leader=1 LIMIT 1',{id})
        local old=leaderMember or pointer
        if not old then return false,'leader_not_set' end
        if not MySQL.transaction.await({
          {query='DELETE FROM cm_gang_members WHERE gang_id=? AND is_leader=1',values={id}},
          {query='UPDATE cm_gangs SET leader_character_id=NULL WHERE gang_id=?',values={id}},
        }) then return false,'transaction_failed' end
        local remains=MySQL.scalar.await('SELECT 1 FROM cm_gang_members WHERE gang_id=? AND is_leader=1 LIMIT 1',{id})
        if remains then return false,'leader_removal_verification_failed' end
        log(id,'admin_leader_removed',actor,old,{pointer=pointer})
        local refreshed, reason = reload(src); if not refreshed then return false, reason end
        return true,'Leader removed. Gang remains enabled without a leader.'
    end, debug.traceback)
    if type(CMGangReleaseMutationLock) == 'function' then CMGangReleaseMutationLock(id, gangToken) end
    if not ok then
        print(('[cm-gang] admin leader removal failed: %s'):format(tostring(success)))
        return false,'internal_error'
    end
    return success,result
end)

exports('AdminRecoverGang', function(src, gangId, operation)
    local actor,id=admin(src),fixed(gangId); if not actor or not id then return false,'invalid_request' end
    if operation=='expire_invites' then MySQL.update.await("UPDATE cm_gang_invites SET status='expired',resolved_at=NOW() WHERE gang_id=? AND status='pending' AND expires_at<=NOW()",{id})
    elseif operation=='reload_cache' then
        local refreshed, reason = reload(src); if not refreshed then return false, reason end
    else return false,'unknown_recovery_operation' end
    log(id,'admin_recovery',actor,nil,{operation=operation}); return true,'Recovery action completed.'
end)

exports('AdminMigrateLegacyGang',function(src,legacyGangId,gangId)
    local actor,id=admin(src),fixed(gangId); legacyGangId=tostring(legacyGangId or '')
    if not actor or not id or not Config.IsLegacyGangId(legacyGangId) then return false,'invalid_request' end
    local legacy=MySQL.scalar.await('SELECT 1 FROM cm_gangs WHERE gang_id=?',{legacyGangId})
    if not legacy then return false,'legacy_gang_not_found' end
    local destinationUse=tonumber(MySQL.scalar.await([[SELECT
        (SELECT COUNT(*) FROM cm_gang_members WHERE gang_id=?)+
        (SELECT COUNT(*) FROM cm_gang_fleet_vehicles WHERE gang_id=?)+
        (SELECT COUNT(*) FROM cm_gang_armory_config WHERE gang_id=?)+
        (SELECT COUNT(*) FROM cm_gang_blacklist WHERE gang_id=?)+
        (SELECT COUNT(*) FROM cm_gang_wardrobe_outfits WHERE gang_id=?)]],{id,id,id,id,id})) or 0
    if destinationUse>0 then return false,'canonical_gang_has_data_choose_empty_destination' end
    local lockToken='legacy:'..legacyGangId..':'..GetGameTimer()
    if not CMGangAcquireMutationLock(id,lockToken) then return false,'operation_busy' end
    local ok,success,message=xpcall(function()
        local committed=MySQL.transaction.await({
            {query='DELETE FROM cm_gang_facilities WHERE gang_id=?',values={id}},
            {query='DELETE FROM cm_gang_profit WHERE gang_id=?',values={id}},
            {query='DELETE FROM cm_gang_ranks WHERE gang_id=?',values={id}},
            {query=[[INSERT INTO cm_gang_ranks(gang_id,tier,name,permissions,is_leader_rank) SELECT ?,tier,name,permissions,is_leader_rank FROM cm_gang_ranks WHERE gang_id=?]],values={id,legacyGangId}},
            {query=[[UPDATE cm_gang_members m
                JOIN cm_gang_ranks oldr ON oldr.id=m.rank_id AND oldr.gang_id=m.gang_id
                JOIN cm_gang_ranks nr ON nr.gang_id=? AND nr.tier=oldr.tier
                SET m.gang_id=?,m.rank_id=nr.id WHERE m.gang_id=?]],values={id,id,legacyGangId}},
            {query=[[INSERT INTO cm_gang_facilities(gang_id,facility_type,enabled,npc_model,display_name,role_label,x,y,z,heading,routing_bucket,updated_by)
                SELECT ?,facility_type,enabled,npc_model,display_name,role_label,x,y,z,heading,routing_bucket,updated_by FROM cm_gang_facilities WHERE gang_id=?]],values={id,legacyGangId}},
            {query='UPDATE cm_gang_fleet_vehicles SET gang_id=? WHERE gang_id=?',values={id,legacyGangId}},
            {query='UPDATE cm_gang_armory_config SET gang_id=? WHERE gang_id=?',values={id,legacyGangId}},
            {query='UPDATE cm_gang_armory_issues SET gang_id=? WHERE gang_id=?',values={id,legacyGangId}},
            {query='UPDATE cm_gang_blacklist SET gang_id=? WHERE gang_id=?',values={id,legacyGangId}},
            {query='UPDATE cm_gang_wardrobe_outfits SET gang_id=? WHERE gang_id=?',values={id,legacyGangId}},
            {query='UPDATE cm_gang_activity SET gang_id=? WHERE gang_id=?',values={id,legacyGangId}},
            {query='UPDATE cm_gang_profit SET gang_id=? WHERE gang_id=?',values={id,legacyGangId}},
            {query="UPDATE cm_gang_invites SET status='cancelled',resolved_at=NOW() WHERE gang_id=? AND status='pending'",values={legacyGangId}},
            {query='DELETE FROM cm_gang_invites WHERE gang_id=?',values={legacyGangId}},
            {query='DELETE FROM cm_gang_members WHERE gang_id=?',values={legacyGangId}},
            {query='DELETE FROM cm_gang_facilities WHERE gang_id=?',values={legacyGangId}},
            {query='DELETE FROM cm_gang_ranks WHERE gang_id=?',values={legacyGangId}},
            {query='UPDATE cm_gangs dst JOIN cm_gangs src ON src.gang_id=? SET dst.leader_character_id=src.leader_character_id,dst.enabled=src.enabled WHERE dst.gang_id=?',values={legacyGangId,id}},
            {query='DELETE FROM cm_gangs WHERE gang_id=?',values={legacyGangId}},
        })
        if committed~=true then return false,'migration_transaction_failed' end
        local refreshed,reason=reload(src); if not refreshed then return false,reason end
        log(id,'legacy_gang_migrated',actor,nil,{legacyGangId=legacyGangId}); refreshGangHeadquarters(id)
        return true,'Legacy gang migrated transactionally.'
    end,debug.traceback)
    CMGangReleaseMutationLock(id,lockToken)
    if not ok then print(('[cm-gang] legacy migration failed: %s'):format(tostring(success))); return false,'migration_failed_no_changes_committed' end
    return success,message
end)

exports('AdminCreateRank', function(src, gangId, data)
    local actor,id=admin(src),fixed(gangId); if not actor or not id or type(data)~='table' then return false,'invalid_request' end
    return withAdminGangMutation(id, 'rank_create', function()
        local name=text(data.name,Config.Ranks.nameMaximumLength,true)
        local tier=math.floor(tonumber(data.tier) or 0)
        if not name or tier<1 or tier>99 then return false,'invalid_rank' end
        local count=tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_gang_ranks WHERE gang_id=?',{id})) or 0
        if count>=Config.Ranks.maximum then return false,'rank_limit' end
        local permissions,allowed={},{}; for _,p in ipairs(Config.Permissions) do allowed[p.key]=true end
        if type(data.permissions)=='table' then for _,key in ipairs(data.permissions) do key=tostring(key); if allowed[key] then permissions[key]=true end end end
        local insertedOk,rankId=pcall(function() return MySQL.insert.await([[INSERT INTO cm_gang_ranks
            (gang_id,tier,name,permissions,is_leader_rank) VALUES (?,?,?,?,0)]],{id,tier,name,json.encode(permissions)}) end)
        if not insertedOk or not rankId then return false,'rank_name_or_tier_conflict' end
        log(id,'admin_rank_created',actor,nil,{rankId=tonumber(rankId),tier=tier})
        local refreshed, reason = reload(src); if not refreshed then return false, reason end
        return true,'Gang rank created.',tonumber(rankId)
    end)
end)

exports('AdminDeleteRank', function(src, gangId, rankId)
    local actor,id=admin(src),fixed(gangId); rankId=tonumber(rankId)
    if not actor or not id or not rankId then return false,'invalid_request' end
    return withAdminGangMutation(id, 'rank_delete', function()
        local rank=MySQL.single.await('SELECT id,is_leader_rank,name FROM cm_gang_ranks WHERE id=? AND gang_id=?',{rankId,id})
        if not rank then return false,'rank_not_found' end
        if CMGangDbTrue(rank.is_leader_rank) then return false,'leader_rank_protected' end
        local nonLeaderCount=tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_gang_ranks WHERE gang_id=? AND is_leader_rank=0',{id})) or 0
        if nonLeaderCount<=1 then return false,'last_nonleader_rank_protected' end
        local inUse=tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_gang_members WHERE gang_id=? AND rank_id=?',{id,rankId})) or 0
        if inUse>0 then return false,'rank_in_use' end
        local changed=MySQL.update.await('DELETE FROM cm_gang_ranks WHERE id=? AND gang_id=?',{rankId,id})
        if tonumber(changed)~=1 then return false,'rank_delete_failed' end
        log(id,'admin_rank_deleted',actor,nil,{rankId=rankId,name=rank.name})
        local refreshed, reason = reload(src); if not refreshed then return false, reason end
        return true,'Gang rank deleted.'
    end)
end)

exports('AdminSaveRank', function(src, gangId, data)
    local actor,id=admin(src),fixed(gangId); if not actor or not id or type(data)~='table' then return false,'invalid_request' end
    return withAdminGangMutation(id, 'rank_save', function()
        local rankId=tonumber(data.rankId); local name=text(data.name,Config.Ranks.nameMaximumLength,true)
        local tier=math.floor(tonumber(data.tier) or 0); if not rankId or rankId<1 or not name or tier<1 or tier>100 then return false,'invalid_rank' end
        local existing=MySQL.single.await('SELECT is_leader_rank FROM cm_gang_ranks WHERE id=? AND gang_id=?',{rankId,id})
        if not existing then return false,'rank_not_found' end
        if CMGangDbTrue(existing.is_leader_rank) and tier~=100 then return false,'leader_rank_tier_locked' end
        if not CMGangDbTrue(existing.is_leader_rank) and tier>=100 then return false,'nonleader_rank_tier_invalid' end
        local permissions,allowed={},{}; for _,p in ipairs(Config.Permissions) do allowed[p.key]=true end
        if type(data.permissions)=='table' then for _,key in ipairs(data.permissions) do key=tostring(key); if allowed[key] then permissions[key]=true end end end
        if CMGangDbTrue(existing.is_leader_rank) then for key in pairs(allowed) do permissions[key]=true end end
        local ok=pcall(function() MySQL.update.await('UPDATE cm_gang_ranks SET name=?,tier=?,permissions=? WHERE id=? AND gang_id=?',{name,tier,json.encode(permissions),rankId,id}) end)
        if not ok then return false,'rank_name_or_tier_conflict' end
        log(id,'admin_rank_updated',actor,nil,{rankId=rankId,tier=tier})
        local refreshed, reason = reload(src); if not refreshed then return false, reason end
        return true,'Gang rank saved.'
    end)
end)

AddEventHandler('onResourceStop', function(name)
    if name == RESOURCE then leaderMutationLocks = {} end
end)
