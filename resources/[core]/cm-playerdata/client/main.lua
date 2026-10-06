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
local deathScreenActive = false
local lifeState = 'alive'
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
local deathReportPending = false
local respawnRequestSent = false
local lastRespawnRequestAt = 0
local respawnRequestCount = 0
local lastHealth = 200
local lastArmor = 0
local lastVitalsSync = 0
local lastPositionSync = 0
local BuildDeathReport -- pre-declared for forward references

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

-- Deprecated: GTA owns health and native death. Kept for legacy callers only.
local function GetDownedHealth()
    return 0
end
local GetUnconsciousHealth = GetDownedHealth

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
        while deathCam and deathScreenActive do
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

BuildDeathReport = function(ped)
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

-- ---------------------------------------------------------------------------
-- Death state
-- ---------------------------------------------------------------------------
local function StartPendingDeathState()
    if not pendingDeathData or deathScreenActive then return end
    if not hasSpawnCompleted or SpawnUiActive() then return end

    local payload = pendingDeathData
    pendingDeathData = nil
    EnterDeathState(payload.killedBy, payload.bleedMs, payload.ambulanceCalled)
end

function EnterDeathState(killedBy, bleedMs, alreadyAmbulanceCalled)
    if deathScreenActive then return end
    deathScreenActive = true

    -- Close inventory before the death screen takes NUI focus. This also hides
    -- drop pickup cards immediately at the death transition.
    TriggerEvent('cm-inventory:client:forceCloseForDeath')

    isDead = true
    lifeState = 'dead'
    ambulanceCalled = alreadyAmbulanceCalled == true
    dieChosen = false
    respawnRequestSent = false
    lastRespawnRequestAt = 0
    respawnRequestCount = 0
    localDeathDeadline = GetGameTimer() + (tonumber(bleedMs) or ((Config.Respawn and Config.Respawn.BleedOutTime) or 120000))

    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    SetPlayerHealthRechargeLimit(PlayerId(), 0.0)

    -- Supply War deaths are immediately resolved through the authoritative
    -- hospital-bed respawn path. Avoid flashing or focusing the normal death UI.
    if LocalPlayer.state.cmSupplyWarParticipant == true then return end

    IgnoreNextRestart(true)
    StartDeathEffect()
    StartDeathCam()

    SendNUIMessage({
        action = 'openDeathScreen',
        remainingMs = tonumber(bleedMs) or ((Config.Respawn and Config.Respawn.BleedOutTime) or 120000),
        killedBy = killedBy -- { label = 'musa bhai' or 'Stranger', charId = 13 } or nil
    })

    -- Mouse cursor for the two buttons; released after either choice.
    SetNuiFocusKeepInput(false)
    SetNuiFocus(true, true)

    CreateThread(function()
        while deathScreenActive do
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
        while deathScreenActive do
            Wait(1000)
            local now = GetGameTimer()
            if localDeathDeadline > 0 and now >= localDeathDeadline then
                if (now - lastRespawnRequestAt) >= 2000 and respawnRequestCount < 10 then
                    lastRespawnRequestAt = now
                    respawnRequestCount = respawnRequestCount + 1
                    respawnRequestSent = true
                    TriggerServerEvent('cm-playerdata:server:requestRespawn')
                end
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
end

local function CleanupDeathState()
    deathScreenActive = false
    isDead = false
    deathReportPending = false
    pendingDeathData = nil
    ambulanceCalled = false
    dieChosen = false
    respawnRequestSent = false
    lastRespawnRequestAt = 0
    respawnRequestCount = 0
    localDeathDeadline = 0
    SetNuiFocus(false, false)
    StopDeathCam()
    StopDeathEffect()
    SendNUIMessage({ action = 'closeDeathScreen' })
end

function ExitDeathState()
    CleanupDeathState()
end

-- ---------------------------------------------------------------------------
-- Data / vitals
-- ---------------------------------------------------------------------------
local function ApplyLoadedData(data)
    PlayerData = data or {}
    lifeState = PlayerData.lifeState or (PlayerData.isDead and 'dead' or 'alive')
    if lifeState == 'downed' then lifeState = 'dead' end
    isDead = (lifeState ~= 'alive')
    applyNativeWantedLevel(PlayerData.wantedStars)
    lastHealth = PlayerData.health or Config.Vitals.MaxHealth
    lastArmor = PlayerData.armor or 0

    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    SetPlayerHealthRechargeLimit(PlayerId(), 0.0)

    local ped = PlayerPedId()
    if not isDead then
        SetEntityHealth(ped, lastHealth)
        SetPedArmour(ped, lastArmor)
    else
        -- Native dead: do not grant health. If ped is alive on connect while dead in DB, kill it
        if not IsEntityDead(ped) then
            SetEntityHealth(ped, 0)
        end
    end

    if isDead then
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

RegisterNetEvent('cm-playerdata:client:lifeStateChanged', function(newLifeState, reason)
    lifeState = newLifeState or 'alive'
    if lifeState == 'downed' then lifeState = 'dead' end
    isDead = (lifeState ~= 'alive')
    if type(PlayerData) == 'table' then
        PlayerData.lifeState = lifeState
        PlayerData.isDead = isDead
    end

    if (lifeState == 'dead') then
        EnsureDeathPresentation({
            bleedMs = (Config.Respawn and Config.Respawn.BleedOutTime) or 120000,
            authoritative = true
        })
    elseif lifeState == 'alive' and deathScreenActive then
        ExitDeathState()
    end
end)

RegisterNetEvent('cm-playerdata:client:loaded', ApplyLoadedData)
RegisterNetEvent('cm-playerdata:client:characterLoaded', ApplyLoadedData)

RegisterNetEvent('cm-playerdata:client:unloaded', function()
    PlayerData = {}
    lifeState = 'alive'
    applyNativeWantedLevel(0)
    pendingDeathData = nil
    hasSpawnCompleted = false
    lastHealth = Config.Vitals.MaxHealth
    lastArmor = 0
    ExitDeathState()
end)
RegisterNetEvent('cm-playerdata:client:characterUnloaded', function()
    PlayerData = {}
    lifeState = 'alive'
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

RegisterNetEvent('cm-playerdata:client:setArmor', function(armor)
    local ped = PlayerPedId()
    armor = math.max(0, math.min((Config.Vitals and Config.Vitals.MaxArmor) or 100, math.floor(tonumber(armor) or 0)))
    SetPedArmour(ped, armor)
    lastArmor = armor
    PlayerData.armor = armor
end)

-- Server tells us we are dead, including who killed us (name only if we know them)
-- and how long the bleed-out is. This is the authoritative confirmation.
local function HandleDownedOrDiedEvent(killerSrc, weaponHash, killedBy, bleedMs)
    deathReportPending = false
    pendingDeathData = nil
    isDead = true
    lifeState = 'dead'
    EnsureDeathPresentation({
        killedBy = killedBy,
        bleedMs = bleedMs,
        ambulanceCalled = false,
        authoritative = true
    })
end

RegisterNetEvent('cm-playerdata:client:playerDowned', HandleDownedOrDiedEvent)
RegisterNetEvent('cm-playerdata:client:playerDied', HandleDownedOrDiedEvent)

RegisterNetEvent('cm-playerdata:client:restoreDeathFocus', function()
    if not deathScreenActive then return end
    if ambulanceCalled then
        SetNuiFocus(false, false)
    else
        SetNuiFocusKeepInput(false)
        SetNuiFocus(true, true)
    end
end)

-- ---------------------------------------------------------------------------
-- Idempotent death presentation. Can be called multiple times safely:
--   1. Native death detection (pending, before server confirms)
--   2. Server death confirmation (authoritative payload with timer/killer)
--   3. Reconnect recovery (dead in DB)
-- Produces exactly ONE death screen.
-- ---------------------------------------------------------------------------
local function EnsureDeathPresentation(payload)
    payload = payload or {}
    local bleedMs = payload.bleedMs or ((Config.Respawn and Config.Respawn.BleedOutTime) or 120000)
    local killedBy = payload.killedBy
    local alreadyAmbulanceCalled = payload.ambulanceCalled == true

    if deathScreenActive then
        -- Already showing: just update timer/payload if server sent authoritative data
        if payload.authoritative then
            localDeathDeadline = GetGameTimer() + bleedMs
            SendNUIMessage({
                action = 'updateDeathTimer',
                remainingMs = bleedMs,
                killedBy = killedBy
            })
            if alreadyAmbulanceCalled and not ambulanceCalled then
                ambulanceCalled = true
                SetNuiFocus(false, false)
                SendNUIMessage({
                    action = 'ambulanceMode',
                    remainingMs = math.max(0, localDeathDeadline - GetGameTimer())
                })
            end
            Debug('DEATH_UI authoritative-update')
        end
        return
    end

    -- First open
    Debug('DEATH_UI opening')
    EnterDeathState(killedBy, bleedMs, alreadyAmbulanceCalled)
end

-- ---------------------------------------------------------------------------
-- Native death detection.
-- GTA/FiveM owns health, damage and native death. The watcher observes when
-- the player ped actually dies natively (IsEntityDead or IsPedFatallyInjured)
-- and reports to the server once. The ped remains natively dead until
-- a trusted revive or hospital respawn occurs.
--
-- CRITICAL: Opens death presentation IMMEDIATELY on native death, before
-- waiting for server confirmation. Server confirmation updates the payload.
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

        if LocalPlayer.state.playerDataLoaded and not isSpawning and not isDead and not deathReportPending and lifeState == 'alive' then
            local ped = PlayerPedId()
            local isPedDead = IsEntityDead(ped)
            local isFatallyInjured = IsPedFatallyInjured(ped)

            if isPedDead or isFatallyInjured then
                deathReportPending = true

                -- 1. Capture killer info and fatal evidence
                local report = BuildDeathReport(ped)
                local hp = GetEntityHealth(ped)

                local fatalEvidence = {
                    preResurrectionHealth = hp,
                    wasDead = isPedDead,
                    wasFatallyInjured = isFatallyInjured,
                    causeHash = report.causeHash,
                    killerServerId = report.killerServerId,
                    killerType = report.killerType,
                    clientTime = GetGameTimer()
                }

                Debug(('NATIVE_DEATH detected hp=%s dead=%s fatal=%s cause=%s killer=%s'):format(hp, tostring(isPedDead), tostring(isFatallyInjured), tostring(report.causeHash), tostring(report.killerServerId)))

                -- 2. Open death presentation IMMEDIATELY in pending state
                --    Do not wait for server round-trip. Player sees death screen now.
                isDead = true
                lifeState = 'dead'
                EnsureDeathPresentation({
                    bleedMs = (Config.Respawn and Config.Respawn.BleedOutTime) or 120000,
                    killedBy = nil, -- server will provide killer identity
                    ambulanceCalled = false,
                    authoritative = false
                })

                -- 3. Notify server while ped is in genuine native fatal state
                Debug('DEATH_EVENT sent')
                TriggerServerEvent('cm-playerdata:server:playerDied', report.killerServerId, report.causeHash, report.killerType, fatalEvidence)

                -- Failsafe: if the server event is lost, clear pending after timeout
                SetTimeout(5000, function()
                    if deathReportPending and not deathScreenActive then
                        deathReportPending = false
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

RegisterNetEvent('cm-playerdata:client:waitingForBed', function(label, retryMs)
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'emsProtection',
        remainingMs = tonumber(retryMs) or 5000,
        etaMs = 0,
        label = tostring(label or 'WAITING FOR HOSPITAL BED'),
        protected = true,
    })
end)

RegisterNetEvent('cm-playerdata:client:canRespawn', function()
    -- kept for backward compatibility; bleed-out handles respawn now
end)

RegisterNetEvent('cm-playerdata:client:revive', function()
    ExitDeathState()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
    ped = PlayerPedId()
    lastHealth = Config.Vitals.MaxHealth
    lastArmor = 0
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
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
    ped = PlayerPedId()
    health = tonumber(health) or GetHealthFromPercent(30)
    lastHealth = health
    lastArmor = 0
    SetEntityHealth(ped, health)
    SetPedArmour(ped, 0)
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedTasksImmediately(ped)
end)

RegisterNetEvent('cm-playerdata:client:respawn', function(spawn, respawnHealth, token)
    isSpawning = true
    pendingDeathData = nil
    ExitDeathState()

    spawn = spawn or Config.Respawn.HospitalSpawn
    local ped = PlayerPedId()

    DoScreenFadeOut(500)
    Wait(600)

    NetworkResurrectLocalPlayer(spawn.x, spawn.y, spawn.z, spawn.h or 0.0, true, false)
    ped = PlayerPedId()
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

    if token then
        TriggerServerEvent('cm-playerdata:server:respawnComplete', token)
    end
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
-- spawn resource may not re-emit spawnComplete, so this thread forces the
-- death UI back up. It uses EnsureDeathPresentation which is idempotent.
-- NEVER sets health or lifeState. Presentation only.
CreateThread(function()
    while true do
        Wait(1500)

        local dataSaysDead = type(PlayerData) == 'table' and (PlayerData.lifeState == 'dead' or PlayerData.lifeState == 'downed' or (PlayerData.lifeState == nil and PlayerData.isDead == true))
        if not deathScreenActive and not isSpawning and dataSaysDead then
            if LocalPlayer.state.playerDataLoaded == true and not SpawnUiActive() then
                isDead = true
                lifeState = 'dead'
                hasSpawnCompleted = true
                pendingDeathData = nil
                Debug('DEATH_UI recovery-open')
                EnsureDeathPresentation({
                    bleedMs = tonumber(PlayerData.deathRemainingMs) or ((Config.Respawn and Config.Respawn.BleedOutTime) or 120000),
                    ambulanceCalled = PlayerData.ambulanceCalled == true,
                    authoritative = true
                })
            end
        elseif not deathScreenActive and not isSpawning and pendingDeathData then
            if LocalPlayer.state.playerDataLoaded == true and not SpawnUiActive() then
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

        if LocalPlayer.state.isLoggedIn and LocalPlayer.state.playerDataLoaded and not deathScreenActive and not isSpawning and not isDead and lifeState == 'alive' then
            local ped = PlayerPedId()
            local currentHealth = GetEntityHealth(ped)
            local currentArmor = GetPedArmour(ped)

            -- Observational only: GTA native health and armor are source-of-truth.
            -- cm-playerdata mirrors native values and syncs to server.
            if currentHealth ~= lastHealth then
                lastHealth = currentHealth
            end
            if currentArmor ~= lastArmor then
                lastArmor = currentArmor
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
    if (deathScreenActive or isDead) and not ambulanceCalled and not dieChosen then
        TriggerServerEvent('cm-playerdata:server:callAmbulance')
    end
end)

RegisterNUICallback('deathDie', function(_, cb)
    cb({})
    if (deathScreenActive or isDead) and not ambulanceCalled and not dieChosen then
        dieChosen = true
        TriggerServerEvent('cm-playerdata:server:chooseDie')
        SendNUIMessage({ action = 'deathChoice', choice = 'die' })
        SetNuiFocus(false, false)
    end
end)

RegisterNUICallback('deathExpired', function(_, cb)
    cb({})
    if deathScreenActive or isDead then
        local now = GetGameTimer()
        if (now - lastRespawnRequestAt) >= 1500 and respawnRequestCount < 10 then
            lastRespawnRequestAt = now
            respawnRequestCount = respawnRequestCount + 1
            respawnRequestSent = true
            TriggerServerEvent('cm-playerdata:server:requestRespawn')
        end
    end
end)

RegisterNUICallback('deathOpenMap', function(_, cb)
    cb({})
    if (not deathScreenActive and not isDead) or IsPauseMenuActive() then return end
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

exports('GetLifeState', function()
    return lifeState or 'alive'
end)

exports('IsAlive', function()
    return lifeState == 'alive' and not isDead
end)

exports('IsDowned', function()
    return isDead
end)

exports('IsFullyDead', function()
    return isDead
end)

exports('IsRespawning', function()
    return lifeState == 'respawning'
end)

exports('IsDead', function()
    return isDead
end)

exports('CanPlayerAct', function()
    return not isDead and not isSpawning and hasSpawnCompleted and not SpawnUiActive()
end)
