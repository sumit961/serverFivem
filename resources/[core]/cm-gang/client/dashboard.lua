local RESOURCE = GetCurrentResourceName()
local dashboardOpen = false
local headquarters
local npcPeds = {}
local npcBlips = {}
local activeContact
local textUiVisible = false
local contactCamera
local playerWasFrozen
local serviceOpen = false
local contactReopenAt = 0
local refreshGeneration = 0
local development = GetConvar('cm_environment', 'production') == 'development'
local HUD_REASON = 'cm-gang-menu'
local function npcKey(entry) return ('%s:%s'):format(tostring(entry and entry.gangId or 'unknown'), tostring(entry and entry.kind or 'main')) end

local function devLog(message)
    if development then print(('[cm-gang] %s'):format(message)) end
end

local function drawNpcName(entry,ped)
    local c=GetEntityCoords(ped); local visible,x,y=World3dToScreen2d(c.x,c.y,c.z+1.12)
    if not visible then return end
    SetTextFont(4); SetTextCentre(true); SetTextOutline(); SetTextScale(0.0,0.32); SetTextColour(235,250,252,235)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(entry.contact.name or 'Gang Contact'); EndTextCommandDisplayText(x,y)
end

local function notify(message, kind)
    local notifyKind = kind == 'inform' and 'info' or (kind or 'info')
    if GetResourceState('cm-hud') == 'started' then
        TriggerEvent('cm-hud:client:notify', tostring(message or ''), notifyKind)
        return
    end
    if lib and lib.notify then lib.notify({ description = message, type = notifyKind }) end
end

local function armoryResult(result, successMessage)
    result = type(result) == 'table' and result or { ok = false, reason = 'request_failed' }
    local message, kind = successMessage, 'success'
    if result.ok ~= true then
        message = tostring(result.reason or 'request_failed'):gsub('_', ' ')
        message = message:sub(1, 1):upper() .. message:sub(2) .. '.'
        kind = 'error'
    end
    notify(message, kind)
    return result
end

local function closeDashboard()
    local wasOpen = dashboardOpen
    dashboardOpen = false
    serviceOpen = false
    contactReopenAt = GetGameTimer() + 750
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    if contactCamera then
        RenderScriptCams(false, true, 350, true, true)
        DestroyCam(contactCamera, false)
        contactCamera = nil
    end
    if playerWasFrozen~=nil then FreezeEntityPosition(PlayerPedId(),playerWasFrozen==true); playerWasFrozen=nil end
    ClearFocus()
    if wasOpen then
        TriggerEvent('cm-hud:client:showAfterUi', HUD_REASON)
        TriggerEvent('cm-chat:client:showAfterUi', HUD_REASON)
    end
    activeContact = nil
end

local function dialogueShot(kind)
    local ped=activeContact and npcPeds[npcKey(activeContact)]
    if not dashboardOpen or not serviceOpen or not ped or not DoesEntityExist(ped) then return end
    local player=PlayerPedId(); local position,target
    if kind=='wide' then
        position=GetOffsetFromEntityInWorldCoords(ped,1.65,2.8,1.35); target=GetEntityCoords(ped)+vector3(0.0,0.0,0.68)
    elseif kind=='shoulder' then
        position=GetOffsetFromEntityInWorldCoords(player,0.65,-0.7,0.72); target=GetPedBoneCoords(ped,31086,0.0,0.0,0.02)
    else
        local head=GetPedBoneCoords(ped,31086,0.0,0.0,0.08); local forward=GetEntityForwardVector(ped)
        position=vector3(head.x+forward.x*1.65,head.y+forward.y*1.65,head.z+0.12); target=head
    end
    local ray=StartShapeTestRay(target.x,target.y,target.z,position.x,position.y,position.z,17,ped,7)
    local _,hit,hitCoords=GetShapeTestResult(ray)
    if hit==1 then
        local direction=target-hitCoords; local length=#direction
        if length>0.01 then position=hitCoords+direction/length*0.28 end
    end
    local nextCamera=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
    SetCamCoord(nextCamera,position.x,position.y,position.z); PointCamAtCoord(nextCamera,target.x,target.y,target.z)
    SetCamFov(nextCamera,kind=='wide' and 52.0 or kind=='shoulder' and 42.0 or 38.0)
    if contactCamera and DoesCamExist(contactCamera) then
        SetCamActiveWithInterp(nextCamera,contactCamera,600,true,true)
        local old=contactCamera; SetTimeout(700,function() if DoesCamExist(old) then DestroyCam(old,false) end end)
    else SetCamActive(nextCamera,true); RenderScriptCams(true,true,450,true,true) end
    contactCamera=nextCamera
end

local function openDashboard(section, mode)
    CreateThread(function()
        local response = lib.callback.await('cm-gang:server:getDashboard', false)
        if type(response) ~= 'table' or response.ok ~= true then closeDashboard(); return notify('Gang dashboard is unavailable.', 'error') end
        dashboardOpen = true
        serviceOpen = mode == 'dialogue' or mode == 'services'
        if mode=='dialogue' and activeContact and npcPeds[npcKey(activeContact)] then
            local ped=npcPeds[npcKey(activeContact)]; local player=PlayerPedId(); local forward=GetEntityForwardVector(ped); local coords=GetEntityCoords(ped)
            local stageX,stageY=coords.x+forward.x*1.9,coords.y+forward.y*1.9
            RequestCollisionAtCoord(stageX,stageY,coords.z)
            local ok,frozen=pcall(IsEntityPositionFrozen,player); playerWasFrozen=ok and frozen==true
            SetEntityCoordsNoOffset(player,stageX,stageY,coords.z,false,false,false)
            SetEntityHeading(player,(GetEntityHeading(ped)+180.0)%360.0)
            FreezeEntityPosition(player,true)
        end
        SetNuiFocus(true, true)
        TriggerEvent('cm-hud:client:hideForUi', HUD_REASON)
        TriggerEvent('cm-chat:client:hideForUi', HUD_REASON)
        SendNUIMessage({ action='open',data=response.data,section=section or 'overview',mode=mode or 'dashboard', contact=activeContact and activeContact.contact,contactKind=activeContact and activeContact.kind })
        if mode=='dialogue' then
            dialogueShot('wide')
            SetTimeout(950,function() if dashboardOpen and serviceOpen then dialogueShot('close') end end)
        end
    end)
end

local function openContactServices()
    local npcPed=activeContact and npcPeds[npcKey(activeContact)]
    if not npcPed or not DoesEntityExist(npcPed) then return end
    openDashboard('dialogue', 'dialogue')
end

local function openContactRefusal(entry)
    activeContact = entry
    dashboardOpen = true
    serviceOpen = true
    SetNuiFocus(true, true)
    TriggerEvent('cm-hud:client:hideForUi', HUD_REASON)
    TriggerEvent('cm-chat:client:hideForUi', HUD_REASON)
    SendNUIMessage({ action='gangRefusalOpen', gangName=entry.gangName, contact=entry.contact })
    dialogueShot('wide')
    SetTimeout(850,function() if dashboardOpen and serviceOpen then dialogueShot('close') end end)
end

RegisterCommand(Config.Commands.dashboard, function() openDashboard('overview') end, false)
RegisterKeyMapping(Config.Commands.dashboard, 'Open gang dashboard', 'keyboard', Config.Keys.dashboard)

RegisterNUICallback('close', function(_, cb) closeDashboard(); cb({ ok = true }) end)
RegisterNUICallback('ready', function(_, cb) closeDashboard(); cb({ ok = true }) end)
RegisterNUICallback('refresh', function(_, cb)
    local response = lib.callback.await('cm-gang:server:getDashboard', false)
    cb(response or { ok = false })
end)
RegisterNUICallback('contactService',function(data,cb)
    data=type(data)=='table' and data or {}
    local result=lib.callback.await('cm-gang:server:validateContactService',false,data.service) or {ok=false,reason='request_failed'}
    if result.ok then devLog(('contact service selected gang=%s service=%s'):format(tostring(result.gangId),tostring(data.service))) end
    cb(result)
end)
RegisterNUICallback('memberAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    local response = lib.callback.await('cm-gang:server:dashboardMemberAction', false, data)
    cb(response or { ok = false, reason = 'request_failed' })
end)
RegisterNUICallback('rankAction', function(data, cb)
    data = type(data) == 'table' and data or {}
    local response = lib.callback.await('cm-gang:server:dashboardRankAction', false, data)
    cb(response or { ok = false, reason = 'request_failed' })
end)
RegisterNUICallback('openStash', function(_, cb)
    closeDashboard()
    local result = lib.callback.await('cm-gang:server:openStash', false) or { ok = false, reason = 'request_failed' }
    if result.ok ~= true then notify(('Stash unavailable: %s'):format(tostring(result.reason or 'request_failed'):gsub('_', ' ')), 'error') end
    cb(result)
end)
RegisterNUICallback('loadArmory', function(_, cb)
    cb(lib.callback.await('cm-gang:server:getArmory', false) or { ok = false })
end)
RegisterNUICallback('armoryCheckout', function(data, cb)
    data = type(data) == 'table' and data or {}
    local result = lib.callback.await('cm-gang:server:armoryCheckout', false, {
        itemId = data.itemId,
        quantity = data.quantity,
    }) or { ok = false }
    local quantity = math.max(1, math.floor(tonumber(data.quantity) or 1))
    cb(armoryResult(result, ('Issued %d item%s from the gang armory.'):format(quantity, quantity == 1 and '' or 's')))
end)
RegisterNUICallback('saveArmorySettings', function(data, cb)
    data = type(data) == 'table' and data or {}
    local result = lib.callback.await('cm-gang:server:saveArmorySettings', false, data) or { ok = false }
    cb(armoryResult(result, data.open == true and 'Gang armory opened and settings saved.' or 'Gang armory closed and settings saved.'))
end)
RegisterNUICallback('loadFleet', function(_, cb) cb(lib.callback.await('cm-gang:server:getFleet', false) or { ok=false }) end)
RegisterNUICallback('callFleetVehicle', function(data, cb) cb(lib.callback.await('cm-gang:server:callFleetVehicle', false, data and data.model) or { ok=false }) end)
RegisterNUICallback('returnFleetVehicle', function(data, cb) cb(lib.callback.await('cm-gang:server:returnFleetVehicle', false, data and data.model) or { ok=false }) end)
RegisterNUICallback('recallFleetVehicle', function(data, cb) cb(lib.callback.await('cm-gang:server:recallFleetVehicle', false, data and data.model) or { ok=false }) end)
RegisterNUICallback('recallAllFreeFleetVehicles', function(_, cb) cb(lib.callback.await('cm-gang:server:recallAllFreeFleetVehicles', false) or { ok=false }) end)
RegisterNUICallback('configureFleetRank', function(data, cb) cb(lib.callback.await('cm-gang:server:configureFleetVehicleRank', false, data) or { ok=false }) end)
RegisterNUICallback('openVehicleTrunk',function(_,cb)
    closeDashboard(); local ok,result=pcall(function() return exports['cm-vehicles']:TryOpenNearbyTrunkInventory() end)
    cb({ok=ok and result==true,reason=ok and 'open_the_vehicle_trunk_first' or 'vehicle_owner_unavailable'})
end)
RegisterNUICallback('armoryDeposit', function(data, cb)
    data = type(data) == 'table' and data or {}
    local result = lib.callback.await('cm-gang:server:armoryDeposit', false, data) or { ok=false }
    local quantity = math.max(1, math.floor(tonumber(data.quantity) or 1))
    cb(armoryResult(result, ('Returned %d item%s to the gang armory.'):format(quantity, quantity == 1 and '' or 's')))
end)
RegisterNUICallback('loadArmoryReturnOptions', function(data, cb)
    data = type(data) == 'table' and data or {}
    cb(lib.callback.await('cm-gang:server:getArmoryReturnOptions', false, data.itemId) or { ok=false })
end)
RegisterNUICallback('blacklistAction', function(data, cb) cb(lib.callback.await('cm-gang:server:dashboardBlacklistAction', false, data) or { ok=false }) end)
RegisterNUICallback('loadScriptedEvents', function(_, cb) cb(lib.callback.await('cm-gang:server:getScriptedEvents', false) or { ok=false }) end)
RegisterNUICallback('loadSupplyWarPresentation',function(_,cb)cb(lib.callback.await('cm-gang:server:getSupplyWarPresentation',false)or{ok=false})end)
RegisterNUICallback('loadArsenalPresentation',function(_,cb)cb(lib.callback.await('cm-gang:server:getArsenalResupplyPresentation',false)or{ok=false})end)
RegisterNUICallback('coordinationAction', function(data, cb)
    data=type(data)=='table' and data or {}
    if data.action=='status' then return cb(lib.callback.await('cm-gang:server:getCoordination',false) or {ok=false}) end
    if data.action=='meeting' then return cb(lib.callback.await('cm-gang:server:setMeetingPoint',false,{clear=data.clear==true}) or {ok=false}) end
    if data.action=='tracking' then
        local result=lib.callback.await('cm-gang:server:setTracking',false,data.enabled==true) or {ok=false}
        if result.ok then TriggerEvent('cm-gang:client:setTracking',result.tracking) end
        return cb(result)
    end
    cb({ok=false,reason='invalid_action'})
end)
RegisterNUICallback('profitAction', function(data, cb)
    data=type(data)=='table' and data or {}
    cb(lib.callback.await(data.action=='collect' and 'cm-gang:server:collectProfit' or 'cm-gang:server:getProfit',false) or {ok=false})
end)
RegisterNUICallback('turfAction',function(data,cb)
 data=type(data)=='table' and data or {}; cb(lib.callback.await(data.action=='collect' and 'cm-gang:server:collectTurfCut' or 'cm-gang:server:getTurfInfo',false) or {ok=false})
end)
RegisterNUICallback('depositGangCash',function(data,cb)
    cb(lib.callback.await('cm-gang:server:depositGangCash',false,data and data.amount) or {ok=false})
end)
RegisterNUICallback('loadNearbyBonusMembers',function(_,cb)
    cb(lib.callback.await('cm-gang:server:getNearbyBonusMembers',false) or {ok=false})
end)
RegisterNUICallback('issueGangBonus',function(data,cb)
    data=type(data)=='table' and data or {}
    cb(lib.callback.await('cm-gang:server:issueNearbyBonus',false,data) or {ok=false})
end)
RegisterNUICallback('wardrobeAction', function(data, cb)
    data=type(data)=='table' and data or {}; local action=tostring(data.action or 'list')
    if action=='list' then return cb(lib.callback.await('cm-gang:server:getWardrobeCatalog',false,data.sex) or {ok=false}) end
    if action=='apply' then
        local result=lib.callback.await('cm-gang:server:applyWardrobeOutfit',false,data.outfitId) or {ok=false}
        if result.ok and type(result.components)=='table' then
            local ped=PlayerPedId()
            for key,value in pairs(result.components.components or {}) do SetPedComponentVariation(ped,tonumber(key),tonumber(value.drawable) or 0,tonumber(value.texture) or 0,tonumber(value.palette) or 0) end
            for key,value in pairs(result.components.props or {}) do local index=tonumber(key); if (tonumber(value.drawable) or -1)<0 then ClearPedProp(ped,index) else SetPedPropIndex(ped,index,tonumber(value.drawable),tonumber(value.texture) or 0,true) end end
        end
        return cb(result)
    end
    if action=='save' then
        local ped=PlayerPedId(); data.components={components={},props={}}
        for index=0,11 do data.components.components[tostring(index)]={drawable=GetPedDrawableVariation(ped,index),texture=GetPedTextureVariation(ped,index),palette=GetPedPaletteVariation(ped,index)} end
        for index=0,7 do data.components.props[tostring(index)]={drawable=GetPedPropIndex(ped,index),texture=GetPedPropTextureIndex(ped,index)} end
        return cb(lib.callback.await('cm-gang:server:saveWardrobeOutfit',false,data) or {ok=false})
    end
    if action=='delete' then return cb(lib.callback.await('cm-gang:server:deleteWardrobeOutfit',false,data.outfitId) or {ok=false}) end
    cb({ok=false,reason='invalid_action'})
end)

local function deleteNpc()
    for kind,ped in pairs(npcPeds) do if DoesEntityExist(ped) then DeleteEntity(ped) end; npcPeds[kind]=nil end
end

local function deleteNpcBlips()
    for key,blip in pairs(npcBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end; npcBlips[key]=nil end
end

local function syncNpcBlips(contacts)
    deleteNpcBlips()
    for _,entry in ipairs(contacts or {}) do
        if entry.kind=='main' and entry.facility then
            local facility=entry.facility
            local blip=AddBlipForCoord(facility.x+0.0,facility.y+0.0,facility.z+0.0)
            SetBlipSprite(blip,543)
            SetBlipColour(blip,tonumber(Config.GangRadarColours and Config.GangRadarColours[entry.gangId]) or 3)
            SetBlipScale(blip,0.82)
            SetBlipDisplay(blip,4)
            SetBlipAsShortRange(blip,true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(('%s Headquarters'):format(entry.gangName or entry.gangId or 'Gang'))
            EndTextCommandSetBlipName(blip)
            npcBlips[npcKey(entry)]=blip
        end
    end
end

local function spawnNpc(entry)
    local facility = entry and entry.facility
    if not facility then return end
    local candidates = entry.contact and entry.contact.modelCandidates or { facility.npcModel }
    local model, modelName
    for _, candidate in ipairs(candidates) do
        local candidateHash = joaat(tostring(candidate or ''))
        if candidate and Config.NpcModels[candidate] and IsModelInCdimage(candidateHash) and IsModelValid(candidateHash) then
            RequestModel(candidateHash)
            local deadline = GetGameTimer() + (Config.ContactStreaming.modelLoadTimeoutMs or 5000)
            while not HasModelLoaded(candidateHash) and GetGameTimer() < deadline do Wait(50) end
            if HasModelLoaded(candidateHash) then model, modelName = candidateHash, candidate; break end
            devLog(('contact model load failed gang=%s model=%s'):format(tostring(entry.gangId), tostring(candidate)))
        else
            devLog(('contact model invalid gang=%s model=%s'):format(tostring(entry.gangId), tostring(candidate)))
        end
    end
    if not model then return end
    RequestCollisionAtCoord(facility.x,facility.y,facility.z)
    local spawnZ=facility.z+0.0
    local foundGround,groundZ=GetGroundZFor_3dCoord(facility.x+0.0,facility.y+0.0,facility.z+2.0,false)
    if foundGround and math.abs(groundZ-facility.z)<=4.0 then spawnZ=groundZ end
    local npcPed = CreatePed(4, model, facility.x + 0.0, facility.y + 0.0, spawnZ, facility.heading + 0.0, false, true)
    if not npcPed or npcPed == 0 or not DoesEntityExist(npcPed) then
        SetModelAsNoLongerNeeded(model)
        return devLog(('contact ped creation failed gang=%s model=%s'):format(tostring(entry.gangId), tostring(modelName)))
    end
    SetEntityInvincible(npcPed, true)
    FreezeEntityPosition(npcPed, true)
    SetBlockingOfNonTemporaryEvents(npcPed, true)
    SetPedCanRagdoll(npcPed, false)
    npcPeds[npcKey(entry)]=npcPed
    local outfit = entry.contact and entry.contact.outfit
    for component, value in pairs(outfit and outfit.components or {}) do
        local index, drawable, texture=tonumber(component),tonumber(value[1]) or 0,tonumber(value[2]) or 0
        if index and drawable < GetNumberOfPedDrawableVariations(npcPed,index)
            and texture < GetNumberOfPedTextureVariations(npcPed,index,drawable) then
            SetPedComponentVariation(npcPed,index,drawable,texture,0)
        end
    end
    SetModelAsNoLongerNeeded(model)
    devLog(('contact spawn gang=%s model=%s coords=%.2f,%.2f,%.2f'):format(
        tostring(entry.gangId),tostring(modelName),facility.x,facility.y,facility.z))
end

local function refreshHeadquarters(retries)
    refreshGeneration = refreshGeneration + 1
    local generation = refreshGeneration
    CreateThread(function()
        local attempts = tonumber(retries) or 1
        for attempt=1,attempts do
            local response = lib.callback.await('cm-gang:server:getHeadquarters', false)
            if generation ~= refreshGeneration then return end
            if response then
                headquarters=response
                deleteNpc()
                syncNpcBlips(response.contacts)
                devLog(('contact sync gang=%s enabled=true'):format(tostring(response.gangId)))
                return
            end
            if attempt<attempts then Wait(math.min(5000,attempt*750)) end
        end
        if generation==refreshGeneration then headquarters=nil; deleteNpc(); deleteNpcBlips() end
    end)
end

RegisterNetEvent('cm-gang:client:refreshHeadquarters', function()
    refreshHeadquarters()
end)

CreateThread(function()
    while true do
        local wait = 1000
        local nearest, distance
        local playerCoords=GetEntityCoords(PlayerPedId())
        for _,entry in ipairs(headquarters and headquarters.contacts or {}) do
            local f=entry.facility; local d=#(playerCoords-vector3(f.x,f.y,f.z)); local key=npcKey(entry); local ped=npcPeds[key]
            if (not ped or not DoesEntityExist(ped)) and d<=(Config.ContactStreaming.spawnDistance or 125.0) then spawnNpc(entry)
            elseif ped and DoesEntityExist(ped) and d>(Config.ContactStreaming.despawnDistance or 150.0) then DeleteEntity(ped); npcPeds[key]=nil end
            ped=npcPeds[key]
            if ped and DoesEntityExist(ped) and d<15.0 then wait=0; drawNpcName(entry,ped) end
            if not distance or d<distance then nearest,distance=entry,d end
        end
        if nearest then
            local facility=nearest.facility; local npcPed=npcPeds[npcKey(nearest)]
            if dashboardOpen and serviceOpen and activeContact and #(playerCoords-vector3(activeContact.facility.x,activeContact.facility.y,activeContact.facility.z)) > (Config.ContactStreaming.interactionDistance or 2.5)+1.5 then
                devLog(('contact dialogue closed reason=distance gang=%s'):format(tostring(nearest.gangId)))
                closeDashboard()
            end
            if npcPed and DoesEntityExist(npcPed) and distance < 15.0 then
                wait = 0
                if distance < (Config.ContactStreaming.interactionDistance or 2.5) and not dashboardOpen then
                    if not textUiVisible then
                        lib.showTextUI(('[E] %s — %s'):format(facility.displayName ~= '' and facility.displayName or nearest.gangName,
                            facility.roleLabel ~= '' and facility.roleLabel or 'Gang Headquarters'))
                        textUiVisible = true
                    end
                    if GetGameTimer() >= contactReopenAt and IsControlJustReleased(0, 38) then
                        lib.hideTextUI(); textUiVisible=false; activeContact=nearest
                        if nearest.isOwn then openContactServices() else openContactRefusal(nearest) end
                    end
                elseif textUiVisible then
                    lib.hideTextUI(); textUiVisible = false
                end
            elseif textUiVisible then
                lib.hideTextUI(); textUiVisible = false
            end
        elseif textUiVisible then
            lib.hideTextUI(); textUiVisible = false
        end
        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        if dashboardOpen and serviceOpen then
            HideHudAndRadarThisFrame()
            if IsControlJustReleased(0, 322) or IsDisabledControlJustReleased(0, 322) then closeDashboard() end
            DisablePlayerFiring(PlayerId(),true)
            DisableControlAction(0,24,true)
            DisableControlAction(0,25,true)
            DisableControlAction(0,140,true)
            DisableControlAction(0,141,true)
            DisableControlAction(0,142,true)
            Wait(0)
        else Wait(500) end
    end
end)

AddStateBagChangeHandler('cmGang', ('player:%s'):format(GetPlayerServerId(PlayerId())), function()
    Wait(250)
    refreshHeadquarters(5)
end)

RegisterNetEvent('cm-playerdata:client:characterLoaded', function() refreshHeadquarters(8) end)
RegisterNetEvent('cm-playerdata:client:loaded', function() refreshHeadquarters(8) end)
RegisterNetEvent('cm-playerdata:client:characterUnloaded', function()
    refreshGeneration=refreshGeneration+1; headquarters=nil; deleteNpc(); deleteNpcBlips(); closeDashboard()
end)

AddEventHandler('onClientResourceStart', function(name)
    if name == RESOURCE then closeDashboard(); Wait(750); refreshHeadquarters(10) end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= RESOURCE then return end
    lib.hideTextUI(); textUiVisible = false
    closeDashboard()
    deleteNpc()
    deleteNpcBlips()
end)
