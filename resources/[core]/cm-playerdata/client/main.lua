local PlayerData = {}
local isDead = false
local canRespawn = false
local lastHealth = 200
local lastArmor = 0

-- Local config
local Config = {
    RespawnTime = 30000,
    HospitalSpawn = {x = 341.0, y = -1397.0, z = 33.0, h = 50.0},
    HealthSyncInterval = 5000, -- Sync every 5 seconds
    DamageThreshold = 101 -- Below this = dead/downed
}

-- ============================================================
-- NET EVENTS
-- ============================================================
RegisterNetEvent('cm-playerdata:client:loaded', function(data)
    PlayerData = data
    lastHealth = data.health or 200
    lastArmor = data.armor or 0
    
    print('[CM-PLAYERDATA] Loaded | HP=' .. lastHealth .. ' | Dead=' .. tostring(data.isDead))

    -- Disable natural health regeneration
    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    SetPlayerHealthRechargeLimit(PlayerId(), 0.0)

    -- Apply loaded health immediately
    local ped = PlayerPedId()
    SetEntityHealth(ped, lastHealth)
    SetPedArmour(ped, lastArmor)

    -- Reconnect while dead
    if data.isDead then
        print('[CM-PLAYERDATA] Reconnecting while dead. Entering death state.')
        EnterDeathState()
        
        SetTimeout(5000, function()
            canRespawn = true
            print('[CM-PLAYERDATA] You can now respawn. Press E.')
        end)
    end
end)

RegisterNetEvent('cm-playerdata:client:update', function(key, value)
    PlayerData[key] = value
end)

RegisterNetEvent('cm-playerdata:client:setHealth', function(health, armor)
    local ped = PlayerPedId()
    SetEntityHealth(ped, health)
    SetPedArmour(ped, armor)
    lastHealth = health
    lastArmor = armor
end)

RegisterNetEvent('cm-playerdata:client:playerDied', function(killerSrc, weaponHash)
    print('[CM-PLAYERDATA] Server confirmed death.')
    EnterDeathState()
    
    SetTimeout(Config.RespawnTime, function()
        if isDead then
            canRespawn = true
            print('[CM-PLAYERDATA] You can now respawn. Press E.')
        end
    end)
end)

RegisterNetEvent('cm-playerdata:client:canRespawn', function()
    canRespawn = true
    print('[CM-PLAYERDATA] Press E to respawn at hospital.')
end)

RegisterNetEvent('cm-playerdata:client:respawn', function(spawn)
    print('[CM-PLAYERDATA] Respawning...')
    ExitDeathState()
    
    local ped = PlayerPedId()
    
    -- CRITICAL: Set health BEFORE anything else to stop death detection
    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 0)
    lastHealth = 200
    lastArmor = 0
    
    DoScreenFadeOut(800)
    Wait(1000)

    SetEntityCoordsNoOffset(ped, spawn.x, spawn.y, spawn.z, false, false, false)
    SetEntityHeading(ped, spawn.h or 0.0)
    
    -- Clear all damage and reset ped
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedTasksImmediately(ped)
    
    -- Unfreeze and enable controls
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetPlayerControl(PlayerId(), true, 0)
    
    -- Stop any ragdoll
    SetPedToRagdoll(ped, 1, 1, 0, false, false, false)

    DoScreenFadeIn(800)
    print('[CM-PLAYERDATA] Respawned at hospital. HP=' .. GetEntityHealth(ped))
end)

RegisterNetEvent('cm-playerdata:client:revive', function(reviver)
    print('[CM-PLAYERDATA] Revived.')
    ExitDeathState()
    
    local ped = PlayerPedId()
    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 0)
    lastHealth = 200
    lastArmor = 0
    
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    SetPlayerControl(PlayerId(), true, 0)
    SetPedToRagdoll(ped, 1, 1, 0, false, false, false)
end)

-- ============================================================
-- DEATH STATE MANAGEMENT
-- ============================================================
function EnterDeathState()
    if isDead then return end
    isDead = true
    canRespawn = false
    
    local ped = PlayerPedId()
    
    -- Force ragdoll
    SetPedToRagdoll(ped, 10000, 10000, 0, false, false, false)
    
    -- Disable all controls loop
    CreateThread(function()
        while isDead do
            Wait(0)
            DisableAllControlActions(0)
            EnableControlAction(0, 1, true)    -- Mouse look X
            EnableControlAction(0, 2, true)    -- Mouse look Y
            EnableControlAction(0, 245, true)  -- Chat
            EnableControlAction(0, 38, true)   -- E key (respawn)
        end
    end)
    
    -- Keep health at 101 (downed but not wasted)
    SetEntityHealth(ped, 101)
    lastHealth = 101
    
    print('[CM-PLAYERDATA] Death state entered.')
end

function ExitDeathState()
    isDead = false
    canRespawn = false
    print('[CM-PLAYERDATA] Death state exited.')
end

-- ============================================================
-- DAMAGE DETECTION — Multiple methods
-- ============================================================

-- Method 1: Health polling (catches all damage, most reliable)
CreateThread(function()
    -- Disable natural regeneration on thread start
    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    
    while true do
        Wait(500) -- Check every 500ms
        
        if not LocalPlayer.state.isLoggedIn then goto continue end
        if isDead then goto continue end
        
        local ped = PlayerPedId()
        local currentHealth = GetEntityHealth(ped)
        local currentArmor = GetPedArmour(ped)
        
        -- Detect health drop (damage taken)
        if currentHealth < lastHealth and currentHealth > 0 then
            local damage = lastHealth - currentHealth
            print('[CM-PLAYERDATA] Damage detected: ' .. damage .. ' HP (was ' .. lastHealth .. ' now ' .. currentHealth .. ')')
            
            -- Sync immediately to server
            TriggerServerEvent('cm-playerdata:server:updateHealth', currentHealth, currentArmor)
            lastHealth = currentHealth
            lastArmor = currentArmor
            
            -- Check if health dropped below threshold (downed/dead)
            if currentHealth <= Config.DamageThreshold then
                print('[CM-PLAYERDATA] Health below threshold! Entering death state.')
                SetEntityHealth(ped, 101) -- Keep at 101 for ragdoll
                TriggerServerEvent('cm-playerdata:server:playerDied', nil, nil)
                EnterDeathState()
                
                SetTimeout(Config.RespawnTime, function()
                    if isDead then
                        canRespawn = true
                        print('[CM-PLAYERDATA] You can now respawn. Press E.')
                    end
                end)
            end
        end
        
        -- Detect armor change
        if currentArmor ~= lastArmor then
            lastArmor = currentArmor
            TriggerServerEvent('cm-playerdata:server:updateHealth', currentHealth, currentArmor)
        end
        
        -- Prevent GTA from healing above our saved value
        if currentHealth > lastHealth and lastHealth > 101 then
            -- GTA tried to heal us, force back
            SetEntityHealth(ped, lastHealth)
        end
        
        ::continue::
    end
end)

-- Method 2: gameEventTriggered (catches fatal damage events)
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    
    local victim = args[1]
    local attacker = args[2]
    local fatal = args[4]
    local weapon = args[7] or args[5]
    
    if victim ~= PlayerPedId() then return end
    if isDead then return end
    
    local ped = PlayerPedId()
    local health = GetEntityHealth(ped)
    
    -- Fatal flag OR health already at/below threshold
    if fatal == 1 or health <= Config.DamageThreshold then
        print('[CM-PLAYERDATA] Fatal damage event! HP=' .. health)
        
        -- Prevent GTA wasted screen
        SetEntityHealth(ped, 101)
        
        local killerSrc = nil
        if attacker and IsEntityAPed(attacker) and IsPedAPlayer(attacker) then
            local killerPlayer = NetworkGetPlayerIndexFromPed(attacker)
            if killerPlayer and killerPlayer >= 0 then
                killerSrc = GetPlayerServerId(killerPlayer)
            end
        end
        
        TriggerServerEvent('cm-playerdata:server:playerDied', killerSrc, weapon)
        EnterDeathState()
        
        SetTimeout(Config.RespawnTime, function()
            if isDead then
                canRespawn = true
                print('[CM-PLAYERDATA] You can now respawn. Press E.')
            end
        end)
    end
end)

-- Method 3: Entity damage event (catches environmental/explosion damage)
AddEventHandler('entityDamaged', function(entity, attacker, weaponHash, damage)
    if entity ~= PlayerPedId() then return end
    if isDead then return end
    
    local ped = PlayerPedId()
    local health = GetEntityHealth(ped)
    
    print('[CM-PLAYERDATA] entityDamaged: health=' .. health .. ' damage=' .. tostring(damage))
    
    if health <= Config.DamageThreshold then
        SetEntityHealth(ped, 101)
        TriggerServerEvent('cm-playerdata:server:playerDied', nil, weaponHash)
        EnterDeathState()
        
        SetTimeout(Config.RespawnTime, function()
            if isDead then
                canRespawn = true
            end
        end)
    end
end)

-- ============================================================
-- PERIODIC SYNC (position + health when alive)
-- ============================================================
CreateThread(function()
    while true do
        Wait(Config.HealthSyncInterval)
        
        if not LocalPlayer.state.isLoggedIn or not LocalPlayer.state.playerDataLoaded then goto continue end
        if isDead then goto continue end
        
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local h = GetEntityHeading(ped)
        
        -- Skip if frozen (in menu/selector)
        if IsEntityPositionFrozen(ped) or not IsEntityVisible(ped) then
            goto continue
        end
        
        -- Skip if at default spawn (0,0,1)
        if math.abs(coords.x) < 1.0 and math.abs(coords.y) < 1.0 and coords.z < 2.0 then
            goto continue
        end
        
        TriggerServerEvent('cm-playerdata:server:updatePosition', {
            x = Round(coords.x, 2),
            y = Round(coords.y, 2),
            z = Round(coords.z, 2),
            h = Round(h, 2)
        })

        local health = GetEntityHealth(ped)
        local armor = GetPedArmour(ped)
        
        -- Only sync if health changed significantly
        if math.abs(health - lastHealth) > 5 or math.abs(armor - lastArmor) > 5 then
            lastHealth = health
            lastArmor = armor
            TriggerServerEvent('cm-playerdata:server:updateHealth', health, armor)
        end
        
        ::continue::
    end
end)

-- ============================================================
-- RESPAWN KEY (E) WHEN DEAD
-- ============================================================
CreateThread(function()
    while true do
        Wait(0)
        
        if isDead and canRespawn then
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('Press ~INPUT_PICKUP~ to respawn at hospital (~g~$500~s~)')
            EndTextCommandDisplayHelp(0, false, true, 1)

            if IsControlJustPressed(0, 38) then -- E key
                canRespawn = false
                TriggerServerEvent('cm-playerdata:server:requestRespawn')
            end
        elseif isDead and not canRespawn then
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('~r~You are unconscious~s~. Wait for respawn...')
            EndTextCommandDisplayHelp(0, false, true, 1)
        end
    end
end)

-- ============================================================
-- UTILS
-- ============================================================
function Round(num, places)
    local mult = 10^(places or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- ============================================================
-- CLIENT EXPORTS
-- ============================================================
exports('IsDead', function()
    return isDead
end)

exports('GetPlayerData', function()
    return PlayerData
end)

exports('GetData', function(key)
    return PlayerData[key]
end)