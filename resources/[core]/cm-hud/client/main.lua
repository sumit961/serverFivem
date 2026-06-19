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
local hudMouseOpen = false

local wasInVehicle = false
local lastVehiclePayload = nil

-- ============================================================
-- NUI FOCUS SAFETY
-- HUD must never take keyboard/mouse focus. If focus stays enabled,
-- the player can feel frozen/stuck and movement keys will not work.
-- ============================================================
local function clearHudNuiFocus()
    hudMouseOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'setMouseOpen', open = false })
end

RegisterCommand('hudfix', function()
    clearHudNuiFocus()
    SendNUIMessage({ action = 'hideDeath' })
    print('[CM-HUD] NUI focus cleared')
end, false)


-- ============================================================
-- LEFT QUICK ACTION MOUSE TOGGLE
-- Press ` / ~ to unlock the mouse for the left-side HUD buttons.
-- Press again, press ESC/backspace, or click the ~ button to lock mouse again.
-- ============================================================
local function setHudMouse(open)
    hudMouseOpen = open == true
    SetNuiFocus(hudMouseOpen, hudMouseOpen)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'setMouseOpen', open = hudMouseOpen })
end

RegisterCommand('hudmouse', function()
    setHudMouse(not hudMouseOpen)
end, false)

RegisterKeyMapping('hudmouse', 'Toggle HUD mouse', 'keyboard', 'GRAVE')
RegisterKeyMapping('hudmouse', 'Toggle HUD mouse alternate', 'keyboard', 'OEM_3')

RegisterNUICallback('closeHudMouse', function(data, cb)
    setHudMouse(false)
    cb('ok')
end)

RegisterNUICallback('hudQuickAction', function(data, cb)
    local action = data and data.action or ''

    if action == 'close' then
        setHudMouse(false)
    elseif action == 'menu' then
        ExecuteCommand('menu')
        setHudMouse(false)
    elseif action == 'phone' then
        ExecuteCommand('phone')
        setHudMouse(false)
    elseif action == 'inventory' then
        ExecuteCommand('inventory')
        setHudMouse(false)
    elseif action == 'lock' then
        ExecuteCommand('lock')
        setHudMouse(false)
    elseif action == 'emote' then
        ExecuteCommand('emote')
        setHudMouse(false)
    end

    cb('ok')
end)

CreateThread(function()
    while true do
        Wait(0)

        -- Vehicle name
        HideHudComponentThisFrame(6)

        -- Area name
        HideHudComponentThisFrame(7)

        -- Vehicle class
        HideHudComponentThisFrame(8)

        -- Street name
        HideHudComponentThisFrame(9)
    end
end)

CreateThread(function()
    while true do
        Wait(0)
        if hudMouseOpen then
            -- ESC / Backspace closes HUD mouse so player never gets stuck in focus.
            if IsControlJustReleased(0, 322) or IsControlJustReleased(0, 177) then
                setHudMouse(false)
            end
        else
            Wait(250)
        end
    end
end)


-- ============================================================
-- NATIVE GTA MINIMAP / RADAR
-- ============================================================
local function setupNativeMinimap()
    -- Use GTA's real radar/minimap. The old HTML minimap placeholder was removed
    -- because NUI cannot render the actual GTA map inside a div.
    SetRadarBigmapEnabled(false, false)
    SetRadarZoom(1100)
end

local function isHudEnabled()
    return LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn
end

-- ============================================================
-- INIT
-- ============================================================
RegisterNetEvent('cm-playerdata:client:loaded', function(data)
    Wait(500)
    clearHudNuiFocus()
    setupNativeMinimap()
    DisplayRadar(true)

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

    -- UI now uses GTA native health/armor under the minimap, so no custom health NUI update is needed.
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

    -- UI now uses GTA native health/armor under the minimap.
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
    clearHudNuiFocus()
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

                -- Custom health/armor NUI update removed; GTA native bars are used.
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
-- VEHICLE SPEEDOMETER
-- ============================================================
local function sendVehicleHidden()
    if wasInVehicle then
        wasInVehicle = false
        lastVehiclePayload = nil
        SendNUIMessage({ action = 'hideVehicle' })
    end
end

CreateThread(function()
    while true do
        Wait(100)

        if isHudEnabled() then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)

            if veh ~= 0 then
                wasInVehicle = true

                local speed = math.floor(GetEntitySpeed(veh) * 3.6 + 0.5) -- KM/H
                local rpm = math.floor((GetVehicleCurrentRpm(veh) or 0.0) * 100)
                local gear = GetVehicleCurrentGear(veh)
                local fuel = math.floor(GetVehicleFuelLevel(veh) + 0.5)
                local engine = math.floor(math.max(0.0, GetVehicleEngineHealth(veh)) / 10.0 + 0.5)
                local locked = GetVehicleDoorLockStatus(veh) >= 2

                if gear == 0 then
                    gear = speed > 1 and 'R' or 'N'
                end

                local payload = {
                    action = 'updateVehicle',
                    visible = true,
                    speed = speed,
                    unit = 'KM/H',
                    rpm = rpm,
                    gear = tostring(gear),
                    fuel = math.max(0, math.min(100, fuel)),
                    engine = math.max(0, math.min(100, engine)),
                    locked = locked
                }

                local encoded = json.encode(payload)
                if encoded ~= lastVehiclePayload then
                    lastVehiclePayload = encoded
                    SendNUIMessage(payload)
                end
            else
                sendVehicleHidden()
            end
        else
            DisplayRadar(false)
            sendVehicleHidden()
            Wait(500)
        end
    end
end)

-- Keep the real GTA minimap enabled when the player is logged in.
CreateThread(function()
    setupNativeMinimap()

    while true do
        Wait(1000)

        if isHudEnabled() then
            DisplayRadar(true)
            SetRadarBigmapEnabled(false, false)
        else
            DisplayRadar(false)
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
        clearHudNuiFocus()
        setupNativeMinimap()
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
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        DisplayRadar(true)
    end
end)
