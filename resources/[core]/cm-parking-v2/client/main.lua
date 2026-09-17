local current=nil
local peds={}
local trackedPlate=nil
local trackedBlip=nil
local trackingToken=0
local spotState={}
local function clearTracking()
 trackingToken=trackingToken+1
 trackedPlate=nil
 if trackedBlip then SetBlipRoute(trackedBlip,false); RemoveBlip(trackedBlip); trackedBlip=nil end
 SetWaypointOff()
end
local function showInteraction(label, name, role)
 if GetResourceState('cm-ui') == 'started' then
  exports['cm-ui']:ShowInteract({
   key = 'E',
   label = label,
   name = name or 'Parking Attendant',
   role = role or 'CM PARKING'
  })
 end
end
local function hideInteraction()
 if GetResourceState('cm-ui') == 'started' then exports['cm-ui']:HideInteract() end
end
local function draw(g) end
local function drawSpot(spot, occupied, owned) end
local function blips() for _,g in ipairs(Config.Parking) do local b=AddBlipForCoord(g.blip); SetBlipSprite(b,267); SetBlipDisplay(b,4); SetBlipColour(b,3); SetBlipScale(b,0.85); SetBlipAsShortRange(b,false); BeginTextCommandSetBlipName('STRING'); AddTextComponentString(g.label); EndTextCommandSetBlipName(b) end end
local function getAccurateGroundZ(x, y, z)
 RequestCollisionAtCoord(x, y, z)
 local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
 if found and groundZ > 0.0 and math.abs(groundZ - z) <= 2.5 then
  return groundZ
 end
 found, groundZ = GetGroundZFor_3dCoord(x, y, z + 5.0, false)
 if found and groundZ > 0.0 and math.abs(groundZ - z) <= 2.5 then
  return groundZ
 end
 found, groundZ = GetGroundZFor_3dCoord(x, y, z, false)
 if found and groundZ > 0.0 and math.abs(groundZ - z) <= 2.5 then
  return groundZ
 end
 return z
end
local function spawnPeds()
 for _, p in pairs(peds) do
  if DoesEntityExist(p) then DeleteEntity(p) end
 end
 peds = {}

 for _, g in ipairs(Config.Parking) do
  local hash = joaat((g.Npc and g.Npc.Hash) or 's_m_m_security_01')
  RequestModel(hash)
  local timeout = GetGameTimer() + 7000
  while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
  if HasModelLoaded(hash) then
   RequestCollisionAtCoord(g.npc.x, g.npc.y, g.npc.z)
   local groundZ = getAccurateGroundZ(g.npc.x, g.npc.y, g.npc.z)
   local p = CreatePed(4, hash, g.npc.x, g.npc.y, groundZ, g.npc.w, false, true)
   if p and p ~= 0 then
    SetEntityHeading(p, g.npc.w)
    SetEntityAsMissionEntity(p, true, true)
    SetEntityInvincible(p, true)
    SetBlockingOfNonTemporaryEvents(p, true)
    SetPedCanRagdoll(p, false)
    SetPedFleeAttributes(p, 0, 0)
    SetPedCombatAttributes(p, 17, 1)

    CreateThread(function()
     local collTimeout = GetGameTimer() + 2500
     while not HasCollisionLoadedAroundEntity(p) and GetGameTimer() < collTimeout do
      RequestCollisionAtCoord(g.npc.x, g.npc.y, g.npc.z)
      Wait(20)
     end
     if DoesEntityExist(p) then
      local finalZ = getAccurateGroundZ(g.npc.x, g.npc.y, g.npc.z)
      SetEntityCoords(p, g.npc.x, g.npc.y, finalZ, false, false, false, true)
      SetEntityHeading(p, g.npc.w)
      FreezeEntityPosition(p, true)
      TaskStartScenarioInPlace(p, 'WORLD_HUMAN_CLIPBOARD', 0, true)
     end
    end)

    peds[g.id] = p
   end
   SetModelAsNoLongerNeeded(hash)
  end
 end
end
RegisterNetEvent('cm-parking-v2:notify',function(m, notifyType)
 m = tostring(m or '')
 notifyType = notifyType or 'info'
 if GetResourceState('cm-hud') == 'started' then
  local ok = pcall(function() exports['cm-hud']:Notify(m, notifyType, 5000) end)
  if ok then return end
 end
 if GetResourceState('cm-core') == 'started' then
  TriggerEvent('cm-core:client:notify', { message = m, type = notifyType, duration = 5000 })
  return
 end
 BeginTextCommandThefeedPost('STRING')
 AddTextComponentSubstringPlayerName(m)
 EndTextCommandThefeedPostTicker(false,false)
end)
RegisterNetEvent('cm-parking-v2:removeVehicle',function(vehicleId,plate)
 local wantedId=tonumber(vehicleId); local wantedPlate=tostring(plate or ''):upper():gsub('%s+','')
 for _,vehicle in ipairs(GetGamePool('CVehicle')) do
  if DoesEntityExist(vehicle) then
   local state=Entity(vehicle).state
   local stateId=tonumber(state.cmVehicleId)
   local currentPlate=GetVehicleNumberPlateText(vehicle):upper():gsub('%s+','')
   if (wantedId and stateId==wantedId) or (wantedPlate~='' and currentPlate==wantedPlate) then
    NetworkRequestControlOfEntity(vehicle)
    local deadline=GetGameTimer()+1000
    while not NetworkHasControlOfEntity(vehicle) and GetGameTimer()<deadline do Wait(0); NetworkRequestControlOfEntity(vehicle) end
    SetEntityAsMissionEntity(vehicle,true,true)
    DeleteVehicle(vehicle)
    DeleteEntity(vehicle)
   end
  end
 end
end)
RegisterNetEvent('cm-parking-v2:trackVehicle',function(plate, spotCoords)
 SetNuiFocus(false,false); current=nil; SendNUIMessage({type='closeMenu'})
 clearTracking()
 local token=trackingToken
 trackedPlate=tostring(plate or ''):upper():gsub('%s+','')

 if spotCoords and spotCoords.x and spotCoords.y then
  SetNewWaypoint(tonumber(spotCoords.x), tonumber(spotCoords.y))
 end

 CreateThread(function()
  local vehicle=0
  for attempt=1,240 do
   if token~=trackingToken then return end
   for _,candidate in ipairs(GetGamePool('CVehicle')) do
    if DoesEntityExist(candidate) then
     local candidatePlate=GetVehicleNumberPlateText(candidate):upper():gsub('%s+','')
     local statePlate=tostring(Entity(candidate).state.cmPlate or ''):upper():gsub('%s+','')
     if candidatePlate==trackedPlate or statePlate==trackedPlate then
      vehicle=candidate
      break
     end
    end
   end
   if vehicle~=0 then break end
   Wait(250)
  end
  if vehicle==0 or token~=trackingToken then return end

  local coords=GetEntityCoords(vehicle)
  SetNewWaypoint(coords.x, coords.y)

  trackedBlip=AddBlipForEntity(vehicle)
  SetBlipSprite(trackedBlip,225)
  SetBlipColour(trackedBlip,3)
  SetBlipScale(trackedBlip,0.9)
  SetBlipRoute(trackedBlip,true)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentString('Called Vehicle')
  EndTextCommandSetBlipName(trackedBlip)

  CreateThread(function()
   while token==trackingToken and trackedPlate and DoesEntityExist(vehicle) do
    local ped=PlayerPedId()
    local pedCoords=GetEntityCoords(ped)
    local vCoords=GetEntityCoords(vehicle)
    local dist=#(pedCoords - vCoords)

    if dist <= 4.5 or GetVehiclePedIsIn(ped, false) == vehicle then
     clearTracking()
     TriggerEvent('cm-parking-v2:notify', 'You arrived at your vehicle.', 'success')
     break
    end

    DrawMarker(2, vCoords.x, vCoords.y, vCoords.z + 2.2, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.6, 0.6, 0.6, 0, 229, 255, 220, false, true, 2, false, nil, nil, false)
    Wait(0)
   end
   if token==trackingToken then clearTracking() end
  end)
 end)
end)
RegisterNetEvent('cm-parking-v2:open',function(pid,p) current=pid; spotState[pid]=p.spots; for i=#p.vehicles,1,-1 do local v=p.vehicles[i]; local h=joaat(tostring(v.model or v.Hash or '')); if IsThisModelABoat(h) or IsThisModelAHeli(h) or IsThisModelAPlane(h) then table.remove(p.vehicles,i) end end; SetNuiFocus(true,true); SendNUIMessage({type='showMenu',parkingSpots=p.spots,headerData=p.header,ownedVehicles=p.vehicles}) end)
RegisterNetEvent('cm-parking-v2:refresh',function(pid,p) if not p then return end; spotState[pid]=p.spots; if current==pid then for i=#p.vehicles,1,-1 do local v=p.vehicles[i]; local h=joaat(tostring(v.model or v.Hash or '')); if IsThisModelABoat(h) or IsThisModelAHeli(h) or IsThisModelAPlane(h) then table.remove(p.vehicles,i) end end; SendNUIMessage({type='showMenu',parkingSpots=p.spots,headerData=p.header,ownedVehicles=p.vehicles}) end end)
RegisterNetEvent('cm-parking-v2:closeMenu',function() SetNuiFocus(false,false); current=nil; SendNUIMessage({type='closeMenu'}) end)
RegisterNUICallback('close',function(_,cb) SetNuiFocus(false,false); current=nil; clearTracking(); cb({ok=true}) end)
RegisterNUICallback('buySpot',function(d,cb)
 local id=d.selectedVehicle and (d.selectedVehicle.vehicleId or d.selectedVehicle.id)
 if not id then cb({ok=false,message='No vehicle selected'}); return end
 if not d.locationIndex then cb({ok=false,message='Please select a parking space first.'}); return end
 TriggerServerEvent('cm-parking-v2:buy',current,d.locationIndex,id)
 cb({ok=true})
end)
RegisterNUICallback('cancel',function(d,cb) TriggerServerEvent('cm-parking-v2:cancelForce',current,d.locationIndex); cb({ok=true,success=true,message='Cancel request sent.'}) end)
RegisterNUICallback('confirmDialog',function(d,cb)
 local v=GetVehiclePedIsIn(PlayerPedId(),false)
 local id=d.selectedVehicle and (d.selectedVehicle.vehicleId or d.selectedVehicle.id)
 if not id then cb({ok=false,message='No vehicle selected'}); return end
 if d.purchase and not d.locationIndex then cb({ok=false,message='Please select a parking space first.'}); return end
 if d.purchase then
  TriggerServerEvent('cm-parking-v2:buy',current,d.locationIndex,id)
 elseif v==0 then
  TriggerServerEvent('cm-parking-v2:call',current,d.locationIndex,id)
 else
  TriggerServerEvent('cm-parking-v2:store',current,d.locationIndex,id,NetworkGetNetworkIdFromEntity(v))
 end
 cb({success=true})
end)
RegisterNUICallback('recallSpot',function(d,cb) TriggerServerEvent('cm-parking-v2:call',current,d.locationIndex); cb({ok=true}) end)
RegisterNUICallback('notify',function(d,cb)
 local msg = d and d.message
 if msg and msg ~= '' then
  TriggerEvent('cm-parking-v2:notify', msg, d.type or 'info')
 end
 cb({ok=true})
end)
RegisterNUICallback('buyBusiness',function(d,cb)
 TriggerServerEvent('cm-parking-v2:buyBusiness',current)
 cb({ok=true})
end)
RegisterNUICallback('setPriceTier',function(d,cb)
 if d and d.tier then
  TriggerServerEvent('cm-parking-v2:setPriceTier',current,d.tier)
 end
 cb({ok=true})
end)
RegisterNUICallback('withdrawRevenue',function(d,cb)
 TriggerServerEvent('cm-parking-v2:withdrawRevenue',current)
 cb({ok=true})
end)

local pendingDialogueGarage = nil
local pendingDialoguePed = nil

local function formatMoney(amount)
 local formatted = tostring(math.floor(tonumber(amount) or 0))
 local k
 while true do
  formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
  if k == 0 then break end
 end
 return formatted
end

local function openNpcDialogue(g, ped)
 if not g then return end
 pendingDialogueGarage = g
 pendingDialoguePed = ped
 TriggerServerEvent('cm-parking-v2:getLotInfo', g.id)
end

RegisterNetEvent('cm-parking-v2:lotInfoResult', function(info)
 local g = pendingDialogueGarage
 local ped = pendingDialoguePed
 if not g or g.id ~= info.parkingId then return end
 if not ped or not DoesEntityExist(ped) then
  ped = peds[g.id]
 end

 if GetResourceState('cm-ui') == 'started' and exports['cm-ui'].OpenNpcDialogue then
  local choices = {}
  local quote = ''
  local ownerStr = info.ownerName or 'City of Los Santos'
  local stateVal = tonumber(info.stateValue) or 250000
  local formattedStateVal = formatMoney(stateVal)
  local spotPrice = tonumber(info.pricePerSpot) or 2500
  local formattedSpotPrice = formatMoney(spotPrice)

  if info.isOwner then
   quote = ('Welcome back, boss!\nFacility: %s\nOwner: %s (You)\nState Value: $%s'):format(
    info.parkingName or g.label,
    ownerStr,
    formattedStateVal
   )
   choices = {
    {
     id = 'owner_dashboard',
     label = 'Manage Parking Business',
     description = ('Adjust daily rates ($%s/day) and manage vault funds'):format(formattedSpotPrice),
     event = 'cm-parking-v2:client:dialogueChoice',
     payload = { action = 'owner_dashboard', parkingId = g.id },
     close = true
    },
    {
     id = 'browse',
     label = 'I need parking',
     description = 'View parking spots and park or retrieve your vehicle',
     event = 'cm-parking-v2:client:dialogueChoice',
     payload = { action = 'open', parkingId = g.id },
     close = true
    },
    {
     id = 'facility_info',
     label = 'Facility Information',
     description = ('Owner: %s (You) • State Value: $%s'):format(ownerStr, formattedStateVal),
     event = 'cm-parking-v2:client:dialogueChoice',
     payload = {
      action = 'facility_info',
      parkingId = g.id,
      parkingName = info.parkingName or g.label,
      ownerName = ownerStr,
      stateValue = formattedStateVal,
      pricePerSpot = formattedSpotPrice,
      isOwned = true
     },
     close = false
    }
   }
  elseif not info.isOwned then
   quote = ('Welcome to %s!\nOwner: %s\nState Value: $%s\nThis parking lot is currently unowned and available for purchase.'):format(
    info.parkingName or g.label,
    ownerStr,
    formattedStateVal
   )
   choices = {
    {
     id = 'browse',
     label = 'I need parking',
     description = ('View available parking spots for $%s/day'):format(formattedSpotPrice),
     event = 'cm-parking-v2:client:dialogueChoice',
     payload = { action = 'open', parkingId = g.id },
     close = true
    },
    {
     id = 'facility_info',
     label = 'Information about this parking',
     description = ('Owner: %s • State Value: $%s'):format(ownerStr, formattedStateVal),
     event = 'cm-parking-v2:client:dialogueChoice',
     payload = {
      action = 'facility_info',
      parkingId = g.id,
      parkingName = info.parkingName or g.label,
      ownerName = ownerStr,
      stateValue = formattedStateVal,
      pricePerSpot = formattedSpotPrice,
      isOwned = false
     },
     close = false
    },
    {
     id = 'buy_business',
     label = ('Buy Parking Business ($%s)'):format(formattedStateVal),
     description = 'Purchase ownership of this parking facility and earn rental profits',
     event = 'cm-parking-v2:client:dialogueChoice',
     payload = { action = 'buy_business', parkingId = g.id },
     close = true
    }
   }
  else
   quote = ('Welcome to %s!\nOwner: %s\nState Value: $%s'):format(
    info.parkingName or g.label,
    ownerStr,
    formattedStateVal
   )
   choices = {
    {
     id = 'browse',
     label = 'I need parking',
     description = ('View available parking spots for $%s/day'):format(formattedSpotPrice),
     event = 'cm-parking-v2:client:dialogueChoice',
     payload = { action = 'open', parkingId = g.id },
     close = true
    },
    {
     id = 'facility_info',
     label = 'Information about this parking',
     description = ('Owner: %s • State Value: $%s'):format(ownerStr, formattedStateVal),
     event = 'cm-parking-v2:client:dialogueChoice',
     payload = {
      action = 'facility_info',
      parkingId = g.id,
      parkingName = info.parkingName or g.label,
      ownerName = ownerStr,
      stateValue = formattedStateVal,
      pricePerSpot = formattedSpotPrice,
      isOwned = true
     },
     close = false
    }
   }
  end

  exports['cm-ui']:OpenNpcDialogue(ped or PlayerPedId(), {
   name = 'Parking Attendant',
   role = g.label or 'CM PARKING',
   quote = quote,
   continueLabel = 'Continue',
   deferChoices = false,
   choices = choices,
   closeEvent = 'cm-parking-v2:client:dialogueDismissed'
  })
 else
  TriggerServerEvent('cm-parking-v2:open', g.id)
 end
end)

AddEventHandler('cm-parking-v2:client:dialogueChoice', function(payload)
 if not payload then return end
 if payload.action == 'open' then
  TriggerServerEvent('cm-parking-v2:open', payload.parkingId)
 elseif payload.action == 'owner_dashboard' then
  TriggerServerEvent('cm-parking-v2:open', payload.parkingId, nil, 'owner')
 elseif payload.action == 'buy_business' then
  TriggerServerEvent('cm-parking-v2:buyBusiness', payload.parkingId)
 elseif payload.action == 'facility_info' then
  if GetResourceState('cm-ui') == 'started' and exports['cm-ui'].NpcDialogueRespond then
   local responseMsg = ('Facility: %s\nOwner: %s\nState Value: $%s\nRate: $%s/day'):format(
    payload.parkingName or 'Parking Lot',
    payload.ownerName or 'City of Los Santos',
    tostring(payload.stateValue or '250,000'),
    tostring(payload.pricePerSpot or '2,500')
   )
   if not payload.isOwned then
    responseMsg = responseMsg .. '\nStatus: Available for purchase'
   else
    responseMsg = responseMsg .. '\nStatus: Privately owned'
   end
   exports['cm-ui']:NpcDialogueRespond(responseMsg, 'info', 4500)
  end
 end
end)

CreateThread(function()
 Wait(1500); blips(); spawnPeds()
 while true do
  local wait = 500; local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then
   hideInteraction(); Wait(400)
  elseif GetResourceState('cm-ui') == 'started' and exports['cm-ui'].IsNpcDialogueOpen and exports['cm-ui']:IsNpcDialogueOpen() then
   hideInteraction(); Wait(300)
  else
   local pos = GetEntityCoords(ped); local nearest = nil; local nearestDist = 9999.0
   for _, g in ipairs(Config.Parking) do
    local npcDist = #(pos - vector3(g.npc.x, g.npc.y, g.npc.z))
    if npcDist <= 3.5 and npcDist < nearestDist then
     nearest = { parking = g, index = nil, ped = peds[g.id] }
     nearestDist = npcDist
    end
    for idx, spot in ipairs(g.spots) do
     local dist = #(pos - vector3(spot.x, spot.y, spot.z))
     if dist <= 4.0 and dist < nearestDist then
      nearest = { parking = g, index = idx }
      nearestDist = dist
     end
    end
   end
   if nearest then
    wait = 0
    if nearest.index then
     showInteraction(('PARKING SPOT #%d'):format(nearest.index), ('Parking Spot #%d'):format(nearest.index), nearest.parking.label or 'CM PARKING')
     if IsControlJustReleased(0, 38) then
      TriggerServerEvent('cm-parking-v2:open', nearest.parking.id, nearest.index)
     end
    else
     showInteraction('TALK TO ATTENDANT', 'Parking Attendant', nearest.parking.label or 'CM PARKING')
     if IsControlJustReleased(0, 38) then
      openNpcDialogue(nearest.parking, nearest.ped)
     end
    end
   else
    hideInteraction()
    wait = 400
   end
   Wait(wait)
  end
 end
end)
AddEventHandler('onResourceStop',function(resource) if resource~=GetCurrentResourceName() then return end; clearTracking(); hideInteraction(); for _,p in pairs(peds) do if DoesEntityExist(p) then DeleteEntity(p) end end end)
