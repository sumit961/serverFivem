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

local gangEventConfig
local function eventConfigServer(action,data) TriggerServerEvent('cm-admin:server:gangEventConfigMode',action,data or {}) end
local function removeEventConfigRadiusBlip()
    if gangEventConfig and gangEventConfig.radiusBlip and DoesBlipExist(gangEventConfig.radiusBlip) then RemoveBlip(gangEventConfig.radiusBlip) end
    if gangEventConfig then gangEventConfig.radiusBlip=nil;gangEventConfig.blipRadius=nil end
end
local function updateEventConfigRadiusBlip(center,radius)
    if not gangEventConfig or not center or gangEventConfig.blipRadius==radius then return end
    removeEventConfigRadiusBlip();local blip=AddBlipForRadius(center.x,center.y,center.z,radius+0.0)
    SetBlipColour(blip,3);SetBlipAlpha(blip,95);gangEventConfig.radiusBlip=blip;gangEventConfig.blipRadius=radius
end
local function drawEventConfigCircle(center,radius)
    local segments=72;local z=center.z+0.35;local previousX=center.x+radius;local previousY=center.y
    for index=1,segments do
        local angle=(index/segments)*(math.pi*2.0);local x=center.x+math.cos(angle)*radius;local y=center.y+math.sin(angle)*radius
        DrawLine(previousX,previousY,z,x,y,z,65,225,245,235)
        if index%6==0 then DrawMarker(28,x,y,z+0.7,0,0,0,0,0,0,.7,.7,1.8,65,225,245,185,false,false,2,false,nil,nil,false) end
        previousX,previousY=x,y
    end
end
local function configHelp(text)
    SetTextFont(4);SetTextScale(.0,.42);SetTextColour(230,250,255,245);SetTextCentre(true);SetTextOutline();BeginTextCommandDisplayText('STRING');AddTextComponentSubstringPlayerName(text);EndTextCommandDisplayText(.5,.86)
end
local function cancelGangEventConfig()
    if not gangEventConfig then return end;removeEventConfigRadiusBlip();eventConfigServer('configCancel');gangEventConfig=nil
end
RegisterNetEvent('cm-admin:client:gangEventConfigMode',function(draft)
    removeEventConfigRadiusBlip();closeMenu();gangEventConfig={stage=1,draft=draft or {},radius=tonumber(draft and draft.radius) or 250,pending=false};notify('Config Mode: select the event center and press E. ESC cancels.','inform')
end)
RegisterNetEvent('cm-admin:client:gangEventConfigDraft',function(draft)
    if not gangEventConfig then return end;gangEventConfig.draft=draft or gangEventConfig.draft;gangEventConfig.radius=tonumber(draft and draft.radius) or gangEventConfig.radius;gangEventConfig.pending=false
    if gangEventConfig.stage==1 and draft and draft.center then gangEventConfig.stage=2 end
    if draft and draft.details then gangEventConfig.stage=5 end
end)
RegisterNetEvent('cm-admin:client:gangEventConfigResult',function(ok,message)
    notify(tostring(message or (ok and 'Configuration updated.' or 'Configuration failed.')),ok and 'success' or 'error');if gangEventConfig then gangEventConfig.pending=false end
end)
RegisterNetEvent('cm-admin:client:gangEventConfigFinished',function(saved)
    removeEventConfigRadiusBlip();gangEventConfig=nil;notify(saved and 'Supply War configuration saved.' or 'Supply War configuration cancelled.',saved and 'success' or 'inform')
end)
local function openEventDetails()
    local function keyboard(prompt,default,maxLength)
        AddTextEntry('CM_GANG_EVENT_INPUT',prompt)
        DisplayOnscreenKeyboard(1,'CM_GANG_EVENT_INPUT','',tostring(default or ''),'','','',maxLength or 96)
        local status=UpdateOnscreenKeyboard();while status==0 do Wait(0);status=UpdateOnscreenKeyboard() end
        if status~=1 then return nil end
        local value=GetOnscreenKeyboardResult();value=value and value:gsub('^%s+',''):gsub('%s+$','') or nil
        return value~='' and value or nil
    end
    local landSeconds=keyboard('Supply spawn seconds - five comma separated values','10,300,600,900,1100',128);if not landSeconds then return end
    local points=keyboard('Objective points - five comma separated values','5,5,6,6,10',64);if not points then return end
    if not gangEventConfig then return end
    gangEventConfig.pending=true;eventConfigServer('configDetails',{landSeconds=landSeconds,points=points})
end
CreateThread(function()
    while true do
        if not gangEventConfig then Wait(500) else
            Wait(0);local cfg=gangEventConfig
            if cfg then
            local draft=cfg.draft or {};local center=draft.center;local radius=tonumber(cfg.radius) or 250
            if center then
                drawEventConfigCircle(center,radius);updateEventConfigRadiusBlip(center,radius)
                DrawMarker(28,center.x,center.y,center.z+1.0,0,0,0,0,0,0,1.2,1.2,1.2,103,232,249,210,false,false,2,false,nil,nil,false)
            end
            for index,p in ipairs(draft.drops or {}) do DrawMarker(2,p.x,p.y,p.z+1.2,0,0,0,0,180.0,0,.7,.7,.7,index==5 and 255 or 103,index==5 and 190 or 232,index==5 and 60 or 249,230,false,true,2,false,nil,nil,false) end
            if cfg.stage==1 then configHelp('1/6  SELECT EVENT CENTER  ~INPUT_CONTEXT~ Capture current location')
            elseif cfg.stage==2 then
                DisableControlAction(0,14,true);DisableControlAction(0,15,true)
                DisableControlAction(0,241,true);DisableControlAction(0,242,true)
                local increase = IsControlJustPressed(0,241) or IsDisabledControlJustPressed(0,241)
                    or IsControlJustPressed(2,241) or IsControlJustPressed(0,15)
                    or IsDisabledControlJustPressed(0,15) or IsControlJustPressed(0,175)
                local decrease = IsControlJustPressed(0,242) or IsDisabledControlJustPressed(0,242)
                    or IsControlJustPressed(2,242) or IsControlJustPressed(0,14)
                    or IsDisabledControlJustPressed(0,14) or IsControlJustPressed(0,174)
                if increase then cfg.radius=math.min(1000,radius+10)
                elseif decrease then cfg.radius=math.max(50,radius-10) end
                configHelp(('2/6  CIRCLE SIZE: %dm  Wheel / LEFT-RIGHT change  ~INPUT_CONTEXT~ Confirm'):format(cfg.radius))
            elseif cfg.stage==3 then configHelp(('3/6  DROP LOCATIONS: %d  ~INPUT_CONTEXT~ Add here  ~INPUT_FRONTEND_RDOWN~ Continue'):format(#(draft.drops or {})))
            elseif cfg.stage==4 then configHelp('4/6  CONFIGURE REWARDS / TIMING  ~INPUT_CONTEXT~ Open form')
            elseif cfg.stage==5 then configHelp(('5/6  COMPLETE PREVIEW  Radius %dm · %d drops  ~INPUT_CONTEXT~ Approve'):format(radius,#(draft.drops or {})))
            elseif cfg.stage==6 then configHelp('6/6  SAVE CONFIGURATION  ~INPUT_CONTEXT~ Save  ~INPUT_FRONTEND_CANCEL~ Cancel') end
            if IsControlJustPressed(0,200) then cancelGangEventConfig()
            elseif not cfg.pending and IsControlJustPressed(0,38) then
                if cfg.stage==1 then cfg.pending=true;eventConfigServer('configCenter')
                elseif cfg.stage==2 then cfg.pending=true;eventConfigServer('configRadius',{radius=cfg.radius});cfg.stage=3
                elseif cfg.stage==3 then cfg.pending=true;eventConfigServer('configDrop')
                elseif cfg.stage==4 then openEventDetails()
                elseif cfg.stage==5 then cfg.stage=6
                elseif cfg.stage==6 then cfg.pending=true;eventConfigServer('configSave') end
            elseif cfg.stage==3 and IsControlJustPressed(0,191) and #(draft.drops or {})>0 then cfg.stage=4 end
            end
        end
    end
end)

local gangFleetPlacement=false

local function drawGangPlacementText(vehicle)
    local c=GetEntityCoords(vehicle)
    local visible,x,y=World3dToScreen2d(c.x,c.y,c.z+1.6)
    if not visible then return end
    SetTextFont(4)
    SetTextScale(0.0,0.46)
    SetTextColour(0,220,255,255)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName('PRESS ~y~H~s~ TO SAVE LOCATION')
    EndTextCommandDisplayText(x,y)
end

RegisterNetEvent('cm-admin:client:gangFleetPlacement',function(data)
    closeMenu()
    SetNuiFocus(false,false)
    gangFleetPlacement=true
    local model=tostring(data and data.model or 'vehicle')
    local netId=tonumber(data and data.netId)
    TriggerServerEvent('cm-gang:server:fleetPlacementReady',model)
    notify('Drive the vehicle into position. Press H to save its location.','inform')
    CreateThread(function()
        while gangFleetPlacement do
            local vehicle=netId and NetworkGetEntityFromNetworkId(netId) or GetVehiclePedIsIn(PlayerPedId(),false)
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('~b~H~s~ save gang vehicle location  ~y~BACKSPACE~s~ cancel')
            EndTextCommandDisplayHelp(0,false,true,-1)
            if vehicle and vehicle~=0 and DoesEntityExist(vehicle) then drawGangPlacementText(vehicle) end
            local save=(IsRawKeyReleased and IsRawKeyReleased(72)) or IsControlJustReleased(0,74)
            local cancel=(IsRawKeyReleased and IsRawKeyReleased(8)) or IsControlJustReleased(0,194)
            if save then
                gangFleetPlacement=false
                ClearAllHelpMessages()
                notify('Saving gang vehicle location...','inform')
                TriggerServerEvent('cm-gang:server:confirmFleetPlacement')
            elseif cancel then
                gangFleetPlacement=false
                ClearAllHelpMessages()
                TriggerServerEvent('cm-gang:server:cancelFleetPlacement')
                notify('Gang vehicle placement cancelled.','inform')
            end
            Wait(0)
        end
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    closeMenu()
    gangFleetPlacement=false
    ClearAllHelpMessages()
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
