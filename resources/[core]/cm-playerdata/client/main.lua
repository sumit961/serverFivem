-- cm-playerdata/client/main.lua
-- Stable v1.2-lite upgrade. No hunger/thirst/stress.

local Config = CMPlayerData.Config
local PlayerData = {}
local isDead = false
local canRespawn = false
local isSpawning = false
local lastHealth = 200
local lastArmor = 0
local injuredWalkstyle = false
local lastVitalsSync = 0
local lastPositionSync = 0

local function Debug(msg)
    if Config.Debug then
        print('[CM-PLAYERDATA-CLIENT] ' .. tostring(msg))
    end
end

local function ApplyInjuredWalkstyle(ped, enabled)
    if enabled and not injuredWalkstyle then
        RequestAnimSet('move_m@injured')
        while not HasAnimSetLoaded('move_m@injured') do Wait(1) end
        SetPedMovementClipset(ped, 'move_m@injured', 1.0)
        injuredWalkstyle = true
    elseif not enabled and injuredWalkstyle then
        ResetPedMovementClipset(ped, 0.0)
        injuredWalkstyle = false
    end
end

function EnterDeathState()
    if isDead then return end
    isDead = true
    canRespawn = false

    local ped = PlayerPedId()
    SetEntityHealth(ped, Config.Vitals.DamageThreshold)
    SetPedToRagdoll(ped, 10000, 10000, 0, false, false, false)
    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    SetPlayerHealthRechargeLimit(PlayerId(), 0.0)

    CreateThread(function()
        while isDead do
            Wait(0)
            DisableAllControlActions(0)
            EnableControlAction(0, 1, true)
            EnableControlAction(0, 2, true)
            EnableControlAction(0, 245, true)
            EnableControlAction(0, 38, true)
        end
    end)

    lastHealth = Config.Vitals.DamageThreshold
end

function ExitDeathState()
    isDead = false
    canRespawn = false
    ApplyInjuredWalkstyle(PlayerPedId(), false)
end

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
        EnterDeathState()
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

RegisterNetEvent('cm-playerdata:client:playerDied', function()
    EnterDeathState()
end)

RegisterNetEvent('cm-playerdata:client:canRespawn', function()
    canRespawn = true
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
                    TriggerServerEvent('cm-playerdata:server:playerDied', nil, nil)
                else
                    lastHealth = currentHealth
                end
            elseif currentHealth > lastHealth then
                lastHealth = currentHealth
            end

            if currentHealth < Config.Vitals.InjuredHealth then
                ApplyInjuredWalkstyle(ped, true)
            else
                ApplyInjuredWalkstyle(ped, false)
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

CreateThread(function()
    while true do
        if isDead then
            Wait(0)

            if canRespawn then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName(('Press ~INPUT_PICKUP~ to respawn at hospital (~g~$%s~s~)'):format(Config.Respawn.Cost))
                EndTextCommandDisplayHelp(0, false, false, 1)

                if IsControlJustPressed(0, 38) then
                    TriggerServerEvent('cm-playerdata:server:requestRespawn')
                    Wait(1000)
                end
            else
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~r~You are unconscious~s~. Please wait for medical dispatch...')
                EndTextCommandDisplayHelp(0, false, false, 1)
            end
        else
            Wait(1000)
        end
    end
end)

RegisterCommand('pdstatus', function()
    print(('[CM-PLAYERDATA] HP=%s Armor=%s Dead=%s'):format(
        tostring(PlayerData.health),
        tostring(PlayerData.armor),
        tostring(isDead)
    ))
end, false)
