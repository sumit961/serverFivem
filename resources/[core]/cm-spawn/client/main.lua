-- cm-spawn/client/main.lua

local spawnCam = nil
local isInSpawn = false
local pendingAppearance = nil

local function setCmHudVisible(visible)
    DisplayRadar(visible == true)
    LocalPlayer.state:set('cmHudHidden', visible ~= true, true)
    TriggerEvent('cm-hud:client:setVisible', visible == true)
    TriggerEvent('cm-hud:client:toggle', visible == true)
    TriggerEvent('cm-hud:client:hide', visible ~= true)
    if GetResourceState('cm-hud') == 'started' then
        pcall(function() exports['cm-hud']:SetVisible(visible == true) end)
        pcall(function() exports['cm-hud']:ToggleHud(visible == true) end)
        pcall(function() exports['cm-hud']:HideHud(visible ~= true) end)
    end
end

local function enablePlayerCombat(ped)
    ped = ped or PlayerPedId()

    -- Re-enable normal player-to-player damage after character selector/spawn protection.
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
    -- Undo selector invisibility guards from cm-characters before the camera reveal.
    pcall(function() NetworkSetEntityInvisibleToNetwork(ped, false) end)
    pcall(function() SetLocalPlayerVisibleLocally(true) end)
    ResetEntityAlpha(ped)
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

    if appearance then
        print('[CM-SPAWN] Applying appearance before camera reveal...')
        TriggerEvent('cm-characters:client:applyAppearance', appearance)
        Wait(450)
    else
        print('[CM-SPAWN] No appearance, using default')
        SetPedDefaultComponentVariation(ped)
        Wait(100)
    end

    ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(ped, heading)
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, true)

    -- IMPORTANT: cm-characters hides the real player with local/network guards.
    -- Reset those guards here, BEFORE the sky camera starts, so the camera lands on
    -- an already-spawned ped instead of the ped popping in at the end.
    pcall(function() NetworkSetEntityInvisibleToNetwork(ped, false) end)
    pcall(function() SetLocalPlayerVisibleLocally(true) end)
    ResetEntityAlpha(ped)
    SetEntityAlpha(ped, 255, false)
    SetEntityVisible(ped, true, false)
    ClearPedTasksImmediately(ped)

    -- Give GTA one short frame window to render/stream the ped while the screen is black.
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

-- Open spawn selector (returning players)
RegisterNetEvent('cm-spawn:client:openSelector')
AddEventHandler('cm-spawn:client:openSelector', function(spawns, appearance, playerInfo)
    print('[CM-SPAWN] Opening spawn selector')
    isInSpawn = true
    pendingAppearance = appearance
    setCmHudVisible(false)

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

    SendNUIMessage({
        action = 'openSelector',
        spawns = spawns,
        player = playerInfo
    })
    SetNuiFocus(true, true)
end)

-- Actual spawn teleport
RegisterNetEvent('cm-spawn:client:spawn')
AddEventHandler('cm-spawn:client:spawn', function(spawnKey, isFirstTime, coords, appearance)
    print('[CM-SPAWN] Spawning at ' .. tostring(spawnKey))

    -- Leave the private character-selector world before final spawn.
    -- If cm-characters does not have this event, this call is harmless.
    TriggerServerEvent('cm-characters:server:leaveSelectorBucket')
    TriggerServerEvent('cm-spawn:server:resetWorldState', false)

    isInSpawn = false
    pendingAppearance = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeSelector' })
    setCmHudVisible(false)

    cleanupSpawnCam(true)

    local spawnCoords = coords or vector4(-1037.0, -2737.0, 13.8, 0.0)

    -- Keep the screen black while we move, load collision, and apply the real character skin.
    -- This prevents the default Michael/free-mode blink before the sky camera starts.
    DoScreenFadeOut(250)
    Wait(300)

    TriggerEvent('cm-characters:client:cleanupAppearance')
    local ped = preparePlayerAtSpawn(spawnCoords, appearance)
    SetFocusEntity(ped)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    -- Player is already at the selected spawn and already visible before this camera starts.
    local skyCam, landCam = setupSkyToPlayerCamera(spawnCoords)
    -- Final visibility pass before fade-in/camera movement.
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
    enablePlayerCombat(ped)
    setCmHudVisible(true)

    print('[CM-SPAWN] Spawn complete')
    TriggerEvent('cm-core:playerSpawned')
    TriggerEvent('cm-spawn:client:spawned')
    TriggerServerEvent('cm-spawn:server:spawnComplete')
end)

RegisterNUICallback('selectSpawn', function(data, cb)
    print('[CM-SPAWN] selectSpawn: ' .. tostring(data.spawnKey))
    TriggerServerEvent('cm-characters:server:leaveSelectorBucket')
    TriggerServerEvent('cm-spawn:server:selectSpawn', data.spawnKey)
    cb('ok')
end)

RegisterNUICallback('closeSpawn', function(data, cb)
    isInSpawn = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeSelector' })
    cleanupSpawnCam(false)
    makePlayerVisible(PlayerPedId())
    enablePlayerCombat(PlayerPedId())
    TriggerServerEvent('cm-spawn:server:resetWorldState', true)
    setCmHudVisible(true)
    cb('ok')
end)


AddEventHandler('cm-spawn:client:spawned', function()
    CreateThread(function()
        -- Some resources/skin changes can briefly re-apply spawn protection.
        -- Refresh combat for a short safe window only, so future admin/death scripts are not fighting this loop forever.
        local untilTime = GetGameTimer() + 15000
        while GetGameTimer() < untilTime do
            enablePlayerCombat(PlayerPedId())
            Wait(1000)
        end
    end)
end)

RegisterCommand('cmfixcombat', function()
    makePlayerVisible(PlayerPedId())
    enablePlayerCombat(PlayerPedId())
    TriggerServerEvent('cm-spawn:server:resetWorldState', true)
    print('[CM-SPAWN] Combat/world state refreshed for this player')
end, false)
