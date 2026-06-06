-- cm-auth/client/main.lua
-- FULL DEBUG + FORCE OPEN FIX

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
    print('[CM-AUTH-CLIENT] NUI message sent to UI')
end)

RegisterNetEvent('cm-auth:client:loginResult', function(success, data)
    print('[CM-AUTH-CLIENT] loginResult success=' .. tostring(success) .. ' data=' .. tostring(data))
    if success then
        display = false
        SetNuiFocus(false, false) -- Remove auth focus safely
        
        -- FIX: Tell cm-auth UI to hide its wrapper layout
        SendNUIMessage({action = 'closeAuth'})
        
        print('[CM-AUTH-CLIENT] Triggering cm-characters:client:openSelector')
        TriggerEvent('cm-characters:client:openSelector', data)
    else
        SendNUIMessage({action = 'error', message = data})
    end
end)

RegisterNetEvent('cm-auth:client:registerResult', function(success, msg)
    print('[CM-AUTH-CLIENT] registerResult success=' .. tostring(success) .. ' msg=' .. tostring(msg))
    SendNUIMessage({action = 'registerResult', success = success, message = msg})
end)

-- ============================================
-- NUI CALLBACKS
-- ============================================

RegisterNUICallback('login', function(data, cb)
    print('[CM-AUTH-CLIENT] NUI login callback!')
    print('[CM-AUTH-CLIENT] data.username=' .. tostring(data.username))
    TriggerServerEvent('cm-auth:server:login', data)
    cb('ok')
end)

RegisterNUICallback('register', function(data, cb)
    print('[CM-AUTH-CLIENT] NUI register callback!')
    print('[CM-AUTH-CLIENT] data.username=' .. tostring(data.username))
    print('[CM-AUTH-CLIENT] data.email=' .. tostring(data.email))
    print('[CM-AUTH-CLIENT] data.password length=' .. tostring(data.password and #data.password or 0))
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
-- AUTO OPEN - MULTIPLE METHODS
-- ============================================

-- Method 1: playerSpawned
AddEventHandler('playerSpawned', function()
    print('[CM-AUTH-CLIENT] >>> playerSpawned EVENT FIRED <<<')
    Wait(1000)
    print('[CM-AUTH-CLIENT] isLoggedIn state=' .. tostring(LocalPlayer.state.isLoggedIn))
    if not LocalPlayer.state.isLoggedIn then
        print('[CM-AUTH-CLIENT] Opening login from playerSpawned')
        TriggerEvent('cm-auth:client:openLogin')
    end
end)

-- Method 2: Resource start (backup)
AddEventHandler('onClientResourceStart', function(resourceName)
    print('[CM-AUTH-CLIENT] Resource start: ' .. tostring(resourceName))
    if resourceName == 'cm-auth' then
        print('[CM-AUTH-CLIENT] cm-auth started, waiting 3 seconds...')
        Wait(3000)
        print('[CM-AUTH-CLIENT] isLoggedIn=' .. tostring(LocalPlayer.state.isLoggedIn))
        if not LocalPlayer.state.isLoggedIn then
            print('[CM-AUTH-CLIENT] FORCE OPENING LOGIN UI')
            TriggerEvent('cm-auth:client:openLogin')
        end
    end
end)

-- Method 3: Command (manual)
RegisterCommand('loginui', function()
    print('[CM-AUTH-CLIENT] Manual /loginui command')
    TriggerEvent('cm-auth:client:openLogin')
end)

-- Method 4: Keybind (F1)
RegisterCommand('openlogin', function()
    print('[CM-AUTH-CLIENT] F1 pressed, opening login')
    TriggerEvent('cm-auth:client:openLogin')
end)
RegisterKeyMapping('openlogin', 'Open Login UI', 'keyboard', 'F1')

print('[CM-AUTH-CLIENT] === SCRIPT LOADED ===')
print('[CM-AUTH-CLIENT] Try pressing F1 or type /loginui')