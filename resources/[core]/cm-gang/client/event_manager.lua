local event, joined, drops, zoneBlip, radiusBlip = nil, false, {}, nil, nil
local function nui(action,data) SendNUIMessage({action=action,data=data}) end
local lastJoinMessage, lastJoinMessageAt, lastCooldownMessageAt = nil, 0, -5000
local boundaryOutside, nextJoinAttemptAt = nil, 0
local combatPairReportAt = {}
local boundarySegments,boundaryGrounded={},false
local lastVehicleMessageAt,nextLocalVehicleEject=-60000,0
local quickResultContext,resultPanelOpen,arsenalResultContext
local RESULT_UI_REASON='cm-gang-event-result'
local function setResultUiHidden(hidden)
    TriggerEvent(hidden and 'cm-hud:client:hideForUi' or 'cm-hud:client:showAfterUi',RESULT_UI_REASON)
    TriggerEvent(hidden and 'cm-chat:client:hideForUi' or 'cm-chat:client:showAfterUi',RESULT_UI_REASON)
end
local function notify(message,kind,duration)
    if lib and lib.notify then lib.notify({description=message,type=kind or 'inform',duration=duration or 5000}) end
end
local function eventPresentation()
    return Config.GangEvents.supplyWar.presentation or{}
end
local function eventNotify(payload)
    if GetResourceState('cm-hud')~='started'then return end
    payload=type(payload)=='table'and payload or{};local visual=type(payload.presentation)=='table'and payload.presentation or eventPresentation();payload.image=visual.image;payload.accent=payload.accent or'#4fd1ff';payload.presentation=nil
    pcall(function()exports['cm-hud']:ShowEventNotification(payload)end)
end
local function vehiclePolicyBlocks(config,ped)
    local policy=config and config.vehiclePolicy or{};local occupied=GetVehiclePedIsIn(ped,false)
    if occupied==0 then return policy.allowVehicles~=true and GetVehiclePedIsTryingToEnter(ped)~=0 end
    if policy.allowVehicles~=true then return true end
    local allowed=policy.allowedClasses or{};if #allowed==0 then return false end
    local class=GetVehicleClass(occupied);for _,allowedClass in ipairs(allowed)do if tonumber(allowedClass)==class then return false end end
    return true
end
local function interaction(text)
    DrawRect(.5,.86,.17,.038,4,24,32,205);DrawRect(.4145,.86,.002,.038,103,232,249,255)
    SetTextFont(4);SetTextScale(.0,.34);SetTextColour(220,250,255,255);SetTextCentre(true);SetTextOutline();BeginTextCommandDisplayText('STRING');AddTextComponentSubstringPlayerName(text);EndTextCommandDisplayText(.5,.85)
end
local function deleteDropVisual(d)
    if not d then return end
    if d.smoke then StopParticleFxLooped(d.smoke,false);d.smoke=nil end
    if d.object and DoesEntityExist(d.object)then DeleteEntity(d.object)end;d.object=nil
    if d.parachute and DoesEntityExist(d.parachute)then DeleteEntity(d.parachute)end;d.parachute=nil
end
local function clearDropVisuals()
    for _,d in pairs(drops)do deleteDropVisual(d)end
    drops={}
end
local function clearBlips()
    if zoneBlip then RemoveBlip(zoneBlip);zoneBlip=nil end;if radiusBlip then RemoveBlip(radiusBlip);radiusBlip=nil end
    clearDropVisuals();boundarySegments={};boundaryGrounded=false;wasInsideEventArea=false
end
local function buildBoundary(config,useGround)
    boundarySegments={};boundaryGrounded=useGround==true;local center=config and config.zone;local radius=tonumber(config and config.radius);if not center or not radius then return end
    local segments=math.max(32,math.min(96,math.floor(tonumber(config.worldBoundary and config.worldBoundary.segments)or 64)))
    for index=0,segments-1 do local angle=(index/segments)*math.pi*2;local x=center.x+math.cos(angle)*radius;local y=center.y+math.sin(angle)*radius;local z=center.z+.15;if useGround then local found,ground=GetGroundZFor_3dCoord(x,y,center.z+1000.0,false);if found then z=ground+.12 end end;boundarySegments[#boundarySegments+1]={x=x,y=y,z=z}end
end
local function drawBoundaryWall(height)
    if #boundarySegments<2 then return end
    height=math.max(3.0,math.min(30.0,tonumber(height)or 12.0))
    for index,bottomA in ipairs(boundarySegments)do
        local bottomB=boundarySegments[index%#boundarySegments+1]
        local topA={x=bottomA.x,y=bottomA.y,z=bottomA.z+height};local topB={x=bottomB.x,y=bottomB.y,z=bottomB.z+height}
        DrawPoly(bottomA.x,bottomA.y,bottomA.z,bottomB.x,bottomB.y,bottomB.z,topB.x,topB.y,topB.z,103,232,249,72)
        DrawPoly(bottomA.x,bottomA.y,bottomA.z,topB.x,topB.y,topB.z,topA.x,topA.y,topA.z,103,232,249,72)
        DrawPoly(topB.x,topB.y,topB.z,bottomB.x,bottomB.y,bottomB.z,bottomA.x,bottomA.y,bottomA.z,103,232,249,72)
        DrawPoly(topA.x,topA.y,topA.z,topB.x,topB.y,topB.z,bottomA.x,bottomA.y,bottomA.z,103,232,249,72)
        DrawLine(bottomA.x,bottomA.y,bottomA.z,bottomB.x,bottomB.y,bottomB.z,103,232,249,210)
        DrawLine(topA.x,topA.y,topA.z,topB.x,topB.y,topB.z,103,232,249,150)
    end
end
local function showZone(payload)
    event=payload;boundaryOutside=nil;nextJoinAttemptAt=0;local c=payload.config and payload.config.zone;if not c then return end
    buildBoundary(payload.config,false)
    clearBlips();radiusBlip=AddBlipForRadius(c.x,c.y,c.z,payload.config.radius+0.0);SetBlipColour(radiusBlip,3);SetBlipAlpha(radiusBlip,75)
    zoneBlip=AddBlipForCoord(c.x,c.y,c.z);SetBlipSprite(zoneBlip,84);SetBlipColour(zoneBlip,3);SetBlipRoute(zoneBlip,true);BeginTextCommandSetBlipName('STRING');AddTextComponentString(payload.config.name or 'Gang Supply War');EndTextCommandSetBlipName(zoneBlip)
end
RegisterNetEvent('cm-gang:client:eventAnnounced',showZone)
RegisterNetEvent('cm-gang:client:eventLive',function(payload)
    payload.live=true;showZone(payload)
end)
RegisterNetEvent('cm-gang:client:eventJoined',function(payload)
    if not zoneBlip then showZone(payload)end;event=payload;event.live=true;joined=true;boundaryOutside=false;lastJoinMessage=nil;nui('gangEventJoined',payload);eventNotify({id=payload.eventId,notificationKey=payload.eventId..':joined',eyebrow='SUPPLY WAR',title='EVENT JOINED',subtitle='Live event HUD is now active.',startsAt=0,duration=5000})
end)

RegisterNetEvent('cm-gang:client:supplyWarResultAvailable',function(data)
    if type(data)~='table'or not data.eventId or tonumber(data.availableUntil or 0)<=os.time()then return end
    quickResultContext={eventId=tostring(data.eventId),availableUntil=tonumber(data.availableUntil)}
    local remaining=math.max(3000,math.min(60000,(quickResultContext.availableUntil-os.time())*1000))
    eventNotify({id='supplywar-result:'..quickResultContext.eventId,notificationKey='supplywar-result:'..quickResultContext.eventId,eyebrow='SUPPLY WAR COMPLETE',title='RESULT IS AVAILABLE',subtitle='Available for 1 minute',startsAt=0,duration=remaining,primaryKey='J',primaryText='VIEW RESULT'})
    SetTimeout(math.max(0,(quickResultContext.availableUntil-os.time())*1000),function()if quickResultContext and quickResultContext.eventId==tostring(data.eventId)then quickResultContext=nil end end)
end)
RegisterNetEvent('cm-gang:client:arsenalResupplyResultAvailable',function(data)
    if type(data)~='table' or not data.eventId then return end
    arsenalResultContext={eventId=tostring(data.eventId),availableUntil=tonumber(data.availableUntil) or os.time()+60}
    local remaining=math.max(3000,math.min(60000,(arsenalResultContext.availableUntil-os.time())*1000))
    eventNotify({id='arsenal-result:'..arsenalResultContext.eventId,notificationKey='arsenal-result:'..arsenalResultContext.eventId,eyebrow='ARSENAL RESUPPLY COMPLETE',title='RESULT IS AVAILABLE',subtitle='Available for 1 minute',startsAt=0,duration=remaining,primaryKey='J',primaryText='VIEW RESULT'})
end)
RegisterNetEvent('cm-gang:client:arsenalResupplyAnnounced',function(data)
    if type(data)~='table' or not data.eventId then return end
    eventNotify({id='arsenal-start:'..data.eventId,notificationKey='arsenal-start:'..data.eventId,eyebrow='ARSENAL RESUPPLY',title='MAJOR MILITARY SHIPMENT',subtitle='Intercept military cargo before Army forces secure it.',startsAt=0,duration=12000,presentation=data.presentation})
end)
RegisterNetEvent('cm-gang:client:arsenalResupplyIntel',function(data)
    if type(data)~='table' then return end
    notify(('CONVOY SIGHTING · %s'):format(tostring(data.text or'Last seen in the area.')),'inform',8000)
end)
local function tryOpenSupplyWarResult()
    if resultPanelOpen or not quickResultContext or quickResultContext.availableUntil<=os.time()then return end
    local response=lib.callback.await('cm-gang:server:getSupplyWarQuickResult',false,quickResultContext.eventId)
    if not response or response.ok~=true then quickResultContext=nil;return end
    resultPanelOpen=true;SetNuiFocus(true,true);setResultUiHidden(true);nui('gangEventQuickResult',response)
    return true
end
local function tryOpenArsenalResult()
    if resultPanelOpen or not arsenalResultContext or arsenalResultContext.availableUntil<=os.time() then return end
    local response=lib.callback.await('cm-gang:server:getArsenalResupplyQuickResult',false,arsenalResultContext.eventId)
    if not response or response.ok~=true then arsenalResultContext=nil;return end
    resultPanelOpen=true;SetNuiFocus(true,true);setResultUiHidden(true);nui('gangEventQuickResult',response);return true
end
exports('TryOpenSupplyWarResult',tryOpenSupplyWarResult)
exports('TryOpenArsenalResupplyResult',tryOpenArsenalResult)
RegisterCommand('+cm_gang_event_result',function() if not tryOpenArsenalResult() then tryOpenSupplyWarResult() end end,false)
RegisterCommand('-cm_gang_event_result',function() end,false)
RegisterKeyMapping('+cm_gang_event_result','View latest gang event result','keyboard','J')
RegisterNUICallback('closeEventResult',function(_,cb)resultPanelOpen=false;SetNuiFocus(false,false);setResultUiHidden(false);nui('gangEventQuickResultClose',{});cb({ok=true})end)
RegisterNetEvent('cm-gang:client:eventLeave',function(data)
    joined=false;boundaryOutside=nil;nextJoinAttemptAt=GetGameTimer()+5000;clearDropVisuals();nui('gangEventLeave',data)
    if data and data.reason=='left_zone' then notify('You stayed outside the event circle. Rejoin is locked for 2 minutes.','error',7000) end
end)
RegisterNetEvent('cm-gang:client:eventCooldown',function(data)
    local untilAt=type(data)=='table'and data.untilAt or data
    local remaining=math.max(1,math.ceil(tonumber(type(data)=='table'and data.remaining)or 1))
    nui('gangEventCooldown',{untilAt=untilAt})
    local tick=GetGameTimer()
    if tick-lastCooldownMessageAt>=5000 then notify(('You cannot join this event for %d more seconds.'):format(remaining),'error');lastCooldownMessageAt=tick end
end)
RegisterNetEvent('cm-gang:client:eventJoinDenied',function(data)
    local message=tostring(data and data.reason or 'You cannot join this event.')
    local tick=GetGameTimer();if message~=lastJoinMessage or tick-lastJoinMessageAt>5000 then notify(message,'error');lastJoinMessage=message;lastJoinMessageAt=tick end
end)
RegisterNetEvent('cm-gang:client:eventBoundaryWarning',function(data)
    local seconds=math.max(1,math.floor(tonumber(data and data.seconds) or 5));nui('gangEventBoundaryWarning',{seconds=seconds});notify(('Return to the event circle within %d seconds or receive a 2-minute cooldown.'):format(seconds),'warning',(seconds+1)*1000)
end)
RegisterNetEvent('cm-gang:client:eventBoundaryReturned',function() nui('gangEventBoundaryReturned',{});notify('You returned to the event circle in time.','success',3000) end)
RegisterNetEvent('cm-gang:client:eventCombatTag',function(data)
    if type(data)=='table'then nui('gangEventCombatTag',data)else nui('gangEventCombatTag',{active=tonumber(data or 0)>0,expiresAt=tonumber(data)or 0,untilAt=tonumber(data)or 0})end
end)
RegisterNetEvent('cm-gang:client:eventScores',function(data) nui('gangEventScores',data) end)
RegisterNetEvent('cm-gang:client:eventKillFeed',function(data) nui('gangEventKillFeed',data) end)
RegisterNetEvent('cm-gang:client:eventDeathFeed',function(data)nui('gangEventDeathFeed',data)end)
RegisterNetEvent('cm-gang:client:eventEnded',function()joined=false;boundaryOutside=nil;nextJoinAttemptAt=0;clearBlips();event=nil;nui('gangEventClear',{})end)
RegisterNetEvent('cm-gang:client:dropDelayed',function(data)
    notify(data and data.final and 'FINAL SUPPLY DELAYED · It will deploy when objective capacity is available.' or 'SUPPLY DROP DELAYED · Objective capacity reached.','inform',6000)
end)
local function receiveDropVisual(data)local d=drops[data.id]or{};d.data=data;d.state=data.state;d.landed=data.state~='INBOUND';drops[data.id]=d;if data.state=='INBOUND'then nui('gangDropInbound',data)end end
RegisterNetEvent('cm-gang:client:dropInbound',receiveDropVisual)
RegisterNetEvent('cm-gang:client:dropVisualSync',receiveDropVisual)
RegisterNetEvent('cm-gang:client:dropLanded',function(data)
    local d=drops[data.id]or{data=data};d.data=data;d.landed=true;d.state='AVAILABLE';if d.parachute and DoesEntityExist(d.parachute)then DeleteEntity(d.parachute)end;d.parachute=nil;drops[data.id]=d
    nui('gangDropLanded',data);if joined and(not event or not event.config or event.config.supplyNotificationEnabled~=false)then eventNotify({id=data.id,notificationKey=tostring(data.id)..':available',eyebrow='SUPPLY WAR',title=data.final and'FINAL SUPPLY DROP' or'SUPPLY DROP ACTIVE',subtitle='A crate is available inside the combat zone.',startsAt=0,duration=6000})end
end)
RegisterNetEvent('cm-gang:client:eventVehicleEject',function()
    if not joined then return end;local ped=PlayerPedId();local vehicle=GetVehiclePedIsIn(ped,false);if vehicle~=0 then TaskLeaveVehicle(ped,vehicle,16);SetTimeout(1200,function()if IsPedInAnyVehicle(ped,false)then ClearPedTasksImmediately(ped)end end)end
end)
RegisterNetEvent('cm-gang:client:dropState',function(data)local d=drops[data.id];if d then d.state=data.state;d.objective=data end end)
RegisterNetEvent('cm-gang:client:dropClaimStarted',function(data)
    nui('gangDropClaim',{active=true,seconds=data.seconds,contested=data.contested});local start=GetGameTimer();while GetGameTimer()-start<data.seconds*1000 do Wait(100);if IsEntityDead(PlayerPedId()) then TriggerServerEvent('cm-gang:server:cancelDropClaim');break end end
end)
RegisterNetEvent('cm-gang:client:dropClaimCancelled',function()
    for _,d in pairs(drops) do if d.landed then d.claimRequested=false end end
    nui('gangDropClaim',{active=false,cancelled=true})
end)
RegisterNetEvent('cm-gang:client:dropClaimed',function(data)local reward={};for _,x in ipairs(data.rewards or{})do reward[#reward+1]=('%dx %s'):format(x.quantity,x.itemId)end;nui('gangDropClaimed',data);notify(('%s SECURED SUPPLY #%d · Gang Armory: %s'):format(tostring(data.gangId):upper(),tonumber(data.number)or 0,table.concat(reward,', ')),'success',7000)end)
RegisterNetEvent('cm-gang:client:dropCleanup',function(id)
    if not id then clearDropVisuals();return end;local d=drops[id];if d then deleteDropVisual(d);drops[id]=nil end
end)
local cloudOffset=GetCloudTimeAsInt()-(GetGameTimer()/1000.0)
local function serverNow()return cloudOffset+(GetGameTimer()/1000.0)end
local function shortDuration(seconds)local total=math.max(0,math.ceil(tonumber(seconds)or 0));local minutes=math.floor(total/60);local remainder=total%60;return minutes>0 and('%dm %02ds'):format(minutes,remainder)or('%ds'):format(remainder)end
local function loadModel(model)
    local hash=type(model)=='number'and model or joaat(model);if not IsModelInCdimage(hash)then return nil end
    RequestModel(hash);local timeout=GetGameTimer()+5000;while not HasModelLoaded(hash)and GetGameTimer()<timeout do Wait(25)end
    return HasModelLoaded(hash)and hash or nil
end
local function ensureDropObject(d)
    local location=d.data and d.data.location;if not location then return false end
    if not d.object or not DoesEntityExist(d.object)then
        local model=loadModel(Config.GangEvents.supplyWar.crateModel);if not model then return false end
        d.object=CreateObjectNoOffset(model,location.x,location.y,location.z,false,false,false);FreezeEntityPosition(d.object,true);SetEntityCollision(d.object,true,true);SetModelAsNoLongerNeeded(model)
    end
    return true
end
local function ensureParachute(d)
    if d.parachute and DoesEntityExist(d.parachute)then return true end
    local model=loadModel(Config.GangEvents.supplyWar.parachuteModel or'p_cargo_chute_s');if not model then return false end
    local location=d.data and d.data.location;if not location then return false end
    d.parachute=CreateObjectNoOffset(model,location.x,location.y,location.z,false,false,false);FreezeEntityPosition(d.parachute,true);SetEntityCollision(d.parachute,false,false);SetModelAsNoLongerNeeded(model);return true
end
local function startDropSmoke(d)
    if d.smoke or not joined then return end;local data=d.data or{};local location=data.location;if not location then return end
    local landedAt=tonumber(data.landedAt)or tonumber(data.landAt)or serverNow();local remaining=math.max(0,(tonumber(Config.GangEvents.supplyWar.smokeSeconds)or 45)-(serverNow()-landedAt));if remaining<=0 then return end
    RequestNamedPtfxAsset('core');local timeout=GetGameTimer()+3000;while not HasNamedPtfxAssetLoaded('core')and GetGameTimer()<timeout do Wait(25)end;if not HasNamedPtfxAssetLoaded('core')then return end
    UseParticleFxAssetNextCall('core');d.smoke=StartParticleFxLoopedAtCoord('exp_grd_flare',location.x,location.y,location.z+.2,0.0,0.0,0.0,1.0,false,false,false,false)
    SetTimeout(math.floor(remaining*1000),function()if d.smoke then StopParticleFxLooped(d.smoke,false);d.smoke=nil end end)
end
local function settleDropVisual(d)
    local data=d.data or{};local location=data.location;if not location then return end
    if not ensureDropObject(d)then return end
    SetEntityCoordsNoOffset(d.object,location.x,location.y,location.z,false,false,false);FreezeEntityPosition(d.object,true);SetEntityCollision(d.object,true,true);d.landed=true
    startDropSmoke(d)
end
local function updateInboundVisual(d)
    local data=d.data or{};local location=data.location;if not location or not ensureDropObject(d)then return false end
    ensureParachute(d);local spawnedAt=tonumber(data.spawnedAt)or(serverNow()-1);local landAt=math.max(spawnedAt+.1,tonumber(data.landAt)or serverNow());local progress=math.max(0.0,math.min(1.0,(serverNow()-spawnedAt)/(landAt-spawnedAt)));local z=location.z+(tonumber(data.spawnHeight)or 70.0)*(1.0-progress)
    FreezeEntityPosition(d.object,true);SetEntityCollision(d.object,false,false);SetEntityCoordsNoOffset(d.object,location.x,location.y,z,false,false,false)
    if d.parachute and DoesEntityExist(d.parachute)then SetEntityCoordsNoOffset(d.parachute,location.x,location.y,z+2.2,false,false,false)end
    return progress<1.0
end
CreateThread(function()
    while true do
        local wait=500
        if joined then
            for _,d in pairs(drops)do if d.state=='INBOUND'then if updateInboundVisual(d)then wait=0 end elseif d.state~='SECURED'then settleDropVisual(d)end end
        end
        Wait(wait)
    end
end)
CreateThread(function()
    while true do
        local wait=1000
        if event and event.config and event.config.zone then
            wait=Config.GangEvents.zonePollMs;local ped=PlayerPedId();local p=GetEntityCoords(ped);local c=event.config.zone;local dx=p.x-c.x;local dy=p.y-c.y;local distanceSquared=dx*dx+dy*dy;local radius=event.config.radius;local inside=distanceSquared<=radius*radius
            local boundary=event.config.worldBoundary or{}
            if boundary.enabled~=false and joined then
                wait=0;if not boundaryGrounded then buildBoundary(event.config,true)end
                drawBoundaryWall(boundary.height)
            end
            local tick=GetGameTimer()
            -- New joins are deliberately limited to the outer entry ring. This
            -- does not restrict active participant movement or boundary checks.
            local ringWidth=math.max(1.0,math.min(radius,tonumber(event.config.joinRing)or tonumber(Config.GangEvents.supplyWar.joinRingWidth)or 8.0));local inJoinRing=inside and distanceSquared>=(radius-ringWidth)*(radius-ringWidth)
            if inJoinRing and event.live and not joined and not IsEntityDead(ped) then
                local vehicleBlocked=vehiclePolicyBlocks(event.config,ped)
                if vehicleBlocked then if tick-lastVehicleMessageAt>=5000 then notify('SUPPLY WAR · Exit your vehicle to join.','error',5000);lastVehicleMessageAt=tick end
                else wait=0;interaction('[E]  JOIN SUPPLY WAR');if IsControlJustReleased(0,38)and tick>=nextJoinAttemptAt then nextJoinAttemptAt=tick+1500;TriggerServerEvent('cm-gang:server:eventJoin')end end
            elseif joined then
                local outsideRadius=radius+3.0
                local outside=boundaryOutside==true and not inside or distanceSquared>outsideRadius*outsideRadius
                if boundaryOutside~=outside then boundaryOutside=outside;TriggerServerEvent('cm-gang:server:eventBoundary',outside) end
            end
            if joined and event.config.vehiclePolicy and vehiclePolicyBlocks(event.config,ped) then
                wait=0;DisableControlAction(0,23,true);if IsPedInAnyVehicle(ped,false)and tick>=nextLocalVehicleEject then nextLocalVehicleEject=tick+3000;local vehicle=GetVehiclePedIsIn(ped,false);if vehicle~=0 then TaskLeaveVehicle(ped,vehicle,16)end end
            end
            if joined and not IsEntityDead(ped) then
                for id,d in pairs(drops) do
                    if d.landed and d.data and d.data.location then
                        local location=vector3(d.data.location.x,d.data.location.y,d.data.location.z);local distance=#(p-location)
                        if distance<=2.2 and(d.state=='AVAILABLE'or d.state=='CAPTURING'or d.state=='CONTESTED')then wait=0;interaction('[E]  SECURE SUPPLY');if IsControlJustReleased(0,38)then TriggerServerEvent('cm-gang:server:beginDropClaim',id)end end
                    end
                end
            end
        end
        Wait(wait)
    end
end)
AddEventHandler('gameEventTriggered',function(name,args)
    if not joined or name~='CEventNetworkEntityDamage'then return end
    local victim,attacker=args[1],args[2]
    if attacker~=PlayerPedId()or not IsEntityAPed(victim)or not IsPedAPlayer(victim)then return end
    local player=NetworkGetPlayerIndexFromPed(victim);if player==-1 then return end
    local target=GetPlayerServerId(player);local tick=GetGameTimer();local throttle=math.max(150,tonumber(Config.GangEvents.supplyWar.combatPairThrottleMs)or 200)
    if tick-(combatPairReportAt[target]or-throttle)<throttle then return end
    combatPairReportAt[target]=tick;TriggerServerEvent('cm-gang:server:eventCombatHit',target)
end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then if resultPanelOpen then resultPanelOpen=false;setResultUiHidden(false) end;clearBlips();nui('gangEventClear',{}) end end)
