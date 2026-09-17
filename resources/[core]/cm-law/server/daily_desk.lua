-- Personal work planner. The checklist remains a private reminder, while the
-- objective counters below are server verified from real activity.
local tasks = { 'equipment', 'radio', 'vehicle', 'assignment', 'records', 'custody', 'handover' }
local objectiveCatalog = {
    patrol = { label = 'Stay on duty', target = 30, unit = 'min' },
    bookings = { label = 'Complete bookings', target = 2, unit = 'booking' },
    dispatch = { label = 'Resolve dispatch calls', target = 3, unit = 'call' },
}
local function identity(src, data)
    if not LawIsReady() then return nil end
    local cid = characterIdFor(src)
    if not cid then return nil end
    local org = tostring(data.organization or '')
    if org == 'police' then
        local member = PoliceLegacyMemberFor(cid)
        if not member then return nil end
    elseif not validOrgId(org) or not memberFor(cid, org) then return nil end
    return ('daily-desk:%s:%s'):format(cid, org)
end
local function readBook(key)
    local raw = GetResourceKvpString(key)
    if not raw then return { days = {}, revision = 0 } end
    local ok, book = pcall(json.decode, raw)
    if not ok or type(book) ~= 'table' or type(book.days) ~= 'table' then return nil end
    return book
end
local function sourceKey(src)
    local member, cid = activeMemberForSource(src)
    if not member or not cid then return nil, nil, nil end
    return ('daily-desk:%s:%s'):format(cid, tostring(member.organizationId)), member, tostring(cid)
end
function LawDailyRecord(src, objective, amount)
    local definition = objectiveCatalog[tostring(objective or '')]
    local key = sourceKey(src)
    if not definition or not key then return false end
    local book = readBook(key); if not book then return false end
    local today = os.date('!%Y-%m-%d'); local day = book.days[today] or { notes = '', checked = {} }
    day.objectives = type(day.objectives) == 'table' and day.objectives or {}
    day.objectives[objective] = math.min(definition.target, math.max(0, tonumber(day.objectives[objective]) or 0) + (tonumber(amount) or 1))
    day.savedAt = os.time(); book.days[today] = day; book.revision = (tonumber(book.revision) or 0) + 1
    local cutoff = os.date('!%Y-%m-%d', os.time() - 6 * 86400)
    for date in pairs(book.days) do if date < cutoff or date > today then book.days[date] = nil end end
    SetResourceKvp(key, json.encode(book)); return true
end
local function objectiveView(book, today)
    local out, day = {}, book.days[today] or {}
    for id, definition in pairs(objectiveCatalog) do
        local weekly = 0
        for date, entry in pairs(book.days) do
            if date >= os.date('!%Y-%m-%d', os.time() - 6 * 86400) and type(entry.objectives) == 'table' then weekly = weekly + (tonumber(entry.objectives[id]) or 0) end
        end
        out[#out + 1] = { id = id, label = definition.label, target = definition.target, unit = definition.unit, today = math.min(definition.target, tonumber(day.objectives and day.objectives[id] or 0) or 0), weekly = weekly }
    end
    table.sort(out, function(a,b) return a.id < b.id end); return out
end
lib.callback.register('cm-law:server:dailyDesk', function(src, data)
    if type(data) ~= 'table' then return { ok = false, error = 'Invalid request.' } end
    if not rateLimit(src, 'dailyDesk', 250) then return { ok = false, error = 'Please wait a moment and try again.' } end
    local key = identity(src, data)
    if not key then return { ok = false, error = 'Organization membership is required.' } end
    local book = readBook(key)
    if not book then return { ok = false, error = 'Saved notes could not be read. They have not been overwritten.' } end
    local today = os.date('!%Y-%m-%d')
    if data.action == 'save' then
        if data.date ~= today then return { ok = false, error = 'A new UTC day has started. Reload the desk before saving.' } end
        if tonumber(data.revision) ~= (tonumber(book.revision) or 0) then return { ok = false, error = 'Your desk changed in another window. Reload before saving.' } end
        if type(data.notes) ~= 'string' or #data.notes > 8000 then return { ok = false, error = 'Notes are too long.' } end
        local checked = {}
        for _, id in ipairs(tasks) do checked[id] = type(data.checked) == 'table' and data.checked[id] == true end
        local existingObjectives = type(book.days[today]) == 'table' and book.days[today].objectives or {}
        book.days[today] = { notes = data.notes, checked = checked, objectives = existingObjectives, savedAt = os.time() }
        book.revision = (tonumber(book.revision) or 0) + 1
        local cutoff = os.date('!%Y-%m-%d', os.time() - 6 * 86400)
        for date in pairs(book.days) do if date < cutoff or date > today then book.days[date] = nil end end
        SetResourceKvp(key, json.encode(book))
    elseif data.action ~= 'get' then return { ok = false, error = 'Unknown desk action.' } end
    local history, cutoff = {}, os.date('!%Y-%m-%d', os.time() - 6 * 86400)
    for date, entry in pairs(book.days) do
        if date < today and date >= cutoff then history[#history + 1] = { date = date, notes = entry.notes or '', checked = entry.checked or {} } end
    end
    table.sort(history, function(a,b) return a.date > b.date end)
    return { ok = true, date = today, revision = book.revision, day = book.days[today] or { checked = {}, notes = '', objectives = {} }, objectives = objectiveView(book, today), history = history }
end)

CreateThread(function()
    while true do
        Wait(60000)
        for _, player in ipairs(GetPlayers()) do
            local src = tonumber(player); local member = activeMemberForSource(src)
            if member and member.onDuty == true and not member.suspended then LawDailyRecord(src, 'patrol', 1) end
        end
    end
end)
