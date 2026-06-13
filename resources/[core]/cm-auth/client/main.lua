-- cm-auth/client/main.lua

local DEBUG = false
local display = false

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

local function openLogin()
    if isLoggedIn() then
        dprint('Blocked login UI because player is already logged in')
        return
    end
    display = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', type = 'login' })
end

RegisterNetEvent('cm-auth:client:openLogin', function()
    openLogin()
end)

RegisterNetEvent('cm-auth:client:loginResult', function(success, data)
    if success then
        display = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'closeAuth' })
    else
        SendNUIMessage({ action = 'error', message = data or 'Login failed. Try again.' })
    end
end)

RegisterNetEvent('cm-auth:client:registerResult', function(success, msg)
    SendNUIMessage({ action = 'registerResult', success = success, message = msg or '' })
end)

RegisterNUICallback('login', function(data, cb)
    if isLoggedIn() then
        cb('blocked')
        return
    end
    TriggerServerEvent('cm-auth:server:login', data or {})
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
    -- Auth UI should not be manually closed before login. This only releases focus if called by UI bugs/dev.
    if not isLoggedIn() then
        cb('blocked')
        return
    end
    display = false
    SetNuiFocus(false, false)
    cb('ok')
end)

AddEventHandler('playerSpawned', function()
    Wait(1000)
    if not isLoggedIn() then
        TriggerServerEvent('cm-auth:server:requestOpen')
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'cm-auth' then
        Wait(2500)
        if not isLoggedIn() then
            TriggerServerEvent('cm-auth:server:requestOpen')
        end
    end
end)

RegisterCommand('loginui', function()
    if not isLoggedIn() then
        TriggerServerEvent('cm-auth:server:requestOpen')
    end
end, false)

print('[CM-AUTH-CLIENT] Modern auth client loaded')
