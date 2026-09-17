local RESOURCE,PLAYERDATA='cm-gang','cm-playerdata'
local tags,sessions,tagLocks,alertAt,placementSessions,available={}, {}, {}, {}, {}, false

local function cid(src)
 local ok,value=pcall(function() return exports[PLAYERDATA]:GetCharacterId(tonumber(src)) end)
 value=ok and tostring(value or '') or ''; return value:match('^%d+$') and value or nil
end
local function membership(src,permission)
 local characterId=cid(src); if not characterId then return nil,'character_not_loaded' end
 local member=exports[RESOURCE]:GetGangForCharacter(characterId)
 if not member or member.enabled~=true or not Config.IsFixedGangId(member.gangId) then return nil,'not_in_enabled_gang' end
 if permission and not exports[RESOURCE]:HasPermission(characterId,permission) then return nil,'no_permission' end
 return {source=tonumber(src),characterId=characterId,member=member}
end
local function publicTag(row)
 return {id=tonumber(row.id),name=tostring(row.name),x=tonumber(row.x),y=tonumber(row.y),z=tonumber(row.z),heading=tonumber(row.heading) or 0,normalX=tonumber(row.normal_x),normalY=tonumber(row.normal_y),normalZ=tonumber(row.normal_z),upX=tonumber(row.up_x),upY=tonumber(row.up_y),upZ=tonumber(row.up_z),rotation=tonumber(row.rotation) or 0,width=tonumber(row.width) or 2.0,height=tonumber(row.height) or 1.2,placementReady=CMGangDbTrue(row.placement_ready),routingBucket=tonumber(row.routing_bucket) or 0,gangId=Config.IsFixedGangId(row.gang_id) and row.gang_id or nil,textureKey=tostring(row.texture_key or 'default'),enabled=CMGangDbTrue(row.enabled)}
end
local function loadTags()
 local exists=tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='cm_gang_graffiti'")) or 0
 if exists~=1 then print('^3[cm-gang] DATABASE ACTION REQUIRED: apply sql/009_cm_gang_graffiti.sql^7'); return end
 tags={}; for _,row in ipairs(MySQL.query.await('SELECT * FROM cm_gang_graffiti') or {}) do tags[tonumber(row.id)]=publicTag(row) end
 available=true; TriggerClientEvent('cm-gang:client:graffitiRefresh',-1)
end
local function closeEnough(c,tag)
 if not tag or not tag.enabled then return false,'graffiti_unavailable' end
 if GetPlayerRoutingBucket(c.source)~=tag.routingBucket then return false,'wrong_routing_bucket' end
 local ped=GetPlayerPed(c.source); if ped==0 or not DoesEntityExist(ped) then return false,'player_entity_unavailable' end
 if #(GetEntityCoords(ped)-vector3(tag.x,tag.y,tag.z))>((Config.Graffiti.interactionDistance or 2.5)+0.75) then return false,'too_far_away' end
 return true
end
local function design(gangId)
 local first=Config.Graffiti.designs[gangId] and Config.Graffiti.designs[gangId][1]
 return first and tostring(first.id) or nil
end
local function inventoryReady()
 return GetResourceState('cm-inventory')=='started'
end
local function hasSprayCan(src)
 if not inventoryReady() then return false,'inventory_unavailable' end
 local item=tostring(Config.Graffiti.requiredItem or 'spray_can')
 local ok,has=pcall(function() return exports['cm-inventory']:HasItemDurability(src,item) end)
 return ok and has==true,ok and 'spray_can_required' or 'inventory_unavailable'
end
local function consumeSprayCan(src)
 if not inventoryReady() then return false,'inventory_unavailable' end
 local item=tostring(Config.Graffiti.requiredItem or 'spray_can'); local gas=math.max(1,math.min(100,math.floor(tonumber(Config.Graffiti.gasPerSpray) or 2)))
 local ok,consumed,remaining,reason=pcall(function() return exports['cm-inventory']:ConsumeItemDurability(src,item,gas,'gang_graffiti_repaint') end)
 return ok and consumed==true,(ok and reason or 'inventory_unavailable'),tonumber(remaining) or 0
end
local function log(gangId,action,actor,target,detail)
 MySQL.insert.await('INSERT INTO cm_gang_activity(event_uid,gang_id,action,actor_character_id,target_character_id,detail) VALUES(?,?,?,?,?,?)',{('graffiti:%s:%d:%d'):format(action,os.time(),math.random(100000,999999)),gangId,action,actor,target,json.encode(detail or {})})
end
local function cancelSession(sessionId,reason)
 local session=sessions[sessionId]; if not session then return end
 sessions[sessionId]=nil; if tagLocks[session.graffitiId]==sessionId then tagLocks[session.graffitiId]=nil end
 if reason then log(session.gangId,'graffiti_repaint_cancelled',session.characterId,nil,{graffitiId=session.graffitiId,reason=reason}) end
end
lib.callback.register('cm-gang:server:getGraffiti',function(src) local out={}; local bucket=GetPlayerRoutingBucket(src); for id,tag in pairs(tags) do if tag.routingBucket==bucket then out[id]=tag end end return {ok=available,tags=out} end)
lib.callback.register('cm-gang:server:graffitiBegin',function(src,rawId)
 local c,reason=membership(src,'gang.graffiti'); if not c then return {ok=false,reason=reason} end
 local hasCan,itemReason=hasSprayCan(c.source); if not hasCan then return {ok=false,reason=itemReason} end
 local id=tonumber(rawId); local tag=tags[id]; local near,nearReason=closeEnough(c,tag); if not near then return {ok=false,reason=nearReason} end
 if tag.gangId==c.member.gangId then return {ok=false,reason='already_owned'} end
 if tagLocks[id] then return {ok=false,reason='repaint_in_progress'} end
 local sessionId=('%s:%d:%d'):format(c.characterId,id,math.random(100000,999999)); local timeout=tonumber(Config.Graffiti.activeSessionTimeout) or 20
 sessions[sessionId]={id=sessionId,graffitiId=id,source=c.source,characterId=c.characterId,gangId=c.member.gangId,victimGang=tag.gangId,ownerAtBegin=tag.gangId,expiresAt=os.time()+timeout}
 tagLocks[id]=sessionId; log(c.member.gangId,'graffiti_repaint_started',c.characterId,nil,{graffitiId=id,victimGang=tag.gangId})
 if tag.gangId and (alertAt[id] or 0)<=os.time() then
  alertAt[id]=os.time()+(tonumber(Config.Graffiti.alertThrottleSeconds) or 60)
  for _,raw in ipairs(GetPlayers()) do local target=tonumber(raw); local m=membership(target); if m and m.member.gangId==tag.gangId then TriggerClientEvent('cm-gang:client:notify',target,('Warning: Your graffiti at %s is being repainted!'):format(tag.name),'warning') end end
 end
 return {ok=true,sessionId=sessionId,duration=tonumber(Config.Graffiti.repaintDuration) or 10000}
end)
lib.callback.register('cm-gang:server:graffitiCancel',function(src,sessionId)
 local s=sessions[tostring(sessionId or '')]; if s and s.source==tonumber(src) then cancelSession(s.id,'cancelled') end; return {ok=true}
end)
lib.callback.register('cm-gang:server:graffitiComplete',function(src,sessionId)
 local s=sessions[tostring(sessionId or '')]; if not s or s.source~=tonumber(src) or s.expiresAt<os.time() then if s then cancelSession(s.id,'expired') end return {ok=false,reason='session_expired'} end
 local c,reason=membership(src,'gang.graffiti'); if not c or c.characterId~=s.characterId or c.member.gangId~=s.gangId then cancelSession(s.id,'membership_changed'); return {ok=false,reason=reason or 'membership_changed'} end
 local tag=tags[s.graffitiId]; local near,nearReason=closeEnough(c,tag); if not near or tag.gangId~=s.ownerAtBegin then cancelSession(s.id,'state_changed'); return {ok=false,reason=nearReason or 'graffiti_changed'} end
 local key=design(c.member.gangId); if not key then cancelSession(s.id,'design_unavailable'); return {ok=false,reason='design_unavailable'} end
 local changed=MySQL.update.await('UPDATE cm_gang_graffiti SET gang_id=?,texture_key=?,updated_by_character_id=?,updated_at=NOW() WHERE id=? AND enabled=1 AND (gang_id<=>?)',{c.member.gangId,key,c.characterId,tag.id,s.ownerAtBegin})
 if tonumber(changed)~=1 then cancelSession(s.id,'race_lost'); return {ok=false,reason='graffiti_changed'} end
 local consumed,consumeReason,gasRemaining=consumeSprayCan(c.source)
 if not consumed then
  MySQL.update.await('UPDATE cm_gang_graffiti SET gang_id=?,texture_key=?,updated_at=NOW() WHERE id=? AND gang_id=? AND texture_key=?',{s.ownerAtBegin,tag.textureKey,tag.id,c.member.gangId,key})
  cancelSession(s.id,'spray_can_missing'); return {ok=false,reason=consumeReason or 'spray_can_required'}
 end
 tag.gangId,tag.textureKey=c.member.gangId,key; cancelSession(s.id); log(c.member.gangId,'graffiti_repainted',c.characterId,nil,{graffitiId=tag.id,victimGang=s.victimGang})
 for _,raw in ipairs(GetPlayers()) do local target=tonumber(raw); if GetPlayerRoutingBucket(target)==tag.routingBucket then TriggerClientEvent('cm-gang:client:graffitiUpdated',target,tag) end end return {ok=true,tag=tag,gasRemaining=gasRemaining}
end)

local function snapshotKey(ts) return os.date('!%Y%m%d%H',ts or os.time()) end
local function createSnapshot(ts,forcedBy)
 local key=snapshotKey(ts); local counts={}; for _,g in ipairs(Config.GangIds) do counts[g]=0 end
 for _,tag in pairs(tags) do if tag.enabled and tag.gangId then counts[tag.gangId]=(counts[tag.gangId] or 0)+1 end end
 for _,gangId in ipairs(Config.GangIds) do
  local eligible=tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_gang_members WHERE gang_id=?',{gangId})) or 0
  local revenue=counts[gangId]*(tonumber(Config.Graffiti.moneyPerTag) or 500)
  local inserted=MySQL.insert.await('INSERT IGNORE INTO cm_gang_turf_snapshots(snapshot_key,gang_id,tag_count,eligible_member_count,revenue) VALUES(?,?,?,?,?)',{key,gangId,counts[gangId],eligible,revenue})
  if tonumber(inserted) and tonumber(inserted)>0 then log(gangId,'turf_snapshot_created',forcedBy,nil,{snapshotKey=key,forced=forcedBy~=nil,tagCount=counts[gangId],revenue=revenue}) end
 end
 return key
end
local function turfInfo(c)
 local row=MySQL.single.await('SELECT snapshot_key,tag_count,eligible_member_count,revenue,created_at FROM cm_gang_turf_snapshots WHERE gang_id=? ORDER BY snapshot_key DESC LIMIT 1',{c.member.gangId})
 local current=0; for _,tag in pairs(tags) do if tag.enabled and tag.gangId==c.member.gangId then current=current+1 end end
 if not row then return {currentTags=current,nextSnapshot=os.date('!%H:00',os.time()+3600)} end
 local claimed=tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_gang_turf_claims WHERE snapshot_key=? AND gang_id=? AND character_id=?',{row.snapshot_key,c.member.gangId,c.characterId})) or 0
 local amount=tonumber(row.revenue) or 0; if Config.Graffiti.payoutMode=='equal_split' then amount=math.floor(amount/math.max(1,tonumber(row.eligible_member_count) or 1)) end
 return {currentTags=current,snapshotKey=row.snapshot_key,lastSnapshotTags=tonumber(row.tag_count) or 0,revenue=amount,claimed=claimed>0,nextSnapshot=os.date('!%H:00',os.time()+3600)}
end
local function nearProfit(c)
 local row=MySQL.single.await("SELECT enabled,x,y,z,routing_bucket FROM cm_gang_facilities WHERE gang_id=? AND facility_type='profit' LIMIT 1",{c.member.gangId})
 if not row or not CMGangDbTrue(row.enabled) then return false,'profit_facility_unavailable' end
 if GetPlayerRoutingBucket(c.source)~=(tonumber(row.routing_bucket) or 0) then return false,'wrong_routing_bucket' end
 local ped=GetPlayerPed(c.source); if ped==0 or not DoesEntityExist(ped) then return false,'player_entity_unavailable' end
 if #(GetEntityCoords(ped)-vector3(tonumber(row.x),tonumber(row.y),tonumber(row.z)))>(Config.Storage.facilityDistance or 3) then return false,'too_far_away' end
 return true
end
lib.callback.register('cm-gang:server:getTurfInfo',function(src) local c,r=membership(src); if not c then return {ok=false,reason=r} end return {ok=true,turf=turfInfo(c)} end)
lib.callback.register('cm-gang:server:collectTurfCut',function(src)
 local c,r=membership(src); if not c then return {ok=false,reason=r} end
 local near,nearReason=nearProfit(c); if not near then return {ok=false,reason=nearReason} end
 local info=turfInfo(c); if not info.snapshotKey then return {ok=false,reason='no_turf_snapshot'} end
 if info.claimed then return {ok=false,reason='turf_already_claimed'} end
 local inserted=MySQL.insert.await('INSERT IGNORE INTO cm_gang_turf_claims(snapshot_key,gang_id,character_id,amount) VALUES(?,?,?,?)',{info.snapshotKey,c.member.gangId,c.characterId,info.revenue})
 if not tonumber(inserted) or tonumber(inserted)<=0 then return {ok=false,reason='turf_already_claimed'} end
 local paid=Config.Graffiti.moneyType=='cash' and exports[PLAYERDATA]:AddCash(src,info.revenue,'gang_turf_cut') or false
 if paid~=true then MySQL.update.await('DELETE FROM cm_gang_turf_claims WHERE snapshot_key=? AND gang_id=? AND character_id=?',{info.snapshotKey,c.member.gangId,c.characterId}); return {ok=false,reason='payment_failed'} end
 log(c.member.gangId,'turf_cut_collected',c.characterId,nil,{snapshotKey=info.snapshotKey,amount=info.revenue}); info.claimed=true; return {ok=true,amount=info.revenue,turf=info}
end)

exports('AdminGetGraffiti',function(src) if GetInvokingResource()~='cm-admin' then return {} end return tags end)
function CMGangGraffitiAdminList() return tags end
local function adminActor(src)
 if GetInvokingResource()~='cm-admin' or exports['cm-admin']:HasPermission(src,'gang.admin.manage')~=true then return nil,'permission_denied' end
 local characterId=cid(src); local ped=GetPlayerPed(src)
 if not characterId then return nil,'character_not_loaded' end
 if ped==0 or not DoesEntityExist(ped) then return nil,'admin_entity_unavailable' end
 return {source=tonumber(src),characterId=characterId,ped=ped,bucket=GetPlayerRoutingBucket(src)}
end
exports('AdminBeginGraffitiPlacement',function(src,data)
 local actor,reason=adminActor(src); if not actor then return false,reason end
 data=type(data)=='table' and data or {}; local mode=tostring(data.mode or 'create'); local id=tonumber(data.id); local existing=id and tags[id] or nil
 if (mode=='edit' or mode=='duplicate') and not existing then return false,'graffiti_not_found' end
 local gang=Config.IsFixedGangId(data.gangId) and data.gangId or (existing and existing.gangId); if not gang then return false,'invalid_gang' end
 local name=tostring(data.name or (existing and existing.name) or ''):sub(1,96); if name=='' then return false,'invalid_name' end
 local sessionId=('admin-graffiti:%s:%d'):format(actor.characterId,math.random(100000,999999)); local editId=mode=='edit' and id or nil
 placementSessions[actor.source]={sessionId=sessionId,characterId=actor.characterId,editId=editId,gangId=gang,name=name,enabled=data.enabled~=false,expiresAt=os.time()+300,bucket=actor.bucket}
 local seed=existing and {id=existing.id,x=existing.x,y=existing.y,z=existing.z,normalX=existing.normalX,normalY=existing.normalY,normalZ=existing.normalZ,upX=existing.upX,upY=existing.upY,upZ=existing.upZ,rotation=existing.rotation,width=existing.width,height=existing.height,placementReady=existing.placementReady} or {width=math.max(.5,math.min(10,tonumber(data.width) or 2)),height=math.max(.25,math.min(6,tonumber(data.height) or 1.2)),rotation=0}
 TriggerClientEvent('cm-gang:client:adminGraffitiPlacement',actor.source,{sessionId=sessionId,mode=mode,gangId=gang,name=name,seed=seed})
 log(gang,'graffiti_admin_placement_started',actor.characterId,nil,{graffitiId=editId,mode=mode})
 return true,'Graffiti placement started.'
end)
lib.callback.register('cm-gang:server:adminGraffitiPlacementSave',function(src,data)
 local session=placementSessions[tonumber(src)]; data=type(data)=='table' and data or {}
 if not session or session.sessionId~=tostring(data.sessionId or '') or session.expiresAt<os.time() then return {ok=false,reason='placement_session_expired'} end
 local invoking='cm-admin'; local actorCid=cid(src); local ped=GetPlayerPed(src)
 local permitted=GetResourceState(invoking)=='started' and exports[invoking]:HasPermission(src,'gang.admin.manage')==true
 if not permitted or actorCid~=session.characterId or ped==0 or GetPlayerRoutingBucket(src)~=session.bucket then return {ok=false,reason='permission_or_identity_changed'} end
 local x,y,z=tonumber(data.x),tonumber(data.y),tonumber(data.z); local nx,ny,nz=tonumber(data.normalX),tonumber(data.normalY),tonumber(data.normalZ); local ux,uy,uz=tonumber(data.upX),tonumber(data.upY),tonumber(data.upZ)
 local width,height,rotation=tonumber(data.width),tonumber(data.height),tonumber(data.rotation) or 0
 if not x or not y or not z or not nx or not ny or not nz or not ux or not uy or not uz or not width or not height then return {ok=false,reason='invalid_transform'} end
 local normalLength=math.sqrt(nx*nx+ny*ny+nz*nz); local upLength=math.sqrt(ux*ux+uy*uy+uz*uz); local dot=nx*ux+ny*uy+nz*uz
 if normalLength<.98 or normalLength>1.02 or upLength<.98 or upLength>1.02 or math.abs(dot)>.03 or math.abs(nz)>.75 or width<.5 or width>10 or height<.25 or height>6 then return {ok=false,reason='invalid_wall_transform'} end
 if #(GetEntityCoords(ped)-vector3(x,y,z))>25.0 then return {ok=false,reason='placement_too_far'} end
 local key=design(session.gangId); if not key then return {ok=false,reason='design_unavailable'} end
 local id=session.editId
 if id then
  local changed=MySQL.update.await('UPDATE cm_gang_graffiti SET name=?,x=?,y=?,z=?,heading=0,normal_x=?,normal_y=?,normal_z=?,up_x=?,up_y=?,up_z=?,rotation=?,width=?,height=?,placement_ready=1,routing_bucket=?,gang_id=?,texture_key=?,enabled=?,updated_by_character_id=?,updated_at=NOW() WHERE id=?',{session.name,x,y,z,nx,ny,nz,ux,uy,uz,rotation,width,height,session.bucket,session.gangId,key,session.enabled and 1 or 0,session.characterId,id})
  if tonumber(changed)~=1 then return {ok=false,reason='graffiti_not_found'} end
 else
  id=MySQL.insert.await('INSERT INTO cm_gang_graffiti(name,x,y,z,heading,normal_x,normal_y,normal_z,up_x,up_y,up_z,rotation,width,height,placement_ready,routing_bucket,gang_id,texture_key,enabled,updated_by_character_id,updated_at) VALUES(?,?,?,?,0,?,?,?,?,?,?,?,?,?,1,?,?,?,?,?,NOW())',{session.name,x,y,z,nx,ny,nz,ux,uy,uz,rotation,width,height,session.bucket,session.gangId,key,session.enabled and 1 or 0,session.characterId})
  if not tonumber(id) or tonumber(id)<=0 then return {ok=false,reason='database_insert_failed'} end
 end
 local row=MySQL.single.await('SELECT * FROM cm_gang_graffiti WHERE id=?',{id}); if not row then return {ok=false,reason='database_readback_failed'} end
 local savedTag=publicTag(row); tags[tonumber(id)]=savedTag; placementSessions[tonumber(src)]=nil
 for _,raw in ipairs(GetPlayers()) do local target=tonumber(raw); if GetPlayerRoutingBucket(target)==savedTag.routingBucket then TriggerClientEvent('cm-gang:client:graffitiUpdated',target,savedTag) end end
 log(session.gangId,session.editId and 'graffiti_admin_placement_updated' or 'graffiti_admin_placement_saved',session.characterId,nil,{graffitiId=tonumber(id),x=x,y=y,z=z,width=width,height=height,rotation=rotation})
 return {ok=true,id=tonumber(id),tag=savedTag}
end)
RegisterNetEvent('cm-gang:server:adminGraffitiPlacementCancel',function(sessionId)
 local src=source; local session=placementSessions[src]; if not session or session.sessionId~=tostring(sessionId or '') then return end
 placementSessions[src]=nil; log(session.gangId,'graffiti_admin_placement_cancelled',session.characterId,nil,{graffitiId=session.editId})
end)
exports('AdminSaveGraffiti',function(src,data)
 if GetInvokingResource()~='cm-admin' or exports['cm-admin']:HasPermission(src,'gang.admin.manage')~=true then return false,'permission_denied' end
 data=type(data)=='table' and data or {}; local ped=GetPlayerPed(src); if ped==0 then return false,'admin_entity_unavailable' end
 local id=tonumber(data.id); if data.remove==true and id then local old=tags[id]; if not old then return false,'graffiti_not_found' end MySQL.update.await('DELETE FROM cm_gang_graffiti WHERE id=?',{id}); tags[id]=nil; TriggerClientEvent('cm-gang:client:graffitiRemoved',-1,id); log(old.gangId or Config.GangIds[1],'graffiti_admin_deleted',cid(src),nil,{graffitiId=id}); return true,'Graffiti location removed.' end
 if not id or not tags[id] then return false,'use_graffiti_placement' end
 local name=tostring(data.name or ''):sub(1,96); if name=='' then return false,'invalid_name' end; local gang=Config.IsFixedGangId(data.gangId) and data.gangId or nil
 MySQL.update.await('UPDATE cm_gang_graffiti SET name=?,gang_id=?,texture_key=?,enabled=?,updated_by_character_id=?,updated_at=NOW() WHERE id=?',{name,gang,gang and design(gang) or nil,data.enabled~=false and 1 or 0,cid(src),id})
 local row=MySQL.single.await('SELECT * FROM cm_gang_graffiti WHERE id=?',{id}); tags[id]=publicTag(row); TriggerClientEvent('cm-gang:client:graffitiRefresh',-1); return true,'Graffiti location saved.'
end)
exports('AdminForceTurfSnapshot',function(src) if GetInvokingResource()~='cm-admin' or exports['cm-admin']:HasPermission(src,'gang.admin.manage')~=true then return false,'permission_denied' end return true,('Snapshot %s created.'):format(createSnapshot(os.time(),cid(src))) end)

CreateThread(function() while not CMGangDatabaseReady do Wait(500) end; loadTags(); if not available then return end while true do local now=os.time(); local nextHour=now-(now%3600)+3600; Wait(math.max(1000,(nextHour-now)*1000)); createSnapshot(nextHour) end end)
CreateThread(function() while true do Wait(1000); local now=os.time(); for id,s in pairs(sessions) do if s.expiresAt<now then cancelSession(id,'expired') end end for src,s in pairs(placementSessions) do if s.expiresAt<now or cid(src)~=s.characterId or exports['cm-admin']:HasPermission(src,'gang.admin.manage')~=true then placementSessions[src]=nil; TriggerClientEvent('cm-gang:client:adminGraffitiPlacementForceCancel',src) end end end end)
AddEventHandler('playerDropped',function() local src=source; placementSessions[src]=nil; for id,s in pairs(sessions) do if s.source==src then cancelSession(id,'disconnect') end end end)
AddEventHandler('onResourceStop',function(name) if name==RESOURCE then sessions,tagLocks,placementSessions={},{},{} end end)
