-- cm-playerdata/client/main.lua

local PlayerData = {}
local isDead = false
local canRespawn = false
local isSpawning = false -- Anti-threading race metric latch

local lastHealth = 200
local lastArmor = 0

local Config = {
    RespawnTime = 30000,
    HealthSyncInterval = 4000, -- Multi-sample tracking
    DamageThreshold = 101
}

-- ============================================================
-- NET ASSIGNMENT RECEIVERS
-- ============================================================
RegisterNetEvent('cm-playerdata:client:loaded', function(data)
    PlayerData = data
    lastHealth = data.health or 200
    lastArmor = data.armor or 0
    
    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    SetPlayerHealthRechargeLimit(PlayerId(), 0.0)

    local ped = PlayerPedId()
    SetEntityHealth(ped, lastHealth)
    SetPedArmour(ped, lastArmor)

    if data.isDead then EnterDeathState() end
end)

RegisterNetEvent('cm-playerdata:client:update', function(key, value)
    PlayerData[key] = value
end)

RegisterNetEvent('cm-playerdata:client:playerDied', function()
    EnterDeathState()
end)

RegisterNetEvent('cm-playerdata:client:canRespawn', function()
    canRespawn = true
end)

RegisterNetEvent('cm-playerdata:client:respawn', function(spawn)
    isSpawning = true
    ExitDeathState()
    
    local ped = PlayerPedId()
    DoScreenFadeOut(500)
    Wait(600)

    SetEntityCoordsNoOffset(ped, spawn.x, spawn.y, spawn.z, false, false, false)
    SetEntityHeading(ped, spawn.h or 0.0)
    
    lastHealth = 200
    lastArmor = 0
    
    SetEntityHealth(ped, 200)
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

-- ============================================================
-- INTERNAL ENGINE STATES
-- ============================================================
function EnterDeathState()
    if isDead then return end
    isDead = true
    canRespawn = false
    
    local ped = PlayerPedId()
    SetPedToRagdoll(ped, 10000, 10000, 0, false, false, false)
    
    CreateThread(function()
        while isDead do
            Wait(0)
            DisableAllControlActions(0)
            EnableControlAction(0, 1, true)   -- Cam Look
            EnableControlAction(0, 2, true)   
            EnableControlAction(0, 245, true) -- Chat Input
            EnableControlAction(0, 38, true)  -- Interaction (E)
        end
    end)
    
    SetEntityHealth(ped, 101)
    lastHealth = 101
end

function ExitDeathState()
    isDead = false
    canRespawn = false
end

-- ============================================================
-- CORE INTEGRITY LOOP POLL ENGINE
-- ============================================================
CreateThread(function()
    while true do
        Wait(1000) -- Base clock tick
        
        if LocalPlayer.state.isLoggedIn and not isDead and not isSpawning then
            local ped = PlayerPedId()
            local currentHealth = GetEntityHealth(ped)
            local currentArmor = GetPedArmour(ped)

            -- Manage Core Engine Physical Damage Variations
            if currentHealth < lastHealth then
                if currentHealth <= Config.DamageThreshold then
                    SetEntityHealth(ped, 101)
                    TriggerServerEvent('cm-playerdata:server:playerDied', nil, nil)
                else
                    lastHealth = currentHealth
                end
            end

            -- Injury Walkstyle Logic Overlay
            if currentHealth < 140 then
                if not IsInInjuredWalkstyle then
                    RequestAnimSet("move_m@injured")
                    while not HasAnimSetLoaded("move_m@injured") do Wait(1) end
                    SetPedMovementClipset(ped, "move_m@injured", 1.0)
                    IsInInjuredWalkstyle = true
                end
            else
                if IsInInjuredWalkstyle then
                    ResetPedMovementClipset(ped, 0.0)
                    IsInInjuredWalkstyle = false
                end
            end

            -- Outward Sync Cycle
            if GetGameTimer() % Config.HealthSyncInterval < 1000 then
                TriggerServerEvent('cm-playerdata:server:syncVitals', currentHealth, currentArmor)
                
                local coords = GetEntityCoords(ped)
                TriggerServerEvent('cm-playerdata:server:updatePosition', {
                    x = math.floor(coords.x * 100) / 100,
                    y = math.floor(coords.y * 100) / 100,
                    z = math.floor(coords.z * 100) / 100,
                    h = math.floor(GetEntityHeading(ped) * 100) / 100
                })
            end
        end
    end
end)

-- ============================================================
-- OPTIMIZED RENDERING INTERACTION HELP TEXT TICKER
-- ============================================================
CreateThread(function()
    while true do
        if isDead then
            Wait(0)
            if canRespawn then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('Press ~INPUT_PICKUP~ to respawn at hospital (~g~$500~s~)')
                EndTextCommandDisplayHelp(0, false, false, 1)

                if IsControlJustPressed(0, 38) then
                    TriggerServerEvent('cm-playerdata:server:requestRespawn')
                    Wait(1000) -- Debounce 안전장치
                end
            else
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('~r~You are unconscious~s~. Please wait for medical dispatch...')
                EndTextCommandDisplayHelp(0, false, false, 1)
            end
        else
            Wait(1000) -- Healthy drop consumption to 0ms
        end
    end
end)