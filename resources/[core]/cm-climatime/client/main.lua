local climateState = nil
local weatherTypes = Config.Weather.AllTypes or {}
local uiConfig = Config.UI or {}
local uiOpen = false
local receivedAtGameTimer = 0
local lastAppliedWeather = nil
local lastEffectiveWeather = nil
local lastWeatherNotifyAt = 0
local currentZoneId = nil
local lastZoneInfo = nil
local zoneDebugEnabled = false
local lastHeartbeatAt = 0
local getEffectiveWeather
local forceEffects


-- ==========================================================================
-- Spawn-gated activation
-- cm-climatime must NOT control time/weather while the player is still in
-- cm-auth / cm-characters / character creator. It becomes active only after
-- cm-spawn says the real character has fully spawned.
-- ==========================================================================
local climateActive = false
local activationReason = nil
local pausedReasons = {}
local pendingApplyAfterResume = false
local lastSyncRequestAt = 0
local applyCurrentClimate -- assigned after weather helpers are declared
local spawnHandoff = nil
local rainRampGeneration = 0
local weatherApplyGeneration = 0
local preSpawnPrepareGeneration = 0
local lastPreSpawnApplyAt = 0
local lastPreSpawnSignature = ''
local activeRainLevel = 0.0
local preSpawnPreparing = false
local preSpawnPreparedUntil = 0
local lastPreSpawnPayload = nil
local preSpawnZoneCoords = nil
local preSpawnZoneCoordsUntil = 0
local localStateCache = {}


local function startupCfg()
    local c = Config.Startup or {}
    return {
        startMode = tostring(c.StartMode or 'cm-spawn'),
        requireCmSpawn = c.RequireCmSpawn ~= false,
        activateIfAlreadySpawned = c.ActivateIfAlreadySpawned ~= false,
        startDelayMs = tonumber(c.StartDelayMs) or 800,
        requestDebounceMs = tonumber(c.RequestDebounceMs) or 1500,
        debugLifecycle = c.DebugLifecycle == true
    }
end

local function lifeDbg(...)
    if Config.Debug or startupCfg().debugLifecycle then
        print('[cm-climatime:lifecycle]', ...)
    end
end

local missingNativeWarnings = {}

local function callNativeIfAvailable(nativeName, ...)
    local fn = rawget(_G, nativeName)
    if type(fn) ~= 'function' then
        if Config.Debug and not missingNativeWarnings[nativeName] then
            missingNativeWarnings[nativeName] = true
            print(('[cm-climatime] native unavailable, skipped: %s'):format(nativeName))
        end
        return false
    end

    local ok, err = pcall(fn, ...)
    if not ok then
        if Config.Debug then
            print(('[cm-climatime] native failed: %s | %s'):format(nativeName, tostring(err)))
        end
        return false
    end

    return true
end

local function setWorldBlackoutSafe(enabled)
    enabled = enabled == true

    -- Some FiveM builds do not expose SetArtificialLightsState as a Lua global.
    -- Prefer it when available, otherwise fall back to SetBlackout.
    local usedArtificialLights = callNativeIfAvailable('SetArtificialLightsState', enabled)
    if not usedArtificialLights then
        callNativeIfAvailable('SetBlackout', enabled)
    end

    callNativeIfAvailable('SetArtificialLightsStateAffectsVehicles', false)
end

local function setSnowEffectsSafe(enabled)
    enabled = enabled == true
    callNativeIfAvailable('SetForceVehicleTrails', enabled)
    callNativeIfAvailable('SetForcePedFootstepsTracks', enabled)
end


local function setLocalState(key, value)
    if not (LocalPlayer and LocalPlayer.state) then return end
    if localStateCache[key] == value then return end
    localStateCache[key] = value
    LocalPlayer.state:set(key, value, true)
end

local function isPreSpawnPrepareActive()
    if preSpawnPreparing then return true end
    local st = LocalPlayer and LocalPlayer.state or nil
    return st and st.cmClimatimePreSpawnPreparing == true
end

local function wasPreSpawnRecentlyPrepared()
    return preSpawnPreparedUntil > 0 and GetGameTimer() < preSpawnPreparedUntil
end

local function hasPausedReason()
    for _, enabled in pairs(pausedReasons) do
        if enabled == true then return true end
    end
    return false
end

local function isCharacterScreenActive()
    -- During the black-screen pre-spawn prepare phase, cm-climatime is allowed
    -- to apply live time/weather even though the character resource is still
    -- finishing its selection flow. This prevents a visible change after spawn.
    if isPreSpawnPrepareActive() then return false end

    local st = LocalPlayer and LocalPlayer.state or nil
    if not st then return false end
    return st.isInCharacterSelector == true
        or st.isInCharacterCreation == true
        or st.cmCharactersWorldLocked == true
        or st.cmCharactersWorldLock == true
        or st.cmClimatimePaused == true
        or st.cmClimatimeIgnore == true
end

local function isPlayerFullySpawned()
    local st = LocalPlayer and LocalPlayer.state or nil
    if not st then return false end
    return st.characterFullySpawned == true
        or st.cmSpawned == true
        or st.isSpawned == true
end

local function shouldApplyClimate()
    if not climateActive then return false end
    if hasPausedReason() then return false end
    if isCharacterScreenActive() then return false end
    return true
end

local function requestStateNow(reason, force)
    reason = tostring(reason or 'manual')
    force = force == true
    if not force and not shouldApplyClimate() then
        pendingApplyAfterResume = true
        lifeDbg('request skipped; inactive/paused', reason)
        return false
    end

    local now = GetGameTimer()
    local debounce = startupCfg().requestDebounceMs
    if not force and (now - lastSyncRequestAt) < debounce then
        lifeDbg('request skipped; debounce', reason)
        return false
    end

    lastSyncRequestAt = now
    TriggerServerEvent('cm-climatime:server:requestState')
    return true
end

local function setClimatePaused(paused, reason)
    reason = tostring(reason or 'external')
    paused = paused == true

    if paused then
        pausedReasons[reason] = true
        pendingApplyAfterResume = true
        lifeDbg('paused by', reason)
    else
        pausedReasons[reason] = nil
        lifeDbg('unpaused by', reason)
    end

    setLocalState('cmClimatimePaused', hasPausedReason())
    setLocalState('cmClimatimeActive', climateActive == true and not hasPausedReason())

    if climateActive and not hasPausedReason() then
        SetTimeout(150, function()
            if shouldApplyClimate() then
                requestStateNow('resume:' .. reason, true)
                if applyCurrentClimate then applyCurrentClimate('resume:' .. reason) end
                pendingApplyAfterResume = false
            end
        end)
    end
end

local function activateClimate(reason)
    reason = tostring(reason or 'cm-spawn')
    local c = startupCfg()
    if c.startMode == 'disabled' then return false end
    if climateActive then
        if shouldApplyClimate() then requestStateNow('already-active:' .. reason, false) end
        return true
    end

    climateActive = true
    activationReason = reason
    pendingApplyAfterResume = true
    lastAppliedWeather = nil
    lastEffectiveWeather = nil

    setLocalState('cmClimatimeStartedAfterSpawn', true)
    setLocalState('cmClimatimeActive', true)
    lifeDbg('activated after spawn:', reason)

    SetTimeout(c.startDelayMs, function()
        if shouldApplyClimate() then
            requestStateNow('activate:' .. reason, true)
            if applyCurrentClimate then applyCurrentClimate('activate:' .. reason) end
            pendingApplyAfterResume = false
        else
            lifeDbg('activation waiting; character screen/pause still active')
        end
    end)
    return true
end

local function deactivateClimate(reason)
    reason = tostring(reason or 'external')
    climateActive = false
    activationReason = nil
    pendingApplyAfterResume = true
    setLocalState('cmClimatimeActive', false)
    lifeDbg('deactivated:', reason)
end

local function dbg(...)
    if Config.Debug then
        print('[cm-climatime]', ...)
    end
end

local function notify(msg, opts)
    msg = tostring(msg or '')
    if msg == '' then return end
    opts = type(opts) == 'table' and opts or {}

    local ncfg = Config.Notifications or {}
    local useFeed = opts.forceFeed == true or ncfg.UseGtaFeed == true
    if useFeed then
        pcall(function()
            BeginTextCommandThefeedPost('STRING')
            AddTextComponentSubstringPlayerName(msg)
            EndTextCommandThefeedPostTicker(false, false)
        end)
    end

    if uiOpen and ncfg.UiToasts ~= false and opts.silentUi ~= true then
        SendNUIMessage({ action = 'toast', message = msg })
    end
end

local function getTimeFromState()
    if not climateState or not climateState.time then
        return 12, 0
    end

    local h = tonumber(climateState.time.displayHour) or tonumber(climateState.time.hour) or 12
    local m = tonumber(climateState.time.displayMinute) or tonumber(climateState.time.minute) or 0

    if climateState.time.freeze then
        return h, m
    end

    local elapsedSeconds = math.floor((GetGameTimer() - receivedAtGameTimer) / 1000)
    local speed = tonumber(climateState.time.speed) or 1
    if speed < 0 then speed = 0 end
    local total = ((h * 60) + m + math.floor((elapsedSeconds * speed) / 60)) % 1440
    return math.floor(total / 60), total % 60
end

local function weatherLabel(weather)
    for _, item in ipairs(weatherTypes) do
        if item.value == weather then return item.label or weather end
    end
    return weather or 'Unknown'
end

local activeZoneId = nil -- the zone we are currently "inside" for hysteresis

local function getZoneDistance(zone, coords)
    local dx = coords.x - tonumber(zone.x)
    local dy = coords.y - tonumber(zone.y)
    return math.sqrt((dx * dx) + (dy * dy))
end

local function getZoneSearchCoords()
    if preSpawnZoneCoords and GetGameTimer() < preSpawnZoneCoordsUntil then
        return preSpawnZoneCoords
    end

    local ped = PlayerPedId()
    return GetEntityCoords(ped)
end

local function findCurrentZone()
    if not climateState or not climateState.zones or climateState.zones.enabled ~= true then
        activeZoneId = nil
        lastZoneInfo = nil
        return nil
    end

    local zones = climateState.zones.items or {}
    if #zones == 0 then
        activeZoneId = nil
        lastZoneInfo = nil
        return nil
    end

    local coords = getZoneSearchCoords()
    local best = nil
    local bestScore = nil
    local bestDistance = nil
    local blendCfg = Config.ZoneBlending or {}
    local blendEnabled = blendCfg.Enabled ~= false
    local edgeMult = tonumber(blendCfg.EdgeMultiplier) or tonumber(Config.ZoneExitMultiplier) or 1.15
    if edgeMult < 1.01 then edgeMult = 1.01 end

    for _, zone in ipairs(zones) do
        if zone.enabled ~= false and tonumber(zone.radius) and tonumber(zone.x) and tonumber(zone.y) then
            local r = tonumber(zone.radius) or 0.0
            local dist = getZoneDistance(zone, coords)
            local hardInside = dist <= r
            local softInside = blendEnabled and dist <= (r * edgeMult)
            local currentSoft = zone.id == activeZoneId and softInside

            if hardInside or currentSoft then
                local alpha = 1.0
                if dist > r then
                    local softWidth = math.max(1.0, (r * edgeMult) - r)
                    alpha = 1.0 - ((dist - r) / softWidth)
                    alpha = math.max(tonumber(blendCfg.MinBlendAlpha) or 0.12, math.min(1.0, alpha))
                end

                local score = ((tonumber(zone.priority) or 0) * 10000000) - dist
                -- Give the active zone a tiny bonus so it does not flicker on
                -- the border when two zones overlap with similar priority.
                if zone.id == activeZoneId then score = score + 2500 end

                if not bestScore or score > bestScore then
                    best = zone
                    bestScore = score
                    bestDistance = dist
                    best._cmBlendAlpha = alpha
                    best._cmDistance = dist
                    best._cmSoftEdge = dist > r
                end
            end
        end
    end

    activeZoneId = best and best.id or nil
    lastZoneInfo = best and {
        id = best.id,
        name = best.name,
        weather = best.currentWeather or best.weather,
        priority = best.priority or 0,
        radius = best.radius or 0,
        distance = bestDistance or best._cmDistance or 0,
        blendAlpha = best._cmBlendAlpha or 1.0,
        softEdge = best._cmSoftEdge == true
    } or nil
    return best
end

local applyingTransition = false

local function isRainWeather(weather)
    weather = tostring(weather or ''):upper()
    return weather == 'RAIN' or weather == 'THUNDER' or weather == 'CLEARING' or weather == 'HALLOWEEN'
end

local function computeLocalTemperature(weather, hour)
    local tcfg = Config.Temperature or {}
    if tcfg.Enabled == false then return nil end
    weather = tostring(weather or Config.Weather.Start or 'CLEAR'):upper()
    hour = tonumber(hour) or 12
    local temp = tonumber(tcfg.BaseC) or 24
    local offsets = tcfg.WeatherOffsets or {}
    temp = temp + (tonumber(offsets[weather]) or 0)
    if hour < 6 or hour >= 21 then temp = temp + (tonumber(tcfg.NightOffsetC) or -4) end
    if hour >= 6 and hour < 10 then temp = temp + (tonumber(tcfg.MorningOffsetC) or -2) end
    return math.floor((temp * 10) + 0.5) / 10
end

local function handoffCfg()
    local c = Config.SpawnHandoff or {}
    return {
        enabled = c.Enabled ~= false,
        fromWeather = tostring(c.FromWeather or 'CLEAR'):upper(),
        fromHour = tonumber(c.FromHour) or 23,
        fromMinute = tonumber(c.FromMinute) or 0,
        holdMs = tonumber(c.HoldMs) or 1200,
        weatherTransitionSeconds = tonumber(c.WeatherTransitionSeconds) or 32,
        timeBlendSeconds = tonumber(c.TimeBlendSeconds) or 9,
        rainRampSeconds = tonumber(c.RainRampSeconds) or tonumber(Config.WeatherEffects and Config.WeatherEffects.RainRampSeconds) or 10,
        debug = c.Debug == true
    }
end

local function handoffDebug(...)
    local c = handoffCfg()
    if c.debug or Config.Debug then
        print('[cm-climatime:handoff]', ...)
    end
end

local function smoothStep(t)
    t = math.max(0.0, math.min(1.0, tonumber(t) or 0.0))
    return t * t * (3.0 - (2.0 * t))
end

local function startSpawnHandoff(data)
    local c = handoffCfg()
    if not c.enabled then return false end
    data = type(data) == 'table' and data or {}

    spawnHandoff = {
        active = true,
        startedAt = GetGameTimer(),
        fromWeather = tostring(data.fromWeather or c.fromWeather or 'CLEAR'):upper(),
        fromHour = tonumber(data.fromHour) or c.fromHour,
        fromMinute = tonumber(data.fromMinute) or c.fromMinute,
        fromSecond = tonumber(data.fromSecond) or 0,
        holdMs = tonumber(data.holdMs) or c.holdMs,
        weatherTransitionSeconds = tonumber(data.weatherTransitionSeconds) or c.weatherTransitionSeconds,
        timeBlendSeconds = tonumber(data.timeBlendSeconds) or c.timeBlendSeconds,
        rainRampSeconds = tonumber(data.rainRampSeconds) or c.rainRampSeconds,
        weatherDone = false,
        clockDone = false,
        reason = tostring(data.reason or 'spawn-handoff')
    }

    -- Make the selector scene the known starting point for the blend.
    pcall(function() SetOverrideWeather(spawnHandoff.fromWeather) end)
    pcall(function() SetWeatherTypeNowPersist(spawnHandoff.fromWeather) end)
    pcall(function() NetworkOverrideClockTime(spawnHandoff.fromHour, spawnHandoff.fromMinute, spawnHandoff.fromSecond or 0) end)
    pcall(function() PauseClock(true) end)

    setLocalState('cmClimatimeHandoff', true)
    handoffDebug(('started from %s %02d:%02d hold=%sms weather=%ss time=%ss'):format(
        spawnHandoff.fromWeather,
        spawnHandoff.fromHour,
        spawnHandoff.fromMinute,
        spawnHandoff.holdMs,
        spawnHandoff.weatherTransitionSeconds,
        spawnHandoff.timeBlendSeconds
    ))

    if not climateActive then activateClimate('spawn-handoff') end
    if applyCurrentClimate then
        SetTimeout(math.max(50, spawnHandoff.holdMs or 0), function()
            if spawnHandoff and spawnHandoff.active and shouldApplyClimate() then
                applyCurrentClimate('spawn-handoff')
            end
        end)
    end
    return true
end

local function finishSpawnHandoffIfReady()
    if not spawnHandoff or not spawnHandoff.active then return end
    if spawnHandoff.weatherDone and spawnHandoff.clockDone then
        handoffDebug('finished')
        spawnHandoff.active = false
        setLocalState('cmClimatimeHandoff', false)
        spawnHandoff = nil
    end
end

local function getHandoffClock(targetHour, targetMinute)
    if not spawnHandoff or not spawnHandoff.active then return targetHour, targetMinute end

    local now = GetGameTimer()
    local elapsed = now - (spawnHandoff.startedAt or now)
    local holdMs = math.max(0, tonumber(spawnHandoff.holdMs) or 0)
    local blendMs = math.max(0, (tonumber(spawnHandoff.timeBlendSeconds) or 0) * 1000)

    if elapsed <= holdMs then
        return spawnHandoff.fromHour or targetHour, spawnHandoff.fromMinute or targetMinute
    end

    if blendMs <= 0 or elapsed >= (holdMs + blendMs) then
        spawnHandoff.clockDone = true
        finishSpawnHandoffIfReady()
        return targetHour, targetMinute
    end

    local t = smoothStep((elapsed - holdMs) / blendMs)
    local fromTotal = (((spawnHandoff.fromHour or targetHour) * 60) + (spawnHandoff.fromMinute or targetMinute)) % 1440
    local toTotal = ((targetHour * 60) + targetMinute) % 1440
    local diff = (toTotal - fromTotal) % 1440
    if diff > 720 then diff = diff - 1440 end
    local total = (fromTotal + (diff * t)) % 1440
    if total < 0 then total = total + 1440 end
    local h = math.floor(total / 60) % 24
    local m = math.floor(total % 60)
    return h, m
end

local function rampRainTo(targetRain, seconds)
    targetRain = tonumber(targetRain) or 0.0
    seconds = tonumber(seconds) or 0

    if seconds <= 0.05 then
        rainRampGeneration = rainRampGeneration + 1
        activeRainLevel = targetRain
        pcall(function() SetRainLevel(targetRain) end)
        pcall(function() SetRainFxIntensity(targetRain) end)
        return
    end

    rainRampGeneration = rainRampGeneration + 1
    local gen = rainRampGeneration
    local start = activeRainLevel or 0.0
    local started = GetGameTimer()
    local duration = seconds * 1000

    CreateThread(function()
        while gen == rainRampGeneration do
            local elapsed = GetGameTimer() - started
            local t = smoothStep(elapsed / duration)
            local value = start + ((targetRain - start) * t)
            activeRainLevel = value
            pcall(function() SetRainLevel(value) end)
            pcall(function() SetRainFxIntensity(value) end)
            if elapsed >= duration then break end
            Wait(350)
        end
        if gen == rainRampGeneration then
            activeRainLevel = targetRain
            pcall(function() SetRainLevel(targetRain) end)
            pcall(function() SetRainFxIntensity(targetRain) end)
        end
    end)
end

local function applyWeatherEffects(weather, rainRampSeconds)
    weather = tostring(weather or Config.Weather.Start or 'CLEAR'):upper()
    local fx = Config.WeatherEffects or {}
    local rainLevels = fx.RainLevels or {}
    local windLevels = fx.Wind or {}
    local rain = tonumber(rainLevels[weather]) or 0.0
    local wind = tonumber(windLevels[weather]) or 0.0

    -- These two natives are the important fix for "RAIN selected but no rain".
    -- SetWeatherTypeNowPersist changes sky; SetRainLevel / SetRainFxIntensity
    -- actually force the particle/rain intensity on many FiveM builds.
    rampRainTo(rain, tonumber(rainRampSeconds) or 0)
    pcall(function() SetWindSpeed(wind) end)
    if weather == 'THUNDER' then
        pcall(function() ForceLightningFlash() end)
    end
end


local function preSpawnCfg()
    local c = Config.PreSpawnPrepare or {}
    return {
        enabled = c.Enabled ~= false,
        weatherTransitionSeconds = tonumber(c.WeatherTransitionSeconds) or 1.2,
        rainRampSeconds = tonumber(c.RainRampSeconds) or 1.2,
        prepareMs = tonumber(c.PrepareMs) or 2600,
        validMs = tonumber(c.ValidMs) or 25000,
        clientThrottleMs = tonumber(c.ClientThrottleMs) or 900,
        debug = c.Debug == true
    }
end

local function preSpawnDebug(...)
    local c = preSpawnCfg()
    if c.debug or Config.Debug then
        print('[cm-climatime:pre-spawn]', ...)
    end
end

local function applyPreSpawnClimate(data)
    local c = preSpawnCfg()
    if not c.enabled then return false end
    data = type(data) == 'table' and data or {}

    -- cm-spawn may emit both applyBeforeSpawn and prepareBeforeSpawn for the
    -- same phase. Accept the first request and ignore duplicate copies for a
    -- short window to prevent reliable event/statebag pressure during spawn.
    local now = GetGameTimer()
    local signature = table.concat({
        tostring(data.reason or ''),
        tostring(data.x or ''),
        tostring(data.y or ''),
        tostring(data.z or ''),
        tostring(data.prepareMs or ''),
        tostring(data.validMs or '')
    }, '|')
    if signature == lastPreSpawnSignature and (now - lastPreSpawnApplyAt) < c.clientThrottleMs then
        preSpawnDebug('duplicate pre-spawn prepare ignored', signature)
        return true
    end
    lastPreSpawnSignature = signature
    lastPreSpawnApplyAt = now
    lastPreSpawnPayload = data
    preSpawnPrepareGeneration = preSpawnPrepareGeneration + 1
    local currentPreSpawnGen = preSpawnPrepareGeneration

    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if x and y then
        preSpawnZoneCoords = vector3(x + 0.0, y + 0.0, (z or 0.0) + 0.0)
        preSpawnZoneCoordsUntil = GetGameTimer() + (tonumber(data.validMs) or c.validMs)
    end

    preSpawnPreparing = true
    preSpawnPreparedUntil = GetGameTimer() + (tonumber(data.validMs) or c.validMs)
    setLocalState('cmClimatimePreSpawnPreparing', true)
    setLocalState('cmClimatimePreSpawnPrepared', false)

    -- Clear selector pause reasons and activate climatime before cm-spawn reveal.
    setClimatePaused(false, 'cm-characters')
    setClimatePaused(false, 'character-screen')
    setClimatePaused(false, 'cm-characters-worldlock')
    climateActive = true
    activationReason = tostring(data.reason or 'pre-spawn-prepare')
    pendingApplyAfterResume = false

    if not climateState then
        requestStateNow('pre-spawn-no-state', true)
        preSpawnDebug('no climate state yet; requested fresh state')
    end

    local weather, isZone, zone = getEffectiveWeather()
    weather = tostring(weather or Config.Weather.Start or 'CLEAR'):upper()
    local h, m = getTimeFromState()
    lastEffectiveWeather = weather
    currentZoneId = zone and zone.id or nil

    local transition = tonumber(data.weatherTransitionSeconds) or c.weatherTransitionSeconds
    local rainRamp = tonumber(data.rainRampSeconds) or c.rainRampSeconds

    spawnHandoff = nil
    applyingTransition = false
    lastAppliedWeather = weather

    ClearOverrideWeather()
    ClearWeatherTypePersist()
    pcall(function() PauseClock(false) end)
    pcall(function() NetworkClearClockTimeOverride() end)

    if transition and transition > 0.05 then
        SetWeatherTypeOvertimePersist(weather, transition + 0.0)
    else
        SetWeatherTypeNowPersist(weather)
        SetWeatherTypeNow(weather)
        SetWeatherTypePersist(weather)
    end

    -- Set the final weather too, because the player is hidden/black-screened.
    -- This is better than letting the transition finish visibly after spawn.
    SetTimeout(math.max(250, math.floor((transition or 0) * 1000)), function()
        if currentPreSpawnGen ~= preSpawnPrepareGeneration then return end
        if preSpawnPreparing or wasPreSpawnRecentlyPrepared() then
            ClearOverrideWeather()
            SetWeatherTypeNowPersist(weather)
            SetWeatherTypeNow(weather)
            SetWeatherTypePersist(weather)
            applyWeatherEffects(weather, 0)
        end
    end)

    applyWeatherEffects(weather, rainRamp)
    pcall(function() NetworkOverrideClockTime(h, m, 0) end)
    pcall(function() SetClockTime(h, m, 0) end)
    forceEffects()

    local prepareMs = tonumber(data.prepareMs) or c.prepareMs
    SetTimeout(math.max(500, prepareMs), function()
        if currentPreSpawnGen ~= preSpawnPrepareGeneration then return end
        preSpawnPreparing = false
        setLocalState('cmClimatimePreSpawnPreparing', false)
        setLocalState('cmClimatimePreSpawnPrepared', true)
        preSpawnDebug(('prepared %s %02d:%02d zone=%s'):format(weather, h, m, zone and tostring(zone.id) or 'global'))
    end)

    setLocalState('cmClimatimeStartedAfterSpawn', true)
    setLocalState('cmClimatimeActive', true)
    return true
end

local function applyWeather(weather, isZoneWeather)
    if not weather or weather == '' then return end
    weather = tostring(weather):upper()
    if weather == lastAppliedWeather and not (spawnHandoff and spawnHandoff.active) then
        applyWeatherEffects(weather)
        return
    end

    local transition = Config.Weather.TransitionSeconds or 20
    local instant = false
    if climateState and climateState.weather then
        instant = climateState.weather.instant == true
        if isZoneWeather then
            local zoneSoft = lastZoneInfo and lastZoneInfo.softEdge == true
            if zoneSoft and Config.ZoneBlending and Config.ZoneBlending.Enabled ~= false then
                transition = tonumber(Config.ZoneBlending.SoftTransitionSeconds) or tonumber(Config.Zones.TransitionSeconds) or 15
            else
                transition = tonumber(Config.Zones.TransitionSeconds) or 10
            end
        else
            transition = tonumber(climateState.weather.transitionSeconds) or transition
        end
    end

    local handoff = spawnHandoff and spawnHandoff.active and spawnHandoff or nil
    local rainRampSeconds = 0
    if handoff then
        instant = false
        transition = tonumber(handoff.weatherTransitionSeconds) or transition
        rainRampSeconds = tonumber(handoff.rainRampSeconds) or tonumber(Config.WeatherEffects and Config.WeatherEffects.RainRampSeconds) or 0
    elseif Config.WeatherEffects and Config.WeatherEffects.SmoothDefault == true and not instant then
        rainRampSeconds = tonumber(Config.WeatherEffects.RainRampSeconds) or 0
    end

    transition = tonumber(transition) or 0
    lastAppliedWeather = weather
    applyingTransition = true

    -- Generation guard: older weather transition threads must never finalize
    -- stale weather after a newer global/zone/admin weather request starts.
    weatherApplyGeneration = weatherApplyGeneration + 1
    local currentGen = weatherApplyGeneration

    CreateThread(function()
        -- During spawn handoff, keep the character selector scene as the visual
        -- starting point for one moment, then let GTA blend into the live climate.
        if handoff then
            pcall(function() SetWeatherTypeNowPersist(handoff.fromWeather or 'CLEAR') end)
            if (tonumber(handoff.holdMs) or 0) > 0 then Wait(tonumber(handoff.holdMs) or 0) end
        end

        if currentGen ~= weatherApplyGeneration then return end

        ClearOverrideWeather()
        ClearWeatherTypePersist()

        if instant or transition <= 0 then
            SetWeatherTypeNowPersist(weather)
            SetWeatherTypeNow(weather)
            SetWeatherTypePersist(weather)
            applyWeatherEffects(weather, rainRampSeconds)

            if currentGen == weatherApplyGeneration then
                applyingTransition = false
            end
        else
            SetWeatherTypeOvertimePersist(weather, transition + 0.0)
            -- Start rain effects early so RAIN/THUNDER visibly works during the transition.
            applyWeatherEffects(weather, rainRampSeconds)

            Wait((transition * 1000) + 500)

            if currentGen == weatherApplyGeneration then
                SetWeatherTypeNowPersist(weather)
                SetWeatherTypeNow(weather)
                SetWeatherTypePersist(weather)
                applyWeatherEffects(weather, 0)
                applyingTransition = false
            end
        end

        if currentGen == weatherApplyGeneration and handoff and spawnHandoff == handoff then
            handoff.weatherDone = true
            finishSpawnHandoffIfReady()
        end
    end)

    local ncfg = Config.Notifications or {}
    if Config.Weather.NotifyPlayers == true and ncfg.WeatherChangeToasts == true and GetGameTimer() - lastWeatherNotifyAt > 10000 then
        lastWeatherNotifyAt = GetGameTimer()
        if isZoneWeather then
            notify(('Local Weather: %s'):format(weatherLabel(weather)), { silentUi = false })
        else
            notify(('Weather Forecast: %s'):format(weatherLabel(weather)), { silentUi = false })
        end
    end
end

forceEffects = function()
    if not climateState or not climateState.weather then return end
    local blackout = climateState.weather.blackout == true
    local snow = climateState.weather.snow == true
    local weather = lastEffectiveWeather or (climateState.weather and climateState.weather.current) or Config.Weather.Start or 'CLEAR'
    local gameplay = Config.GameplayEffects or {}

    setWorldBlackoutSafe(blackout)
    setSnowEffectsSafe(snow)

    if gameplay.Enabled ~= false then
        if gameplay.WetRoads ~= false then
            applyWeatherEffects(weather)
        end

        if gameplay.StormTraction ~= false then
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                local reduce = weather == 'RAIN' or weather == 'THUNDER' or weather == 'BLIZZARD'
                pcall(function() SetVehicleReduceGrip(veh, reduce) end)
            end
        end

        if gameplay.FogTimecycle == true then
            if weather == 'FOGGY' or weather == 'HALLOWEEN' then
                pcall(function() SetTimecycleModifier('foggy') end)
                pcall(function() SetTimecycleModifierStrength(0.35) end)
            else
                pcall(function() ClearTimecycleModifier() end)
            end
        end
    end
end

getEffectiveWeather = function()
    if not climateState or not climateState.weather then return Config.Weather.Start or 'CLEAR', false, nil end
    local globalWeather = climateState.weather.current or Config.Weather.Start or 'CLEAR'
    local zone = findCurrentZone()
    if zone then
        local zoneWeather = zone.currentWeather or zone.weather or globalWeather
        return zoneWeather, true, zone
    end
    return globalWeather, false, nil
end

applyCurrentClimate = function(reason)
    if not climateState then return false end
    if not shouldApplyClimate() then
        pendingApplyAfterResume = true
        return false
    end

    local weather, isZone, zone = getEffectiveWeather()
    currentZoneId = zone and zone.id or nil
    lastEffectiveWeather = weather
    applyWeather(weather, isZone)
    forceEffects()
    return true
end

RegisterNetEvent('cm-climatime:client:sync', function(newState)
    climateState = newState
    receivedAtGameTimer = GetGameTimer()

    if uiOpen then
        SendNUIMessage({ action = 'state', state = climateState, weatherTypes = weatherTypes, ui = uiConfig })
    end

    -- If cm-spawn/characters asked for climate while the screen is still hidden,
    -- apply this fresh server state immediately so the spawn page and reveal
    -- already have the correct weather/time before Last Location/Hotel is clicked.
    if isPreSpawnPrepareActive() or wasPreSpawnRecentlyPrepared() then
        applyPreSpawnClimate(lastPreSpawnPayload or { reason = 'sync-during-pre-spawn', prepareMs = 500 })
        return
    end

    -- Important: receiving state is not the same as starting climate control.
    -- While the player is in character selection/creation, store the state only.
    if not shouldApplyClimate() then
        pendingApplyAfterResume = true
        lifeDbg('stored sync; waiting for cm-spawn/resume')
        return
    end

    applyCurrentClimate('sync')
end)

RegisterNetEvent('cm-climatime:client:openAdmin', function(state, types, ui)
    climateState = state or climateState
    weatherTypes = types or weatherTypes
    uiConfig = ui or uiConfig
    receivedAtGameTimer = GetGameTimer()

    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        state = climateState,
        weatherTypes = weatherTypes,
        ui = uiConfig
    })
end)

RegisterNetEvent('cm-climatime:client:notify', function(msg)
    notify(msg)
end)

RegisterCommand(Config.Admin.Command or 'climatime', function(_, args)
    args = args or {}
    if args[1] == 'debug' then
        zoneDebugEnabled = not zoneDebugEnabled
        notify(zoneDebugEnabled and 'Climatime zone debug ON' or 'Climatime zone debug OFF')
        return
    end
    TriggerServerEvent('cm-climatime:server:command', args)
end, false)

if Config.Admin.CommandAlias and Config.Admin.CommandAlias ~= '' then
    RegisterCommand(Config.Admin.CommandAlias, function(_, args)
        args = args or {}
        if args[1] == 'debug' then
            zoneDebugEnabled = not zoneDebugEnabled
            notify(zoneDebugEnabled and 'Climatime zone debug ON' or 'Climatime zone debug OFF')
            return
        end
        TriggerServerEvent('cm-climatime:server:command', args)
    end, false)
end

RegisterNUICallback('close', function(_, cb)
    uiOpen = false
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNUICallback('requestState', function(_, cb)
    TriggerServerEvent('cm-climatime:server:requestState')
    cb({ ok = true })
end)

RegisterNUICallback('adminAction', function(data, cb)
    if type(data) == 'table' then
        TriggerServerEvent('cm-climatime:server:adminAction', data.action, data.data or {})
    end
    cb({ ok = true })
end)

RegisterNUICallback('getPosition', function(_, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local crossing = crossingHash and GetStreetNameFromHashKey(crossingHash) or ''
    cb({
        ok = true,
        x = tonumber(('%0.2f'):format(coords.x)),
        y = tonumber(('%0.2f'):format(coords.y)),
        z = tonumber(('%0.2f'):format(coords.z)),
        street = street,
        crossing = crossing
    })
end)

CreateThread(function()
    Wait(2500)
    local c = startupCfg()

    if c.startMode == 'immediate' or c.requireCmSpawn == false then
        activateClimate('resource_start_immediate')
        return
    end

    -- If cm-climatime is restarted while the player is already inside the world,
    -- start again. Otherwise wait for cm-spawn:client:spawned.
    if c.activateIfAlreadySpawned and isPlayerFullySpawned() and not isCharacterScreenActive() then
        activateClimate('resource_restart_already_spawned')
    else
        lifeDbg('waiting for cm-spawn:client:spawned before applying time/weather')
    end
end)

-- Keep every client on the exact same 24h server time. Game clock is paused so GTA does not run fast.
CreateThread(function()
    while true do
        if shouldApplyClimate() and climateState then
            local h, m = getTimeFromState()
            h, m = getHandoffClock(h, m)
            NetworkOverrideClockTime(h, m, 0)
            PauseClock(true)
            Wait(spawnHandoff and spawnHandoff.active and 120 or 500)
        else
            -- Do not touch clock while cm-characters owns the character screen.
            Wait(750)
        end
    end
end)

-- Weather and local zone checker.
CreateThread(function()
    while true do
        Wait(Config.Zones.CheckIntervalMs or 1000)
        if shouldApplyClimate() and climateState then
            local weather, isZone, zone = getEffectiveWeather()
            local zoneId = zone and zone.id or nil
            if weather ~= lastEffectiveWeather or zoneId ~= currentZoneId then
                lastEffectiveWeather = weather
                currentZoneId = zoneId
                applyWeather(weather, isZone)
            elseif not applyingTransition then
                -- Re-assert lightly only after cm-spawn. Never fight cm-characters.
                SetWeatherTypePersist(weather)
            end
            forceEffects()
        end
    end
end)

-- Disable pause/attack while NUI is open.
CreateThread(function()
    while true do
        if uiOpen then
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 200, true)
            Wait(0)
        else
            Wait(500)
        end
    end
end)


-- --------------------------------------------------------------------------
-- Lifecycle bridge events used by cm-characters and cm-spawn.
-- Only cm-spawn starts climate; cm-characters can pause/resume around the UI.
-- --------------------------------------------------------------------------
RegisterNetEvent('cm-spawn:client:spawned', function()
    -- Clear any stale character-screen pause reason after the real spawn event.
    setClimatePaused(false, 'cm-characters')
    setClimatePaused(false, 'character-screen')

    -- If cm-characters already prepared live weather/time while the screen was
    -- black, do not start the old CLEAR-night spawn handoff. Just activate and
    -- re-assert the same current climate so there is no visible sky jump.
    local prepared = wasPreSpawnRecentlyPrepared()
    if not prepared and Config.SpawnHandoff and Config.SpawnHandoff.Enabled ~= false and not spawnHandoff then
        startSpawnHandoff({ reason = 'cm-spawn:client:spawned' })
    end

    activateClimate(prepared and 'cm-spawn:client:spawned-prepared' or 'cm-spawn:client:spawned')

    if prepared then
        SetTimeout(250, function()
            if shouldApplyClimate() and applyCurrentClimate then
                applyCurrentClimate('post-spawn-prepared-refresh')
            end
        end)
    end
end)

RegisterNetEvent('cm-climatime:client:startAfterSpawn', function(reason)
    activateClimate(reason or 'manual-start-after-spawn')
end)

RegisterNetEvent('cm-climatime:client:resumeAfterCharacter', function(reason)
    setClimatePaused(false, 'cm-characters')
    setClimatePaused(false, 'character-screen')
    if isPreSpawnPrepareActive() or wasPreSpawnRecentlyPrepared() then
        applyPreSpawnClimate(lastPreSpawnPayload or { reason = reason or 'resume-after-character', prepareMs = 500 })
    end
end)

RegisterNetEvent('cm-climatime:client:beginSpawnHandoff', function(data)
    startSpawnHandoff(data or {})
end)

RegisterNetEvent('cm-climatime:client:prepareBeforeSpawn', function(data)
    applyPreSpawnClimate(data or {})
end)

RegisterNetEvent('cm-climatime:client:applyBeforeSpawn', function(data)
    applyPreSpawnClimate(data or {})
end)

RegisterNetEvent('cm-climatime:client:activate', function(reason)
    activateClimate(reason or 'manual-activate')
end)

RegisterNetEvent('cm-climatime:client:deactivate', function(reason)
    deactivateClimate(reason or 'manual-deactivate')
end)

for _, eventName in ipairs({
    'cm-climatime:client:setPaused',
    'cm-climatime:client:pause',
    'cm-climatime:client:PauseSync',
    'cm-climatime:client:characterScreen',
    'cm-climatime:client:SetCharacterScreenMode',
    'cm-climatime:client:ignoreSync'
}) do
    RegisterNetEvent(eventName, function(paused, reason)
        setClimatePaused(paused == true, reason or eventName)
    end)
end

for _, eventName in ipairs({
    'cm-climatime:client:requestSync',
    'cm-climatime:client:syncNow',
    'cm-climatime:client:forceSync'
}) do
    RegisterNetEvent(eventName, function()
        requestStateNow(eventName, true)
    end)
end



RegisterCommand((Config.ZoneDebug and Config.ZoneDebug.OverlayCommand) or 'climazone', function()
    zoneDebugEnabled = not zoneDebugEnabled
    notify(zoneDebugEnabled and 'Climatime zone debug ON' or 'Climatime zone debug OFF')
end, false)

RegisterNetEvent('cm-climatime:client:status', function(lines)
    if type(lines) == 'table' then
        for _, line in ipairs(lines) do notify(line) end
    else
        notify(tostring(lines or 'Climatime status unavailable'))
    end
end)

local function drawTxt(x, y, text, scale)
    SetTextFont(4)
    SetTextScale(scale or 0.33, scale or 0.33)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

CreateThread(function()
    while true do
        if zoneDebugEnabled and shouldApplyClimate() then
            local weather, isZone, zone = getEffectiveWeather()
            local h, m = getTimeFromState()
            local lines = {
                ('CM Climatime  %02d:%02d  %s'):format(h, m, weather or 'UNKNOWN'),
                ('Active: %s  Paused: %s'):format(tostring(climateActive), tostring(hasPausedReason() or isCharacterScreenActive()))
            }
            if zone then
                lines[#lines + 1] = ('Zone: %s  ID: %s'):format(zone.name or zone.id or 'Zone', zone.id or 'n/a')
                lines[#lines + 1] = ('Radius: %.0f  Dist: %.0f  Blend: %.0f%%  Priority: %s'):format(tonumber(zone.radius) or 0, tonumber(zone._cmDistance) or 0, (tonumber(zone._cmBlendAlpha) or 1.0) * 100.0, tostring(zone.priority or 0))
                local counts = climateState and climateState.zoneDebug and climateState.zoneDebug.counts or {}
                lines[#lines + 1] = ('Players inside: %s'):format(tostring(counts[zone.id] or 0))
            else
                lines[#lines + 1] = 'Zone: Global weather'
            end
            for i, line in ipairs(lines) do drawTxt(0.015, 0.18 + ((i - 1) * 0.024), line, 0.32) end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        Wait((Config.ZoneDebug and Config.ZoneDebug.HeartbeatMs) or 5000)
        if shouldApplyClimate() and climateState then
            local _, _, zone = getEffectiveWeather()
            TriggerServerEvent('cm-climatime:server:zoneHeartbeat', zone and zone.id or nil, zone and (zone.currentWeather or zone.weather) or nil, lastZoneInfo or {})
        end
    end
end)

exports('GetState', function()
    return climateState
end)

exports('GetCurrentWeather', function()
    local weather, isZone, zone = getEffectiveWeather()
    return weather, isZone, zone
end)

exports('GetCurrentTime', function()
    return getTimeFromState()
end)

exports('SetPaused', function(paused, reason)
    setClimatePaused(paused == true, reason or 'export')
    return true
end)

exports('Pause', function(paused, reason)
    setClimatePaused(paused == true, reason or 'export')
    return true
end)

exports('PauseSync', function(paused, reason)
    setClimatePaused(paused == true, reason or 'export')
    return true
end)

exports('SetCharacterScreenMode', function(paused)
    setClimatePaused(paused == true, 'character-screen')
    return true
end)

exports('SetPlayerPaused', function(paused, reason)
    setClimatePaused(paused == true, reason or 'export')
    return true
end)

exports('IgnoreSync', function(paused)
    setClimatePaused(paused == true, 'ignore-sync')
    return true
end)

exports('StartAfterSpawn', function(reason)
    return activateClimate(reason or 'export')
end)

exports('BeginSpawnHandoff', function(data)
    return startSpawnHandoff(data or {})
end)

exports('PrepareBeforeSpawn', function(data)
    return applyPreSpawnClimate(data or {})
end)

exports('IsPreSpawnPrepared', function()
    return wasPreSpawnRecentlyPrepared()
end)

exports('RequestSync', function()
    return requestStateNow('export', true)
end)

exports('SyncNow', function()
    return requestStateNow('export', true)
end)

exports('ForceSync', function()
    return requestStateNow('export', true)
end)

exports('IsActive', function()
    return climateActive == true and shouldApplyClimate()
end)

exports('IsPaused', function()
    return hasPausedReason() or isCharacterScreenActive()
end)


exports('GetForecastTimeline', function()
    if not climateState or not climateState.weather then return {} end
    return climateState.weather.forecast or {}
end)

exports('GetCurrentConditions', function()
    local weather, isZone, zone = getEffectiveWeather()
    local h, m = getTimeFromState()
    return {
        weather = weather,
        isZone = isZone == true,
        zone = zone,
        zoneInfo = lastZoneInfo,
        hour = h,
        minute = m,
        active = climateActive == true and shouldApplyClimate(),
        paused = hasPausedReason() or isCharacterScreenActive(),
        handoff = spawnHandoff and spawnHandoff.active == true or false,
        preSpawnPreparing = preSpawnPreparing == true,
        preSpawnPrepared = wasPreSpawnRecentlyPrepared(),
        forecast = climateState and climateState.weather and climateState.weather.forecast or {},
        temperature = computeLocalTemperature(weather, h),
        temperatureUnit = 'C'
    }
end)

exports('GetCurrentZone', function()
    local _, _, zone = getEffectiveWeather()
    return zone, lastZoneInfo
end)
