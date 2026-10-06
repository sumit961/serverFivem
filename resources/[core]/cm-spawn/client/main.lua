-- cm-spawn/client/main.lua
-- Production-ready spawn client. Handles spawn selector UI, pre-spawn climate handoff,
-- final teleport/camera reveal, and HUD/minimap restore.

local spawnCam = nil
local isInSpawn = false
local spawnTransitionActive = false
local spawnTransitionGeneration = 0
local pendingAppearance = nil
local RESOURCE = 'CM-SPAWN'
local HudStateCache = {}
local LastHudVisible = nil
local ClimatePagePreparedUntil = 0
local selectingSpawn = false

-- PHASE 5: coords/dead-flag captured by beginSpawn (prepare phase) and
-- consumed by revealAfterPublicWorld (reveal phase) once the server has
-- accepted the public-bucket handoff.
local lastPreparedSpawnCoords = nil
local lastPreparedIsDead = false

-- BLACK SCREEN FIX: SendNUIMessage('openSelector') can be lost if it races
-- ui/app.js still mounting (page just (re)loaded from a resource restart, or
-- CEF is momentarily busy) -- the exact same class of bug cm-characters
-- already hardened against with its own nuiReady/pendingSelectorOpen pair.
-- nuiReady flips true once app.js confirms it is listening; selectorRendered
-- flips true once it confirms the card grid actually painted a frame. Until
-- both are true we must assume the player is looking at nothing.
local nuiReady = false
local pendingSelectorPayload = nil
local selectorRenderConfirmed = false
local openSelectorAttempt = 0
-- Independent from spawnTransitionGeneration on purpose: that counter is
-- also compared against the SERVER's own opaque per-transition token in
-- beginSpawn/revealAfterPublicWorld (see PHASE 5). This one bumping here
-- used to double-increment the SAME variable, desyncing it from the
-- server's token and silently dropping every revealAfterPublicWorld ->
-- spawnComplete handshake after a real spawn selection (stage=public would
-- time out even though the server had already accepted it).
local selectorOpenGeneration = 0

local function setLocalState(name, value, replicated)
    local state = LocalPlayer and LocalPlayer.state
    if not state then return end
    if state[name] ~= value then
        state:set(name, value, replicated == true)
    end
end

local function cfg(key, fallback)
    if Config and Config[key] ~= nil then return Config[key] end
    return fallback
end

local function dprint(message)
    if cfg('Debug', false) or cfg('VerboseLogs', false) then
        print(('[%s] %s'):format(RESOURCE, tostring(message)))
    end
end

local function setHudState(name, value, force)
    value = value == true
    if not force and HudStateCache[name] == value then return end
    HudStateCache[name] = value

    if GetResourceState('cm-hud') == 'started' then
        pcall(function() exports['cm-hud']:SetHudState(name, value) end)
        pcall(function() exports['cm-hud']:SetState(name, value) end)
    end

    TriggerEvent('cm-hud:client:setState', name, value)
    TriggerEvent('cm-hud:client:SetState', name, value)
end

local function setCmHudVisible(visible, reason, force)
    visible = visible == true
    DisplayRadar(visible)
    setLocalState('cmHudHidden', not visible, true)

    if visible then
        setHudState('spawning', false, force)
        setHudState('spawnSelector', false, force)
    else
        setHudState('spawning', true, force)
    end

    if not force and LastHudVisible == visible then return end
    LastHudVisible = visible

    TriggerEvent('cm-hud:client:setVisible', visible)
    TriggerEvent('cm-hud:client:SetVisible', visible)
    TriggerEvent('cm-hud:client:setHudVisible', visible, reason or 'cm-spawn')

    if GetResourceState('cm-hud') == 'started' then
        pcall(function() exports['cm-hud']:SetVisible(visible) end)
        pcall(function() exports['cm-hud']:SetHudVisible(visible, reason or 'cm-spawn') end)
        pcall(function() exports['cm-hud']:ToggleHud(visible) end)
    end
end

local function enablePlayerCombat(ped)
    ped = ped or PlayerPedId()
    pcall(function() NetworkSetFriendlyFireOption(true) end)
    pcall(function() SetCanAttackFriendly(ped, true, false) end)

    SetPedCanBeTargetted(ped, true)
    SetEntityInvincible(ped, false)
    pcall(function() SetEntityProofs(ped, false, false, false, false, false, false, false, false) end)
    SetEntityCollision(ped, true, true)
    SetPedCanRagdoll(ped, true)
    pcall(function() SetPedCanRagdollFromPlayerImpact(ped, true) end)
    pcall(function() SetPedSuffersCriticalHits(ped, true) end)
end

local function cleanupSpawnCam(instant)
    if spawnCam and DoesCamExist(spawnCam) then
        RenderScriptCams(false, not instant, instant and 0 or 800, true, true)
        DestroyCam(spawnCam, false)
        spawnCam = nil
    else
        RenderScriptCams(false, false, 0, true, true)
    end
end

local function makePlayerVisible(ped)
    ped = ped or PlayerPedId()
    pcall(function() NetworkSetEntityInvisibleToNetwork(ped, false) end)
    pcall(function() SetLocalPlayerVisibleLocally(true) end)
    ResetEntityAlpha(ped)
    SetEntityAlpha(ped, 255, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    SetPlayerControl(PlayerId(), true, 0)
    ClearPedTasksImmediately(ped)
    SetPedCanRagdoll(ped, true)
    enablePlayerCombat(ped)
end

local function hasProtectedScreenFlow(state)
    state = state or (LocalPlayer and LocalPlayer.state) or {}
    return isInSpawn
        or spawnTransitionActive
        or state.isInCharacterSelector == true
        or state.isInCharacterCreation == true
        or state.isInSpawnSelector == true
        or state.spawnSelectorOpen == true
        or state.cmSpawnOpen == true
        or state.cmSpawnActive == true
        or state.cmCharactersPreparingSpawnClimate == true
        or state.cmClimatimePreSpawnPreparing == true
end

local function restorePlayerScreen(reason)
    local ped = PlayerPedId()
    cleanupSpawnCam(true)
    SetNuiFocus(false, false)
    makePlayerVisible(ped)
    DoScreenFadeIn(350)
    setCmHudVisible(true, reason or 'spawn_recovery', true)
    DisplayRadar(true)
end

local function startSpawnRecoveryWatchdog(generation)
    SetTimeout(30000, function()
        if generation ~= spawnTransitionGeneration or not spawnTransitionActive then return end

        spawnTransitionActive = false
        setLocalState('isInSpawnSelector', false, true)
        setLocalState('spawnSelectorOpen', false, true)
        setLocalState('cmSpawnOpen', false, true)
        setLocalState('cmSpawnActive', false, true)
        restorePlayerScreen('spawn_timeout_recovery')
        print(('[%s] WARNING: spawn transition timed out; restored player visibility and screen'):format(RESOURCE))
    end)
end

local function setupSkyToPlayerCamera(coords)
    local x, y, z = coords.x, coords.y, coords.z
    local skyCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(skyCam, x, y, z + 180.0)
    PointCamAtCoord(skyCam, x, y, z)
    SetCamFov(skyCam, 75.0)

    local landCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(landCam, x + 6.0, y + 6.0, z + 4.0)
    PointCamAtCoord(landCam, x, y, z + 0.8)
    SetCamFov(landCam, 55.0)

    SetCamActive(skyCam, true)
    RenderScriptCams(true, false, 0, true, true)

    return skyCam, landCam
end

local function playSkyToPlayerCamera(skyCam, landCam)
    if not skyCam or not landCam then return end
    Wait(250)
    SetCamActiveWithInterp(landCam, skyCam, 2600, true, true)
    Wait(2700)
    RenderScriptCams(false, true, 900, true, true)
    Wait(900)
    DestroyCam(skyCam, false)
    DestroyCam(landCam, false)
end

local function requestClimateBeforeReveal(coords)
    if GetResourceState('cm-climatime') ~= 'started' then return end

    -- These events are intentionally tolerant. Current or future cm-climatime versions
    -- can handle any of them; if missing, FiveM simply ignores the event.
    local payload = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        h = coords.w or coords.h or coords.heading or 0.0,
        reason = 'cm-spawn-before-reveal'
    }
    TriggerServerEvent('cm-climatime:server:requestPreSpawnClimate', payload)
    TriggerEvent('cm-climatime:client:applyBeforeSpawn', payload)
    TriggerEvent('cm-climatime:client:prepareBeforeSpawn', payload)
    TriggerEvent('cm-climatime:client:resumeAfterCharacter')
    Wait(cfg('PreSpawnClimateWait', 350))
end

local function preloadClimateForSpawnPage()
    if GetResourceState('cm-climatime') ~= 'started' then return end

    local now = GetGameTimer()
    if ClimatePagePreparedUntil > now then return end

    local validMs = tonumber(cfg('SpawnPageClimateValidMs', 30000)) or 30000
    local payload = {
        reason = 'spawn-page-preload',
        prepareMs = tonumber(cfg('SpawnPageClimatePrepareMs', 900)) or 900,
        validMs = validMs
    }
    ClimatePagePreparedUntil = now + validMs

    -- Prepare climate during the black/selector transition. The selected final
    -- location is still prepared again before reveal.
    TriggerServerEvent('cm-climatime:server:requestPreSpawnClimate', payload)
    TriggerEvent('cm-climatime:client:applyBeforeSpawn', payload)
    TriggerEvent('cm-climatime:client:prepareBeforeSpawn', payload)

    local waitMs = tonumber(cfg('SpawnPageClimateWait', 120)) or 0
    if waitMs > 0 then Wait(waitMs) end
end

local function preparePlayerAtSpawn(coords, appearance)
    local ped = PlayerPedId()
    local heading = coords.w or coords.h or coords.heading or 0.0

    SetPlayerControl(PlayerId(), false, 0)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, heading)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, true, false)

    ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, heading)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)

    local timeout = GetGameTimer() + 7000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(50)
    end

    requestClimateBeforeReveal(coords)

    if appearance then
        TriggerEvent('cm-characters:client:applyAppearance', appearance)
        Wait(450)
    else
        SetPedDefaultComponentVariation(ped)
        Wait(100)
    end

    ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, heading)
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, true)

    pcall(function() NetworkSetEntityInvisibleToNetwork(ped, false) end)
    pcall(function() SetLocalPlayerVisibleLocally(true) end)
    ResetEntityAlpha(ped)
    SetEntityAlpha(ped, 255, false)
    SetEntityVisible(ped, true, false)
    ClearPedTasksImmediately(ped)

    local readyUntil = GetGameTimer() + 900
    repeat
        SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(ped, heading)
        SetEntityVisible(ped, true, false)
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(50)
    until GetGameTimer() > readyUntil

    return ped
end

-- BLACK SCREEN FIX: describes exactly what state everything was in the
-- moment we gave up, so a recurrence is diagnosable from one log line
-- instead of another multi-hour trace (see brief's WATCHDOG section).
local function dumpSpawnSelectorState(tag)
    -- Client-side only: routing bucket itself isn't readable from here, but
    -- these state bags are exactly what the server set it based on.
    local st = LocalPlayer and LocalPlayer.state or {}
    print(('[%s] %s | isInSpawn=%s nuiReady=%s renderConfirmed=%s attempt=%s faded=%s skipPositionSave=%s isInCharacterSelector=%s isInCharacterCreation=%s'):format(
        RESOURCE, tag,
        tostring(isInSpawn), tostring(nuiReady), tostring(selectorRenderConfirmed), tostring(openSelectorAttempt),
        tostring(IsScreenFadedOut() or IsScreenFadingOut()),
        tostring(st.skipPositionSave), tostring(st.isInCharacterSelector), tostring(st.isInCharacterCreation)
    ))
end

local function sendOpenSelectorPayload()
    if not pendingSelectorPayload then return end
    openSelectorAttempt = openSelectorAttempt + 1
    dprint('openSelector sent, attempt ' .. tostring(openSelectorAttempt))
    SendNUIMessage({
        action = 'openSelector',
        spawns = pendingSelectorPayload.spawns,
        player = pendingSelectorPayload.player,
        debug = cfg('Debug', false) == true
    })
end

-- BLACK SCREEN FIX: single authoritative recovery path. Never a bare
-- DoScreenFadeIn -- always restores controls/visibility/HUD together so the
-- player ends up in a genuinely usable state, not just a visible one.
local function recoverFromBlackScreen(reason, message)
    print(('[%s] WARNING: recovering from spawn handoff failure (%s)'):format(RESOURCE, tostring(reason)))
    dumpSpawnSelectorState('recovering: ' .. tostring(reason))

    isInSpawn = false
    pendingSelectorPayload = nil
    setLocalState('isInSpawnSelector', false, true)
    setLocalState('spawnSelectorOpen', false, true)
    setLocalState('cmSpawnOpen', false, true)
    setLocalState('cmSpawnActive', false, true)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeSelector' })
    cleanupSpawnCam(false)
    setHudState('spawnSelector', false)
    makePlayerVisible(PlayerPedId())
    setCmHudVisible(true, reason or 'spawn_handoff_failed', true)
    DisplayRadar(true)
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(350) end

    if GetResourceState('cm-core') == 'started' then
        pcall(function()
            exports['cm-core']:Notify(PlayerId(), message or 'Spawn failed to prepare. Please reconnect or try again.', 'error', 6000)
        end)
    end
end

-- WATCHDOG: openSelector is a fullscreen opaque NUI page, so a bad handoff
-- here doesn't just leave a broken panel -- it leaves the whole screen faded
-- black with nothing to interact with, forever, unless something notices
-- and recovers. Retries the send once if app.js never acks that it painted
-- a frame, then gives up and recovers rather than stranding the player.
local function watchSelectorRendered(generation)
    CreateThread(function()
        Wait(2500)
        if not isInSpawn or selectorRenderConfirmed or generation ~= selectorOpenGeneration then return end
        dumpSpawnSelectorState('selector render not confirmed, retrying send')
        sendOpenSelectorPayload()

        Wait(3000)
        if not isInSpawn or selectorRenderConfirmed or generation ~= selectorOpenGeneration then return end
        recoverFromBlackScreen('selector_render_timeout', 'Spawn selector failed to open. Please reconnect or try again.')
    end)
end

-- BLACK SCREEN FIX: explicit failure contract from the server (see
-- server/main.lua's DoSpawn) instead of a silent early return that used to
-- leave PendingSpawns cleared with no client-visible outcome at all.
RegisterNetEvent('cm-spawn:client:spawnPreparationFailed')
AddEventHandler('cm-spawn:client:spawnPreparationFailed', function(reason)
    recoverFromBlackScreen(reason or 'spawn_preparation_failed', 'Failed to prepare your spawn. Please reconnect or try again.')
end)

RegisterNUICallback('uiReady', function(data, cb)
    nuiReady = true
    cb('ok')
    if pendingSelectorPayload then
        sendOpenSelectorPayload()
    end
end)

RegisterNUICallback('selectorRendered', function(data, cb)
    selectorRenderConfirmed = true
    dprint('selector render acknowledged by NUI')
    cb('ok')
end)

RegisterNetEvent('cm-spawn:client:openSelector')
AddEventHandler('cm-spawn:client:openSelector', function(spawns, appearance, playerInfo)
    dprint('Opening spawn selector')
    isInSpawn = true
    pendingAppearance = appearance
    selectorRenderConfirmed = false
    openSelectorAttempt = 0
    selectorOpenGeneration = selectorOpenGeneration + 1
    local myGeneration = selectorOpenGeneration
    setLocalState('isInSpawnSelector', true, true)
    setLocalState('spawnSelectorOpen', true, true)
    setLocalState('cmSpawnOpen', true, true)
    setLocalState('cmSpawnActive', true, true)
    setHudState('spawnSelector', true)
    setCmHudVisible(false, 'spawn_selector')

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetPlayerControl(PlayerId(), false, 0)

    spawnCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(spawnCam, -1037.0, -2737.0, 180.0)
    PointCamAtCoord(spawnCam, -1037.0, -2737.0, 13.8)
    SetCamFov(spawnCam, 80.0)
    SetCamActive(spawnCam, true)
    RenderScriptCams(true, true, 1000, true, true)

    -- Apply synced weather/time before the player sees the spawn page.
    preloadClimateForSpawnPage()

    pendingSelectorPayload = { spawns = spawns or {}, player = playerInfo or {} }
    -- NUI READY HANDSHAKE: if app.js hasn't posted uiReady yet (page just
    -- (re)loaded from a resource restart), sending now would be lost --
    -- store it and the uiReady callback above replays it the moment the
    -- page confirms it's listening. If it's already ready, send immediately.
    if nuiReady then
        sendOpenSelectorPayload()
    else
        dprint('NUI not ready yet, deferring openSelector until uiReady')
    end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    watchSelectorRendered(myGeneration)

    -- FOCUS OWNERSHIP: guard against another resource's own open/close NUI
    -- courtesy sync racing this a moment later and clearing focus cm-spawn
    -- just took (see client/appearance.lua's openAppearanceService for the
    -- exact same proven pattern in this codebase). Only re-asserts while the
    -- selector is still genuinely open for this same instance.
    CreateThread(function()
        Wait(400)
        if isInSpawn then
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
        end
    end)
end)

-- PHASE 5 (Critical Bug 1/2 fix): a spawn card click or the accepted-spawn
-- event must never itself release the private bucket. beginSpawn only
-- prepares the player (hidden, frozen, still in their private bucket) at the
-- server-validated destination, then reports readiness; the server alone
-- decides when the bucket actually becomes public
-- (cm-spawn:server:readyForPublicWorld -> resetPlayerWorldState).
RegisterNetEvent('cm-spawn:client:beginSpawn')
AddEventHandler('cm-spawn:client:beginSpawn', function(spawnKey, isFirstTime, coords, appearance, generation)
    dprint('Preparing spawn at ' .. tostring(spawnKey))
    spawnTransitionGeneration = spawnTransitionGeneration + 1
    local transitionGeneration = spawnTransitionGeneration
    spawnTransitionActive = true
    selectingSpawn = false
    startSpawnRecoveryWatchdog(transitionGeneration)

    local isDeadSpawn = spawnKey == 'dead_location'

    isInSpawn = false
    pendingAppearance = nil
    setLocalState('isInSpawnSelector', false, true)
    setLocalState('spawnSelectorOpen', false, true)
    setLocalState('cmSpawnOpen', false, true)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeSelector' })
    setHudState('spawnSelector', false)
    setCmHudVisible(false, 'spawning')

    cleanupSpawnCam(true)

    local spawnCoords = coords or vector4(-1037.0, -2737.0, 13.8, 0.0)

    DoScreenFadeOut(250)
    Wait(300)

    TriggerEvent('cm-characters:client:cleanupAppearance')
    local ped = preparePlayerAtSpawn(spawnCoords, appearance)
    SetFocusEntity(ped)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    if transitionGeneration ~= spawnTransitionGeneration then return end

    -- Stay hidden/frozen/private here. Only report readiness -- the server
    -- decides if/when the bucket actually becomes public.
    lastPreparedSpawnCoords = spawnCoords
    lastPreparedIsDead = isDeadSpawn
    TriggerServerEvent('cm-spawn:server:readyForPublicWorld', generation)
end)

-- PHASE 5: server has moved the player into bucket 0 (they are now at the
-- real, already-prepared destination, still frozen/hidden). Only now do we
-- run the camera reveal and hand control back.
RegisterNetEvent('cm-spawn:client:revealAfterPublicWorld')
AddEventHandler('cm-spawn:client:revealAfterPublicWorld', function(generation)
    if generation ~= spawnTransitionGeneration then return end

    local spawnCoords = lastPreparedSpawnCoords or vector4(-1037.0, -2737.0, 13.8, 0.0)
    local isDeadSpawn = lastPreparedIsDead == true

    local ped = PlayerPedId()
    local skyCam, landCam = setupSkyToPlayerCamera(spawnCoords)
    makePlayerVisible(ped)
    FreezeEntityPosition(ped, true)
    SetPlayerControl(PlayerId(), false, 0)
    DoScreenFadeIn(350)
    Wait(350)

    playSkyToPlayerCamera(skyCam, landCam)

    ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetPlayerControl(PlayerId(), true, 0)
    makePlayerVisible(ped)
    setHudState('spawnSelector', false)
    setHudState('spawning', false)
    setLocalState('cmSpawnActive', false, true)
    setLocalState('characterFullySpawned', true, true)
    setLocalState('cmSpawned', true, true)
    setLocalState('isSpawned', true, true)

    if isDeadSpawn then
        -- We used NetworkResurrectLocalPlayer only to place the ped cleanly.
        -- Immediately put the player back into the downed threshold so
        -- cm-playerdata can reopen the deathscreen after spawn completion.
        SetEntityHealth(ped, 101)
        SetPedArmour(ped, 0)
        SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
        SetPlayerHealthRechargeLimit(PlayerId(), 0.0)
        setCmHudVisible(false, 'dead_spawn_complete')
        DisplayRadar(false)
    else
        enablePlayerCombat(ped)
        setCmHudVisible(true, 'spawn_complete')
        DisplayRadar(true)
    end

    TriggerEvent('cm-core:playerSpawned')
    TriggerEvent('cm-spawn:client:spawned')
    TriggerEvent('cm-spawn:client:spawnComplete')
    TriggerServerEvent('cm-spawn:server:spawnComplete', generation)
    spawnTransitionActive = false
end)

-- PHASE 5: server rejected a spawn selection (invalid/locked/rate-limited/no
-- pending draft/etc). The selector never actually closed for this, so just
-- clear the local selection lock and let the NUI show the reason and re-open
-- its cards. The player remains exactly where/how they were: private,
-- hidden, skipPositionSave still true.
RegisterNetEvent('cm-spawn:client:spawnRejected')
AddEventHandler('cm-spawn:client:spawnRejected', function(reason)
    selectingSpawn = false
    SendNUIMessage({ action = 'spawnRejected', reason = reason })
end)

RegisterNUICallback('selectSpawn', function(data, cb)
    local key = data and data.spawnKey
    dprint('selectSpawn callback: ' .. tostring(key))
    if type(key) ~= 'string' or selectingSpawn then
        cb({ ok = false })
        return
    end
    -- CRITICAL BUG FIX (Phase 5): do not release the private bucket or close
    -- the UI here. This is an untrusted NUI click; only the server's
    -- acceptance (cm-spawn:client:beginSpawn) may start the transition.
    selectingSpawn = true
    TriggerServerEvent('cm-spawn:server:selectSpawn', key)
    cb({ ok = true })
end)

RegisterNUICallback('closeSpawn', function(_, cb)
    -- PHASE 5 SECURITY FIX (Critical Bug 3): this used to be a generic
    -- recovery path that could mark a pre-spawn player as fully spawned and
    -- force them into the public bucket from an untrusted NUI call. It must
    -- never do that again. It is now a no-op while any spawn transition is
    -- active -- the beginSpawn/readyForPublicWorld/spawnComplete handshake is
    -- the only thing allowed to own bucket/completion state.
    if spawnTransitionActive then
        cb({ ok = false })
        return
    end

    isInSpawn = false
    selectingSpawn = false
    setLocalState('isInSpawnSelector', false, true)
    setLocalState('spawnSelectorOpen', false, true)
    setLocalState('cmSpawnOpen', false, true)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeSelector' })
    cleanupSpawnCam(false)
    setHudState('spawnSelector', false)
    cb({ ok = true })
end)

AddEventHandler('cm-spawn:client:spawned', function()
    CreateThread(function()
        local untilTime = GetGameTimer() + 15000
        while GetGameTimer() < untilTime do
            enablePlayerCombat(PlayerPedId())
            Wait(1000)
        end
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    cleanupSpawnCam(true)
    makePlayerVisible(PlayerPedId())
    DisplayRadar(true)
    setLocalState('isInSpawnSelector', false, true)
    setLocalState('spawnSelectorOpen', false, true)
    setLocalState('cmSpawnOpen', false, true)
    setLocalState('cmSpawnActive', false, true)
end)

-- Resource restarts can interrupt a fade owned by another client script. Once
-- this player is confirmed spawned, recover only a fade that remains black for
-- several seconds and only when no selector/spawn transition is active.
CreateThread(function()
    local fadedSince = nil

    while true do
        Wait(1500)

        local state = LocalPlayer and LocalPlayer.state or {}
        local spawned = state.characterFullySpawned == true
            or state.cmSpawned == true
            or state.isSpawned == true
        local faded = IsScreenFadedOut() or IsScreenFadingOut()

        if spawned and faded and not hasProtectedScreenFlow(state) then
            fadedSince = fadedSince or GetGameTimer()
            if GetGameTimer() - fadedSince >= 6000 then
                DoScreenFadeIn(350)
                print(('[%s] WARNING: recovered a stuck black screen fade'):format(RESOURCE))
                fadedSince = nil
            end
        else
            fadedSince = nil
        end
    end
end)

if cfg('EnableClientFixCommand', false) then
    RegisterCommand('cmfixcombat', function()
        makePlayerVisible(PlayerPedId())
        enablePlayerCombat(PlayerPedId())
        TriggerServerEvent('cm-spawn:server:resetWorldState', true)
        print('[CM-SPAWN] Combat/world state refreshed for this player')
    end, false)
end
