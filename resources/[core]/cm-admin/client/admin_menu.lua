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
    menuOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    setHudVisible(true)
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


local function loadGroundZ(x, y, startZ)
    local z = tonumber(startZ) or 800.0
    RequestCollisionAtCoord(x, y, z)
    for i = 1, 45 do
        local probeZ = 1000.0 - (i * 22.0)
        RequestCollisionAtCoord(x, y, probeZ)
        local found, groundZ = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, probeZ + 0.0, false)
        if found then
            return groundZ + 1.2
        end
        Wait(0)
    end
    return z
end

RegisterNetEvent('cm-admin:client:teleportToWaypoint', function()
    local blip = GetFirstBlipInfoId(8) -- waypoint
    if not DoesBlipExist(blip) then
        notify('Set a GPS waypoint on the map first.', 'error')
        return
    end

    local coords = GetBlipInfoIdCoord(blip)
    local ped = PlayerPedId()
    local entity = currentControlEntity()
    local z = loadGroundZ(coords.x, coords.y, 850.0)

    DoScreenFadeOut(150)
    Wait(150)
    RequestCollisionAtCoord(coords.x, coords.y, z)
    SetEntityCoordsNoOffset(entity, coords.x, coords.y, z, false, false, true)
    if entity ~= ped then SetPedIntoVehicle(ped, entity, -1) end
    Wait(350)
    DoScreenFadeIn(150)
    notify('Teleported to GPS waypoint.', 'success')
end)

local function drawAdminText(x, y, z, text)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end
    SetTextScale(0.0, 0.34)
    SetTextFont(4)
    SetTextProportional(1)
    -- Admin tag is intentionally full red so staff mode is visually clear.
    local c = (Config.AdminTags and Config.AdminTags.Color) or { r = 255, g = 35, b = 35, a = 245 }
    SetTextColour(tonumber(c.r) or 255, tonumber(c.g) or 35, tonumber(c.b) or 35, tonumber(c.a) or 245)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx, sy)
end

local function isLocalAdminNoclip()
    return LocalPlayer and LocalPlayer.state and LocalPlayer.state.cm_admin_noclip == true
end

local adminTagPlayers = {}

local function rebuildAdminTagCache()
    adminTagPlayers = {}
    if not Config.AdminTags or Config.AdminTags.Enabled == false then return end

    -- If this client is in admin noclip, do not render overhead names at all.
    -- This keeps the noclip/admin view clean and avoids showing our own name.
    if isLocalAdminNoclip() then return end

    local myServerId = GetPlayerServerId(PlayerId())
    for _, playerId in ipairs(GetActivePlayers()) do
        local serverId = GetPlayerServerId(playerId)
        if serverId and serverId > 0 and serverId ~= myServerId then
            local state = Player(serverId).state
            local tag = state and state.cm_admin_tag or nil
            local targetNoclip = state and state.cm_admin_noclip == true
            if tag and tag.active == true and tag.noclip ~= true and not targetNoclip then
                adminTagPlayers[#adminTagPlayers + 1] = { playerId = playerId, serverId = serverId, tag = tag }
            end
        end
    end
end

CreateThread(function()
    while true do
        rebuildAdminTagCache()
        Wait(750)
    end
end)

CreateThread(function()
    while true do
        if #adminTagPlayers == 0 then
            Wait(500)
        else
            Wait(0)
            local myPed = PlayerPedId()
            local myCoords = GetEntityCoords(myPed)
            local cfg = Config.AdminTags or {}
            local maxDistance = tonumber(cfg.DrawDistance) or 32.0
            local height = tonumber(cfg.HeightOffset) or 1.18
            local myServerId = GetPlayerServerId(PlayerId())
            for _, item in ipairs(adminTagPlayers) do
                local targetPed = GetPlayerPed(item.playerId)
                if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) and item.serverId ~= myServerId then
                    local state = Player(item.serverId).state
                    local tag = item.tag or {}
                    if tag.active == true and tag.noclip ~= true and not (state and state.cm_admin_noclip == true) then
                        local coords = GetEntityCoords(targetPed)
                        local distance = #(coords - myCoords)
                        if distance <= maxDistance then
                            local charId = tag.characterId or '?'
                            local name = tag.name or GetPlayerName(item.playerId) or 'Admin'
                            local rank = cfg.ShowRank and tag.rank and (' · ' .. tostring(tag.rank)) or ''
                            drawAdminText(coords.x, coords.y, coords.z + height, ('%s%s\n%s (%s)'):format(cfg.Label or 'Administrator', rank, name, charId))
                        end
                    end
                end
            end
        end
    end
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

-- Fatally injures the local ped so cm-playerdata's own death watcher (health/
-- IsPedFatallyInjured poll) picks it up and runs the normal death/EMS flow,
-- instead of duplicating that pipeline here.
RegisterNetEvent('cm-admin:client:kill', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, 0)
    notify('You have been killed for testing.', 'inform')
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


RegisterNetEvent('cm-admin:client:repairVehicleNet', function(netId, plate)
    local veh = 0
    if tonumber(netId or 0) and tonumber(netId or 0) > 0 then
        veh = NetworkGetEntityFromNetworkId(tonumber(netId))
    end
    if (not veh or veh == 0 or not DoesEntityExist(veh)) and plate and plate ~= '' then
        local wanted = tostring(plate):upper():gsub('^%s+', ''):gsub('%s+$', '')
        local vehicles = GetGamePool('CVehicle')
        for _, candidate in ipairs(vehicles) do
            if DoesEntityExist(candidate) and tostring(GetVehicleNumberPlateText(candidate) or ''):upper():gsub('^%s+', ''):gsub('%s+$', '') == wanted then
                veh = candidate
                break
            end
        end
    end
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        SetVehicleFixed(veh)
        SetVehicleDeformationFixed(veh)
        SetVehicleDirtLevel(veh, 0.0)
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehicleBodyHealth(veh, 1000.0)
        notify('Vehicle repaired.', 'success')
    else
        notify('Vehicle is not streamed on your client.', 'error')
    end
end)
