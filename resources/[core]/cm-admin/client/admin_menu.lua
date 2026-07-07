-- cm-admin/client/admin_menu.lua
-- F11 admin menu. Server sends all data and checks all permissions.

local menuOpen = false
local frozen = false

local function notify(msg, msgType)
    if GetResourceState('ox_lib') == 'started' and lib and lib.notify then
        lib.notify({ title = 'CM Admin', description = msg, type = msgType or 'inform' })
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(('[CM Admin] %s'):format(msg))
        EndTextCommandThefeedPostTicker(false, false)
    end
end

local function setHudVisible(visible)
    local hud = 'cm-hud'
    if GetResourceState(hud) == 'started' then
        TriggerEvent('cm-hud:client:setVisible', visible, 'cm-admin')
        TriggerEvent('cm-hud:client:SetVisible', visible, 'cm-admin')
        TriggerEvent('cm-hud:client:setHudVisible', visible, 'cm-admin')
    end
end

local function closeMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    setHudVisible(true)
end

RegisterNetEvent('cm-admin:client:openMenu', function(payload)
    menuOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    setHudVisible(false)
    SendNUIMessage({ action = 'open', data = payload or {} })
end)

RegisterNetEvent('cm-admin:client:updateMenu', function(payload)
    SendNUIMessage({ action = 'update', data = payload or {} })
end)

RegisterNetEvent('cm-admin:client:detailResult', function(payload)
    SendNUIMessage({ action = 'detailResult', data = payload or {} })
end)

RegisterNetEvent('cm-admin:client:closeForDevTool', function()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end)

RegisterNetEvent('cm-admin:client:runCommand', function(command, values)
    if type(command) ~= 'string' or command == '' then return end
    SetNuiFocus(false, false) -- release menu focus so the tool's own UI can take it
    SendNUIMessage({ action = 'close' })
    Wait(150)
    ExecuteCommand(command)
end)

RegisterNetEvent('cm-admin:client:devClientEvent', function(eventName, values)
    if type(eventName) ~= 'string' or eventName == '' then return end
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    Wait(150)
    TriggerEvent(eventName, values)
end)

RegisterNetEvent('cm-admin:client:mapData', function(payload)
    SendNUIMessage({ action = 'mapData', data = payload or {} })
end)

RegisterNetEvent('cm-admin:client:forceClose', function()
    closeMenu()
end)

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb({ ok = true })
end)

RegisterNUICallback('adminAction', function(data, cb)
    TriggerServerEvent('cm-admin:server:nuiAction', data or {})
    cb({ ok = true })
end)

RegisterCommand(Config.MenuKeybindCommand or 'cm_admin_menu', function()
    TriggerServerEvent('cm-admin:server:requestOpenMenu')
end, false)

RegisterKeyMapping(
    Config.MenuKeybindCommand or 'cm_admin_menu',
    'CM Admin: Open admin menu',
    'keyboard',
    Config.DefaultMenuKey or 'F11'
)

CreateThread(function()
    while true do
        if menuOpen then
            Wait(0)
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 45, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 200, true)
            if IsDisabledControlJustPressed(0, 200) then
                closeMenu()
            end
        else
            Wait(300)
        end
    end
end)

local function currentControlEntity()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then return veh end
    return ped
end

RegisterNetEvent('cm-admin:client:teleportToCoords', function(coords)
    if type(coords) ~= 'table' then return end
    local ped = PlayerPedId()
    local entity = currentControlEntity()
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return end
    DoScreenFadeOut(150)
    Wait(150)
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(entity, x, y, z, false, false, true)
    if entity ~= ped then SetPedIntoVehicle(ped, entity, -1) end
    Wait(250)
    DoScreenFadeIn(150)
    notify('Teleported.', 'success')
end)

RegisterNetEvent('cm-admin:client:setFrozen', function(state)
    frozen = state == true
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, frozen)
    SetPlayerControl(PlayerId(), not frozen, 0)
    notify(frozen and 'You have been frozen by an admin.' or 'You have been unfrozen.', frozen and 'error' or 'success')
end)

RegisterNetEvent('cm-admin:client:heal', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    notify('Healed.', 'success')
end)

RegisterNetEvent('cm-admin:client:armor', function()
    SetPedArmour(PlayerPedId(), 100)
    notify('Armor set to 100.', 'success')
end)

RegisterNetEvent('cm-admin:client:repairCurrentVehicle', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return notify('You are not in a vehicle.', 'error') end
    SetVehicleFixed(veh)
    SetVehicleDeformationFixed(veh)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    SetVehicleEngineOn(veh, true, true, false)
    notify('Vehicle repaired.', 'success')
end)

RegisterNetEvent('cm-admin:client:deleteCurrentVehicle', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return notify('You are not in a vehicle.', 'error') end
    SetEntityAsMissionEntity(veh, true, true)
    DeleteEntity(veh)
    notify('Vehicle deleted.', 'success')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    closeMenu()
    if frozen then
        FreezeEntityPosition(PlayerPedId(), false)
        SetPlayerControl(PlayerId(), true, 0)
    end
end)
