-- cm-playerdata/client/main.lua
-- v1.8 Foundation clean: local cache aliases + money/character loaded events.
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
local sixStarChaseStarted = false

local function applyNativeWantedLevel(stars)
    local maxStars = (Config.WantedStars and Config.WantedStars.Max) or 6
    local nativeLevel = (Config.WantedStars and Config.WantedStars.NativeLevelAtMax) or 5
    local target = (tonumber(stars) or 0) >= maxStars and nativeLevel or 0
    SetPlayerWantedLevel(PlayerId(), target, false)
    SetPlayerWantedLevelNow(PlayerId(), false)
    sixStarChaseStarted = target > 0
end

CreateThread(function()
    while true do
        Wait(2000)
        if sixStarChaseStarted and (tonumber(PlayerData.wantedStars) or 0) >= ((Config.WantedStars and Config.WantedStars.Max) or 6)
            and GetPlayerWantedLevel(PlayerId()) == 0 then
            sixStarChaseStarted = false
            TriggerServerEvent('cm-playerdata:server:aiWantedChaseEscaped')
        end
    end
end)
local deathCam = nil
local pendingDeathData = nil
local hasSpawnCompleted = false
local localDeathDeadline = 0
local respawnRequestSent = false
local finishedOffSent = false
local lastHealth = 200
local lastArmor = 0
local lastVitalsSync = 0
local lastPositionSync = 0

local function Debug(msg)
    if Config.Debug then
        print('[CM-PLAYERDATA-CLIENT] ' .. tostring(msg))
    end
end

local function GetHealthFromPercent(percent)
    percent = tonumber(percent) or 20
    if percent < 1 then percent = 1 end
    if percent > 100 then percent = 100 end

    local aliveMin = (Config.Vitals.DamageThreshold or 101) + 1
    local maxHealth = Config.Vitals.MaxHealth or 200
    if aliveMin >= maxHealth then return maxHealth end
    return math.floor(aliveMin + ((maxHealth - aliveMin) * (percent / 100)))
end

local function GetRespawnHealth()
    local respawn = Config.Respawn or {}
    if respawn.Health then return tonumber(respawn.Health) or Config.Vitals.MaxHealth end
    return GetHealthFromPercent(respawn.HealthPercent or 20)
end

-- Health an unconscious body carries: the downed floor plus a small finishing
-- buffer (UnconsciousHealthPercent of max). Depleting the buffer = finished.
local function GetUnconsciousHealth()
    local threshold = Config.Vitals.DamageThreshold or 101
    local maxHp = Config.Vitals.MaxHealth or 200
    local pct = tonumber(Config.Vitals.UnconsciousHealthPercent) or 10
    if pct < 0 then pct = 0 end
    local hp = threshold + math.floor(maxHp * (pct / 100))
    if hp > maxHp then hp = maxHp end
    if hp < threshold then hp = threshold end
    return hp
end

local function SpawnUiActive()
    if not LocalPlayer or not LocalPlayer.state then return true end
    local state = LocalPlayer.state
    return state.isInCharacterSelector == true
        or state.characterSelectorOpen == true
        or state.isInSpawnSelector == true
        or state.spawnSelectorOpen == true
        or state.cmSpawnOpen == true
        or state.cmSpawnActive == true
        or state.spawnSelector == true
        or state.spawning == true
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
local function StartPendingDeathState()
    if not pendingDeathData or isDead then return end
    if not hasSpawnCompleted or SpawnUiActive() then return end

    local payload = pendingDeathData
    pendingDeathData = nil
    EnterDeathState(payload.killedBy, payload.bleedMs, payload.ambulanceCalled)
end

-- While unconscious, watch the finishing buffer. Once the body has taken enough
-- extra damage to drop back to (or below) the downed floor, the player is
-- "finished" and is sent straight to hospital respawn, skipping the bleed-out.
local function StartDownedFinishMonitor()
    finishedOffSent = false
    local monitorStartedAt = GetGameTimer()
    CreateThread(function()
        local threshold = Config.Vitals.DamageThreshold or 101
        -- The death-interception handler ragdolls the ped for up to 2s right as
        -- this monitor starts (see SetPedToRagdoll in the engine-death thread
        -- below). That settling can still burn fall/impact damage into the
        -- unconscious buffer for a moment after entering the death state, which
        -- must never be mistaken for another player finishing off the body.
        local graceMs = 2500
        local armed = false
        while isDead do
            Wait(50)
            local ped = PlayerPedId()
            local hp = GetEntityHealth(ped)
            if not armed then
                -- Arm only once the unconscious buffer is confirmed in place AND
                -- the post-death ragdoll grace period has elapsed, so neither a
                -- one-frame stale read nor settling fall damage can false-trigger.
                if hp > threshold and GetGameTimer() - monitorStartedAt > graceMs then armed = true end
            elseif (hp <= threshold or IsEntityDead(ped)) and not finishedOffSent and not respawnRequestSent then
                finishedOffSent = true
                respawnRequestSent = true
                TriggerServerEvent('cm-playerdata:server:finishedOff')
                break
            end
        end
    end)
end

function EnterDeathState(killedBy, bleedMs, alreadyAmbulanceCalled)
    if isDead then return end

    -- Close inventory before the death screen takes NUI focus. This also hides
    -- drop pickup cards immediately at the unconscious transition.
    TriggerEvent('cm-inventory:client:forceCloseForDeath')

    isDead = true
    ambulanceCalled = alreadyAmbulanceCalled == true
    dieChosen = false
    respawnRequestSent = false
    finishedOffSent = false
    localDeathDeadline = GetGameTimer() + (tonumber(bleedMs) or ((Config.Respawn and Config.Respawn.BleedOutTime) or 120000))

    local ped = PlayerPedId()
    local unconsciousHealth = GetUnconsciousHealth()
    SetEntityHealth(ped, unconsciousHealth)
    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    SetPlayerHealthRechargeLimit(PlayerId(), 0.0)

    IgnoreNextRestart(true)
    StartDeathEffect()
    StartDeathCam()
    ManageLyingBody()
    StartDownedFinishMonitor()

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
            EnableControlAction(0, 199, true) -- pause/map
            EnableControlAction(0, 200, true) -- pause/map alternate (ESC)
        end
    end)

    -- Client-side watchdog. The server is still authoritative, but this avoids
    -- a dead UI stuck at 00:00 if a rejoin/resource restart lost a timer.
    CreateThread(function()
        while isDead do
            Wait(1000)
            if localDeathDeadline > 0 and GetGameTimer() >= localDeathDeadline and not respawnRequestSent then
                respawnRequestSent = true
                TriggerServerEvent('cm-playerdata:server:requestRespawn')
            end
        end
    end)

    if ambulanceCalled then
        SetNuiFocus(false, false)
        SendNUIMessage({
            action = 'ambulanceMode',
            remainingMs = math.max(0, localDeathDeadline - GetGameTimer())
        })
    end

    lastHealth = unconsciousHealth
end

local function CleanupDeathState()
    isDead = false
    finishedOffSent = false
    ambulanceCalled = false
    dieChosen = false
    respawnRequestSent = false
    localDeathDeadline = 0
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
    applyNativeWantedLevel(PlayerData.wantedStars)
    lastHealth = PlayerData.health or Config.Vitals.MaxHealth
    lastArmor = PlayerData.armor or 0

    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    SetPlayerHealthRechargeLimit(PlayerId(), 0.0)

    local ped = PlayerPedId()
    if PlayerData.isDead then
        SetEntityHealth(ped, GetUnconsciousHealth())
    else
        SetEntityHealth(ped, lastHealth)
    end
    SetPedArmour(ped, lastArmor)

    if PlayerData.isDead then
        pendingDeathData = {
            killedBy = nil,
            bleedMs = tonumber(PlayerData.deathRemainingMs) or ((Config.Respawn and Config.Respawn.BleedOutTime) or 120000),
            ambulanceCalled = PlayerData.ambulanceCalled == true
        }
        SetTimeout(1200, StartPendingDeathState)
    else
        pendingDeathData = nil
        ExitDeathState()
    end
end

RegisterNetEvent('cm-playerdata:client:loaded', ApplyLoadedData)
RegisterNetEvent('cm-playerdata:client:characterLoaded', ApplyLoadedData)

RegisterNetEvent('cm-playerdata:client:unloaded', function()
    PlayerData = {}
    applyNativeWantedLevel(0)
    pendingDeathData = nil
    hasSpawnCompleted = false
    lastHealth = Config.Vitals.MaxHealth
    lastArmor = 0
    ExitDeathState()
end)
RegisterNetEvent('cm-playerdata:client:characterUnloaded', function()
    PlayerData = {}
    applyNativeWantedLevel(0)
    pendingDeathData = nil
    hasSpawnCompleted = false
    lastHealth = Config.Vitals.MaxHealth
    lastArmor = 0
    ExitDeathState()
end)

RegisterNetEvent('cm-playerdata:client:update', function(key, value)
    PlayerData[key] = value
    -- GTA5-style wanted stars: only star Config.WantedStars.Max (6) sets a
    -- real native wanted level -- 1-5 stay a HUD-only counter (cm-hud's own
    -- listener on this same event handles that side). Nothing here ever
    -- touches spawned police entities directly; the native level is all
    -- native GTA needs to spawn AND disperse its own police on its own.
    if key == 'wantedStars' then
        applyNativeWantedLevel(value)
    end
end)

-- Read-only client contract used by cm-population to recover the current
-- threshold after that resource is restarted and missed the original event.
exports('GetWantedStars', function()
    return math.max(0, math.floor(tonumber(PlayerData.wantedStars) or 0))
end)

RegisterNetEvent('cm-playerdata:client:moneyChanged', function(account, before, after, reason)
    account = tostring(account or '')
    if account == 'cash' or account == 'bank' then
        PlayerData[account] = tonumber(after) or 0
    end
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
    pendingDeathData = nil
    EnterDeathState(killedBy, bleedMs)
end)

RegisterNetEvent('cm-playerdata:client:restoreDeathFocus', function()
    if not isDead then return end
    if ambulanceCalled then
        SetNuiFocus(false, false)
    else
        SetNuiFocusKeepInput(false)
        SetNuiFocus(true, true)
    end
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
    respawnRequestSent = false
    localDeathDeadline = GetGameTimer() + (tonumber(newRemainingMs) or 0)
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'ambulanceMode',
        remainingMs = tonumber(newRemainingMs) or 0
    })
end)

RegisterNetEvent('cm-playerdata:client:emsProtectionUpdated', function(payload)
    if not isDead or type(payload) ~= 'table' then return end
    local remainingMs = math.max(0, tonumber(payload.remainingMs) or 0)
    ambulanceCalled = true
    respawnRequestSent = false
    localDeathDeadline = GetGameTimer() + remainingMs
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'emsProtection',
        remainingMs = remainingMs,
        etaMs = math.max(0, tonumber(payload.etaMs) or 0),
        label = tostring(payload.label or 'AI EMS RESPONDING'),
        protected = payload.protected == true,
    })
end)

RegisterNetEvent('cm-playerdata:client:canRespawn', function()
    -- kept for backward compatibility; bleed-out handles respawn now
end)

RegisterNetEvent('cm-playerdata:client:revive', function()
    ExitDeathState()
    local ped = PlayerPedId()
    lastHealth = Config.Vitals.MaxHealth
    SetEntityHealth(ped, lastHealth)
    SetPedArmour(ped, 0)
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedTasksImmediately(ped)
end)

-- Street patch: back on your feet at partial health (no teleport, no full heal).
RegisterNetEvent('cm-playerdata:client:revivePartial', function(health)
    ExitDeathState()
    local ped = PlayerPedId()
    health = tonumber(health) or GetHealthFromPercent(30)
    SetEntityHealth(ped, health)
    ClearPedTasksImmediately(ped)
    lastHealth = health
end)

RegisterNetEvent('cm-playerdata:client:respawn', function(spawn, respawnHealth)
    isSpawning = true
    pendingDeathData = nil
    ExitDeathState()

    spawn = spawn or Config.Respawn.HospitalSpawn
    local ped = PlayerPedId()

    DoScreenFadeOut(500)
    Wait(600)

    NetworkResurrectLocalPlayer(spawn.x, spawn.y, spawn.z, spawn.h or 0.0, true, false)
    SetEntityCoordsNoOffset(ped, spawn.x, spawn.y, spawn.z, false, false, false)
    SetEntityHeading(ped, spawn.h or 0.0)

    lastHealth = tonumber(respawnHealth) or GetRespawnHealth()
    lastArmor = 0
    SetEntityHealth(ped, lastHealth)
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


RegisterNetEvent('cm-spawn:client:spawnComplete', function()
    hasSpawnCompleted = true
    SetTimeout(1000, StartPendingDeathState)
end)

RegisterNetEvent('cm-spawn:client:spawned', function()
    hasSpawnCompleted = true
    SetTimeout(1000, StartPendingDeathState)
end)

RegisterNetEvent('cm-spawn:client:openSelector', function()
    hasSpawnCompleted = false
end)

-- Recovery net for players who are dead but not yet showing the death screen.
-- After a resource/server restart, hasSpawnCompleted resets to false and the
-- spawn resource may not re-emit spawnComplete, so StartPendingDeathState keeps
-- bailing out and the player is stuck in a broken half-dead state. This thread
-- forces the layout back up. It also rebuilds pendingDeathData from the loaded
-- data if it was lost, so a dead player is always re-shown their death screen.
CreateThread(function()
    while true do
        Wait(1500)

        local dataSaysDead = type(PlayerData) == 'table' and PlayerData.isDead == true
        if not isDead and (pendingDeathData or dataSaysDead) then
            if LocalPlayer.state.playerDataLoaded == true and not SpawnUiActive() then
                if not pendingDeathData and dataSaysDead then
                    pendingDeathData = {
                        killedBy = nil,
                        bleedMs = tonumber(PlayerData.deathRemainingMs) or ((Config.Respawn and Config.Respawn.BleedOutTime) or 120000),
                        ambulanceCalled = PlayerData.ambulanceCalled == true
                    }
                end
                hasSpawnCompleted = true
                StartPendingDeathState()
            end
        else
            Wait(3000)
        end
    end
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
            disable = { car = true, combat = true }
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

local receivingTreatment = false
RegisterNetEvent('cm-playerdata:client:treatmentProgress', function(status, duration, medicLabel)
    status = tostring(status or '')
    if status == 'started' then
        receivingTreatment = true
        if lib and lib.notify then
            lib.notify({ title = 'Treatment', description = ('%s is treating you. Stay nearby.'):format(tostring(medicLabel or 'A player')), type = 'inform' })
        end
        CreateThread(function()
            if lib and lib.progressBar then
                lib.progressBar({ duration = math.max(3000, tonumber(duration) or 8000), label = 'Receiving treatment...', useWhileDead = true, canCancel = false })
            else
                Wait(math.max(3000, tonumber(duration) or 8000))
            end
            receivingTreatment = false
        end)
    else
        if receivingTreatment and lib and lib.cancelProgress then pcall(lib.cancelProgress) end
        receivingTreatment = false
        if lib and lib.notify then
            lib.notify({ title = 'Treatment', description = status == 'completed' and 'Treatment completed.' or 'Treatment cancelled.', type = status == 'completed' and 'success' or 'error' })
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Vitals + position sync
-- ---------------------------------------------------------------------------
-- GTA or another resource may re-enable native health recharge after model/spawn
-- changes. Reassert this continuously; all valid healing remains server-driven.
CreateThread(function()
    while true do
        SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
        SetPlayerHealthRechargeLimit(PlayerId(), 0.0)
        Wait(1000)
    end
end)

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
                -- Never accept GTA passive regeneration or another client-side
                -- health increase. Legitimate healing must come through the
                -- authoritative cm-playerdata SetHealth/Heal/revive exports,
                -- whose client events update lastHealth before this loop runs.
                SetEntityHealth(ped, lastHealth)
                currentHealth = lastHealth
            end

            local now = GetGameTimer()
            if now - lastVitalsSync >= (Config.Vitals.HealthSyncInterval or 4000) then
                lastVitalsSync = now
                TriggerServerEvent('cm-playerdata:server:syncVitals', currentHealth, currentArmor)
            end

            -- Never sample/send position while the character-selector/creation
            -- preview scene is active -- its fixed coordinates must never be
            -- mistaken for real gameplay position (server also enforces this;
            -- see cm-playerdata:server:updatePosition).
            if now - lastPositionSync >= (Config.Vitals.PositionSyncInterval or 6000)
                and not SpawnUiActive() and LocalPlayer.state.skipPositionSave ~= true
            then
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

RegisterNUICallback('deathExpired', function(_, cb)
    cb({})
    if isDead and not respawnRequestSent then
        respawnRequestSent = true
        TriggerServerEvent('cm-playerdata:server:requestRespawn')
    end
end)

RegisterNUICallback('deathOpenMap', function(_, cb)
    cb({})
    if not isDead or IsPauseMenuActive() then return end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'deathMapVisibility', hidden = true })
    ActivateFrontendMenu(joaat('FE_MENU_VERSION_MP_PAUSE'), false, -1)
    CreateThread(function()
        Wait(500)
        while isDead and IsPauseMenuActive() do Wait(200) end
        if not isDead then return end
        SendNUIMessage({ action = 'deathMapVisibility', hidden = false })
        if not ambulanceCalled and not dieChosen then
            SetNuiFocusKeepInput(false)
            SetNuiFocus(true, true)
        end
    end)
end)

RegisterCommand('pdstatus', function()
    if Config.Debug ~= true then return end
    print(('[CM-PLAYERDATA] CharID=%s Cash=%s Bank=%s HP=%s Armor=%s Dead=%s'):format(
        tostring(PlayerData.charId or PlayerData.characterId),
        tostring(PlayerData.cash),
        tostring(PlayerData.bank),
        tostring(PlayerData.health),
        tostring(PlayerData.armor),
        tostring(isDead)
    ))
end, false)

exports('GetLocalCharacterId', function()
    return tonumber(PlayerData.charId or PlayerData.characterId or (LocalPlayer and LocalPlayer.state and (LocalPlayer.state.charId or LocalPlayer.state.characterId)))
end)

exports('GetLocalPlayerData', function()
    return PlayerData
end)

exports('GetLocalMoney', function(account)
    account = tostring(account or 'cash'):lower()
    if account == 'money' or account == 'wallet' then account = 'cash' end
    if account == 'account' then account = 'bank' end
    return tonumber(PlayerData[account]) or 0
end)

exports('IsCharacterLoaded', function()
    return LocalPlayer and LocalPlayer.state and LocalPlayer.state.playerDataLoaded == true or false
end)
