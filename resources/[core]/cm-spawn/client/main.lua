-- cm-spawn/client/main.lua

local spawnCam = nil
local isInSpawn = false
local pendingAppearance = nil

-- Open spawn selector (returning players)
RegisterNetEvent('cm-spawn:client:openSelector')
AddEventHandler('cm-spawn:client:openSelector', function(spawns, appearance, playerInfo)
    print('[CM-SPAWN] Opening spawn selector')
    isInSpawn = true
    pendingAppearance = appearance

    -- Freeze and hide player while choosing
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)

    -- Sky camera
    spawnCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(spawnCam, -1037.0, -2737.0, 100.0)
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

    isInSpawn = false
    pendingAppearance = nil
    SetNuiFocus(false, false)

    -- Destroy selector camera
    if spawnCam and DoesCamExist(spawnCam) then
        RenderScriptCams(false, true, 1000, true, true)
        DestroyCam(spawnCam, false)
        spawnCam = nil
    end

    -- Cleanup character creator camera if it exists
    TriggerEvent('cm-characters:client:cleanupAppearance')

    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)

    DoScreenFadeOut(500)
    Wait(500)

    -- Teleport
    local spawnCoords = coords or vector4(-1037.0, -2737.0, 13.8, 0.0)
    SetEntityCoords(ped, spawnCoords.x, spawnCoords.y, spawnCoords.z)
    SetEntityHeading(ped, spawnCoords.w or spawnCoords.heading or 0.0)
    FreezeEntityPosition(ped, false)

    -- Reset any stuck camera
    RenderScriptCams(false, false, 0, true, true)

    Wait(100)

    -- Apply appearance
    if appearance then
        print('[CM-SPAWN] Applying appearance...')
        TriggerEvent('cm-characters:client:applyAppearance', appearance)
    else
        print('[CM-SPAWN] No appearance, using default')
        SetPedDefaultComponentVariation(ped)
    end

    Wait(500)
    DoScreenFadeIn(500)

    -- REMOVED: Tutorial trigger. Just finish spawn.
    print('[CM-SPAWN] Spawn complete')
    TriggerEvent('cm-core:playerSpawned')
end)

-- NUI callbacks
RegisterNUICallback('selectSpawn', function(data, cb)
    print('[CM-SPAWN] selectSpawn: ' .. tostring(data.spawnKey))
    TriggerServerEvent('cm-spawn:server:selectSpawn', data.spawnKey)
    cb('ok')
end)

RegisterNUICallback('closeSpawn', function(data, cb)
    isInSpawn = false
    SetNuiFocus(false, false)
    cb('ok')
end)