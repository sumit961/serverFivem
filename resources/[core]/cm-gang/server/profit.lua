local RESOURCE, PLAYERDATA = GetCurrentResourceName(), 'cm-playerdata'
local locks, cooldowns = {}, {}

local function context(src,permission)
    src=tonumber(src); local ok,value=pcall(function() return exports[PLAYERDATA]:GetCharacterId(src) end)
    local characterId=ok and tostring(value or '') or ''; characterId=characterId:match('^%d+$') and characterId or nil
    if not characterId then return nil,'character_not_loaded' end
    local membership=exports[RESOURCE]:GetGangForCharacter(characterId)
    if not membership or membership.enabled~=true then return nil,'not_in_enabled_gang' end
    if permission and not exports[RESOURCE]:HasPermission(characterId,permission) then return nil,'no_permission' end
    return {source=src,characterId=characterId,membership=membership}
end

local function canIssueBonus(c)
    return c.membership.isLeader==true or exports[RESOURCE]:HasPermission(c.characterId,'gang.issue_bonus')
end

local function nearbyBonusTarget(c,targetCharacterId)
    targetCharacterId=tostring(targetCharacterId or '')
    if targetCharacterId=='' or targetCharacterId==c.characterId then return nil,'invalid_target' end
    local ok,targetSrc=pcall(function() return exports[PLAYERDATA]:GetSourceByCharId(targetCharacterId) end)
    targetSrc=ok and tonumber(targetSrc) or nil
    if not targetSrc or not GetPlayerName(targetSrc) then return nil,'member_not_online' end
    local membership=exports[RESOURCE]:GetGangForCharacter(targetCharacterId)
    if not membership or membership.enabled~=true or membership.gangId~=c.membership.gangId then return nil,'not_same_gang' end
    if GetPlayerRoutingBucket(targetSrc)~=GetPlayerRoutingBucket(c.source) then return nil,'not_nearby' end
    local actorPed,targetPed=GetPlayerPed(c.source),GetPlayerPed(targetSrc)
    if actorPed==0 or targetPed==0 or not DoesEntityExist(actorPed) or not DoesEntityExist(targetPed) then return nil,'player_entity_unavailable' end
    local distance=#(GetEntityCoords(actorPed)-GetEntityCoords(targetPed))
    if distance>(tonumber(Config.Profit.bonusDistance) or 5.0) then return nil,'not_nearby' end
    return {source=targetSrc,characterId=targetCharacterId,distance=distance}
end

local function read(gangId)
    local row=MySQL.single.await('SELECT activity_score,pending_amount,last_tick_at,last_collected_at FROM cm_gang_profit WHERE gang_id=?',{gangId}) or {}
    return {activityScore=tonumber(row.activity_score) or 0,pendingAmount=tonumber(row.pending_amount) or 0,lastTickAt=row.last_tick_at and tostring(row.last_tick_at) or nil,lastCollectedAt=row.last_collected_at and tostring(row.last_collected_at) or nil,tickIntervalSeconds=tonumber(Config.Profit.tickIntervalSeconds) or 3600}
end
local function nearCollector(c)
    local row=MySQL.single.await([[SELECT enabled,x,y,z,routing_bucket FROM cm_gang_facilities WHERE gang_id=? AND facility_type='profit' LIMIT 1]],{c.membership.gangId})
    if not row or not CMGangDbTrue(row.enabled) or not tonumber(row.x) or not tonumber(row.y) or not tonumber(row.z) then return false,'profit_facility_unavailable' end
    if GetPlayerRoutingBucket(c.source)~=(tonumber(row.routing_bucket) or 0) then return false,'wrong_routing_bucket' end
    local ped=GetPlayerPed(c.source); if not ped or ped==0 or not DoesEntityExist(ped) then return false,'player_entity_unavailable' end
    if #(GetEntityCoords(ped)-vector3(tonumber(row.x),tonumber(row.y),tonumber(row.z)))>(Config.Storage.facilityDistance or 3.0) then return false,'too_far_away' end
    return true
end

exports('GetGangProfit',function(actorCharacterId)
    local membership=exports[RESOURCE]:GetGangForCharacter(tostring(actorCharacterId or ''))
    if not membership then return nil,'not_in_gang' end; return read(membership.gangId)
end)

exports('AddGangProfitScore',function(gangId,amount)
    if GetInvokingResource()==nil or not Config.IsFixedGangId(gangId) then return false,'untrusted_or_invalid' end
    amount=math.floor(tonumber(amount) or 0); if amount<=0 or amount>100000000 then return false,'invalid_amount' end
    MySQL.update.await([[INSERT INTO cm_gang_profit(gang_id,activity_score) VALUES(?,?) ON DUPLICATE KEY UPDATE activity_score=activity_score+VALUES(activity_score)]],{gangId,amount}); return true
end)

exports('AddGangProfit',function(gangId,amount)
    if GetInvokingResource()==nil or not Config.IsFixedGangId(gangId) then return false,'untrusted_or_invalid' end
    amount=math.floor(tonumber(amount) or 0); if amount<=0 or amount>100000000 then return false,'invalid_amount' end
    MySQL.update.await([[INSERT INTO cm_gang_profit(gang_id,pending_amount) VALUES(?,?) ON DUPLICATE KEY UPDATE pending_amount=pending_amount+VALUES(pending_amount)]],{gangId,amount}); return true
end)

lib.callback.register('cm-gang:server:getProfit',function(src)
    local c,reason=context(src); if not c then return {ok=false,reason=reason} end; return {ok=true,profit=read(c.membership.gangId)}
end)

lib.callback.register('cm-gang:server:getNearbyBonusMembers',function(src)
    local c,reason=context(src); if not c then return {ok=false,reason=reason} end
    if not canIssueBonus(c) then return {ok=false,reason='no_permission'} end
    local members={}
    for _,rawTarget in ipairs(GetPlayers()) do
        local targetSrc=tonumber(rawTarget)
        if targetSrc and targetSrc~=c.source then
            local okId,targetCharacterId=pcall(function() return exports[PLAYERDATA]:GetCharacterId(targetSrc) end)
            local target=okId and nearbyBonusTarget(c,targetCharacterId) or nil
            if target then
                local okName,name=pcall(function() return exports[PLAYERDATA]:GetCharacterFullName(targetSrc) end)
                members[#members+1]={characterId=target.characterId,name=okName and tostring(name or 'Gang Member') or 'Gang Member',distance=math.floor(target.distance*10+0.5)/10}
            end
        end
    end
    table.sort(members,function(a,b) return a.distance<b.distance end)
    return {ok=true,members=members,maxAmount=tonumber(Config.Profit.maxBonusAmount) or 100000}
end)

lib.callback.register('cm-gang:server:issueNearbyBonus',function(src,data)
    local c,reason=context(src); if not c then return {ok=false,reason=reason} end
    if not canIssueBonus(c) then return {ok=false,reason='no_permission'} end
    data=type(data)=='table' and data or {}
    local amount=math.floor(tonumber(data.amount) or 0)
    if amount<1 or amount>(tonumber(Config.Profit.maxBonusAmount) or 100000) then return {ok=false,reason='invalid_amount'} end
    local target,targetReason=nearbyBonusTarget(c,data.targetCharacterId); if not target then return {ok=false,reason=targetReason} end
    local gangId=c.membership.gangId
    if locks[gangId] then return {ok=false,reason='operation_locked'} end
    if (cooldowns[c.characterId] or 0)>GetGameTimer() then return {ok=false,reason='rate_limited'} end
    locks[gangId]=true; cooldowns[c.characterId]=GetGameTimer()+2000
    local ok,result=xpcall(function()
        local claimed=MySQL.update.await('UPDATE cm_gang_profit SET pending_amount=pending_amount-? WHERE gang_id=? AND pending_amount>=?',{amount,gangId,amount})
        if tonumber(claimed)~=1 then return {ok=false,reason='insufficient_gang_funds'} end
        local paid,payReason=exports[PLAYERDATA]:AddCash(target.source,amount,'gang_member_bonus')
        if paid~=true then
            MySQL.update.await('UPDATE cm_gang_profit SET pending_amount=pending_amount+? WHERE gang_id=?',{amount,gangId})
            return {ok=false,reason=payReason or 'payment_failed'}
        end
        MySQL.insert.await([[INSERT INTO cm_gang_activity(event_uid,gang_id,action,actor_character_id,target_character_id,detail) VALUES(?,?,?,?,?,?)]],{('bonus:%s:%d:%d'):format(gangId,os.time(),math.random(100000,999999)),gangId,'member_bonus_issued',c.characterId,target.characterId,json.encode({amount=amount})})
        TriggerClientEvent('cm-gang:client:notify',target.source,('You received a $%d gang bonus.'):format(amount),'success')
        return {ok=true,amount=amount,profit=read(gangId)}
    end,debug.traceback)
    locks[gangId]=nil
    if not ok then print(('[cm-gang] member bonus failed: %s'):format(tostring(result))); return {ok=false,reason='bonus_failed'} end
    return result
end)

lib.callback.register('cm-gang:server:depositGangCash',function(src,rawAmount)
    local c,reason=context(src,'gang.stash'); if not c then return {ok=false,reason=reason} end
    local amount=math.floor(tonumber(rawAmount) or 0)
    if amount<1 or amount>(tonumber(Config.Profit.maxCollectAmount) or 1000000) then return {ok=false,reason='invalid_amount'} end
    -- Deposits belong to the main contact, not the profit collector.
    local hq=MySQL.single.await([[SELECT enabled,x,y,z,routing_bucket FROM cm_gang_facilities WHERE gang_id=? AND facility_type='headquarters' LIMIT 1]],{c.membership.gangId})
    if not hq or not CMGangDbTrue(hq.enabled) or not tonumber(hq.x) or not tonumber(hq.y) or not tonumber(hq.z)
        or GetPlayerRoutingBucket(c.source)~=(tonumber(hq.routing_bucket) or 0) then return {ok=false,reason='contact_not_configured'} end
    local ped=GetPlayerPed(c.source)
    if not ped or ped==0 or #(GetEntityCoords(ped)-vector3(tonumber(hq.x),tonumber(hq.y),tonumber(hq.z)))>(Config.Storage.facilityDistance or 3.0) then return {ok=false,reason='too_far_away'} end
    if locks[c.membership.gangId] then return {ok=false,reason='operation_locked'} end
    locks[c.membership.gangId]=true
    local removed=exports[PLAYERDATA]:RemoveCash(c.source,amount,'gang_common_fund_deposit')
    if removed~=true then locks[c.membership.gangId]=nil; return {ok=false,reason='insufficient_funds'} end
    local ok,changed=pcall(function() return MySQL.update.await([[INSERT INTO cm_gang_profit(gang_id,pending_amount) VALUES(?,?) ON DUPLICATE KEY UPDATE pending_amount=pending_amount+VALUES(pending_amount)]],{c.membership.gangId,amount}) end)
    if not ok or tonumber(changed)<1 then
        exports[PLAYERDATA]:AddCash(c.source,amount,'gang_common_fund_refund')
        locks[c.membership.gangId]=nil
        return {ok=false,reason='deposit_failed'}
    end
    MySQL.insert.await([[INSERT INTO cm_gang_activity(event_uid,gang_id,action,actor_character_id,detail) VALUES(?,?,?,?,?)]],{('deposit:%s:%d:%d'):format(c.membership.gangId,os.time(),math.random(100000,999999)),c.membership.gangId,'cash_deposited',c.characterId,json.encode({amount=amount})})
    locks[c.membership.gangId]=nil
    return {ok=true,amount=amount,profit=read(c.membership.gangId)}
end)

lib.callback.register('cm-gang:server:collectProfit',function(src)
    local c,reason=context(src,'gang.collect_profit'); if not c then return {ok=false,reason=reason} end
    local nearby,nearReason=nearCollector(c); if not nearby then return {ok=false,reason=nearReason} end
    local gangId=c.membership.gangId
    if locks[gangId] then return {ok=false,reason='operation_locked'} end
    if (cooldowns[c.characterId] or 0)>GetGameTimer() then return {ok=false,reason='rate_limited'} end
    locks[gangId]=true; cooldowns[c.characterId]=GetGameTimer()+((Config.Security.profitCollectCooldownSeconds or 5)*1000)
    local ok,result=xpcall(function()
        local amount=math.min(tonumber(MySQL.scalar.await('SELECT pending_amount FROM cm_gang_profit WHERE gang_id=?',{gangId})) or 0,tonumber(Config.Profit.maxCollectAmount) or 1000000)
        if amount<=0 then return {ok=false,reason='no_profit_available'} end
        local claimed=MySQL.update.await([[UPDATE cm_gang_profit SET pending_amount=pending_amount-?,last_collected_at=NOW(),last_collected_by=? WHERE gang_id=? AND pending_amount>=?]],{amount,c.characterId,gangId,amount})
        if tonumber(claimed)~=1 then return {ok=false,reason='profit_changed'} end
        local paid,payReason=exports[PLAYERDATA]:AddCash(c.source,amount,'gang_profit_collection')
        if paid~=true then MySQL.update.await('UPDATE cm_gang_profit SET pending_amount=pending_amount+? WHERE gang_id=?',{amount,gangId}); return {ok=false,reason=payReason or 'payment_failed'} end
        MySQL.insert.await([[INSERT INTO cm_gang_activity(event_uid,gang_id,action,actor_character_id,detail) VALUES(?,?,?,?,?)]],{('profit:%s:%d:%d'):format(gangId,os.time(),math.random(100000,999999)),gangId,'profit_collected',c.characterId,json.encode({amount=amount})})
        return {ok=true,amount=amount,profit=read(gangId)}
    end,debug.traceback)
    locks[gangId]=nil
    if not ok then print(('[cm-gang] profit collection failed: %s'):format(tostring(result))); return {ok=false,reason='collection_failed'} end
    return result
end)

local function tickDueProfits()
    if not CMGangDatabaseReady then return end
    local rate=math.max(0,tonumber(Config.Profit.activityToProfitRate) or 0)
    local interval=math.max(60,tonumber(Config.Profit.tickIntervalSeconds) or 3600)
    for _,gangId in ipairs(Config.GangIds) do
        MySQL.update.await([[INSERT INTO cm_gang_profit(gang_id,last_tick_at) VALUES(?,NOW())
            ON DUPLICATE KEY UPDATE
              pending_amount=pending_amount+IF(last_tick_at IS NULL OR TIMESTAMPDIFF(SECOND,last_tick_at,NOW())>=?,FLOOR(activity_score*?),0),
              activity_score=IF(last_tick_at IS NULL OR TIMESTAMPDIFF(SECOND,last_tick_at,NOW())>=?,0,activity_score),
              last_tick_at=IF(last_tick_at IS NULL OR TIMESTAMPDIFF(SECOND,last_tick_at,NOW())>=?,NOW(),last_tick_at)]],{gangId,interval,rate,interval,interval})
    end
end
CreateThread(function()
    while not CMGangDatabaseReady do Wait(1000) end
    tickDueProfits()
    while true do Wait(60000); tickDueProfits() end
end)
AddEventHandler('onResourceStop',function(name) if name==RESOURCE then locks,cooldowns={},{} end end)
