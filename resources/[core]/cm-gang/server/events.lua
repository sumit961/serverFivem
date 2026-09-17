local RESOURCE = GetCurrentResourceName()

local function characterIdForSource(source)
    local ok, value = pcall(function() return exports['cm-playerdata']:GetCharacterId(tonumber(source)) end)
    value = ok and value and tostring(value) or nil
    return value and value:match('^%d+$') and value or nil
end

local function eventApplies(event, gangId)
    if event.gangs == nil or event.gangs == 'all' then return true end
    if type(event.gangs) ~= 'table' then return false end
    for _, configuredGangId in ipairs(event.gangs) do
        if tostring(configuredGangId) == gangId then return true end
    end
    return false
end

local function scheduledOn(event, weekday)
    for _, configuredDay in ipairs(type(event.weekdays) == 'table' and event.weekdays or {}) do
        if tonumber(configuredDay) == weekday then return true end
    end
    return false
end

local function occurrenceForOffset(event, now, dayOffset)
    local current = os.date('*t', now)
    current.hour, current.min, current.sec = 12, 0, 0
    local day = os.date('*t', os.time(current) + (dayOffset * 86400))
    if not scheduledOn(event, day.wday) then return nil end
    return os.time({ year=day.year, month=day.month, day=day.day,
        hour=math.max(0,math.min(23,math.floor(tonumber(event.hour) or 0))),
        min=math.max(0,math.min(59,math.floor(tonumber(event.minute) or 0))), sec=0 })
end

local function eventWindow(event, now)
    local previous, upcoming
    for offset=-7,7 do
        local startsAt=occurrenceForOffset(event,now,offset)
        if startsAt then
            if startsAt<=now and (not previous or startsAt>previous) then previous=startsAt end
            if startsAt>now and (not upcoming or startsAt<upcoming) then upcoming=startsAt end
        end
    end
    local duration=math.max(1,math.min(1440,math.floor(tonumber(event.durationMinutes) or 60)))*60
    if previous and now<previous+duration then return previous,previous+duration,'ongoing' end
    return upcoming,upcoming and upcoming+duration or nil,'upcoming'
end

lib.callback.register('cm-gang:server:getScriptedEvents',function(source)
    local characterId=characterIdForSource(source)
    if not characterId then return {ok=false,reason='character_not_loaded'} end
    local membership=exports[RESOURCE]:GetGangForCharacter(characterId)
    if not membership or membership.enabled~=true then return {ok=false,reason='not_in_gang'} end
    local now,events=os.time(),{}
    for _,event in ipairs(Config.ScriptedEvents or {}) do
        if eventApplies(event,membership.gangId) then
            local startsAt,endsAt,status=eventWindow(event,now)
            if startsAt then events[#events+1]={id=tostring(event.id or ''),title=tostring(event.title or 'Gang Event'):sub(1,80),description=tostring(event.description or ''):sub(1,240),startsAt=startsAt,endsAt=endsAt,status=status} end
        end
    end
    table.sort(events,function(a,b) if a.status~=b.status then return a.status=='ongoing' end return a.startsAt<b.startsAt end)
    return {ok=true,serverTime=now,events=events}
end)
