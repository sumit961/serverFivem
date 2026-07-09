-- cm-spawn/client/main.lua
-- Production-ready spawn client. Handles spawn selector UI, pre-spawn climate handoff,
-- final teleport/camera reveal, and HUD/minimap restore.

local spawnCam = nil
local isInSpawn = false
local pendingAppearance = nil
local RESOURCE = 'CM-SPAWN'
local HudStateCache = {}
local LastHudVisible = nil
local ClimatePagePreparedUntil = 0

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

RegisterNetEvent('cm-spawn:client:openSelector')
AddEventHandler('cm-spawn:client:openSelector', function(spawns, appearance, playerInfo)
    dprint('Opening spawn selector')
    isInSpawn = true
    pendingAppearance = appearance
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

    SendNUIMessage({
        action = 'openSelector',
        spawns = spawns or {},
        player = playerInfo or {}
    })
    SetNuiFocus(true, true)
end)

RegisterNetEvent('cm-spawn:client:spawn')
AddEventHandler('cm-spawn:client:spawn', function(spawnKey, isFirstTime, coords, appearance)
    dprint('Spawning at ' .. tostring(spawnKey))
    local isDeadSpawn = spawnKey == 'dead_location'

    TriggerServerEvent('cm-characters:server:leaveSelectorBucket')
    TriggerServerEvent('cm-spawn:server:resetWorldState', false)

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
    TriggerServerEvent('cm-spawn:server:spawnComplete')
end)

RegisterNUICallback('selectSpawn', function(data, cb)
    local key = data and data.spawnKey
    if type(key) ~= 'string' then
        cb({ ok = false })
        return
    end
    TriggerServerEvent('cm-characters:server:leaveSelectorBucket')
    TriggerServerEvent('cm-spawn:server:selectSpawn', key)
    cb({ ok = true })
end)

RegisterNUICallback('closeSpawn', function(_, cb)
    -- Spawn selector should normally not close without a selected spawn. This is kept as
    -- a recovery path for dev/test or tutorial skip calls.
    isInSpawn = false
    setLocalState('isInSpawnSelector', false, true)
    setLocalState('spawnSelectorOpen', false, true)
    setLocalState('cmSpawnOpen', false, true)
    setLocalState('cmSpawnActive', false, true)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeSelector' })
    cleanupSpawnCam(false)
    makePlayerVisible(PlayerPedId())
    enablePlayerCombat(PlayerPedId())
    TriggerServerEvent('cm-spawn:server:resetWorldState', true)
    setHudState('spawnSelector', false)
    setHudState('spawning', false)
    setLocalState('cmSpawnActive', false, true)
    setLocalState('characterFullySpawned', true, true)
    setLocalState('cmSpawned', true, true)
    setLocalState('isSpawned', true, true)
    setCmHudVisible(true, 'spawn_close_recovery')
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

if cfg('EnableClientFixCommand', false) then
    RegisterCommand('cmfixcombat', function()
        makePlayerVisible(PlayerPedId())
        enablePlayerCombat(PlayerPedId())
        TriggerServerEvent('cm-spawn:server:resetWorldState', true)
        print('[CM-SPAWN] Combat/world state refreshed for this player')
    end, false)
end
