CMRacing = CMRacing or {}
CMRacing.Client = CMRacing.Client or {}
CMRacing.Client.Menu = {}

local Menu = CMRacing.Client.Menu
local isMenuOpen = false

function Menu.Open()
    if isMenuOpen then return end
    isMenuOpen = true
    SetNuiFocus(true, true)
    TriggerServerEvent('cm-racing:server:requestMenuData')
end

function Menu.Close()
    if not isMenuOpen then return end
    isMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeMenu' })
end

RegisterNetEvent('cm-racing:client:receiveMenuData', function(data)
    if not isMenuOpen then return end
    SendNUIMessage({
        action = 'openMenu',
        data = data
    })
end)

RegisterNUICallback('close', function(_, cb)
    Menu.Close()
    cb({ ok = true })
end)

RegisterNUICallback('startRace', function(data, cb)
    local routeId = data and data.routeId
    if routeId then
        Menu.Close()
        TriggerServerEvent('cm-racing:server:requestStartRace', routeId)
    end
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    TriggerServerEvent('cm-racing:server:requestMenuData')
    cb({ ok = true })
end)
