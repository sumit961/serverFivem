-- cm-spawn/client/selector_weather.lua
-- Fix: weather must be correct DURING the spawn selector, so there is no
-- night->day snap after the player picks "hotel" / "last location".
--
-- Root cause this addresses: cm-climatime intentionally refuses to apply weather
-- while cm-characters owns the character screen ("never fight cm-characters"),
-- and the pre-spawn prepare that clears that pause can be re-paused by the
-- worldlock loop in a race. A single prepare call at selector-open can therefore
-- be undone a frame later, leaving the character-creation night on screen until
-- the reveal.
--
-- This module makes selector weather AUTHORITATIVE and SELF-HEALING: while the
-- spawn selector is open it re-asserts the real synced climate on a short loop,
-- so whichever writer races last, climatime is re-nudged within ~250ms and the
-- sky settles on the correct weather long before the player chooses a spawn.
--
-- It is additive: it does not edit cm-climatime and does not change cm-spawn's
-- existing flow. It only piggybacks on the state cm-spawn already sets
-- (spawnSelectorOpen) and the pre-spawn events cm-climatime already listens for.

local function cfgNum(key, default)
    local ok, v = pcall(function() return Config and Config[key] end)
    if ok and type(v) == 'number' then return v end
    return default
end

local function climatimeStarted()
    return GetResourceState('cm-climatime') == 'started'
end

-- Ask cm-climatime to apply the current synced weather/time NOW, treating the
-- request as the pre-spawn prepare phase (which is allowed to override the
-- character-screen pause). Sending the events it already binds keeps this
-- decoupled from cm-climatime's internals.
local function assertSelectorClimate(reason)
    if not climatimeStarted() then return end

    local payload = {
        reason = reason or 'spawn-selector-assert',
        prepareMs = cfgNum('SpawnPageClimatePrepareMs', 900),
        validMs = cfgNum('SpawnPageClimateValidMs', 30000),
    }

    -- Prefer the direct export when present (newer cm-climatime); fall back to
    -- the events older/current versions listen for. Any missing target is
    -- simply ignored by FiveM, so this is safe across versions.
    local usedExport = false
    pcall(function()
        if exports['cm-climatime'] and exports['cm-climatime'].PrepareBeforeSpawn then
            exports['cm-climatime']:PrepareBeforeSpawn(payload)
            usedExport = true
        end
    end)

    if not usedExport then
        TriggerEvent('cm-climatime:client:prepareBeforeSpawn', payload)
        TriggerEvent('cm-climatime:client:applyBeforeSpawn', payload)
    end

    -- Also make sure the server has pushed us fresh state at least once.
    TriggerServerEvent('cm-climatime:server:requestPreSpawnClimate', payload)
end

-- Is the spawn selector currently open? cm-spawn already publishes these.
local function selectorOpen()
    local st = LocalPlayer and LocalPlayer.state or nil
    if not st then return false end
    return st.spawnSelectorOpen == true or st.cmSpawnOpen == true or st.isInSpawnSelector == true
end

-- Self-healing loop. Sleeps entirely when the selector is closed (no idle cost
-- during normal gameplay). While open, it re-asserts a few times, quickly at
-- first to win the race against the worldlock re-pause, then slowly to hold.
CreateThread(function()
    local wasOpen = false
    local assertsSinceOpen = 0

    while true do
        if selectorOpen() then
            if not wasOpen then
                -- Selector just opened: assert immediately.
                wasOpen = true
                assertsSinceOpen = 0
                assertSelectorClimate('spawn-selector-open')
            end

            assertsSinceOpen = assertsSinceOpen + 1
            assertSelectorClimate('spawn-selector-hold')

            -- Fast re-assert for the first ~2s (8 x 250ms) to beat the pause
            -- race, then settle to a cheap 1s hold that keeps the sky correct
            -- for as long as the player lingers on the selector.
            if assertsSinceOpen < 8 then
                Wait(250)
            else
                Wait(1000)
            end
        else
            if wasOpen then wasOpen = false end
            Wait(500)   -- idle: selector closed, negligible cost
        end
    end
end)
