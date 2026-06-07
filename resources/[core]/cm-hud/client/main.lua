-- cm-hud/client/main.lua

local currentHealth = 200
local currentArmor = 0
local currentCash = 0
local currentBank = 0
local currentArea = 'Unknown'
local currentStreet = 'Unknown'
local isDead = false
local deathTimer = 0
local canRespawn = false

-- ============================================================
-- INIT
-- ============================================================
RegisterNetEvent('cm-playerdata:client:loaded', function(data)
    Wait(500)

    currentHealth = data.health or 200
    currentArmor = data.armor or 0
    currentCash = data.cash or 0
    currentBank = data.bank or 0

    local serverId = GetPlayerServerId(PlayerId())

    SendNUIMessage({
        action = 'init',
        state = {
            serverName = 'CM-RP',
            serverId = serverId,
            level = 1,
            onlinePlayers = #GetActivePlayers(),
            cash = currentCash,
            bank = currentBank,
            health = currentHealth,
            armor = currentArmor,
            area = currentArea,
            street = currentStreet
        }
    })

    print('[CM-HUD] Initialized | ID:' .. serverId)
end)

-- ============================================================
-- HEALTH / ARMOR (from cm-playerdata)
-- ============================================================
RegisterNetEvent('cm-playerdata:client:setHealth', function(health, armor)
    currentHealth = health
    currentArmor = armor

    SendNUIMessage({
        action = 'updateHealth',
        health = health,
        armor = armor
    })
end)

-- ============================================================
-- MONEY (from cm-playerdata)
-- ============================================================
RegisterNetEvent('cm-playerdata:client:update', function(key, value)
    if key == 'cash' then
        currentCash = value
    elseif key == 'bank' then
        currentBank = value
    end

    SendNUIMessage({
        action = 'updateMoney',
        cash = currentCash,
        bank = currentBank
    })
end)

-- ============================================================
-- DEATH / RESPAWN / REVIVE
-- ============================================================
RegisterNetEvent('cm-playerdata:client:playerDied', function(killerSrc, weaponHash)
    isDead = true
    canRespawn = false
    deathTimer = 30

    SendNUIMessage({
        action = 'showDeath',
        time = deathTimer
    })

    -- Local countdown until server says we can respawn
    CreateThread(function()
        while isDead and deathTimer > 0 do
            Wait(1000)
            deathTimer = deathTimer - 1

            SendNUIMessage({
                action = 'updateDeathTime',
                time = deathTimer
            })
        end

        if isDead then
            canRespawn = true
            SendNUIMessage({ action = 'showRespawn' })
        end
    end)
end)

RegisterNetEvent('cm-playerdata:client:canRespawn', function()
    canRespawn = true
    deathTimer = 0
    SendNUIMessage({ action = 'showRespawn' })
end)

RegisterNetEvent('cm-playerdata:client:respawn', function(spawn)
    isDead = false
    canRespawn = false
    deathTimer = 0

    SendNUIMessage({ action = 'hideDeath' })

    currentHealth = 200
    currentArmor = 0

    SendNUIMessage({
        action = 'updateHealth',
        health = 200,
        armor = 0
    })
end)

RegisterNetEvent('cm-playerdata:client:revive', function(reviver)
    isDead = false
    canRespawn = false
    deathTimer = 0
    SendNUIMessage({ action = 'hideDeath' })
end)

-- ============================================================
-- NUI CALLBACK: Respawn button pressed
-- ============================================================
RegisterNUICallback('respawn', function(data, cb)
    if canRespawn and isDead then
        TriggerServerEvent('cm-playerdata:server:requestRespawn')
    end
    cb('ok')
end)

-- ============================================================
-- HEALTH POLLING (smooth bar updates)
-- ============================================================
CreateThread(function()
    while true do
        Wait(200)

        if LocalPlayer.state.isLoggedIn then
            local ped = PlayerPedId()
            local health = GetEntityHealth(ped)
            local armor = GetPedArmour(ped)

            -- Convert FiveM health (0-200) to our scale if needed
            -- GTA max health is 200, but GetEntityHealth returns 100-200 for alive peds
            -- We'll pass raw values and let UI scale it
            if health ~= currentHealth or armor ~= currentArmor then
                currentHealth = health
                currentArmor = armor

                SendNUIMessage({
                    action = 'updateHealth',
                    health = health,
                    armor = armor
                })
            end

            -- Auto-detect death if health drops to 0
            if health <= 0 and not isDead then
                isDead = true
                TriggerServerEvent('cm-playerdata:server:playerDied')
            end
        end
    end
end)

-- ============================================================
-- LOCATION POLLING
-- ============================================================
CreateThread(function()
    while true do
        Wait(1000)

        if LocalPlayer.state.isLoggedIn then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)

            local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
            local street = GetStreetNameFromHashKey(streetHash) or 'Unknown'
            local area = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z)) or 'Unknown'

            if area ~= currentArea or street ~= currentStreet then
                currentArea = area
                currentStreet = street

                SendNUIMessage({
                    action = 'updateLocation',
                    area = area,
                    street = street
                })
            end
        end
    end
end)

-- ============================================================
-- ONLINE PLAYERS POLLING
-- ============================================================
CreateThread(function()
    while true do
        Wait(5000)

        if LocalPlayer.state.isLoggedIn then
            local count = #GetActivePlayers()

            SendNUIMessage({
                action = 'updatePlayers',
                count = count
            })
        end
    end
end)

-- ============================================================
-- KEY STATE POLLING (visual feedback only)
-- ============================================================
CreateThread(function()
    while true do
        Wait(100)

        if LocalPlayer.state.isLoggedIn then
            local keys = {
                { key = 'N',   pad = 0, button = 249 }, -- Push-to-talk / Voice
                { key = 'M',   pad = 0, button = 244 }, -- Interaction menu
                { key = 'U',   pad = 0, button = 303 }, -- Job menu
                { key = 'I',   pad = 0, button = 199 }, -- Inventory / Phone
                { key = 'L',   pad = 0, button = 182 }, -- Lock vehicle
                { key = 'Z',   pad = 0, button = 20  }, -- Multiplayer info
                { key = 'X',   pad = 0, button = 73  }, -- Hands up
            }

            for _, k in ipairs(keys) do
                local pressed = IsControlPressed(k.pad, k.button) or IsDisabledControlPressed(k.pad, k.button)
                SendNUIMessage({
                    action = 'keyState',
                    key = k.key,
                    active = pressed
                })
            end
        end
    end
end)

-- ============================================================
-- VEHICLE HUD (future hook)
-- ============================================================
CreateThread(function()
    while true do
        Wait(500)

        if LocalPlayer.state.isLoggedIn then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)

            if veh ~= 0 then
                -- Future: send speed, fuel, gear to UI
                -- SendNUIMessage({ action = 'updateVehicle', speed = ..., fuel = ... })
            end
        end
    end
end)

-- ============================================================
-- NOTIFICATION BRIDGE
-- ============================================================
RegisterNetEvent('cm-hud:client:notify', function(text, type)
    SendNUIMessage({
        action = 'notify',
        text = text,
        type = type or 'info'
    })
end)

-- ============================================================
-- RESOURCE START
-- ============================================================
AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        Wait(1000)
        if LocalPlayer.state.isLoggedIn then
            local serverId = GetPlayerServerId(PlayerId())
            SendNUIMessage({
                action = 'init',
                state = {
                    serverName = 'CM-RP',
                    serverId = serverId,
                    level = 1,
                    onlinePlayers = #GetActivePlayers(),
                    cash = currentCash,
                    bank = currentBank,
                    health = GetEntityHealth(PlayerPedId()),
                    armor = GetPedArmour(PlayerPedId()),
                    area = currentArea,
                    street = currentStreet
                }
            })
        end
    end
end)