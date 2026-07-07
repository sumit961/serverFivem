-- cm-characters/client/worldlock.lua
-- Character selector / creator world lock.
-- IMPORTANT:
-- This file does NOT try to fight cm-climatime every frame anymore.
-- Fighting two weather systems causes the visible blinking/flicker.
-- Flow:
--   1) tell cm-climatime / weather sync resources to pause once
--   2) apply a local fixed night scene once
--   3) keep only cm-hud NUI/clock locked while character UI is open
--   4) when character spawn/ready is finished, restore native HUD/minimap and resume cm-climatime

local lockReasons = {}
local lockActive = false
local lastHudPulse = 0
local lastClockPulse = 0
local lastWeatherSoftPulse = 0
local enteredAt = 0
local leaveGeneration = 0

local function cfg()
    local c = Config and Config.CharacterScreenWorld or {}
    return {
        enabled = c.enabled ~= false,
        weather = tostring(c.weather or 'CLEAR'):upper(),
        hour = tonumber(c.hour) or 23,
        minute = tonumber(c.minute) or 0,
        second = tonumber(c.second) or 0,
        hideHud = c.hideHud ~= false,
        hideNativeHud = c.hideNativeHud == true,
        hideRadar = c.hideRadar == true,
        suppressClimatime = c.suppressClimatime ~= false,
        hudPulseMs = tonumber(c.hudPulseMs) or 650,
        clockPulseMs = tonumber(c.clockPulseMs) or 0,
        -- Weather should normally be applied only on lock start.
        -- Set this true only if your weather resource cannot be paused.
        reapplyWeatherWhileLocked = c.reapplyWeatherWhileLocked == true,
        weatherSoftPulseMs = tonumber(c.weatherSoftPulseMs) or 8000,
        resumeRetries = tonumber(c.resumeRetries) or 4,
        resumeRetryDelayMs = tonumber(c.resumeRetryDelayMs) or 900,
        preSpawnClimatePrepare = c.preSpawnClimatePrepare == true,
        smoothClimatimeHandoff = c.smoothClimatimeHandoff == true,
        handoffHoldMs = tonumber(c.handoffHoldMs) or 1200,
        handoffWeatherTransitionSeconds = tonumber(c.handoffWeatherTransitionSeconds) or 32,
        handoffTimeBlendSeconds = tonumber(c.handoffTimeBlendSeconds) or 9,
        handoffRainRampSeconds = tonumber(c.handoffRainRampSeconds) or 10
    }
end

local function anyReasonLocked()
    for _, enabled in pairs(lockReasons) do
        if enabled == true then return true end
    end
    return false
end

local function shouldBeLocked()
    local c = cfg()
    if not c.enabled then return false end
    local st = LocalPlayer and LocalPlayer.state or nil
    return anyReasonLocked()
        or (st and st.isInCharacterSelector == true)
        or (st and st.isInCharacterCreation == true)
        or (st and st.cmCharactersWorldLocked == true)
end

local function callExport(resourceName, exportName, ...)
    if GetResourceState(resourceName) ~= 'started' then return false end
    local args = { ... }
    local ok = pcall(function()
        if exports[resourceName] and exports[resourceName][exportName] then
            return exports[resourceName][exportName](table.unpack(args))
        end
    end)
    return ok == true
end

local function setStateFlag(name, value)
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set(name, value, true)
    end
end

local function notifyClimatePause(paused)
    paused = paused == true

    setStateFlag('cmClimatimePaused', paused)
    setStateFlag('cmClimatimeIgnore', paused)
    setStateFlag('cmCharactersWorldLock', paused)
    setStateFlag('cmCharactersWorldLocked', paused)

    if not cfg().suppressClimatime then return end

    -- cm-climatime compatibility names. If your cm-climatime has any of these,
    -- it will pause cleanly instead of fighting the selector weather.
    TriggerEvent('cm-climatime:client:setPaused', paused, 'cm-characters')
    TriggerEvent('cm-climatime:client:pause', paused, 'cm-characters')
    TriggerEvent('cm-climatime:client:PauseSync', paused, 'cm-characters')
    TriggerEvent('cm-climatime:client:characterScreen', paused)
    TriggerEvent('cm-climatime:client:SetCharacterScreenMode', paused)
    TriggerEvent('cm-climatime:client:ignoreSync', paused)

    TriggerServerEvent('cm-climatime:server:setPlayerPaused', paused, 'cm-characters')
    TriggerServerEvent('cm-climatime:server:characterScreen', paused)

    callExport('cm-climatime', 'SetPaused', paused, 'cm-characters')
    callExport('cm-climatime', 'Pause', paused, 'cm-characters')
    callExport('cm-climatime', 'PauseSync', paused, 'cm-characters')
    callExport('cm-climatime', 'SetCharacterScreenMode', paused)
    callExport('cm-climatime', 'SetPlayerPaused', paused, 'cm-characters')
    callExport('cm-climatime', 'IgnoreSync', paused)

    -- Common third-party weather resources, safe best-effort only.
    if paused then
        TriggerEvent('qb-weathersync:client:DisableSync')
        TriggerEvent('qbx_weathersync:client:DisableSync')
        TriggerEvent('vSync:toggle', false)
        TriggerEvent('Renewed-Weathersync:client:DisableSync')
        TriggerEvent('cd_easytime:PauseSync', true)
    else
        TriggerEvent('qb-weathersync:client:EnableSync')
        TriggerEvent('qbx_weathersync:client:EnableSync')
        TriggerEvent('vSync:toggle', true)
        TriggerEvent('Renewed-Weathersync:client:EnableSync')
        TriggerEvent('cd_easytime:PauseSync', false)
    end
end

local function requestClimateSyncNow()
    TriggerEvent('cm-climatime:client:requestSync')
    TriggerEvent('cm-climatime:client:syncNow')
    TriggerEvent('cm-climatime:client:forceSync')
    TriggerServerEvent('cm-climatime:server:requestSync')
    TriggerServerEvent('cm-climatime:server:syncMe')
    callExport('cm-climatime', 'RequestSync')
    callExport('cm-climatime', 'SyncNow')
    callExport('cm-climatime', 'ForceSync')
end

local function beginClimatimeSmoothHandoff(c, reason)
    if not c.smoothClimatimeHandoff then return false end
    if GetResourceState('cm-climatime') ~= 'started' then return false end

    local payload = {
        reason = reason or 'cm-characters-spawn-handoff',
        fromWeather = c.weather or 'CLEAR',
        fromHour = c.hour or 23,
        fromMinute = c.minute or 0,
        fromSecond = c.second or 0,
        holdMs = c.handoffHoldMs or 1200,
        weatherTransitionSeconds = c.handoffWeatherTransitionSeconds or 32,
        timeBlendSeconds = c.handoffTimeBlendSeconds or 9,
        rainRampSeconds = c.handoffRainRampSeconds or 10
    }

    TriggerEvent('cm-climatime:client:beginSpawnHandoff', payload)
    TriggerEvent('cm-climatime:client:startAfterSpawn', payload.reason)
    callExport('cm-climatime', 'BeginSpawnHandoff', payload)
    callExport('cm-climatime', 'StartAfterSpawn', payload.reason)
    return true
end

local function pulseHudLock(c, force)
    -- Do not hide GTA radar/minimap by default. Only hide native HUD/radar if you
    -- explicitly enable hideNativeHud/hideRadar in Config.CharacterScreenWorld.
    if c.hideNativeHud then
        HideHudAndRadarThisFrame()
    end

    if c.hideRadar then
        DisplayRadar(false)
    end

    if c.hideHud then
        local now = GetGameTimer()
        if force or (now - lastHudPulse) >= c.hudPulseMs then
            lastHudPulse = now
            setStateFlag('cmHudHiddenByCharacters', true)
            setStateFlag('cmCharactersHudLock', true)

            -- UI-only bridge: this hides cm-hud NUI but does not touch GTA radar/minimap.
            TriggerEvent('cm-hud:client:hideUiOnly', 'cm-characters-worldlock')
            TriggerEvent('cm-hud:client:setUiVisible', false, 'cm-characters-worldlock')
            callExport('cm-hud', 'SetUiVisible', false, 'cm-characters-worldlock')
            callExport('cm-hud', 'HideUiOnly', 'cm-characters-worldlock')
        end
    end
end

local function applyFixedNightScene(c, force)
    -- Apply weather once. Do not ClearOverrideWeather + SetOverrideWeather in a loop;
    -- that is what causes the weather blink/flicker when another weather script is active.
    pcall(function() SetOverrideWeather(c.weather) end)
    pcall(function() SetWeatherTypeNowPersist(c.weather) end)
    pcall(function() SetRainFxIntensity(0.0) end)
    pcall(function() SetWind(0.0) end)

    -- Clock can safely be locked often because this does not flash the sky.
    pcall(function() PauseClock(true) end)
    pcall(function() NetworkOverrideClockTime(c.hour, c.minute, c.second) end)
    pcall(function() SetClockTime(c.hour, c.minute, c.second) end)

    lastWeatherSoftPulse = GetGameTimer()
    lastClockPulse = GetGameTimer()
end

local function pulseClockOnly(c)
    local now = GetGameTimer()
    if c.clockPulseMs <= 0 or (now - lastClockPulse) >= c.clockPulseMs then
        lastClockPulse = now
        pcall(function() PauseClock(true) end)
        pcall(function() NetworkOverrideClockTime(c.hour, c.minute, c.second) end)
        pcall(function() SetClockTime(c.hour, c.minute, c.second) end)
    end

    -- Optional fallback only. This avoids fast blinking but still recovers slowly if
    -- an unpatched weather resource overwrites selector weather.
    if c.reapplyWeatherWhileLocked and (now - lastWeatherSoftPulse) >= c.weatherSoftPulseMs then
        lastWeatherSoftPulse = now
        pcall(function() SetOverrideWeather(c.weather) end)
        pcall(function() SetWeatherTypeNowPersist(c.weather) end)
        pcall(function() SetRainFxIntensity(0.0) end)
    end
end

local function enterLock()
    lockActive = true
    enteredAt = GetGameTimer()
    local c = cfg()

    notifyClimatePause(true)
    setStateFlag('cmCharactersHudLock', true)
    pulseHudLock(c, true)
    applyFixedNightScene(c, true)

    print(('[CM-CHARACTERS] Character world lock ON | climate paused | fixed %s %02d:%02d'):format(c.weather, c.hour, c.minute))
end

local function resumeClimateWithRetries(generation, c)
    CreateThread(function()
        local retries = math.max(1, c.resumeRetries or 4)
        local delay = math.max(250, c.resumeRetryDelayMs or 900)
        for i = 1, retries do
            if generation ~= leaveGeneration then return end
            notifyClimatePause(false)
            requestClimateSyncNow()
            Wait(delay)
        end
    end)
end

local function leaveLock()
    lockActive = false
    leaveGeneration = leaveGeneration + 1
    local generation = leaveGeneration
    local c = cfg()

    setStateFlag('cmCharactersWorldLocked', false)
    setStateFlag('cmCharactersWorldLock', false)
    setStateFlag('cmCharactersHudLock', false)
    setStateFlag('cmClimatimePaused', false)
    setStateFlag('cmClimatimeIgnore', false)

    local st = LocalPlayer and LocalPlayer.state or nil
    local preparingPreSpawnClimate = st and st.cmCharactersPreparingSpawnClimate == true

    -- v1.5.6 preferred flow: when the player selected a character, the screen is
    -- faded out and cm-climatime prepares the real live weather BEFORE cm-spawn
    -- reveals the player. In that mode, do not start the old post-spawn handoff
    -- and do not show cm-hud early.
    local handoffStarted = false
    if not preparingPreSpawnClimate then
        handoffStarted = beginClimatimeSmoothHandoff(c, 'cm-characters-worldlock-release')
    end

    if not handoffStarted then
        pcall(function() PauseClock(false) end)
        pcall(function() NetworkClearClockTimeOverride() end)
        pcall(function() ClearOverrideWeather() end)
        pcall(function() ClearWeatherTypePersist() end)
        pcall(function() SetRainFxIntensity(-1.0) end)
    end

    -- Safety restore. This prevents a stuck hidden minimap/native HUD if an older
    -- cm-hud/character flow hid radar before this patch.
    pcall(function() DisplayHud(true) end)
    pcall(function() DisplayRadar(true) end)

    if not preparingPreSpawnClimate then
        setStateFlag('cmHudHiddenByCharacters', false)
        TriggerEvent('cm-hud:client:showUiOnly', 'cm-characters-worldlock')
        TriggerEvent('cm-hud:client:setUiVisible', true, 'cm-characters-worldlock')
        callExport('cm-hud', 'SetUiVisible', true, 'cm-characters-worldlock')
        callExport('cm-hud', 'ShowUiOnly', 'cm-characters-worldlock')
    end

    notifyClimatePause(false)
    if not preparingPreSpawnClimate then
        requestClimateSyncNow()
        resumeClimateWithRetries(generation, c)
    end

    print(preparingPreSpawnClimate and '[CM-CHARACTERS] Character world lock OFF | pre-spawn climatime prepare is taking over' or '[CM-CHARACTERS] Character world lock OFF | cm-hud restored | fallback cm-climatime handoff requested')
end

RegisterNetEvent('cm-characters:client:setWorldLock', function(reason, enabled)
    reason = tostring(reason or 'default')
    lockReasons[reason] = enabled == true or nil

    if enabled == true then
        setStateFlag('cmCharactersWorldLocked', true)
        return
    end

    -- Important: when all lock reasons are removed, clear the world-lock statebag too.
    -- The old code only set this flag true, so stale state could keep forcing night after spawn.
    if not anyReasonLocked() then
        local st = LocalPlayer and LocalPlayer.state or nil
        if not (st and (st.isInCharacterSelector == true or st.isInCharacterCreation == true)) then
            setStateFlag('cmCharactersWorldLocked', false)
            setStateFlag('cmCharactersWorldLock', false)
            setStateFlag('cmCharactersHudLock', false)
        end
    end
end)

RegisterNetEvent('cm-characters:client:releaseWorldLockNow', function()
    for k in pairs(lockReasons) do lockReasons[k] = nil end
    setStateFlag('isInCharacterSelector', false)
    setStateFlag('isInCharacterCreation', false)
    setStateFlag('cmCharactersWorldLocked', false)
    setStateFlag('cmCharactersWorldLock', false)
    setStateFlag('cmCharactersHudLock', false)
    setStateFlag('cmHudHiddenByCharacters', false)
    if lockActive then
        leaveLock()
    else
        notifyClimatePause(false)
        requestClimateSyncNow()
        pcall(function() PauseClock(false) end)
        pcall(function() NetworkClearClockTimeOverride() end)
        pcall(function() ClearOverrideWeather() end)
        pcall(function() ClearWeatherTypePersist() end)
        pcall(function() DisplayHud(true) end)
        pcall(function() DisplayRadar(true) end)
        TriggerEvent('cm-hud:client:showUiOnly', 'cm-characters-release')
        TriggerEvent('cm-hud:client:setUiVisible', true, 'cm-characters-release')
        callExport('cm-hud', 'SetUiVisible', true, 'cm-characters-release')
        callExport('cm-hud', 'ShowUiOnly', 'cm-characters-release')
    end
end)

exports('SetCharacterWorldLock', function(reason, enabled)
    reason = tostring(reason or 'external')
    lockReasons[reason] = enabled == true or nil
    if enabled == true then
        setStateFlag('cmCharactersWorldLocked', true)
    end
end)

exports('IsCharacterWorldLocked', function()
    return lockActive or shouldBeLocked()
end)

exports('ReleaseCharacterWorldLock', function()
    TriggerEvent('cm-characters:client:releaseWorldLockNow')
end)

CreateThread(function()
    while true do
        local c = cfg()
        if shouldBeLocked() then
            if not lockActive then enterLock() end
            pulseHudLock(c, false)
            pulseClockOnly(c)
            Wait(0)
        else
            if lockActive then leaveLock() end
            Wait(300)
        end
    end
end)

-- Extra safety: these events mean the player is no longer in selector/creator.
for _, eventName in ipairs({
    'cm-characters:client:characterReady',
    'cm-spawn:client:spawned',
    'cm-spawn:characterLoaded',
    'cm-core:client:characterLoaded',
    'cm-playerdata:client:loaded'
}) do
    RegisterNetEvent(eventName, function()
        SetTimeout(250, function()
            if not shouldBeLocked() and lockActive then leaveLock() end
            if not shouldBeLocked() then
                notifyClimatePause(false)
                requestClimateSyncNow()
            end
        end)
    end)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if lockActive then leaveLock() end
end)
