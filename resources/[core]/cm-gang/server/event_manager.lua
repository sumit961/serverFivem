local PLAYERDATA, EVENT_TYPE = 'cm-playerdata', 'supply_war'
local STATES = { IDLE=true, ANNOUNCED=true, LIVE=true, ENDING=true, ENDED=true }
local runtime = { state='IDLE', participants={}, participantsByCharacterId={}, scores={}, pairKills={}, cooldowns={}, joins={} }
local configDrafts = {}
local combatReportRate = {}
local nextCombatRateCleanupAt = 0
local scheduleStatus={nextAt=nil,lastAttempt=nil}
local quickResult

local function now() return os.time() end
local function cid(src)
    local ok, value = pcall(function() return exports[PLAYERDATA]:GetCharacterId(tonumber(src)) end)
    value = ok and tostring(value or '') or ''
    return value:match('^%d+$') and value or nil
end
local function characterName(src, characterId)
    local ok, value = pcall(function() return exports[PLAYERDATA]:GetCharacterFullName(tonumber(src)) end)
    value = ok and tostring(value or ''):gsub('[\r\n\t]', ' '):gsub('^%s+', ''):gsub('%s+$', '') or ''
    if value ~= '' then return value:sub(1, 96) end
    return ('Character %s'):format(tostring(characterId or 'Unknown'))
end
local function membership(characterId)
    local ok, value = pcall(function() return exports['cm-gang']:GetGangForCharacter(characterId) end)
    return ok and type(value)=='table' and Config.IsFixedGangId(value.gangId) and value.enabled~=false and value or nil
end
local function admin(src)
    if GetResourceState('cm-admin')~='started' then return false end
    local ok, value=pcall(function() return exports['cm-admin']:HasPermission(tonumber(src),'gang.admin.manage') end)
    return ok and value==true
end
local function coords(src)
    local ped=GetPlayerPed(tonumber(src)); if not ped or ped==0 then return nil end
    local c=GetEntityCoords(ped); return {x=c.x+0.0,y=c.y+0.0,z=c.z+0.0}, ped
end
local function distance(a,b)
    local x=(a.x or 0)-(b.x or 0); local y=(a.y or 0)-(b.y or 0); local z=(a.z or 0)-(b.z or 0)
    return math.sqrt(x*x+y*y+z*z)
end
local function distance2D(a,b)
    local x=(a.x or 0)-(b.x or 0); local y=(a.y or 0)-(b.y or 0)
    return math.sqrt(x*x+y*y)
end
local function debugLog(action, detail)
    if Config.GangEvents.supplyWar.debug ~= true then return end
    print(('[cm-gang:supplywar] %s%s'):format(tostring(action), detail and (' '..tostring(detail)) or ''))
end
local function decode(value, fallback)
    if type(value)=='table' then return value end
    local ok, result=pcall(json.decode,value or '')
    return ok and type(result)=='table' and result or fallback
end
local function presentation()
    local source=Config.GangEvents.supplyWar.presentation or{}
    local rules={};for _,rule in ipairs(source.rules or{})do rules[#rules+1]=tostring(rule):sub(1,120)end
    return{id=tostring(source.id or EVENT_TYPE),title=tostring(source.title or'Supply War'),subtitle=tostring(source.subtitle or'Gang Combat Event'),image=tostring(source.image or''),description=tostring(source.description or''),rules=rules}
end
local function resultPayload(eventId)
    local row=MySQL.single.await([[SELECT event_id,status,UNIX_TIMESTAMP(started_at) started_at,UNIX_TIMESTAMP(ended_at) ended_at,winning_gang_id,final_scores FROM cm_gang_events WHERE event_type=? AND event_id=? AND status='completed' LIMIT 1]],{EVENT_TYPE,eventId})
    if not row then return nil end
    local saved=decode(row.final_scores,{})
    return{eventId=row.event_id,status=row.status,startedAt=tonumber(row.started_at),endedAt=tonumber(row.ended_at),winner=row.winning_gang_id,standings=saved.gangs or{},mvp=saved.mvp,topGun=saved.topGun,objectives=saved.objectives,presentation=presentation()}
end
local function targets(eligibleOnly)
    local result={}
    for _, raw in ipairs(GetPlayers()) do
        local src=tonumber(raw); local characterId=cid(src)
        if characterId and (not eligibleOnly or membership(characterId)) then result[#result+1]=src end
    end
    return result
end
local function emit(event, payload, eligibleOnly)
    for _,src in ipairs(targets(eligibleOnly)) do TriggerClientEvent(event,src,payload) end
end
local function participantPayload(p)
    return { eventId=runtime.id, eventType=EVENT_TYPE, state=runtime.state, gangId=p.gangId,
        liveAt=runtime.liveAt, endsAt=runtime.endsAt, config=runtime.publicConfig, scores=runtime.scores,
        player={kills=p.kills,assists=p.assists,deaths=p.deaths,drops=p.drops,defenses=p.defenses} }
end
local function liveInsideCounts()
    local counts={};for _,gangId in ipairs(Config.GangIds)do counts[gangId]=0 end
    if runtime.state~='LIVE'or not runtime.config then return counts end
    for src,p in pairs(runtime.participants)do
        if p.active and not p.respawning and GetPlayerRoutingBucket(src)==runtime.config.bucket and not exports[PLAYERDATA]:IsDead(src)then
            local c=coords(src);if c and distance2D(c,runtime.config.zone)<=runtime.config.radius then counts[p.gangId]=(counts[p.gangId]or 0)+1 end
        end
    end
    return counts
end
local function syncScores()
    if not runtime.id then return end
    local players={}
    for _,p in pairs(runtime.participants) do
        players[#players+1]={cid=p.cid,name=p.name,gangId=p.gangId,kills=p.kills,assists=p.assists or 0,deaths=p.deaths,drops=p.drops,defenses=p.defenses or 0,reachedAt=p.reachedAt}
    end
    table.sort(players,function(a,b) if a.kills~=b.kills then return a.kills>b.kills end if a.deaths~=b.deaths then return a.deaths<b.deaths end return (a.reachedAt or 0)<(b.reachedAt or 0) end)
    local top={}; for i=1,math.min(3,#players) do top[i]=players[i] end
    local leading
    for gangId,s in pairs(runtime.scores) do if not leading or s.score>leading.score or (s.score==leading.score and gangId<leading.gangId) then leading={gangId=gangId,score=s.score,heat=s.heat} end end
    local liveInside=liveInsideCounts();local gangColors={};for _,gangId in ipairs(Config.GangIds)do gangColors[gangId]=(Config.CanonicalIdentity[gangId]or{}).color end
    for src,p in pairs(runtime.participants) do if p.active and GetPlayerRoutingBucket(src)==runtime.config.bucket then TriggerClientEvent('cm-gang:client:eventScores',src,{top=top,gangs=runtime.scores,leading=leading,liveInside=liveInside,gangColors=gangColors,player={kills=p.kills,assists=p.assists or 0,deaths=p.deaths,drops=p.drops,defenses=p.defenses or 0},yourGang=p.gangId})end end
end
local function loadConfig()
    local row=MySQL.single.await('SELECT * FROM cm_gang_event_config WHERE event_type=? LIMIT 1',{EVENT_TYPE})
    if not row then return nil,'event_config_missing' end
    local zone={x=tonumber(row.zone_x),y=tonumber(row.zone_y),z=tonumber(row.zone_z)}
    if not zone.x or not zone.y or not zone.z then return nil,'zone_not_configured' end
    local extra=decode(row.config_json,{})
    local radius=math.max(Config.GangEvents.zoneRadiusMin,math.min(Config.GangEvents.zoneRadiusMax,tonumber(row.zone_radius) or 250))
    local config={enabled=CMGangDbTrue(row.enabled),name=tostring(row.event_name or 'Gang Supply War'),areaName=row.area_name,
        zone=zone,radius=radius,announcement=math.max(10,math.min(600,tonumber(row.announcement_seconds) or 60)),
        duration=math.max(300,math.min(7200,tonumber(row.duration_seconds) or 1500)),bucket=tonumber(row.routing_bucket),
        maxActiveDrops=math.max(1,math.min(5,tonumber(row.max_active_drops) or 2)),capture=math.max(2,math.min(30,tonumber(row.capture_seconds) or 4)),
        contestedCapture=math.max(2,math.min(60,tonumber(row.contested_capture_seconds) or 7)),claimRadius=math.max(1,math.min(8,tonumber(row.claim_radius) or 3)),
        contestRadius=math.max(3,math.min(75,tonumber(row.contest_radius) or 20)),boundaryGrace=math.max(1,math.min(30,tonumber(row.boundary_grace_seconds) or 5)),
        boundaryCooldown=math.max(0,math.min(3600,tonumber(extra.boundaryCooldownSeconds)or Config.GangEvents.supplyWar.boundaryReentryCooldownSeconds or 120)),joinRing=math.max(1,math.min(50,tonumber(extra.joinRingWidth)or Config.GangEvents.supplyWar.joinRingWidth or 8)),
        combatTag=math.max(1,math.min(60,tonumber(row.combat_tag_seconds) or 15)),reentry=math.max(10,math.min(300,tonumber(row.reentry_cooldown_seconds) or 40)),
        antiFarm=math.max(0,math.min(600,tonumber(row.anti_farm_seconds) or 90)),killPoints=math.max(0,math.min(20,tonumber(row.kill_points) or 1)),
        deathReentry=math.max(0,math.min(3600,tonumber(extra.deathReentryCooldownSeconds)or Config.GangEvents.supplyWar.deathReentryCooldownSeconds or 120)),
        vehiclePolicy=type(extra.vehiclePolicy)=='table'and extra.vehiclePolicy or Config.GangEvents.supplyWar.vehiclePolicy,
        worldBoundary=type(extra.worldBoundary)=='table'and extra.worldBoundary or Config.GangEvents.supplyWar.worldBoundary,
        supplyNotificationEnabled=extra.supplyNotificationEnabled~=false,warmupAreaMessageEnabled=extra.warmupAreaMessageEnabled~=false,extra=extra}
    config.vehiclePolicy.allowVehicles=config.vehiclePolicy.allowVehicles==true;config.vehiclePolicy.allowedClasses=type(config.vehiclePolicy.allowedClasses)=='table'and config.vehiclePolicy.allowedClasses or{}
    config.worldBoundary.enabled=config.worldBoundary.enabled~=false;config.worldBoundary.renderDistance=math.max(25,math.min(500,tonumber(config.worldBoundary.renderDistance)or 150));config.worldBoundary.segments=math.max(32,math.min(96,math.floor(tonumber(config.worldBoundary.segments)or 64)))
    if not config.bucket or config.bucket<Config.GangEvents.bucketMin or config.bucket>Config.GangEvents.bucketMax then return nil,'routing_bucket_outside_reserved_range' end
    return config
end
local function restore(src,p,reason)
    src=tonumber(src); if not p then return end
    if GetPlayerName(src) then local player=Player(src);if player then player.state:set('cmSupplyWarParticipant',false,true)end;SetPlayerRoutingBucket(src,tonumber(p.originalBucket) or 0); TriggerClientEvent('cm-gang:client:eventCombatTag',src,{active=false,expiresAt=0});TriggerClientEvent('cm-gang:client:eventLeave',src,{reason=reason});debugLog('BUCKET_RESTORE',('cid=%s bucket=%d reason=%s'):format(p.cid,tonumber(p.originalBucket)or 0,tostring(reason))) end
    p.active=false; p.leftAt=now()
    p.boundary=nil;p.combatUntil=nil;p.lastCombatTagSentUntil=nil
end
local function persistPlayer(p)
    MySQL.update.await([[UPDATE cm_gang_event_players SET kills=?,deaths=?,drops_secured=?,streak=?,left_at=FROM_UNIXTIME(?) WHERE event_id=? AND character_id=?]],
        {p.kills,p.deaths,p.drops,p.streak,p.leftAt or now(),runtime.id,p.cid})
end
local function winnerAndMvp()
    local order={}; for gangId,s in pairs(runtime.scores) do if (s.participants or 0)>0 then order[#order+1]={gangId=gangId,score=s.score,drops=s.drops,kills=s.kills,deaths=s.deaths} end end
    table.sort(order,function(a,b) if a.score~=b.score then return a.score>b.score end if a.drops~=b.drops then return a.drops>b.drops end if a.kills~=b.kills then return a.kills>b.kills end if a.deaths~=b.deaths then return a.deaths<b.deaths end return a.gangId<b.gangId end)
    local mvp,topGun,objectives;local w=Config.GangEvents.supplyWar.mvp
    for _,p in pairs(runtime.participantsByCharacterId or {}) do
        local value=p.kills*w.kill+(p.assists or 0)*w.assist+p.drops*w.drop+(p.finalDrops or 0)*(w.finalDrop-w.drop)+(p.defenses or 0)*w.defense+p.deaths*w.death
        local row={cid=p.cid,name=p.name,gangId=p.gangId,kills=p.kills,assists=p.assists or 0,deaths=p.deaths,drops=p.drops,defenses=p.defenses or 0,value=value}
        if not mvp or value>mvp.value or (value==mvp.value and p.cid<mvp.cid) then mvp=row end
        if not topGun or p.kills>topGun.kills then topGun=row end;if not objectives or p.drops>objectives.drops then objectives=row end
    end
    return order[1],mvp,order,topGun,objectives
end
function CMGangEventFinish(reason,cancelled)
    if not runtime.id or runtime.state=='ENDING' or runtime.state=='ENDED' then return false,'no_active_event' end
    runtime.state='ENDING'; local winner,mvp,order,topGun,objectives=winnerAndMvp()
    if cancelled then winner=nil; mvp=nil;topGun=nil;objectives=nil end
    for src,p in pairs(runtime.participants) do restore(src,p,reason); persistPlayer(p) end
    local status=cancelled and 'cancelled' or 'completed'
    MySQL.update.await([[UPDATE cm_gang_events SET status=?,ended_at=NOW(),winning_gang_id=?,mvp_character_id=?,final_scores=?,end_reason=? WHERE event_id=?]],
        {status,winner and winner.gangId or nil,mvp and mvp.cid or nil,json.encode({gangs=order,mvp=mvp,topGun=topGun,objectives=objectives}),reason,runtime.id})
    if not cancelled then
        for place,row in ipairs(order)do
            local reward=Config.GangEvents.supplyWar.activityPlacementRewards[place]
            if reward and reward>0 then
                local operation=('supplywar:%s:placement:%s'):format(runtime.id,row.gangId)
                local called,committed=pcall(function()return MySQL.transaction.await({
                    {query='INSERT INTO cm_gang_activity(event_uid,gang_id,action,detail) VALUES(?,?,?,?)',values={operation,row.gangId,'supply_war_placement',json.encode({place=place,points=row.score,reward=reward})}},
                    {query=[[INSERT INTO cm_gang_profit(gang_id,activity_score) VALUES(?,?) ON DUPLICATE KEY UPDATE activity_score=activity_score+VALUES(activity_score)]],values={row.gangId,reward}},
                })end)
                if called and committed==true then debugLog('REWARD_SUCCESS',('operation=%s reward=%d'):format(operation,reward))
                elseif MySQL.scalar.await('SELECT 1 FROM cm_gang_activity WHERE event_uid=? LIMIT 1',{operation})then debugLog('REWARD_DUPLICATE_BLOCKED',('operation=%s'):format(operation))
                else print(('[cm-gang] Supply War placement reward transaction failed operation=%s'):format(operation))end
            end
        end
    end
    local endedPayload={cancelled=cancelled,winner=winner,mvp=mvp,topGun=topGun,objectives=objectives,scores=order,resultSeconds=Config.GangEvents.supplyWar.resultSeconds}
    for src in pairs(runtime.participants)do if GetPlayerName(src)then TriggerClientEvent('cm-gang:client:eventEnded',src,endedPayload)end end
    if not cancelled and #order>0 then
        local participating={};for _,row in ipairs(order)do participating[row.gangId]=true end
        local quickSeconds=math.max(10,math.min(300,math.floor(tonumber(runtime.config.extra.resultQuickViewSeconds)or tonumber(Config.GangEvents.supplyWar.resultQuickViewSeconds)or 60)))
        local quickEventId=runtime.id
        quickResult={eventId=quickEventId,participatingGangs=participating,availableUntil=now()+quickSeconds}
        for _,src in ipairs(targets(false))do local characterId=cid(src);local member=characterId and membership(characterId);if member and participating[member.gangId]then TriggerClientEvent('cm-gang:client:supplyWarResultAvailable',src,{eventId=runtime.id,availableUntil=quickResult.availableUntil,presentation=presentation()})end end
        SetTimeout(quickSeconds*1000,function()if quickResult and quickResult.eventId==quickEventId then quickResult=nil end end)
    end
    TriggerEvent('cm-gang:server:eventCleanup',runtime.id,reason)
    runtime={state='ENDED',participants={},participantsByCharacterId={},scores={},pairKills={},cooldowns={},joins={}};combatReportRate={}
    SetTimeout(15000,function() if runtime.state=='ENDED' then runtime.state='IDLE' end end)
    return true
end
function CMGangEventStart(src,automatic,options)
    if automatic~=true and not admin(src) then return false,'permission_denied' end
    if runtime.state~='IDLE' and runtime.state~='ENDED' then return false,'event_already_active' end
    if not CMGangDatabaseReady then return false,'database_not_ready' end
    local config,reason=loadConfig(); if not config then return false,reason end
    if not config.enabled then return false,'event_disabled' end
    if GetResourceState(PLAYERDATA)~='started' then return false,'medical_death_integration_not_ready' end
    if type(CMGangSupplyWarValidate)~='function' then return false,'supply_war_not_ready' end
    local valid,why=CMGangSupplyWarValidate(config); if not valid then return false,why end
    options=type(options)=='table'and options or{};local scheduledAt=tonumber(options.scheduledAt);local eventId=scheduledAt and('supply_war:auto:%d'):format(scheduledAt)or('supply_war:%d:%06d'):format(now(),math.random(0,999999))
    if scheduledAt and MySQL.scalar.await('SELECT 1 FROM cm_gang_events WHERE event_id=? LIMIT 1',{eventId})then return false,'scheduled_event_already_processed'end
    runtime={id=eventId,state='ANNOUNCED',config=config,participants={},participantsByCharacterId={},scores={},pairKills={},cooldowns={},joins={},automatic=automatic==true,scheduledAt=scheduledAt}
    for _,gangId in ipairs(Config.GangIds) do runtime.scores[gangId]={score=0,kills=0,deaths=0,drops=0,heat=0,participants=0} end
    runtime.liveAt=scheduledAt and math.max(now(),scheduledAt)or(now()+config.announcement);runtime.endsAt=runtime.liveAt+config.duration
    runtime.publicConfig={name=config.name,areaName=config.areaName,zone=config.zone,radius=config.radius,boundaryGrace=config.boundaryGrace,combatTag=config.combatTag,reentry=config.reentry,joinRing=config.joinRing,vehiclePolicy=config.vehiclePolicy,worldBoundary=config.worldBoundary,supplyNotificationEnabled=config.supplyNotificationEnabled,warmupAreaMessageEnabled=config.warmupAreaMessageEnabled}
    MySQL.insert.await([[INSERT INTO cm_gang_events (event_id,event_type,status,routing_bucket,live_at,config_snapshot) VALUES (?,?,?,?,FROM_UNIXTIME(?),?)]],{runtime.id,EVENT_TYPE,'announced',config.bucket,runtime.liveAt,json.encode(config)})
    emit('cm-gang:client:eventAnnounced',{eventId=runtime.id,eventType=EVENT_TYPE,state=runtime.state,liveAt=runtime.liveAt,endsAt=runtime.endsAt,config=runtime.publicConfig},true)
    TriggerEvent('cm-gang:server:eventStarted',runtime.id,config,runtime.liveAt)
    local warmupDelay=math.max(0,runtime.liveAt-now());SetTimeout(warmupDelay*1000,function()
        if runtime.id and runtime.state=='ANNOUNCED' then runtime.state='LIVE'; MySQL.update.await("UPDATE cm_gang_events SET status='live',started_at=NOW() WHERE event_id=?",{runtime.id}); emit('cm-gang:client:eventLive',{eventId=runtime.id,liveAt=runtime.liveAt,endsAt=runtime.endsAt,config=runtime.publicConfig},true) end
    end)
    SetTimeout((warmupDelay+config.duration)*1000,function() if runtime.id and runtime.state=='LIVE' then CMGangEventFinish('duration_elapsed',false) end end)
    return true,runtime.id
end
local function join(src, reconnectRestore)
    src=tonumber(src); if not src then return end
    if runtime.state~='LIVE' then debugLog('JOIN_DENY','reason=EVENT_NOT_ACTIVE');TriggerClientEvent('cm-gang:client:eventJoinDenied',src,{reason='Event entry is not open.'}); return end
    local tick=GetGameTimer(); if (runtime.joins[src] or 0)>tick then return end; runtime.joins[src]=tick+Config.GangEvents.joinCooldownMs
    local characterId=cid(src); local member=characterId and membership(characterId)
    if not characterId then debugLog('JOIN_DENY','reason=CHARACTER_NOT_READY');TriggerClientEvent('cm-gang:client:eventJoinDenied',src,{reason='Character data is not ready.'}); return end
    if not member then debugLog('JOIN_DENY',('cid=%s reason=NOT_IN_GANG'):format(characterId));TriggerClientEvent('cm-gang:client:eventJoinDenied',src,{reason='You must belong to an enabled gang to join.'}); return end
    local existing=runtime.participantsByCharacterId[characterId]
    if exports[PLAYERDATA]:IsDead(src)then TriggerClientEvent('cm-gang:client:eventJoinDenied',src,{reason='You cannot join Supply War while dead.'}); return end
    local ped=GetPlayerPed(src);if ped==0 then TriggerClientEvent('cm-gang:client:eventJoinDenied',src,{reason='Player entity is unavailable.'});return end
    local occupiedVehicle=GetVehiclePedIsIn(ped,false)
    if occupiedVehicle~=0 then
        if runtime.config.vehiclePolicy.allowVehicles~=true then debugLog('JOIN_DENY',('cid=%s reason=IN_VEHICLE'):format(characterId));TriggerClientEvent('cm-gang:client:eventJoinDenied',src,{reason='Exit your vehicle to join Supply War.',code='IN_VEHICLE'});return end
        local allowed=runtime.config.vehiclePolicy.allowedClasses or{}
        if #allowed>0 then local ok,class=pcall(GetVehicleClass,occupiedVehicle);local accepted=false;if ok then for _,allowedClass in ipairs(allowed)do if tonumber(allowedClass)==tonumber(class)then accepted=true;break end end end;if not accepted then debugLog('JOIN_DENY',('cid=%s reason=VEHICLE_CLASS class=%s'):format(characterId,tostring(class)));TriggerClientEvent('cm-gang:client:eventJoinDenied',src,{reason='This vehicle class is not allowed in Supply War.',code='VEHICLE_CLASS'});return end end
    end
    if (runtime.cooldowns[characterId] or 0)>now() then local untilAt=runtime.cooldowns[characterId];debugLog('JOIN_DENY',('cid=%s reason=COOLDOWN remaining=%d'):format(characterId,math.max(1,untilAt-now())));TriggerClientEvent('cm-gang:client:eventCooldown',src,{untilAt=untilAt,remaining=math.max(1,untilAt-now())}); return end
    local c=coords(src);local zoneDistance=c and distance2D(c,runtime.config.zone)or math.huge
    local restoring=reconnectRestore==true and existing and existing.disconnected==true
    -- Supply War design: new/rejoining non-participants enter only from the
    -- outer ring. Active participants may use the complete event radius.
    if not restoring then
        local width=math.max(1.0,math.min(runtime.config.radius,runtime.config.joinRing or 8.0))
        local tolerance=math.max(0.0,math.min(2.0,tonumber(Config.GangEvents.supplyWar.joinRingTolerance)or 0.75))
        if zoneDistance<runtime.config.radius-width or zoneDistance>runtime.config.radius+tolerance then debugLog('JOIN_DENY',('cid=%s reason=OUTSIDE_JOIN_RING distance=%.2f'):format(characterId,zoneDistance));TriggerClientEvent('cm-gang:client:eventJoinDenied',src,{reason='Join Supply War from the outer edge of the event circle.'}); return end
    end
    local p=existing
    if p and p.cid~=characterId then restore(src,p,'identity_changed'); runtime.participants[src]=nil; p=nil end
    if p and p.gangId~=member.gangId then TriggerClientEvent('cm-gang:client:eventJoinDenied',src,{reason='Your gang changed during this event.'}); return end
    if p and p.active and p.source and GetPlayerName(p.source) then TriggerClientEvent('cm-gang:client:eventJoinDenied',src,{reason='You already joined this Supply War.'}); return end
    restoring=p and p.disconnected==true
    if not p then
        local original=GetPlayerRoutingBucket(src); p={cid=characterId,gangId=member.gangId,name=characterName(src,characterId),kills=0,assists=0,deaths=0,drops=0,defenses=0,streak=0,reachedAt=now(),originalBucket=original,active=true,firstEntry=true,damageBy={}};runtime.participantsByCharacterId[characterId]=p;runtime.scores[p.gangId].participants=runtime.scores[p.gangId].participants+1
        MySQL.insert.await([[INSERT INTO cm_gang_event_players (event_id,character_id,gang_id,original_bucket) VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE left_at=NULL]],{runtime.id,characterId,p.gangId,original})
    else p.active=true;p.name=characterName(src,characterId);p.leftAt=nil end
    p.deathProcessing=nil
    if not restoring or not p.joinPosition then local ped=GetPlayerPed(src);p.joinPosition={x=c.x,y=c.y,z=c.z,heading=ped~=0 and GetEntityHeading(ped)or 0}end
    p.disconnected=nil
    p.source=src;runtime.participants[src]=p
    SetPlayerRoutingBucket(src,runtime.config.bucket)
    local player=Player(src);if player then player.state:set('cmSupplyWarParticipant',true,true)end
    p.boundary=nil
    debugLog('JOIN_ACCEPT',('cid=%s gang=%s'):format(p.cid,p.gangId));debugLog('BUCKET_ENTER',('cid=%s bucket=%d'):format(p.cid,runtime.config.bucket))
    TriggerClientEvent('cm-gang:client:eventJoined',src,participantPayload(p));TriggerEvent('cm-gang:server:eventParticipantJoined',src,runtime.id);p.firstEntry=false
end
RegisterNetEvent('cm-gang:server:eventJoin',function() join(source) end)
AddEventHandler('cm-playerdata:server:characterLoaded',function(src)
    src=tonumber(src);if not src or runtime.state~='LIVE'then return end
    SetTimeout(1000,function()
        if runtime.state~='LIVE'or not GetPlayerName(src)then return end
        local characterId=cid(src);local member=characterId and membership(characterId);if not member then return end
        local p=runtime.participantsByCharacterId[characterId];local c=coords(src)
        if p and p.disconnected and p.gangId==member.gangId and c and distance2D(c,runtime.config.zone)<=runtime.config.radius+3 then join(src,true)
        else TriggerClientEvent('cm-gang:client:eventLive',src,{eventId=runtime.id,eventType=EVENT_TYPE,state=runtime.state,liveAt=runtime.liveAt,endsAt=runtime.endsAt,config=runtime.publicConfig}) end
    end)
end)
AddEventHandler('cm-playerdata:server:characterLoaded',function(src)
    src=tonumber(src);if not src or not quickResult or quickResult.availableUntil<=now()then return end
    SetTimeout(1200,function()local characterId=cid(src);local member=characterId and membership(characterId);if quickResult and member and quickResult.participatingGangs[member.gangId]then TriggerClientEvent('cm-gang:client:supplyWarResultAvailable',src,{eventId=quickResult.eventId,availableUntil=quickResult.availableUntil,presentation=presentation()})end end)
end)
local function setBoundaryState(src,p,outside)
    if outside then
        if p.boundary then return end
        local seconds=math.max(1,tonumber(Config.GangEvents.supplyWar.boundaryGraceSeconds)or 5)
        p.boundary={outsideSince=now(),deadline=now()+seconds,penalized=false}
        TriggerClientEvent('cm-gang:client:eventBoundaryWarning',src,{seconds=seconds,deadline=p.boundary.deadline})
        debugLog('BOUNDARY_START',('cid=%s deadline=%d'):format(p.cid,p.boundary.deadline))
    elseif p.boundary then
        p.boundary=nil;TriggerClientEvent('cm-gang:client:eventBoundaryReturned',src)
        debugLog('BOUNDARY_CANCEL',('cid=%s'):format(p.cid))
    end
end
local function punishBoundary(src,p,reason)
    if not p or not p.active or (p.boundary and p.boundary.penalized) then return end
    if p.boundary then p.boundary.penalized=true end
    local cooldown=math.max(0,tonumber(runtime.config.boundaryCooldown)or 120)
    runtime.cooldowns[p.cid]=now()+cooldown
    debugLog('COOLDOWN_SET',('cid=%s seconds=%d reason=%s'):format(p.cid,cooldown,tostring(reason)))
    debugLog('BOUNDARY_PENALTY',('cid=%s'):format(p.cid))
    restore(src,p,'left_zone');persistPlayer(p)
end
RegisterNetEvent('cm-gang:server:eventBoundary',function()
    local src=tonumber(source);local p=runtime.participants[src]
    if runtime.state~='LIVE'or not p or not p.active or p.respawning then return end
    local c=coords(src);setBoundaryState(src,p,not c or distance2D(c,runtime.config.zone)>runtime.config.radius)
end)
CreateThread(function()
    while true do
        if runtime.state~='LIVE'then Wait(1000)else
            local currentNow=now();local tick=GetGameTimer();local countsChanged=false
            if tick>=nextCombatRateCleanupAt then for key,expires in pairs(combatReportRate)do if expires<=tick then combatReportRate[key]=nil end end;nextCombatRateCleanupAt=tick+60000 end
            for src,p in pairs(runtime.participants)do
                if p.active and not p.respawning then
                    local c=coords(src);local outside=not c or distance2D(c,runtime.config.zone)>runtime.config.radius
                    local ped=GetPlayerPed(src);local occupiedVehicle=ped~=0 and GetVehiclePedIsIn(ped,false)or 0;local vehicleViolation=runtime.config.vehiclePolicy.allowVehicles~=true and occupiedVehicle~=0
                    if not vehicleViolation and occupiedVehicle~=0 and #(runtime.config.vehiclePolicy.allowedClasses or{})>0 then local ok,class=pcall(GetVehicleClass,occupiedVehicle);vehicleViolation=not ok;for _,allowedClass in ipairs(runtime.config.vehiclePolicy.allowedClasses)do if ok and tonumber(allowedClass)==tonumber(class)then vehicleViolation=false;break end end end
                    if vehicleViolation and currentNow>=(p.nextVehicleEjectAt or 0)then p.nextVehicleEjectAt=currentNow+5;TriggerClientEvent('cm-gang:client:eventVehicleEject',src);debugLog('EVENT_VEHICLE_EJECT',('cid=%s'):format(p.cid))end
                    setBoundaryState(src,p,outside)
                    if outside and p.boundary and currentNow>=p.boundary.deadline then punishBoundary(src,p,'boundary_deadline')end
                end
            end
            local encodedCounts=json.encode(liveInsideCounts());if encodedCounts~=runtime.lastLiveInsideCounts then runtime.lastLiveInsideCounts=encodedCounts;countsChanged=true end
            if countsChanged then syncScores()end
            Wait(math.max(500,tonumber(Config.GangEvents.supplyWar.zoneCheckMs)or 750))
        end
    end
end)
local function scheduleFor(config,current)
    local defaults=Config.GangEvents.supplyWar.schedule or{};local saved=config.extra and config.extra.schedule or{};local enabled=saved.autoStart;if enabled==nil then enabled=defaults.autoStart~=false end
    local interval=math.max(1,math.min(24,tonumber(saved.intervalHours)or tonumber(defaults.intervalHours)or 2))*3600
    local hour=math.max(0,math.min(23,math.floor(tonumber(saved.anchorHour)or tonumber(defaults.anchorHour)or 0)));local minute=math.max(0,math.min(59,math.floor(tonumber(saved.anchorMinute)or tonumber(defaults.anchorMinute)or 0)))
    local date=os.date('*t',current);date.hour=hour;date.min=minute;date.sec=0;local anchor=os.time(date);local steps=math.floor((current-anchor)/interval);local latest=anchor+steps*interval;if latest>current then latest=latest-interval end
    local nextAt=latest+interval;local warmup=math.max(0,math.min(60,tonumber(saved.warmupMinutes)or tonumber(defaults.warmupMinutes)or 5))*60;local grace=math.max(0,math.min(30,tonumber(saved.graceMinutes)or tonumber(defaults.graceMinutes)or 5))*60
    return{enabled=enabled,latest=latest,nextAt=nextAt,warmup=warmup,grace=grace,intervalHours=interval/3600,anchorHour=hour,anchorMinute=minute}
end
CreateThread(function()
    while not CMGangDatabaseReady do Wait(500)end
    while true do
        local config=loadConfig();if config then local current=now();local schedule=scheduleFor(config,current);local candidate=current<=schedule.latest+schedule.grace and schedule.latest or schedule.nextAt
            scheduleStatus.nextAt=candidate
            local triggerAt=candidate-schedule.warmup
            if schedule.enabled and current>=triggerAt and current<=candidate+schedule.grace and scheduleStatus.lastAttempt~=candidate then
                scheduleStatus.lastAttempt=candidate;local ok,reason=CMGangEventStart(nil,true,{scheduledAt=candidate});if not ok then debugLog('AUTO_START_SKIP',('scheduled=%d reason=%s'):format(candidate,tostring(reason)))end
            end
            scheduleStatus.enabled=schedule.enabled;scheduleStatus.intervalHours=schedule.intervalHours;scheduleStatus.anchorHour=schedule.anchorHour;scheduleStatus.anchorMinute=schedule.anchorMinute
        end
        Wait(15000)
    end
end)
local function updateCombatTag(src,p,expiry)
    local old=p.combatUntil or 0;p.combatUntil=math.max(old,expiry)
    local threshold=math.max(1,tonumber(Config.GangEvents.supplyWar.combatTagNotifyThresholdSeconds)or 1)
    if (p.lastCombatTagSentUntil or 0)<=now() or p.combatUntil-(p.lastCombatTagSentUntil or 0)>=threshold then
        p.lastCombatTagSentUntil=p.combatUntil
        TriggerClientEvent('cm-gang:client:eventCombatTag',src,{active=true,expiresAt=p.combatUntil})
    end
end
local function combatHit(src,targetSrc)
    src=tonumber(src);targetSrc=tonumber(targetSrc)
    if runtime.state~='LIVE'or not runtime.config or not src or not targetSrc or src==targetSrc then return end
    local a=runtime.participants[src];local b=runtime.participants[targetSrc]
    if not a or not b or not a.active or not b.active or a.gangId==b.gangId then return end
    if GetPlayerRoutingBucket(src)~=runtime.config.bucket or GetPlayerRoutingBucket(targetSrc)~=runtime.config.bucket then return end
    if exports[PLAYERDATA]:IsDead(src)or exports[PLAYERDATA]:IsDead(targetSrc)then return end
    local ac,aped=coords(src);local bc,bped=coords(targetSrc);if not ac or not bc or aped==0 or bped==0 or GetEntityHealth(aped)<=0 or GetEntityHealth(bped)<=0 then return end
    if distance(ac,bc)>math.max(25,tonumber(Config.GangEvents.supplyWar.combatValidationMaxDistance)or 250)then return end
    local key=a.cid..':'..b.cid;local tick=GetGameTimer();local throttle=math.max(100,tonumber(Config.GangEvents.supplyWar.combatPairThrottleMs)or 200)
    if(combatReportRate[key]or 0)>tick then return end;combatReportRate[key]=tick+throttle
    b.damageBy=b.damageBy or {};b.damageBy[a.cid]={lastHitAt=now(),registered=true}
    local expiry=now()+runtime.config.combatTag;updateCombatTag(src,a,expiry);updateCombatTag(targetSrc,b,expiry)
end
RegisterNetEvent('cm-gang:server:eventCombatHit',function(targetSrc)combatHit(source,targetSrc)end)
-- Compatibility wrappers for older internal clients. They share the same server throttle.
RegisterNetEvent('cm-gang:server:eventCombat',function(targetSrc)combatHit(source,targetSrc)end)
RegisterNetEvent('cm-gang:server:eventDamage',function(targetSrc)combatHit(source,targetSrc)end)
AddEventHandler('cm-playerdata:server:deathDetail',function(victimSrc, detail)
    victimSrc=tonumber(victimSrc); local victim=runtime.participants[victimSrc]
    if runtime.state~='LIVE' or not victim or not victim.active then return end
    if victim.deathProcessing then debugLog('DEATH_DUPLICATE_BLOCKED',('cid=%s event=%s'):format(victim.cid,tostring(runtime.id)));return end
    victim.deathProcessing=true
    local contextCall,contextMarked=pcall(function()return exports[PLAYERDATA]:MarkSupplyWarDeathContext(victimSrc,runtime.id)end);local contextOk=contextCall and contextMarked==true
    debugLog(contextOk and'WEAPON_DROP_SUPPRESSION_SET'or'WEAPON_DROP_SUPPRESSION_FAILED',('cid=%s event=%s'):format(victim.cid,tostring(runtime.id)))
    victim.deaths=victim.deaths+1; victim.streak=0; runtime.scores[victim.gangId].deaths=runtime.scores[victim.gangId].deaths+1
    local killerSrc=tonumber(detail and detail.killerSource); local killer=killerSrc and runtime.participants[killerSrc]
    local scored=false
    local enemyDeath=killerSrc and killerSrc~=victimSrc and killer and killer.active and killer.cid~=victim.cid and tostring(detail and detail.killerCharacterId or'')==killer.cid and killer.gangId~=victim.gangId and GetPlayerRoutingBucket(killerSrc)==runtime.config.bucket and detail.killerPlausible==true
    if enemyDeath then
        local key=killer.cid..':'..victim.cid; local farmed=(runtime.pairKills[key] or 0)+runtime.config.antiFarm>now()
        if not farmed then
            killer.kills=killer.kills+1;killer.streak=killer.streak+1;killer.reachedAt=now();runtime.pairKills[key]=now();local ks=runtime.scores[killer.gangId];ks.kills=ks.kills+1;ks.score=ks.score+runtime.config.killPoints;ks.heat=ks.heat+1
            for contributorCid,hit in pairs(victim.damageBy or {}) do local assist=runtime.participantsByCharacterId[contributorCid];local hitAt=type(hit)=='table'and hit.lastHitAt or tonumber(hit);if contributorCid~=killer.cid and assist and assist.active and assist.gangId~=victim.gangId and hitAt and now()-hitAt<=Config.GangEvents.supplyWar.assistWindowSeconds then assist.assists=(assist.assists or 0)+1 end end
            scored=true
        end
    end
    local killerValid=enemyDeath==true
    local killerIdentity=Config.CanonicalIdentity[killerValid and killer.gangId or'']or{}
    local victimIdentity=Config.CanonicalIdentity[victim.gangId]or{}
    for targetSrc,target in pairs(runtime.participants)do if target.active then TriggerClientEvent('cm-gang:client:eventDeathFeed',targetSrc,{killer=killerValid and killer.name or nil,killerGang=killerValid and killer.gangId or nil,killerColor=killerValid and killerIdentity.color or nil,victim=victim.name,victimGang=victim.gangId,victimColor=victimIdentity.color,cause=killerValid and'combat'or'environment',scored=scored,streak=killerValid and killer.streak or 0})end end
    victim.damageBy={}
    debugLog(killerValid and'DEATH_ENEMY'or'DEATH_ENVIRONMENT',('cid=%s killer=%s scored=%s'):format(victim.cid,killerValid and killer.cid or'none',tostring(scored)))
    syncScores();persistPlayer(victim);if killer then persistPlayer(killer) end
    runtime.cooldowns[victim.cid]=now()+runtime.config.deathReentry;debugLog('COOLDOWN_SET',('cid=%s seconds=%d reason=death'):format(victim.cid,runtime.config.deathReentry));restore(victimSrc,victim,'event_death')
    SetTimeout(100,function()if GetPlayerName(victimSrc)then exports[PLAYERDATA]:Respawn(victimSrc,nil,0)end end)
end)
AddEventHandler('playerDropped',function()
    local src=tonumber(source)
    if not src then return end
    local p=runtime.participants[src]
    if p then if p.boundary then punishBoundary(src,p,'disconnect_outside')else p.leftAt=now();p.active=false;p.disconnected=true;p.source=nil;persistPlayer(p)end;runtime.participants[src]=nil end
end)
CreateThread(function()
    while not CMGangDatabaseReady do Wait(500) end
    local changed=MySQL.update.await([[UPDATE cm_gang_events SET status='interrupted',ended_at=NOW(),end_reason='resource_or_server_restart' WHERE event_type=? AND status IN ('announced','live')]],{EVENT_TYPE})
    if tonumber(changed or 0)>0 then debugLog('EVENT_RECOVERY',('interrupted=%d'):format(tonumber(changed)))end
end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() and runtime.id then CMGangEventFinish('cancelled_resource_restart',true) end end)
exports('GetGangEventState',function() return {state=runtime.state,eventId=runtime.id,eventType=runtime.id and EVENT_TYPE or nil,liveAt=runtime.liveAt,endsAt=runtime.endsAt} end)
exports('AdminStartGangEvent',function(src) if GetInvokingResource()~='cm-admin' then return false,'trusted_resource_required' end return CMGangEventStart(src) end)
exports('AdminStopGangEvent',function(src,cancel) if GetInvokingResource()~='cm-admin' or not admin(src) then return false,'permission_denied' end return CMGangEventFinish(cancel and 'admin_cancel' or 'forced_end',cancel==true) end)
exports('GetGangEventParticipant',function(src) local p=runtime.participants[tonumber(src)]; return p and p.active and p or nil end)
exports('IsSupplyWarParticipant',function(src)local n=tonumber(src);local p=n and runtime.participants[n];return runtime.state=='LIVE'and p~=nil and p.active==true and GetPlayerRoutingBucket(n)==runtime.config.bucket end)
exports('AddGangEventObjectiveScore',function(src,points) local p=runtime.participants[tonumber(src)]; if not p or not p.active then return false end; p.drops=p.drops+1; local s=runtime.scores[p.gangId]; s.drops=s.drops+1;s.score=s.score+math.max(0,tonumber(points) or 0);s.heat=s.heat+3;syncScores();persistPlayer(p);return true end)
exports('GetGangEventRuntime',function() return runtime end)
exports('AnnounceArsenalResupply',function(payload)
    if GetInvokingResource()~='cm-law' or type(payload)~='table' or type(payload.presentation)~='table' then return false end
    emit('cm-gang:client:arsenalResupplyAnnounced',{eventId=tostring(payload.eventId or''),presentation=payload.presentation},true)
    return true
end)
exports('SendArsenalResupplyIntel',function(payload)
    if GetInvokingResource()~='cm-law' or type(payload)~='table' then return false end
    emit('cm-gang:client:arsenalResupplyIntel',{eventId=tostring(payload.eventId or''),text=tostring(payload.text or'Convoy sighting reported in the area.'):sub(1,160),radius=math.max(250,math.min(1500,tonumber(payload.radius)or 750))},true)
    return true
end)

lib.callback.register('cm-gang:server:getSupplyWarPresentation',function(source)
    local characterId=cid(source);local member=characterId and membership(characterId);if not member then return{ok=false,reason='not_in_gang'}end
    local config=loadConfig();local state=runtime.state=='ANNOUNCED'and'WARMUP'or runtime.state
    local history=MySQL.query.await([[SELECT event_id,status,UNIX_TIMESTAMP(started_at) started_at,UNIX_TIMESTAMP(ended_at) ended_at,winning_gang_id,final_scores FROM cm_gang_events WHERE event_type=? AND status='completed' ORDER BY ended_at DESC LIMIT 12]],{EVENT_TYPE})or{}
    local rows={};for _,row in ipairs(history)do local saved=decode(row.final_scores,{});rows[#rows+1]={eventId=row.event_id,status=row.status,startedAt=tonumber(row.started_at),endedAt=tonumber(row.ended_at),winner=row.winning_gang_id,standings=saved.gangs or{},mvp=saved.mvp,topGun=saved.topGun,objectives=saved.objectives}end
    return{ok=true,serverTime=now(),event=presentation(),runtime={state=state,nextAt=scheduleStatus.nextAt,liveAt=runtime.liveAt,endsAt=runtime.endsAt,duration=config and config.duration or 1200,resultAvailable=quickResult~=nil and quickResult.availableUntil>now()},history=rows}
end)
lib.callback.register('cm-gang:server:getArsenalResupplyPresentation',function(source)
    if GetResourceState('cm-law')~='started'then return{ok=false,reason='event_unavailable'}end
    local ok,result=pcall(function()return exports['cm-law']:GetArsenalResupplyPresentation(source)end)
    return ok and result or{ok=false,reason='event_unavailable'}
end)
lib.callback.register('cm-gang:server:getSupplyWarQuickResult',function(source,eventId)
    local characterId=cid(source);local member=characterId and membership(characterId)
    if not member or not quickResult or quickResult.availableUntil<=now()or tostring(eventId or'')~=quickResult.eventId or not quickResult.participatingGangs[member.gangId]then return{ok=false,reason='result_unavailable'}end
    local result=resultPayload(quickResult.eventId);if not result then return{ok=false,reason='result_unavailable'}end
    return{ok=true,availableUntil=quickResult.availableUntil,result=result}
end)
lib.callback.register('cm-gang:server:getArsenalResupplyQuickResult',function(source,eventId)
    if GetResourceState('cm-law')~='started' then return {ok=false,reason='result_unavailable'} end
    local ok,result=pcall(function() return exports['cm-law']:GetArsenalResupplyQuickResult(source,eventId) end)
    return ok and result or {ok=false,reason='result_unavailable'}
end)
AddEventHandler('cm-playerdata:server:characterLoaded',function(src)
    if GetResourceState('cm-law')~='started' then return end
    src=tonumber(src)
    SetTimeout(1200,function()
        if not src or not GetPlayerName(src) then return end
        local ok,result=pcall(function() return exports['cm-law']:GetLatestArsenalResupplyQuickResult(src) end)
        if ok and result and result.ok then
            TriggerClientEvent('cm-gang:client:arsenalResupplyResultAvailable',src,result)
        end
    end)
end)

local function trustedAdmin(src)
    return GetInvokingResource()=='cm-admin' and admin(src)
end
exports('AdminGetGangEventManagement',function(src)
    if GetInvokingResource()~='cm-admin' or not admin(src) then return nil end
    local config=MySQL.single.await('SELECT * FROM cm_gang_event_config WHERE event_type=?',{EVENT_TYPE})
    local extra=decode(config and config.config_json,{});return {state={state=runtime.state,eventId=runtime.id,liveAt=runtime.liveAt,endsAt=runtime.endsAt},schedule=scheduleStatus,extra=extra,config=config,presentation=presentation(),
        entryPoints=MySQL.query.await('SELECT * FROM cm_gang_event_entry_points WHERE event_type=? ORDER BY gang_id',{EVENT_TYPE}) or {},
        dropLocations=MySQL.query.await('SELECT * FROM cm_gang_event_drop_locations WHERE event_type=? ORDER BY id',{EVENT_TYPE}) or {},
        rewards=MySQL.query.await('SELECT * FROM cm_gang_event_reward_config WHERE event_type=? ORDER BY tier,id',{EVENT_TYPE}) or {},
        history=MySQL.query.await('SELECT event_id,status,started_at,ended_at,winning_gang_id,end_reason FROM cm_gang_events WHERE event_type=? ORDER BY created_at DESC LIMIT 25',{EVENT_TYPE}) or {}}
end)
exports('AdminConfigureGangEvent',function(src,action,data)
    if not trustedAdmin(src) then return false,'permission_denied' end
    if runtime.state~='IDLE' and runtime.state~='ENDED' then return false,'event_active' end
    data=type(data)=='table' and data or {};action=tostring(action or '')
    local characterId=cid(src);local c,ped=coords(src)
    local existingDraft=configDrafts[tonumber(src)]
    if action~='configBegin' and action:find('^config') and existingDraft then
        local tick=GetGameTimer();if (existingDraft.nextMutation or 0)>tick then return false,'rate_limited' end;existingDraft.nextMutation=tick+250
    end
    if action=='configBegin' then
        local current=MySQL.single.await('SELECT * FROM cm_gang_event_config WHERE event_type=?',{EVENT_TYPE}) or {}
        local existing=MySQL.query.await('SELECT label,x,y,z FROM cm_gang_event_drop_locations WHERE event_type=? AND enabled=1 ORDER BY id',{EVENT_TYPE}) or {}
        local draft={radius=math.max(Config.GangEvents.zoneRadiusMin,math.min(Config.GangEvents.zoneRadiusMax,tonumber(current.zone_radius) or 250)),label=tostring(current.area_name or ''),drops={},settings={}}
        if tonumber(current.zone_x) then draft.center={x=tonumber(current.zone_x),y=tonumber(current.zone_y),z=tonumber(current.zone_z)} end
        for _,p in ipairs(existing) do draft.drops[#draft.drops+1]={label=tostring(p.label),x=tonumber(p.x),y=tonumber(p.y),z=tonumber(p.z)} end
        configDrafts[tonumber(src)]=draft
        TriggerClientEvent('cm-admin:client:gangEventConfigMode',tonumber(src),draft)
        return true,'Supply War config mode started.'
    elseif action=='configCenter' then
        local draft=configDrafts[tonumber(src)];if not draft or not c then return false,'config_session_missing' end
        draft.center={x=c.x,y=c.y,z=c.z};draft.drops={};TriggerClientEvent('cm-admin:client:gangEventConfigDraft',tonumber(src),draft);return true,'Event center captured.'
    elseif action=='configRadius' then
        local draft=configDrafts[tonumber(src)];if not draft or not draft.center then return false,'center_required' end
        draft.radius=math.max(Config.GangEvents.zoneRadiusMin,math.min(Config.GangEvents.zoneRadiusMax,tonumber(data.radius) or draft.radius));TriggerClientEvent('cm-admin:client:gangEventConfigDraft',tonumber(src),draft);return true,'Event radius staged.'
    elseif action=='configDrop' then
        local draft=configDrafts[tonumber(src)];if not draft or not draft.center or not c then return false,'center_required' end
        if distance(c,draft.center)>draft.radius+25 then return false,'drop_outside_event_zone' end
        if #draft.drops>=20 then return false,'drop_location_limit' end
        draft.drops[#draft.drops+1]={label=('Drop %d'):format(#draft.drops+1),x=c.x,y=c.y,z=c.z};TriggerClientEvent('cm-admin:client:gangEventConfigDraft',tonumber(src),draft);return true,'Drop location staged.'
    elseif action=='configDetails' then
        local draft=configDrafts[tonumber(src)];if not draft then return false,'config_session_missing' end
        local lands={};for value in tostring(data.landSeconds or ''):gmatch('%d+') do lands[#lands+1]=tonumber(value) end
        local points={};for value in tostring(data.points or ''):gmatch('%d+') do points[#points+1]=tonumber(value) end
        if #lands~=5 or #points~=5 then return false,'five_drop_timings_and_scores_required' end
        local previous=-1;for i=1,5 do lands[i]=math.max(0,math.min(7000,math.floor(lands[i])));if lands[i]<=previous then return false,'drop_timings_must_increase' end;previous=lands[i];points[i]=math.max(0,math.min(100,math.floor(points[i]))) end
        draft.details={landSeconds=lands,points=points};TriggerClientEvent('cm-admin:client:gangEventConfigDraft',tonumber(src),draft);return true,'Drop timing staged.'
    elseif action=='configSave' then
        local draft=configDrafts[tonumber(src)];if not draft or not draft.center or #draft.drops<1 or not draft.details then return false,'config_incomplete' end
        local schedule={};for i=1,5 do schedule[i]={at=draft.details.landSeconds[i],points=draft.details.points[i],final=i==5} end
        local current=MySQL.single.await('SELECT config_json FROM cm_gang_event_config WHERE event_type=?',{EVENT_TYPE})or{};local extra=decode(current.config_json,{});extra.drops=schedule;extra.rewardPackage=type(extra.rewardPackage)=='table'and extra.rewardPackage or Config.GangEvents.supplyWar.rewardPackage
        MySQL.update.await([[UPDATE cm_gang_event_config SET enabled=1,zone_x=?,zone_y=?,zone_z=?,zone_radius=?,area_name=?,duration_seconds=?,config_json=?,updated_by_character_id=? WHERE event_type=?]],{draft.center.x,draft.center.y,draft.center.z,draft.radius,draft.label,math.max(300,draft.details.landSeconds[5]+270),json.encode(extra),characterId,EVENT_TYPE})
        MySQL.update.await('DELETE FROM cm_gang_event_drop_locations WHERE event_type=?',{EVENT_TYPE});for _,p in ipairs(draft.drops) do MySQL.insert.await('INSERT INTO cm_gang_event_drop_locations(event_type,label,enabled,x,y,z,updated_by_character_id) VALUES(?,?,1,?,?,?,?)',{EVENT_TYPE,p.label,p.x,p.y,p.z,characterId}) end
        configDrafts[tonumber(src)]=nil;TriggerClientEvent('cm-admin:client:gangEventConfigFinished',tonumber(src),true);return true,'Supply War configuration saved.'
    elseif action=='configCancel' then configDrafts[tonumber(src)]=nil;TriggerClientEvent('cm-admin:client:gangEventConfigFinished',tonumber(src),false);return true,'Supply War configuration cancelled.'
    elseif action=='zoneHere' then
        if not c then return false,'entity_not_found' end;local radius=math.max(Config.GangEvents.zoneRadiusMin,math.min(Config.GangEvents.zoneRadiusMax,tonumber(data.radius) or 250))
        MySQL.update.await('UPDATE cm_gang_event_config SET zone_x=?,zone_y=?,zone_z=?,zone_radius=?,area_name=?,updated_by_character_id=? WHERE event_type=?',{c.x,c.y,c.z,radius,tostring(data.label or ''):sub(1,96),characterId,EVENT_TYPE});return true
    elseif action=='entryHere' then
        local gangId=tostring(data.gangId or '');if not c or not Config.IsFixedGangId(gangId) then return false,'invalid_request' end
        MySQL.query.await([[INSERT INTO cm_gang_event_entry_points(event_type,gang_id,enabled,x,y,z,heading,updated_by_character_id) VALUES(?,?,1,?,?,?,?,?) ON DUPLICATE KEY UPDATE enabled=1,x=VALUES(x),y=VALUES(y),z=VALUES(z),heading=VALUES(heading),updated_by_character_id=VALUES(updated_by_character_id)]],{EVENT_TYPE,gangId,c.x,c.y,c.z,GetEntityHeading(ped),characterId});return true
    elseif action=='dropHere' then
        if not c then return false,'entity_not_found' end;local config,why=loadConfig();if not config then return false,why end;if distance(c,config.zone)>config.radius+25 then return false,'drop_outside_event_zone' end
        MySQL.insert.await('INSERT INTO cm_gang_event_drop_locations(event_type,label,enabled,x,y,z,updated_by_character_id) VALUES(?,?,1,?,?,?,?)',{EVENT_TYPE,tostring(data.label or 'Supply Drop'):sub(1,96),c.x,c.y,c.z,characterId});return true
    elseif action=='dropMoveHere' then
        local id=math.floor(tonumber(data.id)or 0);if id<1 or not c then return false,'invalid_request'end;local config,why=loadConfig();if not config then return false,why end;if distance(c,config.zone)>config.radius+25 then return false,'drop_outside_event_zone'end
        local changed=MySQL.update.await('UPDATE cm_gang_event_drop_locations SET x=?,y=?,z=?,updated_by_character_id=? WHERE id=? AND event_type=?',{c.x,c.y,c.z,characterId,id,EVENT_TYPE});if tonumber(changed or 0)<1 then return false,'drop_not_found'end;return true
    elseif action=='dropToggle' then local id=tonumber(data.id);if not id then return false,'invalid_request' end;MySQL.update.await('UPDATE cm_gang_event_drop_locations SET enabled=? WHERE id=? AND event_type=?',{data.enabled==true and 1 or 0,id,EVENT_TYPE});return true
    elseif action=='dropDelete' then local id=tonumber(data.id);if not id then return false,'invalid_request' end;MySQL.update.await('DELETE FROM cm_gang_event_drop_locations WHERE id=? AND event_type=?',{id,EVENT_TYPE});return true
    elseif action=='dropScheduleSave' then
        local index=math.floor(tonumber(data.index)or 0);if index<1 or index>20 then return false,'invalid_drop_index'end
        local row=MySQL.single.await('SELECT config_json FROM cm_gang_event_config WHERE event_type=?',{EVENT_TYPE})or{};local extra=decode(row.config_json,{});extra.drops=type(extra.drops)=='table'and extra.drops or{}
        while#extra.drops<index do extra.drops[#extra.drops+1]={at=(#extra.drops)*300,points=5,final=false}end
        extra.drops[index]={at=math.max(0,math.min(7200,math.floor(tonumber(data.at)or 0))),points=math.max(0,math.min(100,math.floor(tonumber(data.points)or 5))),final=data.final==true}
        MySQL.update.await('UPDATE cm_gang_event_config SET config_json=?,updated_by_character_id=? WHERE event_type=?',{json.encode(extra),characterId,EVENT_TYPE});return true
    elseif action=='rewardSave' then
        local tier=tostring(data.tier or ''):upper();local item=tostring(data.itemId or ''):lower();if not ({BASIC=true,IMPROVED=true,HIGH_VALUE=true})[tier] or item=='' then return false,'invalid_reward' end
        local min=math.max(1,math.floor(tonumber(data.min) or 1));local max=math.max(min,math.floor(tonumber(data.max) or min));local weight=math.max(1,math.min(10000,math.floor(tonumber(data.weight) or 1)))
        local known=false;if GetResourceState('cm-weapons')=='started' then local ok,v=pcall(function() return exports['cm-weapons']:GetWeapon(item) end);known=ok and v~=nil end;if not known and GetResourceState('cm-items')=='started' then local ok,v=pcall(function() return exports['cm-items']:GetItem(item) end);known=ok and v~=nil end;if not known then return false,'unknown_catalog_item' end
        MySQL.query.await([[INSERT INTO cm_gang_event_reward_config(event_type,tier,item_id,enabled,min_quantity,max_quantity,weight,updated_by_character_id) VALUES(?,?,?,1,?,?,?,?) ON DUPLICATE KEY UPDATE enabled=1,min_quantity=VALUES(min_quantity),max_quantity=VALUES(max_quantity),weight=VALUES(weight),updated_by_character_id=VALUES(updated_by_character_id)]],{EVENT_TYPE,tier,item,min,max,weight,characterId});return true
    elseif action=='settings' then
        local row=MySQL.single.await('SELECT * FROM cm_gang_event_config WHERE event_type=?',{EVENT_TYPE})or{};local extra=decode(row.config_json,{})
        extra.schedule={autoStart=data.autoStart==true,intervalHours=math.max(1,math.min(24,tonumber(data.intervalHours)or 2)),anchorHour=math.max(0,math.min(23,math.floor(tonumber(data.anchorHour)or 0))),anchorMinute=math.max(0,math.min(59,math.floor(tonumber(data.anchorMinute)or 0))),graceMinutes=math.max(0,math.min(30,tonumber(data.graceMinutes)or 5)),warmupMinutes=math.max(0,math.min(60,tonumber(data.warmupMinutes)or 5))}
        extra.joinRingWidth=math.max(1,math.min(50,tonumber(data.joinRing)or 8));extra.deathReentryCooldownSeconds=math.max(0,math.min(3600,tonumber(data.deathReentry)or 120));extra.boundaryCooldownSeconds=math.max(0,math.min(3600,tonumber(data.boundaryCooldown)or 120));extra.supplyPoints=math.max(0,math.min(100,tonumber(data.supplyPoints)or 5))
        local classes={};if type(data.allowedVehicleClasses)=='table'then local seen={};for _,value in ipairs(data.allowedVehicleClasses)do local class=math.floor(tonumber(value)or-1);if class>=0 and class<=22 and not seen[class]then seen[class]=true;classes[#classes+1]=class end end end
        extra.vehiclePolicy={allowVehicles=data.allowVehicles==true,allowedClasses=classes};extra.worldBoundary={enabled=data.worldBoundaryEnabled~=false,renderDistance=math.max(25,math.min(500,tonumber(data.worldBoundaryRenderDistance)or 150)),segments=64};extra.supplyNotificationEnabled=data.supplyNotificationEnabled~=false;extra.warmupAreaMessageEnabled=false;extra.resultQuickViewSeconds=math.max(10,math.min(300,math.floor(tonumber(data.resultQuickViewSeconds)or tonumber(extra.resultQuickViewSeconds)or 60)))
        local enabled=data.enabled==true and 1 or 0;local announce=math.max(10,math.min(3600,math.floor((tonumber(data.warmupMinutes)or 5)*60)));local duration=math.max(300,math.min(7200,math.floor(tonumber(data.duration)or tonumber(row.duration_seconds)or 1200)));local bucket=math.max(Config.GangEvents.bucketMin,math.min(Config.GangEvents.bucketMax,math.floor(tonumber(data.bucket)or tonumber(row.routing_bucket)or 7100)))
        MySQL.update.await([[UPDATE cm_gang_event_config SET enabled=?,event_name=?,announcement_seconds=?,duration_seconds=?,routing_bucket=?,max_active_drops=?,capture_seconds=?,contest_radius=?,kill_points=?,anti_farm_seconds=?,combat_tag_seconds=?,boundary_grace_seconds=?,config_json=?,updated_by_character_id=? WHERE event_type=?]],{enabled,tostring(data.name or row.event_name or'Supply War'):sub(1,96),announce,duration,bucket,math.max(1,math.min(5,tonumber(data.maxDrops)or tonumber(row.max_active_drops)or 2)),math.max(2,math.min(30,tonumber(data.capture)or tonumber(row.capture_seconds)or 4)),math.max(3,math.min(75,tonumber(data.contestRadius)or tonumber(row.contest_radius)or 20)),math.max(0,math.min(20,tonumber(data.killPoints)or tonumber(row.kill_points)or 1)),math.max(0,math.min(600,tonumber(data.antiFarm)or tonumber(row.anti_farm_seconds)or 90)),math.max(1,math.min(60,tonumber(data.combatTag)or tonumber(row.combat_tag_seconds)or 15)),math.max(1,math.min(30,tonumber(data.boundaryWarning)or tonumber(row.boundary_grace_seconds)or 5)),json.encode(extra),characterId,EVENT_TYPE});return true
    elseif action=='rewardPackageAdd' then
        local item=tostring(data.itemId or''):lower();local amount=math.floor(tonumber(data.amount)or 0);if item==''or#item>96 or not item:match('^[%w_%-]+$')or amount<1 or amount>10000 then return false,'invalid_reward_item'end
        local known=false;if GetResourceState('cm-weapons')=='started'then local ok,value=pcall(function()return exports['cm-weapons']:GetWeapon(item)end);known=ok and value~=nil end;if not known and GetResourceState('cm-items')=='started'then local ok,value=pcall(function()return exports['cm-items']:GetItem(item)end);known=ok and value~=nil end;if not known then return false,'unknown_catalog_item'end
        local row=MySQL.single.await('SELECT config_json FROM cm_gang_event_config WHERE event_type=?',{EVENT_TYPE})or{};local extra=decode(row.config_json,{});extra.rewardPackage=type(extra.rewardPackage)=='table'and extra.rewardPackage or{}
        local normalized,found={},false;for _,entry in ipairs(extra.rewardPackage)do local existing=tostring(entry.item or entry.itemId or''):lower();if existing==item then if not found then normalized[#normalized+1]={item=item,amount=amount};found=true end elseif existing~=''then normalized[#normalized+1]={item=existing,amount=math.max(1,math.min(10000,math.floor(tonumber(entry.amount)or 1)))}end end;if not found then normalized[#normalized+1]={item=item,amount=amount}end;extra.rewardPackage=normalized;MySQL.update.await('UPDATE cm_gang_event_config SET config_json=?,updated_by_character_id=? WHERE event_type=?',{json.encode(extra),characterId,EVENT_TYPE});return true
    elseif action=='rewardPackageRemove' then
        local item=tostring(data.itemId or''):lower();local row=MySQL.single.await('SELECT config_json FROM cm_gang_event_config WHERE event_type=?',{EVENT_TYPE})or{};local extra=decode(row.config_json,{});local nextPackage={};for _,entry in ipairs(type(extra.rewardPackage)=='table'and extra.rewardPackage or Config.GangEvents.supplyWar.rewardPackage)do if tostring(entry.item)~=item then nextPackage[#nextPackage+1]=entry end end;if#nextPackage<1 then return false,'reward_package_cannot_be_empty'end;extra.rewardPackage=nextPackage;MySQL.update.await('UPDATE cm_gang_event_config SET config_json=?,updated_by_character_id=? WHERE event_type=?',{json.encode(extra),characterId,EVENT_TYPE});return true
    elseif action=='reset' and data.confirm==true then MySQL.update.await([[UPDATE cm_gang_event_config SET enabled=0,event_name='Gang Supply War',announcement_seconds=60,duration_seconds=1500,routing_bucket=7100,max_active_drops=2,capture_seconds=4,contested_capture_seconds=7,contest_radius=20,kill_points=1,anti_farm_seconds=90,combat_tag_seconds=15,reentry_cooldown_seconds=40,config_json=NULL WHERE event_type=?]],{EVENT_TYPE});return true end
    return false,'unknown_event_admin_action'
end)
AddEventHandler('playerDropped',function()
    local src=tonumber(source)
    if src then configDrafts[src]=nil end
end)
