-- cm-chat/client/main.lua
-- Modular RP chat UI. Messages stay visible; input/tabs/actions only show when chat is open.

local chatOpen = false
local externalHideReasons = {}
local loggedIn = false
local characterId = nil
local characterHints = {}

local function externalChatHidden()
    return next(externalHideReasons) ~= nil
end

local function cleanText(value, maxLen)
    value = tostring(value or ''):gsub('[\r\n\t]+', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return value:sub(1, tonumber(maxLen) or 180)
end

local function isPlayerLoggedIn()
    return loggedIn or (LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn == true)
end

local function cleanCharacterId(value)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' or value == 'nil' then return nil end
    return value
end

local function extractCharacterId(value)
    if type(value) == 'table' then
        local found = value.id or value.characterId or value.charId or value.charid or value.char_id or value.citizenid
        if found then return cleanCharacterId(found) end
        if type(value.character) == 'table' then
            return extractCharacterId(value.character)
        end
        return nil
    end
    return cleanCharacterId(value)
end

local function captureStateHints()
    if not LocalPlayer or not LocalPlayer.state then return end
    local st = LocalPlayer.state
    characterId = characterId
        or extractCharacterId(st.characterId)
        or extractCharacterId(st.charId)
        or extractCharacterId(st.charid)
        or extractCharacterId(st.char_id)
        or extractCharacterId(st.currentCharacterId)
        or extractCharacterId(st.citizenid)

    characterHints.id = characterHints.id or characterId
    characterHints.characterId = characterHints.characterId or characterId
    characterHints.account_id = characterHints.account_id or st.account_id or st.accountId or st.account or st.accountid
    characterHints.slot = characterHints.slot or st.slot or st.charSlot or st.character_slot
end

local function syncCharacterFromData(data, extra)
    data = data or {}
    if type(data) ~= 'table' then
        data = { id = data, characterId = data, slot = extra }
    end

    local newId = extractCharacterId(data)
    if newId then characterId = newId end

    characterHints = {
        id = characterId,
        characterId = characterId,
        account_id = data.account_id or data.accountId or data.account or data.accountid,
        slot = data.slot or data.charSlot or data.character_slot,
        first_name = data.first_name or data.firstname,
        last_name = data.last_name or data.lastname
    }

    captureStateHints()
    TriggerServerEvent('cm-chat:server:resolveCharacter', characterId, characterHints)
    TriggerServerEvent('cm-chat:server:requestChannels')
end

local function requestUiBootstrap()
    TriggerServerEvent('cm-chat:server:requestChannels')
    SendNUIMessage({
        action = 'setChatConfig',
        maxMessages = Config.MaxVisibleMessages or 45,
        actions = Config.Actions or {},
        ui = Config.UI or {}
    })
end

local function setChatOpen(open)
    open = open == true

    if open then
        if externalChatHidden() then return end
        if not isPlayerLoggedIn() then return end
        if IsNuiFocused and IsNuiFocused() and not chatOpen then return end
        captureStateHints()
        requestUiBootstrap()
    end

    chatOpen = open
    SetNuiFocus(chatOpen, chatOpen)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'setChatOpen', open = chatOpen })
end

local function setExternalChatHidden(hidden, reason)
    reason = tostring(reason or 'external-ui')
    if hidden == true then
        externalHideReasons[reason] = true
        setChatOpen(false)
    else
        externalHideReasons[reason] = nil
    end
    SendNUIMessage({ action = 'setChatVisible', visible = not externalChatHidden() })
end

RegisterNetEvent('cm-chat:client:hideForUi', function(reason)
    setExternalChatHidden(true, reason)
end)

RegisterNetEvent('cm-chat:client:showAfterUi', function(reason)
    setExternalChatHidden(false, reason)
end)

exports('HideForUi', function(reason)
    setExternalChatHidden(true, reason)
end)

exports('ShowAfterUi', function(reason)
    setExternalChatHidden(false, reason)
end)

RegisterCommand('cmchat', function()
    setChatOpen(true)
end, false)

RegisterKeyMapping('cmchat', 'Open CM chat', 'keyboard', Config.OpenKey or 'T')

RegisterNUICallback('chatClose', function(_, cb)
    setChatOpen(false)
    cb('ok')
end)

RegisterNUICallback('chatSend', function(data, cb)
    local channel = data and data.channel or 'rp'
    local msg = cleanText(data and data.text or '', Config.MaxMessageLength or 180)

    if msg ~= '' then
        if msg:sub(1, 1) == '/' then
            ExecuteCommand(msg:sub(2))
        else
            TriggerServerEvent('cm-chat:server:sendChatMessage', channel, msg)
        end
    end

    setChatOpen(false)
    cb('ok')
end)

RegisterNUICallback('chatRefreshChannels', function(_, cb)
    TriggerServerEvent('cm-chat:server:requestChannels')
    cb('ok')
end)

RegisterNetEvent('cm-chat:client:addMessage', function(message)
    SendNUIMessage({ action = 'addChatMessage', message = message })
end)

RegisterNetEvent('cm-chat:client:setChannels', function(channels, actions)
    SendNUIMessage({
        action = 'setChatChannels',
        channels = channels or {},
        actions = actions or Config.Actions or {}
    })
end)

RegisterNetEvent('cm-chat:client:open', function()
    setChatOpen(true)
end)

RegisterNetEvent('cm-chat:client:clear', function()
    SendNUIMessage({ action = 'clearChat' })
end)

RegisterNetEvent('cm-playerdata:client:loaded', function(data)
    loggedIn = true
    syncCharacterFromData(data or {})
    Wait(500)
    if SetTextChatEnabled then SetTextChatEnabled(false) end
    requestUiBootstrap()
end)

RegisterNetEvent('cm-playerdata:client:unloaded', function()
    loggedIn = false
    characterId = nil
    characterHints = {}
    setChatOpen(false)
    TriggerServerEvent('cm-chat:server:clearCharacter')
end)

for _, eventName in ipairs({
    'cm-characters:client:characterLoaded',
    'cm-characters:client:characterSelected',
    'cm-characters:client:selectedCharacter',
    'cm-spawn:client:characterLoaded',
    'cm-spawn:characterLoaded',
    'cm-core:client:characterLoaded'
}) do
    RegisterNetEvent(eventName, function(data, extra)
        loggedIn = true
        syncCharacterFromData(data, extra)
    end)
end

CreateThread(function()
    Wait(1000)
    if SetTextChatEnabled then SetTextChatEnabled(false) end
    requestUiBootstrap()

    while true do
        Wait(0)
        if chatOpen then
            DisableAllControlActions(0)
            EnableControlAction(0, 1, true)
            EnableControlAction(0, 2, true)
            EnableControlAction(0, 200, true)

            if IsControlJustReleased(0, 322) or IsControlJustReleased(0, 177) then
                setChatOpen(false)
            end
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        if SetTextChatEnabled then SetTextChatEnabled(true) end
    end
end)
