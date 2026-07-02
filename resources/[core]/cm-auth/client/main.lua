-- cm-auth/client/main.lua
-- Loading screen handoff + one-click trusted device auth + skip callback support.

local DEBUG = false
local display = false
local uiReady = false
local pendingOpen = nil
local initialAuthStarted = false
local loadingShutdown = false
local characterSelectorOpened = false
local pendingAccountId = nil

local AUTH_TOKEN_KVP = 'cm_auth_token'
local AUTH_EMAIL_KVP = 'cm_auth_email'

local function dprint(...)
    if not DEBUG then return end
    local args = { ... }
    local msg = ''
    for i = 1, #args do msg = msg .. tostring(args[i]) .. ' ' end
    print('[CM-AUTH-CLIENT] ' .. msg)
end

local function isLoggedIn()
    return LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn == true
end

local function shutdownLoading()
    if loadingShutdown then return end
    loadingShutdown = true

    pcall(function() ShutdownLoadingScreenNui() end)
    pcall(function() ShutdownLoadingScreen() end)
end

local function setTrustedToken(token, email)
    token = tostring(token or '')
    if token ~= '' then
        SetResourceKvp(AUTH_TOKEN_KVP, token)
    end

    email = tostring(email or '')
    if email ~= '' then
        SetResourceKvp(AUTH_EMAIL_KVP, email)
    end
end

local function getTrustedToken()
    local token = GetResourceKvpString(AUTH_TOKEN_KVP)
    if token and token ~= '' then return token end
    return nil
end

local function getTrustedEmail()
    local email = GetResourceKvpString(AUTH_EMAIL_KVP)
    if email and email ~= '' then return email end
    return ''
end

local function clearTrustedToken()
    DeleteResourceKvp(AUTH_TOKEN_KVP)
    DeleteResourceKvp(AUTH_EMAIL_KVP)
end

local function openLogin(mode, profile)
    if isLoggedIn() then
        dprint('Blocked login UI because player is already logged in')
        return
    end

    if not uiReady then
        pendingOpen = { mode = mode or 'login', profile = profile }
        return
    end

    shutdownLoading()
    display = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        type = mode or 'login',
        profile = profile or {}
    })
end

local function startAuthFlow(force)
    if isLoggedIn() then return end
    if initialAuthStarted and not force then return end
    if not uiReady then return end

    initialAuthStarted = true

    local token = getTrustedToken()
    if token then
        TriggerServerEvent('cm-auth:server:previewToken', { token = token, email = getTrustedEmail() })
    else
        TriggerServerEvent('cm-auth:server:requestOpen')
    end
end

local function tryOpenCharacterSelector()
    if characterSelectorOpened then return end
    if not isLoggedIn() then return end

    -- On reconnect/token login, loginResult can arrive before the accountId
    -- state bag is visible locally. Keep the accountId from loginResult as
    -- a fallback so the character selector still opens.
    local accountId = LocalPlayer.state.accountId or pendingAccountId
    if not accountId or tostring(accountId) == '' then return end

    characterSelectorOpened = true

    SetTimeout(0, function()
        TriggerEvent('cm-characters:client:openSelector', tostring(accountId))
    end)
end

RegisterNetEvent('cm-auth:client:openLogin', function()
    openLogin('login')
end)

RegisterNetEvent('cm-auth:client:tokenPreview', function(success, data)
    if success then
        openLogin('trusted', data or {})
    else
        clearTrustedToken()
        openLogin('login')
    end
end)

RegisterNetEvent('cm-auth:client:clearToken', function()
    clearTrustedToken()
end)

RegisterNetEvent('cm-auth:client:loginResult', function(success, data)
    if success then
        if type(data) == 'table' then
            setTrustedToken(data.authToken, data.email)
            pendingAccountId = data.accountId
        end

        display = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'closeAuth' })
        shutdownLoading()

        tryOpenCharacterSelector()

        -- Reconnect/token-login fallback. The saved-token flow is fast, so
        -- accountId/isLoggedIn can replicate a moment after loginResult.
        local attempts = 0
        local function retrySelector()
            if characterSelectorOpened then return end
            attempts = attempts + 1
            tryOpenCharacterSelector()

            if not characterSelectorOpened and attempts < 25 then
                SetTimeout(200, retrySelector)
            end
        end

        SetTimeout(200, retrySelector)
    else
        SendNUIMessage({ action = 'error', message = data or 'Login failed. Try again.' })
    end
end)

RegisterNetEvent('cm-auth:client:registerResult', function(success, msg)
    SendNUIMessage({ action = 'registerResult', success = success, message = msg or '' })
end)

RegisterNetEvent('cm-auth:client:resetResult', function(success, msg)
    SendNUIMessage({ action = 'resetResult', success = success, message = msg or '' })
end)

RegisterNUICallback('uiReady', function(data, cb)
    uiReady = true
    cb('ok')

    if pendingOpen then
        local queued = pendingOpen
        pendingOpen = nil
        openLogin(queued.mode, queued.profile)
    else
        startAuthFlow(false)
    end
end)

RegisterNUICallback('loadingSkip', function(data, cb)
    cb('ok')

    if isLoggedIn() then
        shutdownLoading()
        return
    end

    if pendingOpen == nil then
        pendingOpen = { mode = 'login', profile = {} }
    end

    shutdownLoading()
    startAuthFlow(true)
end)

RegisterNUICallback('login', function(data, cb)
    if isLoggedIn() then
        cb('blocked')
        return
    end
    TriggerServerEvent('cm-auth:server:login', data or {})
    cb('ok')
end)

RegisterNUICallback('tokenLogin', function(data, cb)
    if isLoggedIn() then
        cb('blocked')
        return
    end

    local token = getTrustedToken()
    if not token then
        openLogin('login')
        cb('missing')
        return
    end

    TriggerServerEvent('cm-auth:server:loginWithToken', { token = token, email = getTrustedEmail() })
    cb('ok')
end)

RegisterNUICallback('resetPassword', function(data, cb)
    if isLoggedIn() then
        cb('blocked')
        return
    end
    TriggerServerEvent('cm-auth:server:resetPassword', data or {})
    cb('ok')
end)

RegisterNUICallback('forgetToken', function(data, cb)
    clearTrustedToken()
    openLogin('login')
    cb('ok')
end)

RegisterNUICallback('register', function(data, cb)
    if isLoggedIn() then
        cb('blocked')
        return
    end
    TriggerServerEvent('cm-auth:server:register', data or {})
    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    if not isLoggedIn() then
        cb('blocked')
        return
    end
    display = false
    SetNuiFocus(false, false)
    cb('ok')
end)

AddEventHandler('playerSpawned', function()
    startAuthFlow(false)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        startAuthFlow(false)
    end
end)

AddStateBagChangeHandler('isLoggedIn', nil, function(bagName, key, value)
    local player = GetPlayerFromStateBagName(bagName)
    if player ~= PlayerId() then return end
    if value == true then tryOpenCharacterSelector() end
end)

AddStateBagChangeHandler('accountId', nil, function(bagName, key, value)
    local player = GetPlayerFromStateBagName(bagName)
    if player ~= PlayerId() then return end
    if value and tostring(value) ~= '' then tryOpenCharacterSelector() end
end)

RegisterCommand('loginui', function()
    if not isLoggedIn() then
        openLogin('login')
    end
end, false)

print('[CM-AUTH-CLIENT] Auth client loaded with GTA-IV loading handoff, skip support, and trusted-device login')
