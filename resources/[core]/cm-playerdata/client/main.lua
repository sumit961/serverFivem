-- cm-playerdata/client/main.lua
-- v1.7 Medical Layer.
--   * NUI death screen: bleed-out timer, killed-by line, [1] Call Ambulance / [2] Give Up
--   * Ambulance: +extra bleed time, overlay swaps to a mini timer, lying pose changes
--   * Death cam: slow orbit around the body + grayscale screen effect
--   * Street patch: another player treats the body -> back up at partial health
-- No hunger/thirst/stress. No injured walkstyle effects.

local Config = CMPlayerData.Config
local Medical = Config.Medical or {}
local PlayerData = {}
local isDead = false
local isSpawning = false
local deathPending = false
local ambulanceCalled = false
local dieChosen = false
local deathCam = nil
local lastHealth = 200
local lastArmor = 0
local lastVitalsSync = 0
local lastPositionSync = 0

local function Debug(msg)
    if Config.Debug then
        print('[CM-PLAYERDATA-CLIENT] ' .. tostring(msg))
    end
end

-- ---------------------------------------------------------------------------
-- Death visuals
-- ---------------------------------------------------------------------------
local function StartDeathEffect()
    if Medical.DeathEffect == false then return end
    AnimpostfxPlay('DeathFailOut', 0, true)
end

local function StopDeathEffect()
    AnimpostfxStop('DeathFailOut')
end

local function StartDeathCam()
    if Medical.DeathCam == false then return end
    if deathCam then return end

    deathCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(deathCam, true)
    RenderScriptCams(true, true, 750, true, true)

    CreateThread(function()
        local radius = Medical.DeathCamRadius or 3.4
        local height = Medical.DeathCamHeight or 1.6
        local speed = Medical.DeathCamSpeed or 0.25 -- degrees per frame at 60fps

        local angle = 0.0
        while deathCam and isDead do
            Wait(0)
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)

            angle = angle + speed
            if angle >= 360.0 then angle = angle - 360.0 end
            local rad = math.rad(angle)

            SetCamCoord(deathCam,
                coords.x + math.cos(rad) * radius,
                coords.y + math.sin(rad) * radius,
                coords.z + height)
            PointCamAtEntity(deathCam, ped, 0.0, 0.0, 0.3, true)
        end
    end)
end

local function StopDeathCam()
    if not deathCam then return end
    RenderScriptCams(false, true, 750, true, true)
    DestroyCam(deathCam, false)
    deathCam = nil
end

-- Keep the body lying down for the whole dead period. Initial ragdoll, then a
-- looped dead pose. Calling the ambulance switches to a different pose.
local function PlayLyingPose()
    local ped = PlayerPedId()
    local anim = ambulanceCalled and (Medical.AmbulancePose or 'dead_b') or (Medical.DeadPose or 'dead_a')

    RequestAnimDict('dead')
    local tries = 0
    while not HasAnimDictLoaded('dead') and tries < 100 do
        Wait(10)
        tries = tries + 1
    end

    if HasAnimDictLoaded('dead') then
        TaskPlayAnim(ped, 'dead', anim, 8.0, -8.0, -1, 1, 0.0, false, false, false)
    end
end

local function ManageLyingBody()
    CreateThread(function()
        local ped = PlayerPedId()
        SetPedToRagdoll(ped, 4000, 4000, 0, false, false, false)
        Wait(4200)

        local lastPose = nil
        while isDead do
            ped = PlayerPedId()
            local wantedPose = ambulanceCalled and 'amb' or 'norm'
            if not IsEntityPlayingAnim(ped, 'dead', ambulanceCalled and (Medical.AmbulancePose or 'dead_b') or (Medical.DeadPose or 'dead_a'), 3)
                or wantedPose ~= lastPose then
                PlayLyingPose()
                lastPose = wantedPose
            end
            Wait(1500)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Death state
-- ---------------------------------------------------------------------------
function EnterDeathState(killedBy, bleedMs)
    if isDead then return end
    isDead = true
    ambulanceCalled = false
    dieChosen = false

    local ped = PlayerPedId()
    SetEntityHealth(ped, Config.Vitals.DamageThreshold)
    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    SetPlayerHealthRechargeLimit(PlayerId(), 0.0)

    IgnoreNextRestart(true)
    StartDeathEffect()
    StartDeathCam()
    ManageLyingBody()

    SendNUIMessage({
        action = 'openDeathScreen',
        remainingMs = tonumber(bleedMs) or ((Config.Respawn and Config.Respawn.BleedOutTime) or 120000),
        killedBy = killedBy -- { label = 'musa bhai' or 'Stranger', charId = 13 } or nil
    })

    -- Mouse cursor for the two buttons; released after either choice.
    SetNuiFocusKeepInput(false)
    SetNuiFocus(true, true)

    CreateThread(function()
        while isDead do
            Wait(0)
            DisableAllControlActions(0)
            EnableControlAction(0, 245, true) -- chat stays available
        end
    end)

    lastHealth = Config.Vitals.DamageThreshold
end

local function CleanupDeathState()
    isDead = false
    ambulanceCalled = false
    dieChosen = false
    SetNuiFocus(false, false)
    StopDeathCam()
    StopDeathEffect()
    SendNUIMessage({ action = 'closeDeathScreen' })
    ClearPedTasks(PlayerPedId())
end

function ExitDeathState()
    CleanupDeathState()
end

-- ---------------------------------------------------------------------------
-- Data / vitals
-- ---------------------------------------------------------------------------
local function ApplyLoadedData(data)
    PlayerData = data or {}
    lastHealth = PlayerData.health or Config.Vitals.MaxHealth
    lastArmor = PlayerData.armor or 0

    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    SetPlayerHealthRechargeLimit(PlayerId(), 0.0)

    local ped = PlayerPedId()
    SetEntityHealth(ped, lastHealth)
    SetPedArmour(ped, lastArmor)

    if PlayerData.isDead then
        EnterDeathState(nil, (Config.Respawn and Config.Respawn.BleedOutTime) or 120000)
    else
        ExitDeathState()
    end
end

RegisterNetEvent('cm-playerdata:client:loaded', ApplyLoadedData)

RegisterNetEvent('cm-playerdata:client:update', function(key, value)
    PlayerData[key] = value
end)

RegisterNetEvent('cm-playerdata:client:setHealth', function(health)
    local ped = PlayerPedId()
    health = tonumber(health) or Config.Vitals.MaxHealth
    SetEntityHealth(ped, health)
    lastHealth = health
end)

local function BuildDeathReport(ped)
    local report = { killerServerId = nil, causeHash = nil, killerType = 'unknown' }

    report.causeHash = GetPedCauseOfDeath(ped)

    local killerEntity = GetPedSourceOfDeath(ped)
    if killerEntity and killerEntity ~= 0 and DoesEntityExist(killerEntity) then
        if IsEntityAVehicle(killerEntity) then
            report.killerType = 'vehicle'
            local driver = GetPedInVehicleSeat(killerEntity, -1)
            if driver and driver ~= 0 then killerEntity = driver end
        end

        if IsEntityAPed(killerEntity) and IsPedAPlayer(killerEntity) then
            local killerIndex = NetworkGetPlayerIndexFromPed(killerEntity)
            if killerIndex ~= -1 then
                local sid = GetPlayerServerId(killerIndex)
                if sid and sid > 0 and sid ~= GetPlayerServerId(PlayerId()) then
                    report.killerServerId = sid
                    report.killerType = report.killerType == 'vehicle' and 'player_vehicle' or 'player'
                end
            end
        elseif IsEntityAPed(killerEntity) then
            report.killerType = 'npc'
        end
    end

    if not report.killerServerId and report.killerType == 'unknown' then
        report.killerType = 'environment'
    end

    return report
end

-- Server tells us we are dead, including who killed us (name only if we know them)
-- and how long the bleed-out is.
RegisterNetEvent('cm-playerdata:client:playerDied', function(killerSrc, weaponHash, killedBy, bleedMs)
    deathPending = false
    EnterDeathState(killedBy, bleedMs)
end)

-- ---------------------------------------------------------------------------
-- Engine death interception. Massive damage (headshot/explosion) can zero the
-- ped's health between vitals checks: the ped truly dies and GTA starts its
-- native wasted sequence (grayscale wobble, slow-mo, fade) over our death flow.
-- Watcher: the instant the ped is fatally injured, resurrect them in place,
-- clamp health to the downed threshold and route into our own death state.
-- ---------------------------------------------------------------------------
CreateThread(function()
    -- Never let the engine run its own death/arrest restart or fades.
    PauseDeathArrestRestart(true)
    SetFadeOutAfterDeath(false)
    -- If spawnmanager is ever added to the server, keep its autospawn off too.
    pcall(function()
        if GetResourceState('spawnmanager') == 'started' then
            exports.spawnmanager:setAutoSpawn(false)
        end
    end)

    while true do
        Wait(100)

        if LocalPlayer.state.playerDataLoaded and not isDead and not isSpawning and not deathPending then
            local ped = PlayerPedId()
            if IsPedFatallyInjured(ped) or IsEntityDead(ped) then
                deathPending = true

                -- Read killer info BEFORE resurrecting (death source is cleared after).
                local report = BuildDeathReport(ped)
                local coords = GetEntityCoords(ped)
                local heading = GetEntityHeading(ped)

                NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
                local newPed = PlayerPedId()
                SetEntityHealth(newPed, Config.Vitals.DamageThreshold)
                SetPedToRagdoll(newPed, 2000, 2000, 0, false, false, false)

                TriggerServerEvent('cm-playerdata:server:playerDied', report.killerServerId, report.causeHash, report.killerType)

                -- Failsafe: if the server event is lost, don't stay stuck forever.
                SetTimeout(4000, function()
                    if deathPending and not isDead then
                        deathPending = false
                        EnterDeathState(nil, (Config.Respawn and Config.Respawn.BleedOutTime) or 120000)
                    end
                end)
            end
        end
    end
end)

-- Ambulance accepted by the server: overlay swaps to the mini timer,
-- the lying pose changes, the player stays dead.
RegisterNetEvent('cm-playerdata:client:ambulanceConfirmed', function(newRemainingMs)
    if not isDead then return end
    ambulanceCalled = true
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'ambulanceMode',
        remainingMs = tonumber(newRemainingMs) or 0
    })
end)

RegisterNetEvent('cm-playerdata:client:canRespawn', function()
    -- kept for backward compatibility; bleed-out handles respawn now
end)

RegisterNetEvent('cm-playerdata:client:revive', function()
    ExitDeathState()
    local ped = PlayerPedId()
    SetEntityHealth(ped, Config.Vitals.MaxHealth)
    SetPedArmour(ped, 0)
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedTasksImmediately(ped)
end)

-- Street patch: back on your feet at partial health (no teleport, no full heal).
RegisterNetEvent('cm-playerdata:client:revivePartial', function(health)
    ExitDeathState()
    local ped = PlayerPedId()
    health = tonumber(health) or math.floor(Config.Vitals.MaxHealth * 0.3)
    SetEntityHealth(ped, health)
    ClearPedTasksImmediately(ped)
    lastHealth = health
end)

RegisterNetEvent('cm-playerdata:client:respawn', function(spawn)
    isSpawning = true
    ExitDeathState()

    spawn = spawn or Config.Respawn.HospitalSpawn
    local ped = PlayerPedId()

    DoScreenFadeOut(500)
    Wait(600)

    NetworkResurrectLocalPlayer(spawn.x, spawn.y, spawn.z, spawn.h or 0.0, true, false)
    SetEntityCoordsNoOffset(ped, spawn.x, spawn.y, spawn.z, false, false, false)
    SetEntityHeading(ped, spawn.h or 0.0)

    lastHealth = Config.Vitals.MaxHealth
    lastArmor = 0
    SetEntityHealth(ped, Config.Vitals.MaxHealth)
    SetPedArmour(ped, 0)

    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetPlayerControl(PlayerId(), true, 0)

    Wait(1000)
    DoScreenFadeIn(500)
    isSpawning = false
end)

-- ---------------------------------------------------------------------------
-- Treatment (the treater's side): kneel + progress, then confirm to the server.
-- ---------------------------------------------------------------------------
RegisterNetEvent('cm-playerdata:client:startTreatment', function(duration)
    duration = tonumber(duration) or 8000
    local ped = PlayerPedId()

    local finished = false

    if GetResourceState('ox_lib') == 'started' and type(lib) == 'table' and type(lib.progressCircle) == 'function' then
        finished = lib.progressCircle({
            duration = duration,
            label = 'Patching up...',
            position = 'bottom',
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base' }
        })
    else
        RequestAnimDict('amb@medic@standing@kneel@base')
        local tries = 0
        while not HasAnimDictLoaded('amb@medic@standing@kneel@base') and tries < 100 do
            Wait(10); tries = tries + 1
        end
        TaskPlayAnim(ped, 'amb@medic@standing@kneel@base', 'base', 8.0, -8.0, -1, 1, 0.0, false, false, false)
        Wait(duration)
        ClearPedTasks(ped)
        finished = true
    end

    TriggerServerEvent('cm-playerdata:server:treatComplete', finished == true)
end)

-- ---------------------------------------------------------------------------
-- Vitals + position sync
-- ---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(500)

        if LocalPlayer.state.isLoggedIn and LocalPlayer.state.playerDataLoaded and not isDead and not isSpawning then
            local ped = PlayerPedId()
            local currentHealth = GetEntityHealth(ped)
            local currentArmor = GetPedArmour(ped)

            if currentHealth < lastHealth then
                if currentHealth <= Config.Vitals.DamageThreshold then
                    SetEntityHealth(ped, Config.Vitals.DamageThreshold)
                    local report = BuildDeathReport(ped)
                    TriggerServerEvent('cm-playerdata:server:playerDied', report.killerServerId, report.causeHash, report.killerType)
                else
                    lastHealth = currentHealth
                end
            elseif currentHealth > lastHealth then
                lastHealth = currentHealth
            end

            local now = GetGameTimer()
            if now - lastVitalsSync >= Config.Vitals.HealthSyncInterval then
                lastVitalsSync = now
                TriggerServerEvent('cm-playerdata:server:syncVitals', currentHealth, currentArmor)
            end

            if now - lastPositionSync >= Config.Vitals.PositionSyncInterval then
                lastPositionSync = now
                local coords = GetEntityCoords(ped)
                TriggerServerEvent('cm-playerdata:server:updatePosition', {
                    x = math.floor(coords.x * 100) / 100,
                    y = math.floor(coords.y * 100) / 100,
                    z = math.floor(coords.z * 100) / 100,
                    h = math.floor(GetEntityHeading(ped) * 100) / 100
                })
            end
        else
            Wait(1000)
        end
    end
end)

RegisterNUICallback('deathAmbulance', function(_, cb)
    cb({})
    if isDead and not ambulanceCalled and not dieChosen then
        TriggerServerEvent('cm-playerdata:server:callAmbulance')
    end
end)

RegisterNUICallback('deathDie', function(_, cb)
    cb({})
    if isDead and not ambulanceCalled and not dieChosen then
        dieChosen = true
        TriggerServerEvent('cm-playerdata:server:chooseDie')
        SendNUIMessage({ action = 'deathChoice', choice = 'die' })
        SetNuiFocus(false, false)
    end
end)

RegisterCommand('pdstatus', function()
    print(('[CM-PLAYERDATA] HP=%s Armor=%s Dead=%s'):format(
        tostring(PlayerData.health),
        tostring(PlayerData.armor),
        tostring(isDead)
    ))
end, false)
