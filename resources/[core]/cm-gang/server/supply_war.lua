local TYPE='supply_war'
local drops,pending,pendingIds,lastLocation={}, {}, {}, nil
local function runtime()return exports['cm-gang']:GetGangEventRuntime()end
local function now()return os.time()end
local function dist(a,b)local x=a.x-b.x;local y=a.y-b.y;local z=a.z-b.z;return math.sqrt(x*x+y*y+z*z)end
local function debugLog(action,detail)if Config.GangEvents.supplyWar.debug==true then print(('[cm-gang:supplywar] %s%s'):format(action,detail and(' '..detail)or''))end end
local function locations(config)
    local rows=MySQL.query.await('SELECT id,label,x,y,z FROM cm_gang_event_drop_locations WHERE event_type=? AND enabled=1',{TYPE})or{}
    local valid={};for _,row in ipairs(rows)do local p={id=tonumber(row.id),label=row.label,x=tonumber(row.x),y=tonumber(row.y),z=tonumber(row.z)};if p.x and p.y and p.z and dist(p,config.zone)<=config.radius+25 then valid[#valid+1]=p end end;return valid
end
local function rewardPackage(config)
    local configured=config and config.extra and config.extra.rewardPackage
    local source=type(configured)=='table'and#configured>0 and configured or Config.GangEvents.supplyWar.rewardPackage
    local result,byItem={},{};for _,entry in ipairs(source or{})do local item=tostring(entry.item or entry.itemId or''):lower();local amount=math.floor(tonumber(entry.amount or entry.quantity)or 0);if item~=''and amount>0 then if byItem[item]then byItem[item].amount=byItem[item].amount+amount else local reward={item=item,amount=amount};byItem[item]=reward;result[#result+1]=reward end end end;return result
end
local function catalogItem(item)
    if GetResourceState('cm-weapons')=='started'then local ok,value=pcall(function()return exports['cm-weapons']:GetWeapon(item)end);if ok and value then return true end end
    if GetResourceState('cm-items')=='started'then local ok,value=pcall(function()return exports['cm-items']:GetItem(item)end);if ok and value then return true end end
    return false
end
function CMGangSupplyWarValidate(config)
    local problems={};if#locations(config)<1 then problems[#problems+1]='Missing supply drop locations'end
    local package=rewardPackage(config);if#package<1 then problems[#problems+1]='Missing supply reward package'end
    for _,reward in ipairs(package)do
        if reward.amount<1 or reward.amount>10000 or not catalogItem(reward.item)then problems[#problems+1]='Invalid reward: '..reward.item end
        local rows=MySQL.query.await('SELECT gang_id FROM cm_gang_armory_config WHERE item_id=? AND enabled=1',{reward.item})or{};local enabled={};for _,row in ipairs(rows)do enabled[tostring(row.gang_id)]=true end
        for _,gangId in ipairs(Config.GangIds)do if not enabled[gangId]then problems[#problems+1]=('Reward %s not enabled for %s'):format(reward.item,gangId)end end
    end
    if Config.GangEvents.supplyWar.objectiveTickMs<250 then problems[#problems+1]='Invalid objective timing configuration'end
    if#problems>0 then return false,'SUPPLY WAR CONFIG INVALID: '..table.concat(problems,'; ')end;return true
end
local function targets(r)local out={};for src,p in pairs(r.participants or{})do if p.active and r.config and GetPlayerRoutingBucket(src)==r.config.bucket then out[#out+1]=src end end;return out end
local function sendAll(event,payload)local r=runtime();for _,src in ipairs(targets(r))do TriggerClientEvent(event,src,payload)end end
local function activeCount()local count=0;for _,drop in pairs(drops)do if drop.state~='SECURED'and drop.state~='EXPIRED'then count=count+1 end end;return count end
local function selectLocation(config)local list=locations(config);if#list==0 then return end;local pool={};for _,point in ipairs(list)do if#list==1 or point.id~=lastLocation then pool[#pool+1]=point end end;local picked=pool[math.random(1,#pool)];lastLocation=picked.id;return picked end
local function statePayload(d)return{id=d.id,number=d.number,tier='SUPPLY',final=d.final,state=d.state,controllingGang=d.controllingGang,captureProgress=math.floor((d.captureProgress or 0)+.5),participantsInside=d.participantsInside or{},securedBy=d.securedBy}end
local function visualPayload(d)return{id=d.id,number=d.number,tier='SUPPLY',final=d.final,state=d.state,location=d.location,landAt=d.landedAt,landedAt=d.state~='INBOUND'and d.landedAt or nil,spawnedAt=d.spawnedAt,spawnHeight=d.spawnHeight}end
local function broadcast(d,force)local payload=statePayload(d);local encoded=json.encode(payload);if force or encoded~=d.lastPayload then d.lastPayload=encoded;sendAll('cm-gang:client:dropState',payload)end end
local processPending
local function queueDrop(number,spec,config,eventId)
    local id=('%s:drop:%d'):format(eventId,number);if pendingIds[id]or drops[id]then return end;pendingIds[id]=true;pending[#pending+1]={id=id,number=number,spec=spec,config=config,eventId=eventId};sendAll('cm-gang:client:dropDelayed',{number=number,final=spec.final==true});debugLog('DROP_DELAYED',('event=%s drop=%d'):format(eventId,number))
end
local function createDrop(number,spec,config,eventId)
    if activeCount()>=config.maxActiveDrops then queueDrop(number,spec,config,eventId);return false end
    local point=selectLocation(config);if not point then queueDrop(number,spec,config,eventId);return false end
    local id=('%s:drop:%d'):format(eventId,number);pendingIds[id]=nil;local spawned=now();local descent=math.max(3,math.min(60,math.floor(tonumber(Config.GangEvents.supplyWar.parachuteDescentSeconds)or 12)));local defaultPoints=config.extra and config.extra.supplyPoints or 5;local d={eventId=eventId,id=id,number=number,points=math.max(0,tonumber(spec.points)or tonumber(defaultPoints)or 5),final=spec.final==true,location=point,state='INBOUND',spawnedAt=spawned,landedAt=spawned+descent,spawnHeight=math.max(20.0,math.min(200.0,tonumber(Config.GangEvents.supplyWar.parachuteSpawnHeight)or 70.0)),captureProgress=0,participantsInside={}};drops[id]=d
    MySQL.insert.await([[INSERT INTO cm_gang_event_drops(event_id,drop_id,drop_number,tier,location_id,state,spawned_at,landed_at)VALUES(?,?,?,?,?,'INBOUND',NOW(),NULL)]],{eventId,id,number,'SUPPLY',point.id})
    sendAll('cm-gang:client:dropInbound',visualPayload(d));broadcast(d,true);debugLog('DROP_INBOUND',('event=%s drop=%d landing_in=%d'):format(eventId,number,descent))
    SetTimeout(descent*1000,function()
        local r=runtime();local current=drops[id];if r.id~=eventId or r.state~='LIVE'or current~=d or d.state~='INBOUND'then return end
        d.state='AVAILABLE';d.landedAt=now();MySQL.update.await("UPDATE cm_gang_event_drops SET state='AVAILABLE',landed_at=NOW() WHERE event_id=? AND drop_id=? AND state='INBOUND'",{eventId,id})
        sendAll('cm-gang:client:dropLanded',visualPayload(d));broadcast(d,true);debugLog('DROP_AVAILABLE',('event=%s drop=%d final=%s'):format(eventId,number,tostring(d.final)));debugLog('SUPPLY_NOTIFICATION',('event=%s drop=%d targets=participants'):format(eventId,number))
    end)
    return true
end
processPending=function()
    local r=runtime();if r.state~='LIVE'or#pending==0 or activeCount()>=r.config.maxActiveDrops then return end
    local selected=1;for index,row in ipairs(pending)do if row.spec.final==true then selected=index;break end end;local row=table.remove(pending,selected);pendingIds[row.id]=nil;if not createDrop(row.number,row.spec,row.config,row.eventId)then queueDrop(row.number,row.spec,row.config,row.eventId)end
end
AddEventHandler('cm-gang:server:eventStarted',function(eventId,config,liveAt)
    drops={};pending={};pendingIds={};lastLocation=nil;local schedule=(config.extra and config.extra.drops)or Config.GangEvents.supplyWar.drops
    for index,spec in ipairs(schedule)do local at=math.max(0,tonumber(spec.at or spec.inbound or spec.land)or 0);SetTimeout(math.max(0,liveAt+at-now())*1000,function()local r=runtime();if r.id==eventId and r.state=='LIVE'then createDrop(index,spec,config,eventId)end end)end
end)
AddEventHandler('cm-gang:server:eventParticipantJoined',function(src,eventId)
    local r=runtime();src=tonumber(src);if not src or r.id~=eventId or r.state~='LIVE'or GetPlayerRoutingBucket(src)~=r.config.bucket then return end;local p=r.participants[src];if not p or not p.active then return end
    for _,d in pairs(drops)do if d.state~='SECURED'and d.state~='EXPIRED'then TriggerClientEvent('cm-gang:client:dropVisualSync',src,visualPayload(d));TriggerClientEvent('cm-gang:client:dropState',src,statePayload(d))end end
end)
local function actor(src,r,d)
    local p=r.participants and r.participants[src];if r.state~='LIVE'or not p or not p.active or not d or(d.state~='AVAILABLE'and d.state~='CAPTURING'and d.state~='CONTESTED')then return end
    if GetPlayerRoutingBucket(src)~=r.config.bucket or exports['cm-playerdata']:IsDead(src)then return end;local ped=GetPlayerPed(src);if ped==0 then return end;local c=GetEntityCoords(ped);if dist({x=c.x,y=c.y,z=c.z},d.location)>r.config.claimRadius then return end;return p
end
RegisterNetEvent('cm-gang:server:beginDropClaim',function(dropId)
    local src=tonumber(source);local r=runtime();local d=drops[tostring(dropId or'')];local p=actor(src,r,d);if not p then return end;local tick=GetGameTimer();if(p.objectiveRequestAt or 0)+1000>tick then return end;p.objectiveRequestAt=tick
    if d.controllingGang and d.controllingGang~=p.gangId and(d.captureProgress or 0)>Config.GangEvents.supplyWar.takeoverProgress then return TriggerClientEvent('cm-gang:client:dropClaimCancelled',src,{reason='Enemy control must decay first.'})end
    d.controllingGang=p.gangId;d.claimant=p.cid;d.state='CAPTURING';broadcast(d,true)
end)
local function secure(d,r)
    if d.awarding or d.state=='SECURED'then return end;d.awarding=true;local participant=r.participantsByCharacterId[d.claimant];if not participant or participant.gangId~=d.controllingGang then d.awarding=nil;d.state='AVAILABLE';return end
    local package=rewardPackage(r.config);local summary={};debugLog('REWARD_BEGIN',('event=%s drop=%d gang=%s'):format(r.id,d.number,participant.gangId))
    for _,reward in ipairs(package)do local operation=('sw:%s:%d:%s'):format(r.id,d.number,reward.item);local ok,reason=exports['cm-gang']:AddGangArmoryStock(participant.gangId,reward.item,reward.amount,{eventId=r.id,dropId=d.id,operationId=operation});if not ok then d.awarding=nil;d.state='AVAILABLE';print(('[cm-gang] supply package reward failed item=%s reason=%s'):format(reward.item,tostring(reason)));return end;if reason=='already_applied'then debugLog('REWARD_DUPLICATE_BLOCKED','operation='..operation)end;summary[#summary+1]={itemId=reward.item,quantity=reward.amount}end
    local claimOperation=('supplywar:%s:drop:%d:package'):format(r.id,d.number);local changed=MySQL.update.await([[UPDATE cm_gang_event_drops SET state='SECURED',claimed_at=NOW(),claimed_gang_id=?,claimed_character_id=?,reward_summary=?,claim_operation_id=? WHERE event_id=? AND drop_id=? AND state<>'SECURED']],{participant.gangId,participant.cid,json.encode(summary),claimOperation,r.id,d.id});if tonumber(changed or 0)<1 then return end
    d.state='SECURED';d.securedBy=participant.gangId;exports['cm-gang']:AddGangEventObjectiveScore(participant.source,d.points);sendAll('cm-gang:client:dropClaimed',{id=d.id,number=d.number,gangId=participant.gangId,player=participant.name,points=d.points,rewards=summary});broadcast(d,true);sendAll('cm-gang:client:dropCleanup',d.id);debugLog('REWARD_SUCCESS',('event=%s drop=%d gang=%s'):format(r.id,d.number,participant.gangId));processPending()
end
CreateThread(function()
    while true do local r=runtime();if r.state~='LIVE'then Wait(1000)else local tick=Config.GangEvents.supplyWar.objectiveTickMs
        for _,d in pairs(drops)do if d.state=='AVAILABLE'or d.state=='CAPTURING'or d.state=='CONTESTED'then local counts={};for src,p in pairs(r.participants or{})do if p.active and GetPlayerRoutingBucket(src)==r.config.bucket and not exports['cm-playerdata']:IsDead(src)then local ped=GetPlayerPed(src);if ped~=0 then local c=GetEntityCoords(ped);if dist({x=c.x,y=c.y,z=c.z},d.location)<=r.config.contestRadius then counts[p.gangId]=(counts[p.gangId]or 0)+1 end end end end;d.participantsInside=counts;local allies=d.controllingGang and(counts[d.controllingGang]or 0)or 0;local enemies=0;for gang,count in pairs(counts)do if gang~=d.controllingGang then enemies=enemies+count end end
            if d.controllingGang and allies>0 and enemies>0 then d.state='CONTESTED'elseif d.controllingGang and allies>0 then d.state='CAPTURING';local duration=d.final and Config.GangEvents.supplyWar.finalCaptureSeconds or(r.config.capture or Config.GangEvents.supplyWar.captureSeconds);d.captureProgress=math.min(100,(d.captureProgress or 0)+(tick/1000)/duration*100)elseif d.controllingGang then d.captureProgress=math.max(0,(d.captureProgress or 0)-Config.GangEvents.supplyWar.captureDecayPerSecond*(tick/1000));if d.captureProgress<=Config.GangEvents.supplyWar.takeoverProgress then d.controllingGang=nil;d.claimant=nil;d.state='AVAILABLE'end end;broadcast(d,false);if d.captureProgress>=100 then secure(d,r)end
        end end;Wait(tick)
    end end
end)
AddEventHandler('cm-gang:server:eventCleanup',function()sendAll('cm-gang:client:dropCleanup',nil);drops={};pending={};pendingIds={}end)
