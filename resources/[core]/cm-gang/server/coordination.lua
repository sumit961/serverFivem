local RESOURCE, PLAYERDATA = GetCurrentResourceName(), 'cm-playerdata'
local meetings, tracking, cooldowns = {}, {}, {}

local function member(src, permission)
    src=tonumber(src); local ok,value=pcall(function() return exports[PLAYERDATA]:GetCharacterId(src) end)
    local characterId=ok and tostring(value or '') or ''; characterId=characterId:match('^%d+$') and characterId or nil
    if not characterId then return nil,'character_not_loaded' end
    local membership=exports[RESOURCE]:GetGangForCharacter(characterId)
    if not membership or membership.enabled~=true then return nil,'not_in_enabled_gang' end
    if permission and not exports[RESOURCE]:HasPermission(characterId,permission) then return nil,'no_permission' end
    return {source=src,characterId=characterId,membership=membership}
end

local function log(c,action,detail)
    MySQL.insert.await([[INSERT INTO cm_gang_activity(event_uid,gang_id,action,actor_character_id,detail) VALUES(?,?,?,?,?)]],{
        ('coord:%s:%d:%d'):format(action,os.time(),math.random(100000,999999)),c.membership.gangId,action,c.characterId,json.encode(detail or {})})
end

local function meeting(gangId)
    local value=meetings[gangId]
    if value and value.expiresAt<=os.time() then meetings[gangId]=nil; value=nil end
    return value and {active=true,x=value.x,y=value.y,z=value.z,expiresAt=value.expiresAt} or {active=false}
end
local function emitMeeting(gangId,value)
    for _,player in ipairs(GetPlayers()) do
        local target=member(tonumber(player))
        if target and target.membership.gangId==gangId then TriggerClientEvent('cm-gang:client:meetingChanged',target.source,gangId,value) end
    end
end

lib.callback.register('cm-gang:server:getCoordination',function(src)
    local c,reason=member(src); if not c then return {ok=false,reason=reason} end
    return {ok=true,meeting=meeting(c.membership.gangId),tracking=tracking[c.characterId]==true}
end)

lib.callback.register('cm-gang:server:setMeetingPoint',function(src,request)
    local c,reason=member(src,'gang.set_meeting_point'); if not c then return {ok=false,reason=reason} end
    if (cooldowns[c.characterId] or 0)>GetGameTimer() then return {ok=false,reason='rate_limited'} end
    cooldowns[c.characterId]=GetGameTimer()+((Config.Security.meetingCooldownSeconds or 10)*1000)
    request=type(request)=='table' and request or {}
    if request.clear==true then
        meetings[c.membership.gangId]=nil; log(c,'meeting_point_cleared',{})
        emitMeeting(c.membership.gangId,{active=false})
        return {ok=true,meeting={active=false}}
    end
    local ped=GetPlayerPed(c.source); if not ped or ped==0 or not DoesEntityExist(ped) then return {ok=false,reason='player_entity_unavailable'} end
    local coords=GetEntityCoords(ped); local value={x=coords.x,y=coords.y,z=coords.z,expiresAt=os.time()+math.max(30,tonumber(Config.Meeting.ttlSeconds) or 240)}
    meetings[c.membership.gangId]=value; log(c,'meeting_point_set',value)
    emitMeeting(c.membership.gangId,meeting(c.membership.gangId))
    return {ok=true,meeting=meeting(c.membership.gangId)}
end)

lib.callback.register('cm-gang:server:setTracking',function(src,enabled)
    local c,reason=member(src,'gang.view_map'); if not c then return {ok=false,reason=reason} end
    tracking[c.characterId]=enabled==true or nil; return {ok=true,tracking=tracking[c.characterId]==true}
end)

lib.callback.register('cm-gang:server:getTrackingSnapshot',function(src)
    local c,reason=member(src,'gang.view_map'); if not c or tracking[c.characterId]~=true then return {ok=false,reason=reason or 'tracking_disabled'} end
    local rows={}
    for _,player in ipairs(GetPlayers()) do
        local target=tonumber(player); local targetContext=member(target)
        if target~=c.source and targetContext and targetContext.membership.gangId==c.membership.gangId
            and GetPlayerRoutingBucket(target)==GetPlayerRoutingBucket(c.source) then
            local ped=GetPlayerPed(target)
            if ped and ped~=0 and DoesEntityExist(ped) then
                local coords=GetEntityCoords(ped); local okName,name=pcall(function() return exports[PLAYERDATA]:GetCharacterFullName(target) end)
                rows[#rows+1]={characterId=targetContext.characterId,name=okName and tostring(name or 'Gang member') or 'Gang member',x=coords.x,y=coords.y,z=coords.z}
            end
        end
    end
    return {ok=true,members=rows,meeting=meeting(c.membership.gangId)}
end)

AddEventHandler('playerDropped',function() local c=member(source); if c then tracking[c.characterId]=nil; cooldowns[c.characterId]=nil end end)
AddEventHandler('onResourceStop',function(name) if name==RESOURCE then meetings,tracking,cooldowns={},{},{} end end)
