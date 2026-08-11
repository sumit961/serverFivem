local RESOURCE = GetCurrentResourceName()
local STATE_FILE = 'data/state.json'

local VALID_WEATHER = {}
for _, item in ipairs(Config.Weather.AllTypes or {}) do
    VALID_WEATHER[item.value] = true
end

local function dbg(...)
    if Config.Debug then
        print(('[%s]'):format(RESOURCE), ...)
    end
end

local function clamp(n, min, max)
    n = tonumber(n) or min
    if n < min then return min end
    if n > max then return max end
    return n
end

local function upperWeather(weather)
    if type(weather) ~= 'string' then return nil end
    weather = weather:upper():gsub('%s+', '')
    if VALID_WEATHER[weather] then return weather end
    return nil
end

local function shallowCopyArray(arr)
    local out = {}
    if type(arr) ~= 'table' then return out end
    for _, v in ipairs(arr) do
        out[#out + 1] = v
    end
    return out
end

local function makeId(prefix)
    return ('%s_%d_%d'):format(prefix or 'id', os.time(), math.random(1000, 9999))
end

local function realClock()
    local t
    if Config.Time.UseServerLocalTime then
        t = os.date('*t')
    else
        t = os.date('!*t', os.time() + ((Config.Time.TimezoneOffsetMinutes or 0) * 60))
    end
    return tonumber(t.hour) or 12, tonumber(t.min) or 0
end

local function defaultState()
    local hour, minute = realClock()
    if not Config.Time.UseRealLifeTime then
        hour = Config.Time.DefaultHour or 12
        minute = Config.Time.DefaultMinute or 0
    end

    return {
        version = 1,
        serverUnix = os.time(),
        weather = {
            profile = Config.DefaultProfile or 'normal',
            forecast = {},
            current = Config.Weather.Start or 'CLEAR',
            previous = Config.Weather.Start or 'CLEAR',
            dynamic = Config.Weather.Dynamic ~= false,
            freeze = false,
            instant = Config.Weather.InstantChange == true,
            blackout = false,
            snow = false,
            durationMinutes = Config.Weather.DefaultDurationMinutes or 30,
            transitionSeconds = Config.Weather.TransitionSeconds or 20,
            nextChangeAt = os.time() + ((Config.Weather.DefaultDurationMinutes or 30) * 60)
        },
        time = {
            mode = Config.Time.UseRealLifeTime and 'realtime' or 'manual', -- realtime/manual
            freeze = false,
            speed = tonumber(Config.Time.Speed) or 1,
            hour = hour,
            minute = minute,
            baseUnix = os.time()
        },
        schedule = {
            active = false,
            items = {},
            index = 1,
            nextChangeAt = 0,
            activeEvent = nil
        },
        zones = {
            enabled = Config.Zones.Enabled ~= false,
            items = {}
        },
        history = {
            items = {},
            max = 20
        },
        runtime = {
            paused = false
        }
    }
end

local state = defaultState()
local playerPaused = {}
local playerZones = {}
local lastStateSendAt = {}
local lastPreSpawnRequestAt = {}

local function sanitizeWeatherPool(pool, fallback)
    local cleaned = {}
    if type(pool) == 'table' then
        for _, w in ipairs(pool) do
            local nw = upperWeather(w)
            if nw then cleaned[#cleaned + 1] = nw end
        end
    end
    if #cleaned == 0 and type(fallback) == 'table' then
        for _, w in ipairs(fallback) do
            local nw = upperWeather(w)
            if nw then cleaned[#cleaned + 1] = nw end
        end
    end
    if #cleaned == 0 then cleaned = { Config.Weather.Start or 'CLEAR' } end
    return cleaned
end

local function sanitizeState(raw)
    local base = defaultState()
    if type(raw) ~= 'table' then return base end

    if type(raw.weather) == 'table' then
        base.weather.current = upperWeather(raw.weather.current) or base.weather.current
        base.weather.previous = upperWeather(raw.weather.previous) or base.weather.current
        base.weather.dynamic = raw.weather.dynamic == true
        if raw.weather.dynamic == nil then base.weather.dynamic = Config.Weather.Dynamic ~= false end
        base.weather.freeze = raw.weather.freeze == true
        base.weather.instant = raw.weather.instant == true
        base.weather.smooth = raw.weather.smooth ~= false
        if raw.weather.profile and Config.WeatherProfiles[tostring(raw.weather.profile)] then base.weather.profile = tostring(raw.weather.profile) end
        if type(raw.weather.forecast) == 'table' then base.weather.forecast = raw.weather.forecast end
        base.weather.blackout = raw.weather.blackout == true
        base.weather.snow = raw.weather.snow == true
        base.weather.durationMinutes = clamp(raw.weather.durationMinutes, 1, 240)
        base.weather.transitionSeconds = clamp(raw.weather.transitionSeconds, 0, 120)
        base.weather.nextChangeAt = tonumber(raw.weather.nextChangeAt) or base.weather.nextChangeAt
    end

    if type(raw.time) == 'table' then
        local mode = raw.time.mode == 'manual' and 'manual' or 'realtime'
        base.time.mode = mode
        base.time.freeze = raw.time.freeze == true
        base.time.hour = clamp(raw.time.hour, 0, 23)
        base.time.minute = clamp(raw.time.minute, 0, 59)
        base.time.speed = clamp(raw.time.speed or base.time.speed, 0.1, 60)
        base.time.baseUnix = tonumber(raw.time.baseUnix) or os.time()
    end

    if type(raw.schedule) == 'table' then
        base.schedule.active = raw.schedule.active == true
        base.schedule.index = clamp(raw.schedule.index, 1, 999)
        base.schedule.nextChangeAt = tonumber(raw.schedule.nextChangeAt) or 0
        base.schedule.items = {}
        if type(raw.schedule.items) == 'table' then
            for _, item in ipairs(raw.schedule.items) do
                local weather = upperWeather(item.weather)
                if weather then
                    local mode = tostring(item.mode or item.type or 'sequence')
                    if mode ~= 'sequence' and mode ~= 'delay' and mode ~= 'time' then mode = 'sequence' end
                    base.schedule.items[#base.schedule.items + 1] = {
                        id = tostring(item.id or makeId('sched')),
                        label = tostring(item.label or ''),
                        mode = mode,
                        weather = weather,
                        durationMinutes = clamp(item.durationMinutes or item.duration, 1, 1440),
                        delayMinutes = clamp(item.delayMinutes, 1, 1440),
                        startAt = tonumber(item.startAt) or 0,
                        startMinutes = clamp(item.startMinutes or item.startTimeMinutes, 0, 1439),
                        repeatDaily = item.repeatDaily == true,
                        fired = item.fired == true,
                        lastRunDate = tostring(item.lastRunDate or '')
                    }
                end
            end
        end
    end

    if type(raw.zones) == 'table' then
        base.zones.enabled = raw.zones.enabled ~= false
        base.zones.items = {}
        if type(raw.zones.items) == 'table' then
            for _, zone in ipairs(raw.zones.items) do
                local id = tostring(zone.id or makeId('zone'))
                local currentWeather = upperWeather(zone.currentWeather or zone.weather) or base.weather.current
                local pool = sanitizeWeatherPool(zone.pool or zone.weatherPool, Config.Weather.DynamicPool)
                base.zones.items[#base.zones.items + 1] = {
                    id = id,
                    name = tostring(zone.name or id),
                    enabled = zone.enabled ~= false,
                    x = tonumber(zone.x) or 0.0,
                    y = tonumber(zone.y) or 0.0,
                    z = tonumber(zone.z) or 0.0,
                    radius = clamp(zone.radius, 10.0, Config.Zones.MaxRadius or 5000.0),
                    mode = (zone.mode == 'dynamic' or zone.mode == 'mix') and zone.mode or 'static',
                    weather = upperWeather(zone.weather) or currentWeather,
                    currentWeather = currentWeather,
                    pool = pool,
                    durationMinutes = clamp(zone.durationMinutes or Config.Zones.DynamicDurationMinutes, 1, 240),
                    nextChangeAt = tonumber(zone.nextChangeAt) or (os.time() + ((Config.Zones.DynamicDurationMinutes or 20) * 60)),
                    priority = tonumber(zone.priority) or 0
                }
            end
        end
    end

    if type(raw.history) == 'table' then
        base.history = { items = {}, max = clamp(raw.history.max or 20, 1, 50) }
        if type(raw.history.items) == 'table' then
            for i, item in ipairs(raw.history.items) do
                if i > base.history.max then break end
                if type(item) == 'table' then
                    base.history.items[#base.history.items + 1] = {
                        id = tostring(item.id or makeId('hist')),
                        action = tostring(item.action or 'unknown'),
                        admin = tostring(item.admin or 'unknown'),
                        at = tonumber(item.at) or os.time(),
                        data = type(item.data) == 'table' and item.data or {},
                        before = type(item.before) == 'table' and {
                            weather = item.before.weather,
                            time = item.before.time,
                            schedule = item.before.schedule,
                            zones = item.before.zones
                        } or nil
                    }
                end
            end
        end
    end

    return base
end

-- Persist to the database (single-row key/value) instead of a JSON file, so
-- weather zones and schedules survive restarts and live in your central DB.
-- Falls back to the JSON file if oxmysql is unavailable, so nothing breaks.
local DB_READY = false

local function ensureSchema()
    if not MySQL or not MySQL.query then return end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_climatime_state (
            id TINYINT PRIMARY KEY DEFAULT 1,
            state_json LONGTEXT NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        );
    ]], {})
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cm_climatime_admin_logs (
            id INT AUTO_INCREMENT PRIMARY KEY,
            admin_identifier VARCHAR(100),
            admin_name VARCHAR(100),
            action VARCHAR(100),
            data LONGTEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    ]], {})
    DB_READY = true
end

local function logAdmin(src, action, data)
    if not Config.LogAdminActions then return end
    local name = src > 0 and GetPlayerName(src) or 'console'
    local ident = 'console'
    if src > 0 then
        for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
            if id:find('^license:') then ident = id break end
        end
    end
    if DB_READY and MySQL and MySQL.insert then
        MySQL.insert('INSERT INTO cm_climatime_admin_logs (admin_identifier, admin_name, action, data) VALUES (?, ?, ?, ?)',
            { ident, name, tostring(action), json.encode(data or {}) })
    end
    -- Also feed the cm-admin unified log if present.
    TriggerEvent('cm-admin:server:actionLogged', src, 'climatime_' .. tostring(action), data)
end

local function saveState()
    state.serverUnix = os.time()
    local encoded = json.encode(state)
    if DB_READY and MySQL and MySQL.prepare then
        MySQL.prepare.await(
            'INSERT INTO cm_climatime_state (id, state_json) VALUES (1, ?) ON DUPLICATE KEY UPDATE state_json = ?',
            { encoded, encoded }
        )
    else
        SaveResourceFile(RESOURCE, STATE_FILE, encoded, -1)
    end
end

local function loadState()
    -- Prefer DB; migrate an existing JSON file into the DB on first run.
    if DB_READY and MySQL and MySQL.scalar then
        local raw = MySQL.scalar.await('SELECT state_json FROM cm_climatime_state WHERE id = 1', {})
        if raw and raw ~= '' then
            local ok, decoded = pcall(json.decode, raw)
            if ok and type(decoded) == 'table' then
                state = sanitizeState(decoded)
                dbg('Loaded state from DB')
                return
            end
        end
    end

    local rawFile = LoadResourceFile(RESOURCE, STATE_FILE)
    if rawFile and rawFile ~= '' then
        local ok, decoded = pcall(json.decode, rawFile)
        if ok and type(decoded) == 'table' then
            state = sanitizeState(decoded)
            dbg('Loaded state from JSON file (migrating to DB)')
            saveState()
            return
        end
    end

    state = defaultState()
    saveState()
end

local function getCurrentTimeForState()
    if state.time.mode == 'realtime' then
        return realClock()
    end

    -- Manual mode: compute the display time WITHOUT mutating the stored base,
    -- otherwise elapsed minutes get double-counted on every read (drift bug).
    local baseMinutes = ((tonumber(state.time.hour) or 0) * 60) + (tonumber(state.time.minute) or 0)
    local addMinutes = 0
    if not state.time.freeze then
        local speed = tonumber(state.time.speed) or 1
        addMinutes = math.floor(((os.time() - (tonumber(state.time.baseUnix) or os.time())) / 60) * speed)
    end

    local total = (baseMinutes + addMinutes) % 1440
    return math.floor(total / 60), total % 60
end

local zoneCounts, compactHistory

-- Periodically "bake" running manual time back into the stored base so the
-- saved value stays roughly current for restarts, without read-time drift.

local function computeTemperature(weather, hour)
    local tcfg = Config.Temperature or {}
    if tcfg.Enabled == false then return nil end
    weather = upperWeather(weather) or state.weather.current or Config.Weather.Start or 'CLEAR'
    hour = tonumber(hour) or 12
    local temp = tonumber(tcfg.BaseC) or 24
    local offsets = tcfg.WeatherOffsets or {}
    temp = temp + (tonumber(offsets[weather]) or 0)
    if hour < 6 or hour >= 21 then temp = temp + (tonumber(tcfg.NightOffsetC) or -4) end
    if hour >= 6 and hour < 10 then temp = temp + (tonumber(tcfg.MorningOffsetC) or -2) end
    return math.floor((temp * 10) + 0.5) / 10
end

local function rebaseManualTime()
    if state.time.mode == 'realtime' or state.time.freeze then return false end

    local speed = tonumber(state.time.speed) or 1
    if speed <= 0 then return false end

    local baseUnix = tonumber(state.time.baseUnix) or os.time()
    local elapsedSeconds = os.time() - baseUnix
    if elapsedSeconds <= 0 then return false end

    -- Convert only full in-game minutes. Fractional remainders remain anchored
    -- to baseUnix so slow speeds like 0.5x do not freeze and 1.5x does not
    -- drift behind client-side predictive clocks.
    local addMinutes = math.floor((elapsedSeconds / 60) * speed)
    if addMinutes <= 0 then return false end

    local baseMinutes = ((tonumber(state.time.hour) or 0) * 60) + (tonumber(state.time.minute) or 0)
    local total = (baseMinutes + addMinutes) % 1440

    state.time.hour = math.floor(total / 60)
    state.time.minute = total % 60

    local consumedSeconds = math.floor((addMinutes * 60) / speed)
    state.time.baseUnix = baseUnix + math.max(1, consumedSeconds)
    return true
end


local function compactCopy(value, depth)
    depth = (tonumber(depth) or 0) + 1
    if depth > 8 then return nil end
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do
        -- Raw history contains undo snapshots and can grow very large. Public
        -- clients/admin UI use historyPublic instead.
        if k ~= 'history' and k ~= 'before' then
            out[k] = compactCopy(v, depth)
        end
    end
    return out
end

local function publicState()
    -- Build a compact snapshot instead of returning the live `state` table.
    -- Returning the live table leaked raw history undo snapshots into every sync;
    -- after a few admin edits this could exceed 1MB and hitch the server.
    local h, m = getCurrentTimeForState()
    local now = os.time()

    if state.time.mode == 'realtime' then
        state.time.hour = h
        state.time.minute = m
    end

    return {
        version = state.version or 1,
        serverUnix = now,
        weather = compactCopy(state.weather or {}),
        time = (function()
            local out = compactCopy(state.time or {})
            out.displayHour = h
            out.displayMinute = m
            return out
        end)(),
        schedule = compactCopy(state.schedule or { active = false, items = {} }),
        zones = compactCopy(state.zones or { enabled = true, items = {} }),
        runtime = compactCopy(state.runtime or {}),
        zoneDebug = { counts = zoneCounts(), updatedAt = now },
        temperature = { c = computeTemperature(state.weather and state.weather.current or Config.Weather.Start, h), unit = 'C' },
        historyPublic = compactHistory()
    }
end

local function sendSync(target, payload)
    payload = payload or publicState()
    local encoded = json.encode(payload) or '{}'
    local bytes = #encoded
    if bytes > (Config.Sync and Config.Sync.LatentThresholdBytes or 65536) then
        -- Latent events avoid a single huge network burst if an admin has many zones.
        TriggerLatentClientEvent('cm-climatime:client:sync', target, Config.Sync and Config.Sync.LatentBps or 25000, payload)
    else
        TriggerClientEvent('cm-climatime:client:sync', target, payload)
    end
end

local function broadcast()
    sendSync(-1, publicState())
end

local function nowMs()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return math.floor(os.clock() * 1000)
end

local function sendTo(src, opts)
    opts = type(opts) == 'table' and opts or {}
    src = tonumber(src) or 0
    if src <= 0 then return false end

    local throttleMs = tonumber(opts.throttleMs) or tonumber(Config.Sync and Config.Sync.RequestThrottleMs) or 750
    if opts.force ~= true and throttleMs > 0 then
        local now = nowMs()
        if lastStateSendAt[src] and (now - lastStateSendAt[src]) < throttleMs then
            return false
        end
        lastStateSendAt[src] = now
    end

    sendSync(src, publicState())
    return true
end


local function deepCopy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepCopy(v) end
    return out
end

local function historyMeta(src, action, data, before)
    local name = src > 0 and GetPlayerName(src) or 'console'
    return {
        id = makeId('hist'),
        action = tostring(action or 'unknown'),
        admin = name or 'unknown',
        at = os.time(),
        data = data or {},
        before = before
    }
end

local function buildUndoSnapshot()
    -- Only store the parts needed for admin undo. Never store history inside
    -- history, otherwise payload size grows exponentially over time.
    return {
        weather = deepCopy(state.weather or {}),
        time = deepCopy(state.time or {}),
        schedule = deepCopy(state.schedule or {}),
        zones = deepCopy(state.zones or {})
    }
end

local function pushHistory(src, action, data)
    state.history = state.history or { items = {}, max = 20 }
    local item = historyMeta(src, action, data, buildUndoSnapshot())
    table.insert(state.history.items, 1, item)
    local max = tonumber(state.history.max) or 20
    while #state.history.items > max do table.remove(state.history.items) end
end

compactHistory = function()
    local out = {}
    if not state.history or type(state.history.items) ~= 'table' then return out end
    for _, item in ipairs(state.history.items) do
        out[#out + 1] = { id = item.id, action = item.action, admin = item.admin, at = item.at, data = item.data }
    end
    return out
end

zoneCounts = function()
    local counts = {}
    for src, info in pairs(playerZones) do
        if GetPlayerPing(src) and GetPlayerPing(src) > 0 and info and info.zoneId then
            counts[info.zoneId] = (counts[info.zoneId] or 0) + 1
        end
    end
    return counts
end

local function dayKey(now)
    return os.date('%Y-%m-%d', now or os.time())
end

local function todayAtMinutes(minutes, now)
    now = now or os.time()
    local t = os.date('*t', now)
    t.hour = math.floor((tonumber(minutes) or 0) / 60)
    t.min = (tonumber(minutes) or 0) % 60
    t.sec = 0
    return os.time(t)
end

local function computeNextDailyStart(item, now)
    now = now or os.time()
    local start = todayAtMinutes(item.startMinutes or 0, now)
    if start <= now and (item.repeatDaily == true or item.lastRunDate == dayKey(now)) then
        start = start + 86400
    end
    return start
end

local function startScheduleEvent(item, now)
    now = now or os.time()
    state.schedule.activeEvent = {
        id = item.id,
        weather = item.weather,
        startedAt = now,
        endsAt = now + ((item.durationMinutes or 30) * 60),
        restoreWeather = state.weather.current
    }
    state.weather.previous = state.weather.current
    state.weather.current = item.weather
    state.weather.nextChangeAt = state.schedule.activeEvent.endsAt
    state.schedule.nextChangeAt = state.schedule.activeEvent.endsAt
end

local function notifyAdmin(src, msg)
    TriggerClientEvent('cm-climatime:client:notify', src, msg)
end

local function hasCmAdminPermission(src, mode)
    if src == 0 then return true end
    if Config.Admin.AllowEveryone then return true end
    mode = mode or 'edit'

    local rankPerm = mode == 'view'
        and (Config.Admin.ViewRankPermission or Config.Admin.RankPermission or 'dev.climatime')
        or (Config.Admin.EditRankPermission or Config.Admin.RankPermission or 'dev.climatime')

    local ok, allowed = pcall(function()
        return exports['cm-admin']:HasPermission(src, rankPerm)
    end)
    if ok and allowed == true then return true end

    if mode == 'view' then
        if IsPlayerAceAllowed(src, Config.Admin.ViewAcePermission or 'cmclimatime.view') then return true end
        if IsPlayerAceAllowed(src, Config.Admin.EditAcePermission or Config.Admin.AcePermission or 'cmclimatime.admin') then return true end
    else
        if IsPlayerAceAllowed(src, Config.Admin.EditAcePermission or Config.Admin.AcePermission or 'cmclimatime.admin') then return true end
        if IsPlayerAceAllowed(src, Config.Admin.AcePermission or 'cmclimatime.admin') then return true end
    end

    if IsPlayerAceAllowed(src, ('command.%s'):format(Config.Admin.Command or 'climatime')) then return true end
    return false
end

local function canView(src) return hasCmAdminPermission(src, 'view') end
local function canEdit(src) return hasCmAdminPermission(src, 'edit') end
local function isAdmin(src) return canEdit(src) end

local function pickWeather(pool, avoid)
    pool = sanitizeWeatherPool(pool, Config.Weather.DynamicPool)
    if #pool == 1 then return pool[1] end

    local picked = pool[math.random(1, #pool)]
    local tries = 0
    while picked == avoid and tries < 8 do
        picked = pool[math.random(1, #pool)]
        tries = tries + 1
    end
    return picked
end

-- Weighted pick from a profile pool (a map of WEATHER = weight).
local function weightedPick(poolMap, allowed)
    local total, entries = 0, {}
    for weather, weight in pairs(poolMap or {}) do
        weather = upperWeather(weather)
        weight = tonumber(weight) or 0
        if weather and weight > 0 and (not allowed or allowed[weather]) then
            total = total + weight
            entries[#entries + 1] = { w = weather, weight = weight }
        end
    end
    if total <= 0 or #entries == 0 then return nil end
    local roll = math.random() * total
    local acc = 0
    for _, e in ipairs(entries) do
        acc = acc + e.weight
        if roll <= acc then return e.w end
    end
    return entries[#entries].w
end

-- Forecast-based next weather: pick from the active profile pool, but only
-- among weathers reachable from the current one via the transition chain.
local function pickNextForecast(current, profileKey)
    local profile = Config.WeatherProfiles[profileKey or state.weather.profile or Config.DefaultProfile]
    if not profile or not profile.pool then
        return pickWeather(Config.Weather.DynamicPool, current)
    end

    current = upperWeather(current) or 'CLEAR'
    local chain = Config.WeatherChains[current]

    if chain then
        local allowed = {}
        for _, w in ipairs(chain) do allowed[upperWeather(w)] = true end
        local picked = weightedPick(profile.pool, allowed)
        if picked then return picked end
    end

    -- Chain produced nothing in this profile: fall back to a plain weighted pick.
    return weightedPick(profile.pool, nil) or pickWeather(Config.Weather.DynamicPool, current)
end

-- Build the upcoming forecast timeline (does not change live weather).
local function buildForecast(fromWeather, count)
    local list = {}
    local cur = upperWeather(fromWeather) or 'CLEAR'
    local durationMin = state.weather.durationMinutes or Config.Weather.DefaultDurationMinutes or 30
    local etaMin = math.max(1, math.floor(((state.weather.nextChangeAt or os.time()) - os.time()) / 60))

    for i = 1, (count or Config.ForecastLength or 4) do
        local nxt = pickNextForecast(cur, state.weather.profile)
        list[#list + 1] = { weather = nxt, inMinutes = etaMin }
        cur = nxt
        etaMin = etaMin + durationMin
    end
    return list
end

local function setGlobalWeather(weather, byAdmin)
    weather = upperWeather(weather)
    if not weather then return false, 'Invalid weather type' end
    state.weather.previous = state.weather.current
    state.weather.current = weather
    state.weather.nextChangeAt = os.time() + ((state.weather.durationMinutes or Config.Weather.DefaultDurationMinutes or 30) * 60)
    state.schedule.active = false
    state.schedule.activeEvent = nil
    if byAdmin then state.weather.dynamic = false end
    state.weather.forecast = buildForecast(state.weather.current, Config.ForecastLength)
    saveState()
    broadcast()
    return true
end

local function runDynamicTick()
    local changed = false
    local now = os.time()

    if state.schedule.active and #state.schedule.items > 0 and not state.weather.freeze then
        local activeEvent = state.schedule.activeEvent
        if activeEvent and tonumber(activeEvent.endsAt) and now >= tonumber(activeEvent.endsAt) then
            state.weather.previous = state.weather.current
            state.weather.current = activeEvent.restoreWeather or state.weather.previous or Config.Weather.Start or 'CLEAR'
            state.schedule.activeEvent = nil
            changed = true
        end

        if not state.schedule.activeEvent then
            for _, item in ipairs(state.schedule.items) do
                if item.mode == 'delay' then
                    if (not item.fired) and tonumber(item.startAt) and tonumber(item.startAt) > 0 and now >= tonumber(item.startAt) then
                        item.fired = true
                        startScheduleEvent(item, now)
                        changed = true
                        break
                    end
                elseif item.mode == 'time' then
                    item.nextStartAt = tonumber(item.nextStartAt) or computeNextDailyStart(item, now)
                    if now >= item.nextStartAt and (item.repeatDaily == true or item.fired ~= true) then
                        item.fired = true
                        item.lastRunDate = dayKey(now)
                        if item.repeatDaily == true then
                            item.nextStartAt = computeNextDailyStart(item, now + 1)
                        end
                        startScheduleEvent(item, now)
                        changed = true
                        break
                    end
                end
            end
        end

        if not state.schedule.activeEvent then
            local sequence = {}
            for _, item in ipairs(state.schedule.items) do
                if (item.mode or 'sequence') == 'sequence' then sequence[#sequence + 1] = item end
            end
            if #sequence > 0 then
                if state.schedule.nextChangeAt <= 0 then
                    state.schedule.index = clamp(state.schedule.index, 1, #sequence)
                    local item = sequence[state.schedule.index]
                    state.weather.previous = state.weather.current
                    state.weather.current = item.weather
                    state.schedule.nextChangeAt = now + ((item.durationMinutes or 30) * 60)
                    changed = true
                elseif now >= state.schedule.nextChangeAt then
                    state.schedule.index = state.schedule.index + 1
                    if state.schedule.index > #sequence then state.schedule.index = 1 end
                    local item = sequence[state.schedule.index]
                    if item then
                        state.weather.previous = state.weather.current
                        state.weather.current = item.weather
                        state.schedule.nextChangeAt = now + ((item.durationMinutes or 30) * 60)
                        changed = true
                    end
                end
            end
        end
    elseif state.weather.dynamic and not state.weather.freeze then
        if now >= (state.weather.nextChangeAt or 0) then
            state.weather.previous = state.weather.current
            if (Config.DynamicMode or 'forecast') == 'forecast' then
                state.weather.current = pickNextForecast(state.weather.current, state.weather.profile)
            else
                state.weather.current = pickWeather(Config.Weather.DynamicPool, state.weather.current)
            end
            state.weather.nextChangeAt = now + ((state.weather.durationMinutes or Config.Weather.DefaultDurationMinutes or 30) * 60)
            state.weather.forecast = buildForecast(state.weather.current, Config.ForecastLength)
            changed = true
        end
    end

    if state.zones.enabled and type(state.zones.items) == 'table' then
        for _, zone in ipairs(state.zones.items) do
            if zone.enabled ~= false and (zone.mode == 'dynamic' or zone.mode == 'mix') then
                if now >= (zone.nextChangeAt or 0) then
                    zone.currentWeather = pickWeather(zone.pool, zone.currentWeather or zone.weather)
                    zone.nextChangeAt = now + ((zone.durationMinutes or Config.Zones.DynamicDurationMinutes or 20) * 60)
                    changed = true
                end
            else
                zone.currentWeather = upperWeather(zone.weather) or state.weather.current
            end
        end
    end

    if changed then
        state.weather.forecast = buildForecast(state.weather.current, Config.ForecastLength)
        saveState()
        broadcast()
    end
end

local function normalizeScheduleItems(items)
    local out = {}
    if type(items) ~= 'table' then return out end
    local now = os.time()
    for _, item in ipairs(items) do
        local weather = upperWeather(item.weather)
        if weather then
            local mode = tostring(item.mode or item.type or 'sequence')
            if mode ~= 'sequence' and mode ~= 'delay' and mode ~= 'time' then mode = 'sequence' end
            local normalized = {
                id = tostring(item.id or makeId('sched')),
                label = tostring(item.label or ''),
                mode = mode,
                weather = weather,
                durationMinutes = clamp(item.durationMinutes or item.duration, 1, 1440),
                delayMinutes = clamp(item.delayMinutes, 1, 1440),
                startMinutes = clamp(item.startMinutes or item.startTimeMinutes, 0, 1439),
                repeatDaily = item.repeatDaily == true,
                fired = item.fired == true,
                lastRunDate = tostring(item.lastRunDate or '')
            }
            if mode == 'delay' then
                normalized.startAt = now + ((normalized.delayMinutes or 1) * 60)
                normalized.fired = false
            elseif mode == 'time' then
                normalized.nextStartAt = computeNextDailyStart(normalized, now)
                normalized.fired = false
            end
            out[#out + 1] = normalized
        end
    end
    return out
end

local function normalizeZone(data)
    if type(data) ~= 'table' then return nil end
    local id = tostring(data.id or '')
    if id == '' or id == '#auto' then id = makeId('zone') end

    local mode = tostring(data.mode or 'static')
    if mode == 'alltime' then mode = 'static' end
    if mode ~= 'static' and mode ~= 'dynamic' and mode ~= 'mix' then mode = 'static' end

    local weather = upperWeather(data.weather) or state.weather.current or Config.Weather.Start
    local pool = sanitizeWeatherPool(data.pool or data.weatherPool, Config.Weather.DynamicPool)

    return {
        id = id,
        name = tostring(data.name or id),
        enabled = data.enabled ~= false,
        x = tonumber(data.x) or 0.0,
        y = tonumber(data.y) or 0.0,
        z = tonumber(data.z) or 0.0,
        radius = clamp(data.radius, 10.0, Config.Zones.MaxRadius or 5000.0),
        mode = mode,
        weather = weather,
        currentWeather = (mode == 'static') and weather or (upperWeather(data.currentWeather) or pickWeather(pool, nil)),
        pool = pool,
        durationMinutes = clamp(data.durationMinutes or Config.Zones.DynamicDurationMinutes, 1, 240),
        nextChangeAt = os.time() + (clamp(data.durationMinutes or Config.Zones.DynamicDurationMinutes, 1, 240) * 60),
        priority = tonumber(data.priority) or 0
    }
end

RegisterNetEvent('cm-climatime:server:requestState', function()
    sendTo(source)
end)

-- Compatibility aliases used by cm-characters/worldlock.
RegisterNetEvent('cm-climatime:server:requestSync', function()
    sendTo(source)
end)

RegisterNetEvent('cm-climatime:server:syncMe', function()
    sendTo(source)
end)

RegisterNetEvent('cm-climatime:server:requestPreSpawnClimate', function(payload)
    local src = source
    local cfg = Config.PreSpawnPrepare or {}
    local throttleMs = tonumber(cfg.ServerRequestThrottleMs) or 1500
    local now = nowMs()

    -- cm-spawn can ask for climate while opening the spawn page and again before
    -- final reveal. Rate-limit this server path so a bad loop cannot overflow the
    -- reliable event queue during login/spawn.
    if lastPreSpawnRequestAt[src] and (now - lastPreSpawnRequestAt[src]) < throttleMs then
        return
    end
    lastPreSpawnRequestAt[src] = now

    sendTo(src, { force = true })

    -- Disabled by default for current cm-spawn because it already triggers the
    -- local client pre-spawn event. Enabling this for old spawn resources still
    -- remains rate-limited by the guard above.
    if cfg.ServerClientPrepareNudge == true then
        TriggerClientEvent('cm-climatime:client:prepareBeforeSpawn', src, type(payload) == 'table' and payload or { reason = 'server-pre-spawn-request' })
    end
end)

RegisterNetEvent('cm-climatime:server:setPlayerPaused', function(paused, reason)
    local src = source
    playerPaused[src] = paused == true and tostring(reason or 'external') or nil
end)

RegisterNetEvent('cm-climatime:server:characterScreen', function(paused)
    local src = source
    playerPaused[src] = paused == true and 'character-screen' or nil
end)

AddEventHandler('playerDropped', function()
    playerPaused[source] = nil
    playerZones[source] = nil
    lastStateSendAt[source] = nil
    lastPreSpawnRequestAt[source] = nil
end)

local function openAdminFor(src)
    if not canView(src) then
        notifyAdmin(src, 'You are not allowed to open Climatime.')
        return
    end
    local ui = deepCopy(Config.UI or {})
    ui.Permissions = { view = true, edit = canEdit(src) }
    ui.EventPresets = Config.EventPresets or {}
    ui.WeatherProfiles = Config.WeatherProfiles or {}
    ui.Map = Config.Map or {}
    TriggerClientEvent('cm-climatime:client:openAdmin', src, publicState(), Config.Weather.AllTypes, ui)
end

RegisterNetEvent('cm-climatime:server:open', function()
    openAdminFor(source)
end)


local ApplyAdminAction

local function statusLinesFor(src)
    local h, m = getCurrentTimeForState()
    local zoneInfo = playerZones[src]
    local zoneText = zoneInfo and zoneInfo.zoneId and zoneInfo.zoneId or 'global'
    local counts = zoneCounts()
    local zonePlayers = zoneInfo and zoneInfo.zoneId and counts[zoneInfo.zoneId] or 0
    return {
        ('Climatime: %s | weather %s | time %02d:%02d'):format(state.schedule.active and 'schedule' or (state.weather.dynamic and 'dynamic' or 'manual'), state.weather.current or 'UNKNOWN', h, m),
        ('Active event: %s | next change: %s'):format(state.schedule.activeEvent and state.schedule.activeEvent.weather or 'none', tostring(state.schedule.nextChangeAt or state.weather.nextChangeAt or 0)),
        ('Your zone: %s | players inside: %s'):format(zoneText, tostring(zonePlayers)),
        ('Paused before spawn is client-side; /climatime debug toggles live local overlay.')
    }
end

RegisterNetEvent('cm-climatime:server:command', function(args)
    local src = source
    args = type(args) == 'table' and args or {}
    local sub = tostring(args[1] or ''):lower()
    if sub == 'status' then
        if not canView(src) then notifyAdmin(src, 'No permission.') return end
        TriggerClientEvent('cm-climatime:client:status', src, statusLinesFor(src))
        return
    elseif sub == 'undo' then
        if not canEdit(src) then notifyAdmin(src, 'No edit permission.') return end
        ApplyAdminAction(src, 'undo', {})
        return
    end
    openAdminFor(src)
end)

RegisterNetEvent('cm-climatime:server:zoneHeartbeat', function(zoneId, weather, info)
    local src = source
    if GetPlayerPing(src) <= 0 then return end
    playerZones[src] = {
        zoneId = zoneId and tostring(zoneId) or nil,
        weather = weather and tostring(weather) or nil,
        info = type(info) == 'table' and info or {},
        updatedAt = os.time()
    }
end)


ApplyAdminAction = function(src, action, data)
    action = tostring(action or '')
    data = type(data) == 'table' and data or {}
    logAdmin(src, action, data)

    local noHistory = { undo = true, requestHistory = true }
    if not noHistory[action] then pushHistory(src, action, data) end

    if action == 'undo' then
        local hist = state.history and state.history.items and table.remove(state.history.items, 1) or nil
        if hist and hist.before then
            state = sanitizeState(hist.before)
            state.history = state.history or { items = {}, max = 20 }
            saveState()
            broadcast()
            notifyAdmin(src, 'Climatime undo applied: ' .. tostring(hist.action))
        else
            notifyAdmin(src, 'Nothing to undo.')
        end
        return

    elseif action == 'applyPreset' then
        local key = tostring(data.preset or data.key or '')
        local preset = Config.EventPresets and Config.EventPresets[key]
        if not preset then notifyAdmin(src, 'Unknown weather preset.') return end
        if preset.profile and Config.WeatherProfiles[preset.profile] then state.weather.profile = preset.profile end
        if preset.weather then state.weather.current = upperWeather(preset.weather) or state.weather.current end
        state.weather.previous = state.weather.previous or state.weather.current
        state.weather.dynamic = false
        state.weather.freeze = false
        state.weather.blackout = preset.blackout == true
        if preset.snow ~= nil then state.weather.snow = preset.snow == true end
        state.weather.durationMinutes = clamp(preset.durationMinutes or state.weather.durationMinutes, 1, 1440)
        state.weather.transitionSeconds = clamp(preset.transitionSeconds or state.weather.transitionSeconds, 0, 300)
        state.weather.nextChangeAt = os.time() + (state.weather.durationMinutes * 60)
        state.schedule.active = false
        state.weather.forecast = buildForecast(state.weather.current, Config.ForecastLength)
        saveState()
        broadcast()
        notifyAdmin(src, preset.message or ('Preset applied: ' .. tostring(preset.label or key)))
        return

    elseif action == 'setProfile' then
        local key = tostring(data.profile or '')
        if not Config.WeatherProfiles[key] then
            notifyAdmin(src, 'Unknown weather profile.')
            return
        end
        state.weather.profile = key
        state.weather.dynamic = true
        state.weather.freeze = false
        state.schedule.active = false
        -- Immediately reforecast from the new profile.
        state.weather.forecast = buildForecast(state.weather.current, Config.ForecastLength)
        state.weather.nextChangeAt = os.time() + ((state.weather.durationMinutes or Config.Weather.DefaultDurationMinutes or 30) * 60)
        saveState()
        broadcast()
        notifyAdmin(src, ('Weather profile: %s'):format(Config.WeatherProfiles[key].label))
        return

    elseif action == 'setTimeSpeed' then
        if state.time.mode ~= 'realtime' then
            -- Rebase using the OLD speed first so the new speed applies from now,
            -- not retroactively.
            local h, m = getCurrentTimeForState()
            state.time.hour, state.time.minute = h, m
            state.time.baseUnix = os.time()
        end
        state.time.speed = math.max(0.1, math.min(60, tonumber(data.speed) or 1))
        saveState()
        broadcast()
        notifyAdmin(src, ('Time speed x%s'):format(state.time.speed))
        return

    elseif action == 'setWeather' then
        local ok, err = setGlobalWeather(data.weather, true)
        if not ok then notifyAdmin(src, err or 'Failed to set weather') return end
        notifyAdmin(src, ('Weather set to %s'):format(state.weather.current))

    elseif action == 'weatherOptions' then
        state.weather.dynamic = data.dynamic == true
        state.weather.freeze = data.freeze == true
        if data.smoothChange ~= nil then
            state.weather.smooth = data.smoothChange == true
            state.weather.instant = not state.weather.smooth
        else
            state.weather.instant = data.instant == true
            state.weather.smooth = not state.weather.instant
        end
        state.weather.blackout = data.blackout == true
        state.weather.snow = data.snow == true
        state.weather.durationMinutes = clamp(data.durationMinutes, 1, 240)
        state.weather.transitionSeconds = clamp(data.transitionSeconds, 0, 120)
        if state.weather.dynamic then state.schedule.active = false end
        saveState()
        broadcast()
        notifyAdmin(src, 'Weather settings updated')

    elseif action == 'resetWeather' then
        state.weather.current = Config.Weather.Start or 'CLEAR'
        state.weather.previous = state.weather.current
        state.weather.dynamic = Config.Weather.Dynamic ~= false
        state.weather.freeze = false
        state.weather.instant = Config.Weather.InstantChange == true
        state.weather.smooth = Config.Weather.SmoothChange ~= false
        state.weather.blackout = false
        state.weather.snow = false
        state.weather.durationMinutes = Config.Weather.DefaultDurationMinutes or 30
        state.weather.transitionSeconds = Config.Weather.TransitionSeconds or 20
        state.weather.nextChangeAt = os.time() + (state.weather.durationMinutes * 60)
        state.schedule.active = false
        state.schedule.activeEvent = nil
        state.weather.forecast = buildForecast(state.weather.current, Config.ForecastLength)
        saveState()
        broadcast()
        notifyAdmin(src, 'Weather reset')

    elseif action == 'setTime' then
        state.time.mode = 'manual'
        state.time.hour = clamp(data.hour, 0, 23)
        state.time.minute = clamp(data.minute, 0, 59)
        state.time.freeze = data.freeze == true
        state.time.baseUnix = os.time()
        saveState()
        broadcast()
        notifyAdmin(src, ('Time set to %02d:%02d'):format(state.time.hour, state.time.minute))

    elseif action == 'resetTime' then
        local h, m = realClock()
        state.time.mode = Config.Time.UseRealLifeTime and 'realtime' or 'manual'
        state.time.freeze = false
        state.time.hour = h
        state.time.minute = m
        state.time.baseUnix = os.time()
        saveState()
        broadcast()
        notifyAdmin(src, 'Time is following real life again')

    elseif action == 'freezeTime' then
        local h, m = getCurrentTimeForState()
        state.time.mode = 'manual'
        state.time.hour = h
        state.time.minute = m
        state.time.freeze = data.freeze == true
        state.time.baseUnix = os.time()
        saveState()
        broadcast()
        notifyAdmin(src, state.time.freeze and 'Time frozen' or 'Time unfrozen')

    elseif action == 'setSchedule' then
        state.schedule.items = normalizeScheduleItems(data.items)
        state.schedule.active = data.active == true and #state.schedule.items > 0
        state.schedule.index = clamp(data.index or 1, 1, math.max(#state.schedule.items, 1))
        state.schedule.nextChangeAt = 0
        state.schedule.activeEvent = nil
        if state.schedule.active then
            state.weather.dynamic = false
        end
        saveState()
        broadcast()
        notifyAdmin(src, 'Schedule updated')

    elseif action == 'toggleZones' then
        state.zones.enabled = data.enabled == true
        saveState()
        broadcast()
        notifyAdmin(src, state.zones.enabled and 'Weather zones enabled' or 'Weather zones disabled')

    elseif action == 'saveZone' then
        local zone = normalizeZone(data.zone or data)
        if not zone then notifyAdmin(src, 'Invalid zone data') return end

        local replaced = false
        for i, existing in ipairs(state.zones.items) do
            if existing.id == zone.id then
                state.zones.items[i] = zone
                replaced = true
                break
            end
        end
        if not replaced then state.zones.items[#state.zones.items + 1] = zone end
        saveState()
        broadcast()
        notifyAdmin(src, replaced and 'Zone updated' or 'Zone saved')

    elseif action == 'deleteZone' then
        local id = tostring(data.id or '')
        for i = #state.zones.items, 1, -1 do
            if state.zones.items[i].id == id then
                table.remove(state.zones.items, i)
            end
        end
        saveState()
        broadcast()
        notifyAdmin(src, 'Zone deleted')

    elseif action == 'importState' then
        local imported = sanitizeState(data.state)
        state = imported
        saveState()
        broadcast()
        notifyAdmin(src, 'Climatime state imported')

    else
        notifyAdmin(src, 'Unknown action: ' .. action)
    end
end

RegisterNetEvent('cm-climatime:server:adminAction', function(action, data)
    local src = source
    if not canEdit(src) then
        notifyAdmin(src, 'No edit permission.')
        return
    end
    ApplyAdminAction(src, action, data)
end)

RegisterCommand(Config.Admin.Command or 'climatime', function(src, args)
    args = args or {}
    if src == 0 then
        print('CM Climatime status: weather=' .. tostring(state.weather.current) .. ' schedule=' .. tostring(state.schedule.active))
        return
    end
    local sub = tostring(args[1] or ''):lower()
    if sub == 'status' then
        if not canView(src) then notifyAdmin(src, 'No permission.') return end
        TriggerClientEvent('cm-climatime:client:status', src, statusLinesFor(src))
    elseif sub == 'undo' then
        if not canEdit(src) then notifyAdmin(src, 'No edit permission.') return end
        ApplyAdminAction(src, 'undo', {})
    else
        openAdminFor(src)
    end
end, false)

if Config.Admin.CommandAlias and Config.Admin.CommandAlias ~= '' then
    RegisterCommand(Config.Admin.CommandAlias, function(src, args)
        if src == 0 then return end
        args = args or {}
        local sub = tostring(args[1] or ''):lower()
        if sub == 'status' then
            if not canView(src) then notifyAdmin(src, 'No permission.') return end
            TriggerClientEvent('cm-climatime:client:status', src, statusLinesFor(src))
        elseif sub == 'undo' then
            if not canEdit(src) then notifyAdmin(src, 'No edit permission.') return end
            ApplyAdminAction(src, 'undo', {})
        else
            openAdminFor(src)
        end
    end, false)
end

AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(5000, function()
        if GetPlayerPing(src) > 0 then sendTo(src) end
    end)
end)

-- Exports for future scripts.
exports('GetState', function()
    return publicState()
end)

exports('SetGlobalWeather', function(weather)
    return setGlobalWeather(weather, false)
end)

exports('SetManualTime', function(hour, minute, freeze)
    state.time.mode = 'manual'
    state.time.hour = clamp(hour, 0, 23)
    state.time.minute = clamp(minute, 0, 59)
    state.time.freeze = freeze == true
    state.time.baseUnix = os.time()
    saveState()
    broadcast()
    return true
end)

exports('ResetRealTime', function()
    local h, m = realClock()
    state.time.mode = 'realtime'
    state.time.freeze = false
    state.time.hour = h
    state.time.minute = m
    state.time.baseUnix = os.time()
    saveState()
    broadcast()
    return true
end)

CreateThread(function()
    math.randomseed(os.time())
    ensureSchema()
    loadState()
    -- Save once after sanitizeState() so old oversized history snapshots are
    -- compacted in DB/file and future restarts stay fast.
    pcall(saveState)
    Wait(1000)
    broadcast()

    local lastSync = 0
    local lastRebase = 0
    while true do
        Wait(1000)
        runDynamicTick()

        -- Bake running manual time into the stored base every ~60s so a restart
        -- resumes near the right time (read path stays drift-free in between).
        if os.time() - lastRebase >= 60 then
            lastRebase = os.time()
            if rebaseManualTime() then
                saveState()
            end
        end

        if os.time() - lastSync >= (Config.Time.SyncIntervalSeconds or 30) then
            lastSync = os.time()
            broadcast()
        end
    end
end)


-- ===========================================================================
-- cm-admin Developer tab integration (self-registering plugin).
-- If cm-admin is absent nothing breaks; the /climatime command still works.
-- ===========================================================================
-- Server-internal open event for the cm-admin Developer button (not client-triggerable).
AddEventHandler('cm-climatime:dev:open', function(src)
    if not isAdmin(src) then return end
    openAdminFor(src)
end)

CreateThread(function()
    -- Retry: cm-climatime may start BEFORE cm-admin in the server.cfg ensure
    -- order; bailing on the first check meant the tool never registered.
    local tries = 0
    while GetResourceState('cm-admin') ~= 'started' and tries < 24 do
        Wait(5000)
        tries = tries + 1
    end
    if GetResourceState('cm-admin') ~= 'started' then
        print('[CM-CLIMATIME] cm-admin never started; dev tool not registered (standalone /climatime still works)')
        return
    end

    local weatherOptions = {}
    for _, t in ipairs(Config.Weather.AllTypes or {}) do
        weatherOptions[#weatherOptions + 1] = t.value
    end

    pcall(function()
        exports['cm-admin']:RegisterDevTool({
            id = 'climatime',
            label = 'Climate & Time',
            category = 'World',
            icon = 'cloud',
            permission = Config.Admin.RankPermission or 'dev.climatime',
            actions = {
                { id = 'open', label = 'Open Climatime Panel', type = 'launcher', realm = 'server',
                  event = 'cm-climatime:dev:open',
                  hint = 'Opens the full weather / time / schedule / zones panel' }
            }
        })
    end)
end)

-- ===========================================================================
-- Exports for cm-hud and other resources (forecast, current weather, time).
-- ===========================================================================
exports('GetCurrentWeather', function()
    return state.weather.current
end)

exports('GetForecast', function()
    return state.weather.forecast or {}
end)

exports('GetTime', function()
    local h, m = getCurrentTimeForState()
    return { hour = h, minute = m, mode = state.time.mode, frozen = state.time.freeze == true }
end)

exports('GetActiveProfile', function()
    local key = state.weather.profile or Config.DefaultProfile
    return { key = key, label = (Config.WeatherProfiles[key] or {}).label }
end)


exports('GetForecastTimeline', function()
    return state.weather.forecast or buildForecast(state.weather.current, Config.ForecastLength)
end)

exports('GetCurrentConditions', function()
    local h, m = getCurrentTimeForState()
    return {
        weather = state.weather.current,
        previous = state.weather.previous,
        profile = state.weather.profile,
        mode = state.schedule.active and 'schedule' or (state.weather.dynamic and 'dynamic' or 'manual'),
        hour = h,
        minute = m,
        nextChangeAt = state.schedule.active and state.schedule.nextChangeAt or state.weather.nextChangeAt,
        zoneCounts = zoneCounts(),
        forecast = state.weather.forecast or {},
        temperature = computeTemperature(state.weather.current, h),
        temperatureUnit = 'C'
    }
end)

exports('ApplyPreset', function(key)
    local preset = Config.EventPresets and Config.EventPresets[tostring(key or '')]
    if not preset then return false, 'unknown preset' end
    state.weather.previous = state.weather.current
    state.weather.current = upperWeather(preset.weather) or state.weather.current
    if preset.profile and Config.WeatherProfiles[preset.profile] then state.weather.profile = preset.profile end
    state.weather.dynamic = false
    state.schedule.active = false
    state.schedule.activeEvent = nil
    state.weather.durationMinutes = clamp(preset.durationMinutes or state.weather.durationMinutes, 1, 1440)
    state.weather.transitionSeconds = clamp(preset.transitionSeconds or state.weather.transitionSeconds, 0, 300)
    state.weather.nextChangeAt = os.time() + (state.weather.durationMinutes * 60)
    state.weather.forecast = buildForecast(state.weather.current, Config.ForecastLength)
    saveState()
    broadcast()
    return true
end)
