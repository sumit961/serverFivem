-- cm-hud/client/main.lua

local currentHealth = 200
local currentArmor = 0
local currentCash = 0
local currentBank = 0
local currentArea = 'Unknown'
local currentStreet = 'Unknown'
local currentDir = 'N'
local isDead = false
local deathTimer = 0
local canRespawn = false
local hudMouseOpen = false
local hudAdminOpen = false
local hudVisible = false
local characterId = nil
local characterName = 'Unknown'
local characterHints = {}
local loggedIn = false
local uiHiddenByExternal = false
local seatbeltOn = false
local cruiseOn = false
local cruiseSpeed = 0.0
local isDeathThreadRunning = false
local HUD_DEBUG = false
local function hudDebug(message)
    if HUD_DEBUG then print(message) end
end

local wasInVehicle = false
local lastVehiclePayload = nil
local lastSeatbeltAlarmAt = 0
local HIDE_DEFAULT_AMMO_PREVIEW = true
local HIDE_DEFAULT_VEHICLE_NAME = true



-- ============================================================
-- HUD ADMIN / USER SETTINGS
-- Saved locally per player with FiveM KVP. Open with /hud admin.
-- ============================================================
local HUD_DEFAULT_SETTINGS = {
    speedoStyle = 1,
    speedUnit = 'KM/H',
    theme = 'cyan',
    uiScale = 1.35,
    speedoScale = 1.0,
    locationOffsetX = -7,
    locationOffsetY = -112,
    speedoOffsetX = 0,
    speedoOffsetY = 0,
    showTopRight = true,
    showLocation = true,
    showLeftKeys = true,
    showTime = true,
    showSpeedometer = true,
    compactMode = false,
    previewVehicle = false
}

local hudSettings = {}
local function cloneTable(tbl)
    local out = {}
    for k, v in pairs(tbl or {}) do out[k] = v end
    return out
end

local function boolOrDefault(value, fallback)
    if value == nil then return fallback end
    return value == true
end

local function clampNumber(value, minVal, maxVal, fallback)
    local n = tonumber(value)
    if not n then return fallback end
    if n < minVal then return minVal end
    if n > maxVal then return maxVal end
    return n
end

local function normaliseHudSettings(raw)
    raw = type(raw) == 'table' and raw or {}
    local out = cloneTable(HUD_DEFAULT_SETTINGS)
    out.speedoStyle = math.floor(clampNumber(raw.speedoStyle, 1, 30, out.speedoStyle))
    out.speedUnit = tostring(raw.speedUnit or out.speedUnit):upper()
    if out.speedUnit ~= 'MPH' then out.speedUnit = 'KM/H' end
    out.theme = tostring(raw.theme or out.theme):lower()
    local allowedThemes = { cyan = true, blue = true, green = true, red = true, purple = true, yellow = true }
    if not allowedThemes[out.theme] then out.theme = 'cyan' end
    out.uiScale = clampNumber(raw.uiScale, 0.75, 1.35, out.uiScale)
    out.speedoScale = clampNumber(raw.speedoScale, 0.70, 1.40, out.speedoScale)
    out.locationOffsetX = math.floor(clampNumber(raw.locationOffsetX, -500, 500, out.locationOffsetX))
    out.locationOffsetY = math.floor(clampNumber(raw.locationOffsetY, -300, 300, out.locationOffsetY))
    out.speedoOffsetX = math.floor(clampNumber(raw.speedoOffsetX, -500, 500, out.speedoOffsetX))
    out.speedoOffsetY = math.floor(clampNumber(raw.speedoOffsetY, -300, 300, out.speedoOffsetY))
    out.showTopRight = boolOrDefault(raw.showTopRight, out.showTopRight)
    out.showLocation = boolOrDefault(raw.showLocation, out.showLocation)
    out.showLeftKeys = boolOrDefault(raw.showLeftKeys, out.showLeftKeys)
    out.showTime = boolOrDefault(raw.showTime, out.showTime)
    out.showSpeedometer = boolOrDefault(raw.showSpeedometer, out.showSpeedometer)
    out.compactMode = boolOrDefault(raw.compactMode, out.compactMode)
    out.previewVehicle = boolOrDefault(raw.previewVehicle, out.previewVehicle)
    return out
end

local function loadHudSettings()
    local raw = GetResourceKvpString('cm_hud_settings_v17')
    if raw and raw ~= '' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            hudSettings = normaliseHudSettings(decoded)
        else
            hudSettings = normaliseHudSettings({})
        end
    else
        hudSettings = normaliseHudSettings({})
    end
end

local function saveHudSettings()
    SetResourceKvp('cm_hud_settings_v17', json.encode(hudSettings))
end

local function sendHudSettings()
    SendNUIMessage({ action = 'setHudSettings', settings = hudSettings })
end

local function playHudSound(soundName, volume)
    SendNUIMessage({
        action = 'playHudSound',
        sound = tostring(soundName or ''),
        volume = tonumber(volume) or 0.55
    })
end

local function resetHudSettings()
    hudSettings = normaliseHudSettings({})
    saveHudSettings()
    sendHudSettings()
end

local function openHudAdmin()
    hudAdminOpen = true
    hudMouseOpen = false
    SendNUIMessage({ action = 'setMouseOpen', open = false })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    sendHudSettings()
    SendNUIMessage({ action = 'openHudAdmin', settings = hudSettings })
end

local function closeHudAdmin()
    hudAdminOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'closeHudAdmin' })
end

loadHudSettings()

-- ============================================================
-- NUI FOCUS SAFETY
-- HUD must never take keyboard/mouse focus. If focus stays enabled,
-- the player can feel frozen/stuck and movement keys will not work.
-- ============================================================
local function clearHudNuiFocus()
    hudMouseOpen = false
    hudAdminOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'setMouseOpen', open = false })
    SendNUIMessage({ action = 'closeHudAdmin' })
end

RegisterCommand('hudfix', function()
    clearHudNuiFocus()
    SendNUIMessage({ action = 'hideDeath' })
    hudDebug('[CM-HUD] NUI focus cleared')
end, false)

local function isPlayerLoggedIn()
    return loggedIn or (LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn == true)
end

local function isVehicleShopTestDriveState()
    local st = LocalPlayer and LocalPlayer.state
    if not st then return false end
    return st.cmVehicleShop == 'test_drive' or st.cmVehicleShopTestDrive == true
end

-- Some resources, especially showroom/admin UIs, teleport the player or briefly drop
-- NUI focus while the menu is still open. The old recovery loop could then show the
-- HUD again for a moment, causing a blink. Keep these explicit state locks authoritative.
local function isHudHiddenByExternalState()
    local st = LocalPlayer and LocalPlayer.state
    if not st then return false end

    local vehicleShopMode = st.cmVehicleShop
    -- Test drive is intentionally HUD-visible. Ignore any stale vehicle-shop hide
    -- state that may arrive from the showroom transition.
    if vehicleShopMode == 'test_drive' or st.cmVehicleShopTestDrive == true then
        return false
    end

    if st.cmHudHiddenByVehicleShop or st.cmHudHiddenByClothing or st.inClothingStore then
        return true
    end

    return vehicleShopMode == 'store' or vehicleShopMode == 'admin' or vehicleShopMode == 'capture'
end

local function setHudVisible(visible, external)
    if external ~= nil then uiHiddenByExternal = external == true end

    local externallyHidden = uiHiddenByExternal or isHudHiddenByExternalState()
    hudVisible = (visible == true) and isPlayerLoggedIn() and not externallyHidden

    -- Hide/show both the native GTA HUD and this custom NUI HUD.
    -- DisplayHud(false) alone does NOT hide cm-hud, so we also send setHudVisible to NUI.
    DisplayHud(hudVisible)
    DisplayRadar(hudVisible)
    SendNUIMessage({
        action = 'setHudVisible',
        visible = hudVisible,
        externalHidden = externallyHidden
    })

    if not hudVisible then
        SendNUIMessage({ action = 'hideVehicle' })
    end
end

-- UI-only visibility bridge.
-- Used by cm-characters during selector/creation so only the CM NUI HUD is hidden.
-- This intentionally does NOT call DisplayHud() or DisplayRadar(), so the GTA minimap/native
-- HUD cannot get stuck hidden after character creation closes.
local function setHudUiOnlyVisible(visible, reason)
    local shouldShow = (visible == true) and isPlayerLoggedIn() and not isHudHiddenByExternalState()
    hudVisible = shouldShow

    SendNUIMessage({
        action = 'setHudVisible',
        visible = shouldShow,
        externalHidden = not shouldShow,
        reason = reason or 'ui_only'
    })

    if not shouldShow then
        SendNUIMessage({ action = 'hideVehicle' })
    end
end

RegisterCommand('togglehud', function()
    setHudVisible(not hudVisible)
end, false)

RegisterKeyMapping('togglehud', 'Toggle all HUD', 'keyboard', 'F7')


RegisterCommand('hud', function(_, args)
    local sub = args and tostring(args[1] or ''):lower() or ''

    if sub == 'admin' or sub == 'settings' or sub == '' then
        openHudAdmin()
        return
    end

    if sub == 'reset' then
        resetHudSettings()
        TriggerEvent('cm-hud:client:notify', 'HUD settings reset', 'success')
        return
    end

    if sub == 'speedo' or sub == 'speedometer' then
        local id = math.floor(clampNumber(args and args[2], 1, 30, hudSettings.speedoStyle or 1))
        hudSettings.speedoStyle = id
        saveHudSettings()
        sendHudSettings()
        TriggerEvent('cm-hud:client:notify', ('Speedometer style %s selected'):format(id), 'success')
        return
    end

    TriggerEvent('cm-hud:client:notify', 'Use /hud admin, /hud speedo 1-30, or /hud reset', 'info')
end, false)



-- Chat was moved to cm-chat. HUD no longer owns chat focus or chat NUI.


-- Auto-hide HUD when another NUI takes focus (inventory, store, phone, menus).
-- HUD mouse is excluded because it belongs to this resource. cm-chat now owns chat focus.
CreateThread(function()
    local lastExternalFocus = false
    while true do
        Wait(250)
        if isPlayerLoggedIn() then
            local focused = false
            if IsNuiFocused then focused = IsNuiFocused() == true end
            local externalFocus = focused and not hudMouseOpen and not hudAdminOpen
            local stateHidden = isHudHiddenByExternalState()

            if stateHidden then
                -- Explicit locks from clothing/vehicle/admin resources always win over
                -- the recovery logic. This prevents HUD blink while a UI owns the screen.
                uiHiddenByExternal = true
                setHudVisible(false)
            elseif externalFocus ~= lastExternalFocus then
                lastExternalFocus = externalFocus
                uiHiddenByExternal = externalFocus
                setHudVisible(not externalFocus)
            elseif not externalFocus and not uiHiddenByExternal and not hudVisible then
                -- Recovery: logged in, nothing external hiding us, but HUD is off.
                -- This catches routing-bucket-driven unload/reload cycles where
                -- cm-playerdata fires 'unloaded' without a matching 'loaded'.
                setHudVisible(true)
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
    if open == true and hudAdminOpen then closeHudAdmin() end
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

-- Lightweight visual-only key listeners for radio indicators.
-- These do not run gameplay logic; future family/org resources can own the real radio actions.
local visualKeyState = { O = false, U = false }
local function setVisualKeyState(key, active)
    key = tostring(key or ''):upper()
    active = active == true
    if visualKeyState[key] == active then return end
    visualKeyState[key] = active
    if isPlayerLoggedIn() then
        SendNUIMessage({ action = 'keyState', key = key, active = active })
    end
end

RegisterCommand('+cmhud_family_radio_visual', function() setVisualKeyState('O', true) end, false)
RegisterCommand('-cmhud_family_radio_visual', function() setVisualKeyState('O', false) end, false)
RegisterKeyMapping('+cmhud_family_radio_visual', 'HUD family radio indicator', 'keyboard', 'O')

RegisterCommand('+cmhud_org_radio_visual', function() setVisualKeyState('U', true) end, false)
RegisterCommand('-cmhud_org_radio_visual', function() setVisualKeyState('U', false) end, false)
RegisterKeyMapping('+cmhud_org_radio_visual', 'HUD organization radio indicator', 'keyboard', 'U')


RegisterNUICallback('closeHudMouse', function(data, cb)
    setHudMouse(false)
    cb('ok')
end)

RegisterNUICallback('hudAdminClose', function(data, cb)
    closeHudAdmin()
    cb('ok')
end)

RegisterNUICallback('hudAdminSave', function(data, cb)
    hudSettings = normaliseHudSettings(data and data.settings or data or {})
    saveHudSettings()
    sendHudSettings()
    cb({ ok = true, settings = hudSettings })
end)

RegisterNUICallback('hudAdminReset', function(data, cb)
    resetHudSettings()
    cb({ ok = true, settings = hudSettings })
end)

RegisterNUICallback('hudAdminPreview', function(data, cb)
    hudSettings.previewVehicle = data and data.enabled == true
    saveHudSettings()
    sendHudSettings()
    if hudSettings.previewVehicle then
        SendNUIMessage({
            action = 'updateVehicle',
            visible = true,
            vehType = 'car',
            speed = hudSettings.speedUnit == 'MPH' and 88 or 142,
            unit = hudSettings.speedUnit,
            rpm = 73,
            gear = '4',
            fuel = 64,
            engine = 92,
            locked = true,
            seatbelt = true,
            cruise = false,
            lights = 1
        })
    elseif not wasInVehicle then
        SendNUIMessage({ action = 'hideVehicle' })
    end
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
        elseif hudAdminOpen then
            if IsControlJustReleased(0, 322) or IsControlJustReleased(0, 177) then
                closeHudAdmin()
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

-- Native minimap position changes with resolution, aspect ratio and GTA safe-zone.
-- The NUI location block now follows the real minimap instead of using vw/vh.
local function getScreenData()
    local resX, resY = GetActiveScreenResolution()
    local nuiX, nuiY = resX, resY

    local getNuiRes = rawget(_G, 'GetNuiScreenResolution') or rawget(_G, 'GetNUIScreenResolution')
    if getNuiRes then
        local ok, x, y = pcall(getNuiRes)
        if ok and tonumber(x) and tonumber(y) and x > 0 and y > 0 then
            nuiX, nuiY = x, y
        end
    end

    if not nuiX or nuiX <= 0 then nuiX = 1920 end
    if not nuiY or nuiY <= 0 then nuiY = 1080 end
    if not resX or resX <= 0 then resX = nuiX end
    if not resY or resY <= 0 then resY = nuiY end

    local aspect = GetAspectRatio(false)
    local getNuiAspect = rawget(_G, 'GetNuiAspectRatio') or rawget(_G, 'GetNUIAspectRatio')
    if getNuiAspect then
        local ok, a = pcall(getNuiAspect)
        if ok and tonumber(a) and a > 0.0 then aspect = a end
    end
    if not aspect or aspect <= 0.0 then aspect = nuiX / nuiY end

    return resX, resY, nuiX, nuiY, aspect
end

-- JG-style minimap bounds calculation, adapted for CM HUD.
-- This follows NUI resolution + safe-zone + aspect ratio, so location text stays
-- correct on 1080p, 1440p/taller, windowed mode and ultrawide screens.
local function getMinimapAnchorPx()
    local resX, resY, nuiX, nuiY, aspectRatio = getScreenData()
    local safezone = GetSafeZoneSize()
    local standardAspect = 16.0 / 9.0

    local yOffset = -0.06
    if nuiY < 1400 then yOffset = -0.06 end
    if nuiY < 1240 then yOffset = -0.07 end
    if nuiY < 1050 then yOffset = -0.09 end
    if nuiY < 850 then yOffset = -0.10 end
    if nuiY < 650 then yOffset = -0.14 end

    local xOffset = 0.0
    if aspectRatio > standardAspect then
        xOffset = (standardAspect - aspectRatio) / 3.6
    end

    local left, top, width, height
    local ok = pcall(function()
        SetScriptGfxAlign(string.byte('L'), string.byte('B'))
        local baseX = select(1, GetScriptGfxPosition(0.0, -0.186888))
        local adjustedX, adjustedY = GetScriptGfxPosition(0.0 + (xOffset / (aspectRatio / standardAspect)), -0.186888 + yOffset)
        ResetScriptGfxAlign()

        local calcAspect = aspectRatio
        if calcAspect > 2.0 then calcAspect = standardAspect end

        left = nuiX * adjustedX
        top = nuiY * adjustedY
        width = nuiX / (4.0 * calcAspect)

        local scaleFactor = 1.0
        if aspectRatio > 2.0 then
            scaleFactor = 0.76
        elseif aspectRatio > 1.8 then
            scaleFactor = 0.995
        end
        width = width * scaleFactor
        width = width * ((nuiX * (1.0 / safezone)) - (nuiX * baseX * 2.0)) / nuiX
        height = nuiY / 5.5
    end)

    if not ok or not left or not top or left ~= left or top ~= top then
        local safeDiff = math.abs((safezone or 1.0) - 1.0)
        width = nuiX / (4.0 * math.max(1.33, aspectRatio))
        height = nuiY / 5.674
        left = nuiX * ((1.0 / 20.0) * (safeDiff * 10.0))
        top = nuiY - height - (nuiY * ((1.0 / 20.0) * (safeDiff * 10.0)))
    end

    if left < 0 then left = 0 end
    if top < 0 then top = 0 end
    local right = left + width
    local bottom = top + height

    local locOffsetX = hudSettings.locationOffsetX or 0
    local locOffsetY = hudSettings.locationOffsetY or 0
    local locationLeft = math.floor(math.min(nuiX - 420, math.max(220, right + 18)) + locOffsetX)
    local locationBottom = math.floor(math.min(nuiY - 90, math.max(28, (nuiY - bottom) + 16)) + locOffsetY)

    local uiScale = 1.0
    if nuiY >= 1400 then uiScale = 1.04 end
    if nuiY <= 900 then uiScale = 0.92 end

    return {
        action = 'updateLayout',
        screenW = nuiX,
        screenH = nuiY,
        gameW = resX,
        gameH = resY,
        aspect = aspectRatio,
        minimapLeft = math.floor(left),
        minimapRight = math.floor(right),
        minimapTop = math.floor(top),
        minimapBottom = math.floor(bottom),
        locationLeft = locationLeft,
        locationBottom = locationBottom,
        uiScale = uiScale
    }
end

local function sendHudLayout()
    SendNUIMessage(getMinimapAnchorPx())
end

CreateThread(function()
    local lastLayout = ''
    while true do
        Wait(1500)
        if isPlayerLoggedIn() then
            local layout = getMinimapAnchorPx()
            local encoded = json.encode(layout)
            if encoded ~= lastLayout then
                lastLayout = encoded
                SendNUIMessage(layout)
            end
        end
    end
end)

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
    sendHudLayout()
    uiHiddenByExternal = false
    setHudVisible(true)
    sendHudSettings()
    sendHudLayout()

    currentHealth = data.health or 200
    currentArmor = data.armor or 0
    currentCash = data.cash or 0
    currentBank = data.bank or 0

    local serverId = characterId or ''

    SendNUIMessage({
        action = 'init',
        state = {
            hudSettings = hudSettings,
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
    hudDebug('[CM-HUD] Initialized | ID:' .. tostring(serverId))
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
    -- Vehicle test drive must stay HUD-visible. Ignore stale hide events from the
    -- showroom/admin transition, but still allow explicit show events.
    if visible == false and isVehicleShopTestDriveState() then return end
    uiHiddenByExternal = visible == false
    setHudVisible(visible == true)
end)

RegisterNetEvent('cm-hud:client:hideForUi', function(reason)
    -- Explicit bridge used by inventory/phone/store UI.
    if isVehicleShopTestDriveState() or reason == 'test_drive' then return end
    uiHiddenByExternal = true
    setHudVisible(false)
end)

RegisterNetEvent('cm-hud:client:showAfterUi', function()
    -- Restore after external UI closes, but never override an active store/admin lock.
    if isHudHiddenByExternalState() then
        uiHiddenByExternal = true
        setHudVisible(false)
        return
    end

    uiHiddenByExternal = false
    setHudVisible(true)
    -- Belt-and-suspenders: if isPlayerLoggedIn() was temporarily false (e.g. after a
    -- routing-bucket change when the vehicle shop sends the player back to bucket 0),
    -- setHudVisible(true) above would leave hudVisible=false. Force it here so the NUI
    -- panel always appears when an in-game UI explicitly tells us to show.
    if not hudVisible and not isHudHiddenByExternalState() then
        hudVisible = true
        DisplayHud(true)
        DisplayRadar(true)
        SendNUIMessage({ action = 'setHudVisible', visible = true, externalHidden = false })
    end
end)

exports('SetHudVisible', function(visible)
    if visible == false and isVehicleShopTestDriveState() then return end
    uiHiddenByExternal = visible == false
    setHudVisible(visible == true)
end)

RegisterNetEvent('cm-hud:client:hideUiOnly', function(reason)
    if isVehicleShopTestDriveState() or reason == 'test_drive' then return end
    uiHiddenByExternal = true
    setHudUiOnlyVisible(false, reason or 'ui_only')
end)

RegisterNetEvent('cm-hud:client:showUiOnly', function(reason)
    if isHudHiddenByExternalState() then
        uiHiddenByExternal = true
        setHudUiOnlyVisible(false, reason or 'ui_only')
        return
    end

    uiHiddenByExternal = false
    setHudUiOnlyVisible(true, reason or 'ui_only')
end)

RegisterNetEvent('cm-hud:client:setUiVisible', function(visible, reason)
    if visible == false and isVehicleShopTestDriveState() then return end
    uiHiddenByExternal = visible ~= true
    setHudUiOnlyVisible(visible == true, reason or 'ui_only')
end)

exports('SetUiVisible', function(visible, reason)
    if visible == false and isVehicleShopTestDriveState() then return end
    uiHiddenByExternal = visible ~= true
    setHudUiOnlyVisible(visible == true, reason or 'ui_only_export')
end)

exports('HideUiOnly', function(reason)
    if isVehicleShopTestDriveState() then return end
    uiHiddenByExternal = true
    setHudUiOnlyVisible(false, reason or 'ui_only_export')
end)

exports('ShowUiOnly', function(reason)
    if isHudHiddenByExternalState() then return end
    uiHiddenByExternal = false
    setHudUiOnlyVisible(true, reason or 'ui_only_export')
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
-- Death UI is owned by cm-playerdata (v1.7 medical layer: bleed-out screen,
-- ambulance/give-up choices, death cam). The HUD only tracks the dead flag so
-- other HUD modules can react; it never draws a death overlay anymore.
RegisterNetEvent('cm-playerdata:client:playerDied', function()
    isDead = true
    canRespawn = false
    deathTimer = 0
    SendNUIMessage({ action = 'hideDeath' })
end)

RegisterNetEvent('cm-playerdata:client:canRespawn', function()
    -- handled by cm-playerdata; kept for event compatibility
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
-- HIDE GTA DEFAULT WEAPON / AMMO PREVIEW + VEHICLE NAME POPUP
-- Keeps CM HUD clean and prevents GTA's default ammo/weapon box
-- and default vehicle name/class popups from appearing over the custom HUD.
-- ============================================================
CreateThread(function()
    while true do
        if isPlayerLoggedIn() and hudVisible and not uiHiddenByExternal then
            if HIDE_DEFAULT_AMMO_PREVIEW then
                HideHudComponentThisFrame(2)   -- Weapon icon / ammo preview
                HideHudComponentThisFrame(20)  -- Weapon wheel stats
                HideHudComponentThisFrame(22)  -- Weapon wheel components
                pcall(function() DisplayAmmoThisFrame(false) end)
            end

            if HIDE_DEFAULT_VEHICLE_NAME then
                local ped = PlayerPedId()
                if ped and ped ~= 0 and IsPedInAnyVehicle(ped, false) then
                    HideHudComponentThisFrame(6) -- Vehicle name popup
                    HideHudComponentThisFrame(8) -- Vehicle class/name popup
                end
            end

            Wait(0)
        else
            Wait(500)
        end
    end
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

            -- Death detection is owned by cm-playerdata (it reports the killer
            -- and weapon; a bare event from here would race it and win the
            -- server's rate limit, wiping the killed-by info and kill logs).
            if health <= 100 and not isDead then
                isDead = true
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

            -- Compass letter (Grand RP style: shown next to the street name).
            local heading = 360.0 - GetEntityHeading(ped)
            local dirs = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N' }
            local dir = dirs[math.floor(((heading % 360) + 22.5) / 45) + 1] or 'N'

            if area ~= currentArea or street ~= currentStreet or dir ~= currentDir then
                currentArea = area
                currentStreet = street
                currentDir = dir

                SendNUIMessage({
                    action = 'updateLocation',
                    area = area,
                    street = street,
                    dir = dir
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
local lastHudKeyStates = {}
CreateThread(function()
    while true do
        Wait(100)

        if isPlayerLoggedIn() then
            local keys = {
                { key = 'N',   pad = 0, button = 249 }, -- Push-to-talk / Voice
                { key = 'M',   pad = 0, button = 244 }, -- Interaction menu
                { key = 'I',   pad = 0, button = 199 }, -- Inventory / Phone
                { key = 'L',   pad = 0, button = 182 }, -- Lock vehicle
                { key = 'Z',   pad = 0, button = 20  }, -- Multiplayer info
                { key = 'X',   pad = 0, button = 73  }, -- Hands up
            }

            for _, k in ipairs(keys) do
                local pressed = IsControlPressed(k.pad, k.button) or IsDisabledControlPressed(k.pad, k.button)
                if lastHudKeyStates[k.key] ~= pressed then
                    lastHudKeyStates[k.key] = pressed
                    SendNUIMessage({
                        action = 'keyState',
                        key = k.key,
                        active = pressed
                    })
                end
            end
        elseif next(lastHudKeyStates) ~= nil then
            for key, active in pairs(lastHudKeyStates) do
                if active then SendNUIMessage({ action = 'keyState', key = key, active = false }) end
            end
            lastHudKeyStates = {}
        end
    end
end)

-- ============================================================
-- VEHICLE INDICATORS
-- ============================================================
local function canVehicleUseSeatbelt(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local class = GetVehicleClass(vehicle)
    local allowed = {
        [0] = true, [1] = true, [2] = true, [3] = true, [4] = true,
        [5] = true, [6] = true, [7] = true, [9] = true, [10] = true,
        [11] = true, [12] = true, [17] = true, [18] = true,
        [19] = true, [20] = true
    }
    return allowed[class] == true
end

RegisterCommand('seatbelt', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and canVehicleUseSeatbelt(veh) then
        seatbeltOn = not seatbeltOn
        LocalPlayer.state:set('seatbelt', seatbeltOn, true)
        playHudSound(seatbeltOn and 'seatbelt-on' or 'seatbelt-off', seatbeltOn and 0.62 or 0.58)
        TriggerEvent('cm-hud:client:notify', seatbeltOn and 'Seatbelt fastened' or 'Seatbelt removed', seatbeltOn and 'success' or 'warning')
    elseif veh ~= 0 then
        TriggerEvent('cm-hud:client:notify', 'This vehicle has no seatbelt', 'info')
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
        LocalPlayer.state:set('seatbelt', false, true)
        SendNUIMessage({ action = 'hideVehicle' })
    end
end

CreateThread(function()
    local lastVeh = 0
    local vehType = 'car'

    -- Electric models get the digital speedo. Extend in Config.ElectricModels.
    local electricModels = {}
    for _, model in ipairs((Config and Config.ElectricModels) or {
        'voltic', 'voltic2', 'raiden', 'cyclone', 'neon', 'tezeract', 'imorgon',
        'dilettante', 'dilettante2', 'khamelion', 'surge', 'iwagen', 'virtue',
        'omnisegt', 'caddy', 'caddy2', 'caddy3', 'airtug', 'rcbandito', 'inductor', 'inductor2'
    }) do
        electricModels[GetHashKey(model)] = true
    end

    while true do
        Wait(100)

        if isHudEnabled() then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)

            local isDriver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped

            if veh ~= 0 and isDriver and hudSettings.showSpeedometer ~= false then
                wasInVehicle = true

                if veh ~= lastVeh then
                    lastVeh = veh
                    local vclass = GetVehicleClass(veh)
                    if vclass == 13 then vehType = 'bike'
                    elseif vclass == 14 then vehType = 'boat'
                    elseif vclass == 15 or vclass == 16 then vehType = 'air'
                    elseif vclass == 21 then vehType = 'train'
                    elseif electricModels[GetEntityModel(veh)] then vehType = 'electric'
                    else vehType = 'car' end

                    if not canVehicleUseSeatbelt(veh) then
                        seatbeltOn = false
                        LocalPlayer.state:set('seatbelt', false, true)
                    end
                end

                local speedMultiplier = (hudSettings.speedUnit == 'MPH') and 2.236936 or 3.6
                local speed = math.floor(GetEntitySpeed(veh) * speedMultiplier + 0.5)
                local rpm = math.floor((GetVehicleCurrentRpm(veh) or 0.0) * 100)
                local gear = GetVehicleCurrentGear(veh)
                local fuel = math.floor(GetVehicleFuelLevel(veh) + 0.5)
                local engine = math.floor(math.max(0.0, GetVehicleEngineHealth(veh)) / 10.0 + 0.5)
                local locked = GetVehicleDoorLockStatus(veh) >= 2

                if canVehicleUseSeatbelt(veh) and not seatbeltOn and speed > 25 then
                    local now = GetGameTimer()
                    if now - lastSeatbeltAlarmAt > 6500 then
                        lastSeatbeltAlarmAt = now
                        playHudSound('seatbelt-alarm', 0.32)
                    end
                end

                if cruiseOn and GetPedInVehicleSeat(veh, -1) == ped and cruiseSpeed > 1.0 then
                    SetVehicleForwardSpeed(veh, cruiseSpeed)
                end

                if gear == 0 then
                    gear = speed > 1 and 'R' or 'N'
                end

                local payload = {
                    action = 'updateVehicle',
                    visible = true,
                    vehType = vehType,
                    speed = speed,
                    unit = hudSettings.speedUnit or 'KM/H',
                    rpm = rpm,
                    gear = tostring(gear),
                    fuel = math.max(0, math.min(100, fuel)),
                    engine = math.max(0, math.min(100, engine)),
                    locked = locked,
                    seatbelt = seatbeltOn,
                    cruise = cruiseOn,
                    lights = (function()
                        local _, low, high = GetVehicleLightsState(veh)
                        return (low == 1 or high == 1) and (high == 1 and 2 or 1) or 0
                    end)()
                }

                if vehType == 'air' then
                    local rot = GetEntityRotation(veh, 2)
                    local coords = GetEntityCoords(veh)
                    payload.heading = math.floor(360.0 - GetEntityHeading(veh))
                    payload.altitude = math.floor(coords.z)
                    payload.pitch = math.floor(rot.x)
                    payload.roll = math.floor(rot.y)
                    payload.gearDown = GetLandingGearState(veh) == 0
                    payload.stall = (speed < 90 and coords.z > 120)
                elseif vehType == 'boat' then
                    payload.anchor = GetVehicleHandbrake and GetVehicleHandbrake(veh) or false
                elseif vehType == 'train' then
                    payload.heading = math.floor(360.0 - GetEntityHeading(veh))
                end

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
local lastNotifyHash = nil
local lastNotifyAt = 0
local function Notify(text, notifyType)
    if not isPlayerLoggedIn() then return end
    local safeText = tostring(text or '')
    local safeType = tostring(notifyType or 'info')
    local now = GetGameTimer()
    local hash = safeType .. ':' .. safeText
    if hash == lastNotifyHash and (now - lastNotifyAt) < 850 then return end
    lastNotifyHash = hash
    lastNotifyAt = now
    SendNUIMessage({
        action = 'notify',
        text = safeText,
        type = safeType
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
        sendHudLayout()
        if isPlayerLoggedIn() then
            sendHudSettings()
            sendHudLayout()
            local serverId = characterId or ''
            SendNUIMessage({
                action = 'init',
                state = {
                    hudSettings = hudSettings,
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
        DisplayHud(true)
        DisplayRadar(true)
    end
end)
