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
local hudVisible = false
local characterId = nil
local characterName = 'Unknown'
local characterHints = {}
local loggedIn = false
local uiHiddenByExternal = false
local chatOpen = false
local setChatOpen
local seatbeltOn = false
local cruiseOn = false
local cruiseSpeed = 0.0
local isDeathThreadRunning = false

local wasInVehicle = false
local lastVehiclePayload = nil

-- ============================================================
-- NUI FOCUS SAFETY
-- HUD must never take keyboard/mouse focus. If focus stays enabled,
-- the player can feel frozen/stuck and movement keys will not work.
-- ============================================================
local function clearHudNuiFocus()
    hudMouseOpen = false
    chatOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'setMouseOpen', open = false })
    SendNUIMessage({ action = 'setChatOpen', open = false })
end

RegisterCommand('hudfix', function()
    clearHudNuiFocus()
    SendNUIMessage({ action = 'hideDeath' })
    print('[CM-HUD] NUI focus cleared')
end, false)

local function isPlayerLoggedIn()
    return loggedIn or (LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn == true)
end

local function setHudVisible(visible, external)
    if external ~= nil then uiHiddenByExternal = external == true end
    hudVisible = (visible == true) and isPlayerLoggedIn() and not uiHiddenByExternal
    DisplayRadar(hudVisible)
    SendNUIMessage({ action = 'setHudVisible', visible = hudVisible })
    if not hudVisible then
        SendNUIMessage({ action = 'hideVehicle' })
        if setChatOpen then setChatOpen(false) end
    end
end

RegisterCommand('togglehud', function()
    setHudVisible(not hudVisible)
end, false)

RegisterKeyMapping('togglehud', 'Toggle all HUD', 'keyboard', 'F7')



-- ============================================================
-- CUSTOM CHAT
-- Press T to open. Enter sends. Empty Enter / ESC closes.
-- Default GTA/FiveM chat text is disabled, this NUI chat is used instead.
-- ============================================================
function setChatOpen(open)
    chatOpen = open == true

    if chatOpen then
        hudMouseOpen = false
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        SendNUIMessage({ action = 'setMouseOpen', open = false })
    else
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
    end

    SendNUIMessage({ action = 'setChatOpen', open = chatOpen })
end

RegisterCommand('cmchat', function()
    if not hudVisible then return end
    setChatOpen(true)
end, false)
RegisterKeyMapping('cmchat', 'Open RP chat', 'keyboard', 'T')

RegisterNUICallback('chatClose', function(data, cb)
    setChatOpen(false)
    cb('ok')
end)

RegisterNUICallback('chatSend', function(data, cb)
    local channel = data and data.channel or 'rp'
    local msg = data and data.text or ''
    msg = tostring(msg or ''):gsub('[\r\n\t]+', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 180)

    if msg:gsub('%s+', '') ~= '' then
        if msg:sub(1, 1) == '/' then
            -- Route slash messages to FiveM/GTA command handler. Example: /me waves
            ExecuteCommand(msg:sub(2))
            setChatOpen(false)
        else
            TriggerServerEvent('cm-hud:server:sendChatMessage', channel, msg)
            -- Close the input box after sending. Chat history remains visible.
            setChatOpen(false)
        end
    else
        setChatOpen(false)
    end

    cb('ok')
end)

RegisterNetEvent('cm-hud:client:addChatMessage', function(message)
    SendNUIMessage({ action = 'addChatMessage', message = message })
end)

RegisterNetEvent('cm-hud:client:setChatChannels', function(channels)
    SendNUIMessage({ action = 'setChatChannels', channels = channels })
end)

CreateThread(function()
    Wait(1000)
    if SetTextChatEnabled then SetTextChatEnabled(false) end
    TriggerServerEvent('cm-hud:server:requestChatChannels')

    while true do
        Wait(0)
        -- Hide default GTA/FiveM location, street and vehicle name popups.
        HideHudComponentThisFrame(6)
        HideHudComponentThisFrame(7)
        HideHudComponentThisFrame(8)
        HideHudComponentThisFrame(9)

        if chatOpen then
            DisableAllControlActions(0)
            EnableControlAction(0, 1, true)   -- Look left/right
            EnableControlAction(0, 2, true)   -- Look up/down
            EnableControlAction(0, 200, true) -- ESC pause menu
            if IsControlJustReleased(0, 322) or IsControlJustReleased(0, 177) then
                setChatOpen(false)
            end
        end
    end
end)


-- Auto-hide HUD when another NUI takes focus (inventory, store, phone, menus).
-- Chat and HUD mouse are excluded because they belong to this resource.
CreateThread(function()
    local lastExternalFocus = false
    while true do
        Wait(250)
        if isPlayerLoggedIn() then
            local focused = false
            if IsNuiFocused then focused = IsNuiFocused() == true end
            local externalFocus = focused and not chatOpen and not hudMouseOpen
            if externalFocus ~= lastExternalFocus then
                lastExternalFocus = externalFocus
                uiHiddenByExternal = externalFocus
                setHudVisible(not externalFocus)
            end
        elseif hudVisible then
            setHudVisible(false)
        end
    end
end)

-- ============================================================
-- LEFT QUICK ACTION MOUSE TOGGLE
-- Press ` / ~ to unlock the mouse for the left-side HUD buttons.
-- Press again, press ESC/backspace, or click the ~ button to lock mouse again.
-- ============================================================
local function setHudMouse(open)
    hudMouseOpen = open == true
    if hudMouseOpen then
        chatOpen = false
        SendNUIMessage({ action = 'setChatOpen', open = false })
    end
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
    return hudVisible and isPlayerLoggedIn()
end


local function cleanLocalCharacterId(value)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    return value
end

local function extractLocalCharacterId(value)
    if type(value) == 'table' then
        local found = value.id or value.characterId or value.charId or value.charid or value.char_id or value.citizenid
        if found then return cleanLocalCharacterId(found) end
        if type(value.character) == 'table' then
            return extractLocalCharacterId(value.character)
        end
        return nil
    end
    return cleanLocalCharacterId(value)
end

local function captureStateCharacterHints()
    if not LocalPlayer or not LocalPlayer.state then return end
    local state = LocalPlayer.state
    characterId = characterId
        or extractLocalCharacterId(state.characterId)
        or extractLocalCharacterId(state.charId)
        or extractLocalCharacterId(state.charid)
        or extractLocalCharacterId(state.char_id)
        or extractLocalCharacterId(state.citizenid)
        or extractLocalCharacterId(state.currentCharacterId)

    characterHints.id = characterHints.id or characterId
    characterHints.characterId = characterHints.characterId or characterId
    characterHints.account_id = characterHints.account_id or state.account_id or state.accountId or state.account or state.accountid
    characterHints.slot = characterHints.slot or state.slot or state.charSlot or state.character_slot
end

local function syncCharacterHudFromData(data)
    data = data or {}
    local newId = extractLocalCharacterId(data)
    if newId then characterId = newId end

    local first = data.first_name or data.firstname
    local last = data.last_name or data.lastname
    local full = ((first or '') .. ' ' .. (last or '')):gsub('^%s+', ''):gsub('%s+$', '')
    if full ~= '' then characterName = full elseif data.name then characterName = tostring(data.name) end

    characterHints = characterHints or {}
    characterHints.id = characterId
    characterHints.characterId = characterId
    characterHints.account_id = data.account_id or data.accountId or data.account or data.accountid or characterHints.account_id
    characterHints.slot = data.slot or data.charSlot or data.character_slot or characterHints.slot

    captureStateCharacterHints()
    TriggerServerEvent('cm-hud:server:requestCharacterHud', characterId, characterHints)
    if characterId then TriggerServerEvent('cm-hud:server:setCharacter', characterId) end
end

for _, eventName in ipairs({
    'cm-characters:client:characterLoaded',
    'cm-characters:client:characterSelected',
    'cm-characters:client:selectedCharacter',
    'cm-spawn:client:characterLoaded',
    'cm-spawn:characterLoaded',
    'cm-core:client:characterLoaded'
}) do
    RegisterNetEvent(eventName, function(data, extra)
        if type(data) == 'table' then
            syncCharacterHudFromData(data)
        else
            syncCharacterHudFromData({ id = data, characterId = data, slot = extra })
        end
    end)
end

-- ============================================================
-- INIT
-- ============================================================
RegisterNetEvent('cm-playerdata:client:loaded', function(data)
    loggedIn = true
    data = data or {}
    characterId = data.id or data.characterId or data.citizenid or data.charid or data.char_id
    characterName = ((data.first_name or data.firstname or '') .. ' ' .. (data.last_name or data.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    if characterName == '' then characterName = data.name or 'Unknown' end
    characterHints = {
        id = characterId,
        characterId = characterId,
        account_id = data.account_id or data.accountId or data.account or data.accountid,
        slot = data.slot or data.charSlot or data.character_slot,
        first_name = data.first_name or data.firstname,
        last_name = data.last_name or data.lastname
    }
    Wait(500)
    clearHudNuiFocus()
    setupNativeMinimap()
    if SetTextChatEnabled then SetTextChatEnabled(false) end
    TriggerServerEvent('cm-hud:server:requestChatChannels')
    uiHiddenByExternal = false
    setHudVisible(true)

    currentHealth = data.health or 200
    currentArmor = data.armor or 0
    currentCash = data.cash or 0
    currentBank = data.bank or 0

    local serverId = characterId or ''

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

    captureStateCharacterHints()
    TriggerServerEvent('cm-hud:server:requestCharacterHud', characterId, characterHints)
    if characterId then TriggerServerEvent('cm-hud:server:setCharacter', characterId) end
    print('[CM-HUD] Initialized | ID:' .. tostring(serverId))
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
        currentCash = tonumber(value) or currentCash
    elseif key == 'bank' then
        currentBank = tonumber(value) or currentBank
    end

    SendNUIMessage({
        action = 'updateMoney',
        cash = currentCash,
        bank = currentBank
    })
end)


RegisterNetEvent('cm-hud:client:updateCharacterHud', function(payload)
    payload = payload or {}
    if payload.id ~= nil and tostring(payload.id) ~= '' then characterId = tostring(payload.id) end
    if payload.name ~= nil and tostring(payload.name) ~= '' then characterName = tostring(payload.name) end
    if payload.cash ~= nil then currentCash = tonumber(payload.cash) or currentCash end
    if payload.bank ~= nil then currentBank = tonumber(payload.bank) or currentBank end

    SendNUIMessage({
        action = 'updateCharacterHud',
        id = characterId or '',
        name = characterName,
        cash = currentCash,
        bank = currentBank
    })
end)

RegisterNetEvent('cm-hud:client:setHudVisible', function(visible)
    uiHiddenByExternal = visible == false
    setHudVisible(visible == true)
end)

RegisterNetEvent('cm-hud:client:hideForUi', function()
    uiHiddenByExternal = true
    setHudVisible(false)
end)

RegisterNetEvent('cm-hud:client:showAfterUi', function()
    uiHiddenByExternal = false
    setHudVisible(true)
end)

exports('SetHudVisible', function(visible)
    uiHiddenByExternal = visible == false
    setHudVisible(visible == true)
end)

RegisterNetEvent('cm-playerdata:client:unloaded', function()
    loggedIn = false
    characterId = nil
    characterName = 'Unknown'
    characterHints = {}
    uiHiddenByExternal = false
    clearHudNuiFocus()
    setHudVisible(false)
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

    -- Local countdown until server says we can respawn. Guard prevents stacked threads.
    if not isDeathThreadRunning then
        isDeathThreadRunning = true
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
            isDeathThreadRunning = false
        end)
    end
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

        if isPlayerLoggedIn() then
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

        if isPlayerLoggedIn() then
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

        if isPlayerLoggedIn() then
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

        if isPlayerLoggedIn() then
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
-- VEHICLE INDICATORS
-- ============================================================
RegisterCommand('seatbelt', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        seatbeltOn = not seatbeltOn
        TriggerEvent('cm-hud:client:notify', seatbeltOn and 'Seatbelt fastened' or 'Seatbelt removed', seatbeltOn and 'success' or 'warning')
    end
end, false)
RegisterKeyMapping('seatbelt', 'Toggle seatbelt', 'keyboard', 'B')

RegisterCommand('cruise', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
        cruiseOn = not cruiseOn
        cruiseSpeed = GetEntitySpeed(veh)
        TriggerEvent('cm-hud:client:notify', cruiseOn and 'Cruise control enabled' or 'Cruise control disabled', cruiseOn and 'success' or 'info')
    end
end, false)
RegisterKeyMapping('cruise', 'Toggle cruise control', 'keyboard', 'Y')

-- ============================================================
-- VEHICLE SPEEDOMETER
-- ============================================================
local function sendVehicleHidden()
    if wasInVehicle then
        wasInVehicle = false
        lastVehiclePayload = nil
        seatbeltOn = false
        cruiseOn = false
        cruiseSpeed = 0.0
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

                if cruiseOn and GetPedInVehicleSeat(veh, -1) == ped and cruiseSpeed > 1.0 then
                    SetVehicleForwardSpeed(veh, cruiseSpeed)
                end

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
                    locked = locked,
                    seatbelt = seatbeltOn,
                    cruise = cruiseOn
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


-- ============================================================
-- NOTIFICATION BRIDGE
-- ============================================================
local function Notify(text, notifyType)
    if not isPlayerLoggedIn() then return end
    SendNUIMessage({
        action = 'notify',
        text = tostring(text or ''),
        type = notifyType or 'info'
    })
end

exports('Notify', Notify)
RegisterNetEvent('cm-hud:client:notify', function(text, type)
    Notify(text, type)
end)
RegisterNetEvent('cm-hud:notify', function(text, type)
    Notify(text, type)
end)

-- ============================================================
-- RESOURCE START
-- ============================================================
AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then
        Wait(500)
        setHudVisible(false)
        Wait(500)
        clearHudNuiFocus()
        setupNativeMinimap()
        if isPlayerLoggedIn() then
            local serverId = characterId or ''
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
