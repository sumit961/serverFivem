-- cm-auth/client/main.lua

local DEBUG = true

local function dprint(...)
    if DEBUG then
        local args = {...}
        local msg = ''
        for i = 1, #args do
            msg = msg .. tostring(args[i]) .. ' '
        end
        print('[CM-AUTH-CLIENT] ' .. msg)
    end
end

local display = false

-- ============================================
-- EVENTS FROM SERVER
-- ============================================

RegisterNetEvent('cm-auth:client:openLogin', function()
    print('[CM-AUTH-CLIENT] openLogin event received!')
    display = true
    SetNuiFocus(true, true)
    SendNUIMessage({action = 'open', type = 'login'})
end)

RegisterNetEvent('cm-auth:client:loginResult', function(success, data)
    print('[CM-AUTH-CLIENT] loginResult success=' .. tostring(success))
    if success then
        display = false
        SetNuiFocus(false, false)
        -- Hide auth UI
        SendNUIMessage({action = 'closeAuth'})
        print('[CM-AUTH-CLIENT] Auth UI hidden, waiting for character selector...')
    else
        SendNUIMessage({action = 'error', message = data})
    end
end)

RegisterNetEvent('cm-auth:client:registerResult', function(success, msg)
    print('[CM-AUTH-CLIENT] registerResult success=' .. tostring(success))
    SendNUIMessage({action = 'registerResult', success = success, message = msg})
end)

-- ============================================
-- NUI CALLBACKS
-- ============================================

RegisterNUICallback('login', function(data, cb)
    print('[CM-AUTH-CLIENT] NUI login callback!')
    TriggerServerEvent('cm-auth:server:login', data)
    cb('ok')
end)

RegisterNUICallback('register', function(data, cb)
    print('[CM-AUTH-CLIENT] NUI register callback!')
    TriggerServerEvent('cm-auth:server:register', data)
    cb('ok')
end)

RegisterNUICallback('close', function(data, cb)
    print('[CM-AUTH-CLIENT] NUI close callback')
    display = false
    SetNuiFocus(false, false)
    cb('ok')
end)

-- ============================================
-- AUTO OPEN
-- ============================================

AddEventHandler('playerSpawned', function()
    print('[CM-AUTH-CLIENT] playerSpawned')
    Wait(1000)
    if not LocalPlayer.state.isLoggedIn then
        TriggerEvent('cm-auth:client:openLogin')
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'cm-auth' then
        Wait(3000)
        if not LocalPlayer.state.isLoggedIn then
            TriggerEvent('cm-auth:client:openLogin')
        end
    end
end)

RegisterCommand('loginui', function()
    TriggerEvent('cm-auth:client:openLogin')
end)

print('[CM-AUTH-CLIENT] === SCRIPT LOADED ===')