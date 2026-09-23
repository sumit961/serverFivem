local locks={}
local vehicleLocks={}
local houseTransfers={}
local transferSequence=0
local function lockVehicle(vehicleId, token)
 vehicleId=tonumber(vehicleId)
 if not vehicleId or vehicleLocks[vehicleId] then return nil end
 transferSequence=transferSequence+1
 token=token or ('parking:%d:%d:%d'):format(vehicleId,GetGameTimer(),transferSequence)
 vehicleLocks[vehicleId]=token
 return token
end
local function unlockVehicle(vehicleId, token)
 vehicleId=tonumber(vehicleId)
 if vehicleId and token and vehicleLocks[vehicleId]==token then vehicleLocks[vehicleId]=nil end
end
local function withLock(src)
 if locks[src] then return false end
 locks[src]=GetGameTimer()+15000
 return true
end
local function unlock(src) locks[src]=nil end
local function releaseExpired()
 local rows=MySQL.query.await('SELECT id,vehicle_id FROM cm_parking_spaces WHERE expires_at IS NOT NULL AND expires_at <= NOW()') or {}
 for _,row in ipairs(rows) do
  local vehicleId=tonumber(row.vehicle_id)
  local token=vehicleId and lockVehicle(vehicleId) or nil
  if not vehicleId or token then
   if vehicleId then pcall(exports['cm-vehicles'].DeleteSpawnedVehicle,vehicleId) end
   MySQL.update.await('DELETE FROM cm_parking_spaces WHERE id=? AND expires_at IS NOT NULL AND expires_at <= NOW()',{row.id})
   if vehicleId then pcall(exports['cm-vehicles'].TransitionVehicleLocation,vehicleId,'OUTSIDE',{reason='public_parking_expired'}) end
   if token then unlockVehicle(vehicleId,token) end
  end
 end
end
local function cid(src) return exports['cm-playerdata']:GetCharacterId(src) end
local function garage(id) for _,g in ipairs(Config.Parking) do if g.id==tostring(id) then return g end end end
local function near(src,p,d) local ped=GetPlayerPed(src); return ped>0 and #(GetEntityCoords(ped)-vector3(p.x,p.y,p.z))<=d end
local function nearParkingInteraction(src,g,idx)
 local spot=g and idx and g.spots[idx]
 if not spot then return false end
 return near(src,g.npc,25.0) or near(src,spot,Config.VehicleDistance)
end
local function notify(src,msg) TriggerClientEvent('cm-parking-v2:notify',src,msg) end
local function allowedModel(model)
 local name=tostring(model or ''):lower()
 return not name:find('dinghy',1,true) and not name:find('jetmax',1,true) and not name:find('marquis',1,true) and not name:find('seashark',1,true) and not name:find('submersible',1,true) and not name:find('frogger',1,true) and not name:find('maverick',1,true) and not name:find('buzzard',1,true) and not name:find('cuban800',1,true) and not name:find('dodo',1,true)
end
local function getCharacterName(src, charId)
 if not src then return 'Citizen' end
 if GetResourceState('cm-playerdata') == 'started' then
  local ok, name = pcall(function()
   return exports['cm-playerdata']:GetCharacterFullName(src)
  end)
  if ok and name and name ~= '' then return name end
 end
 local row = MySQL.single.await('SELECT first_name, last_name FROM cm_characters WHERE id = ? LIMIT 1', { charId })
 if row and row.first_name then
  return ('%s %s'):format(row.first_name, row.last_name or '')
 end
 return GetPlayerName(src) or 'Citizen'
end

local function data(src,pid,initialTab)
 releaseExpired()
 local c=cid(src); local g=garage(pid); if not c or not g then return nil end
 local owned=MySQL.query.await('SELECT * FROM cm_owned_vehicles WHERE owner_character_id = ? ORDER BY id DESC',{tostring(c)}) or {}
 local personal=MySQL.single.await('SELECT parking_id,spot_index,vehicle_id,expires_at FROM cm_parking_spaces WHERE character_id=? AND (expires_at IS NULL OR expires_at > NOW()) LIMIT 1',{tostring(c)})
 local spaces=MySQL.query.await('SELECT spot_index,character_id,vehicle_id FROM cm_parking_spaces WHERE parking_id = ?',{g.id}) or {}; local map={}
 for _,s in ipairs(spaces) do map[tonumber(s.spot_index)]={owned=tostring(s.character_id)==tostring(c),vehicleId=tonumber(s.vehicle_id)} end
 for i=#owned,1,-1 do local v=owned[i]; if not allowedModel(v.model) then table.remove(owned,i) else v.vehicleId=tonumber(v.id); v.Label=v.label or v.model; v.Plate=v.plate; v.Hash=v.model end end
 local spots={}; local free=0
 for i=1,#g.spots do local s=map[i]; spots[i]={Free=not s,CoordsIdx=i,IsOwner=s and s.owned or false}; if not s then free=free+1 end end
 local parkName=nil
 if personal and personal.parking_id then
  local pg=garage(personal.parking_id)
  parkName=pg and pg.label or personal.parking_id
 end

 local lot = MySQL.single.await('SELECT * FROM cm_parking_lots WHERE parking_id = ? LIMIT 1', { g.id })
 local isOwner = c and lot and lot.owner_character_id and tostring(lot.owner_character_id) == tostring(c)
 local activePrice = lot and tonumber(lot.price_per_spot) or Config.Price or 2500
 local stateValue = (Config.Ownership and Config.Ownership.purchasePrice) or 250000

 return {
  spots=spots,
  header={
   FreeSpaces=free,
   TotalSpaces=#g.spots,
   OccupiedSpots=#g.spots - free,
   ParkingName=g.label,
   PricePerSpot=activePrice,
   Balance=tonumber(balance) or 0,
   AlreadyParked=personal~=nil,
   AlreadyParkedAt=personal and personal.parking_id or nil,
   AlreadyParkedName=parkName,
   PriceConfirmation=('Buy this parking space for $%d?'):format(activePrice),
   IsOwner=isOwner == true,
   OwnerName=lot and lot.owner_name or 'City of Los Santos',
   StateValue=stateValue,
   PriceTier=lot and lot.price_tier or 'normal',
   BusinessBalance=isOwner and (tonumber(lot.business_balance) or 0) or 0,
   DailyIncome=isOwner and (tonumber(lot.daily_income) or 0) or 0,
   WeeklyIncome=isOwner and (tonumber(lot.weekly_income) or 0) or 0,
   InitialTab=initialTab
  },
  vehicles=owned
 }
end
RegisterNetEvent('cm-parking-v2:open',function(pid,idx,initialTab) local s=source; local g=garage(pid); idx=tonumber(idx); if not g then return end; if idx then if not g.spots[idx] or not near(s,g.spots[idx],Config.VehicleDistance) then return end else if not near(s,g.npc,Config.InteractionDistance) then return end end; local payload=data(s,pid,initialTab); if not payload then return end; if idx then local selected=payload.spots[idx]; payload.spots={selected}; payload.header.SelectedSpot=idx end; TriggerClientEvent('cm-parking-v2:open',s,pid,payload) end)
RegisterNetEvent('cm-parking-v2:buy',function(pid,idx,vehicleId)
 local s=source; if not withLock(s) then return end; releaseExpired(); local g=garage(pid); local c=cid(s); idx=tonumber(idx); vehicleId=tonumber(vehicleId);
 if not g or not c or not g.spots[idx] or not vehicleId then notify(s,'Select a car and an available parking space first.'); unlock(s); return end;
 if not nearParkingInteraction(s,g,idx) then notify(s,'Move closer to the parking attendant or selected parking space.'); unlock(s); return end;
 local exists=MySQL.single.await('SELECT id FROM cm_parking_spaces WHERE parking_id=? AND spot_index=? AND (expires_at IS NULL OR expires_at > NOW())',{g.id,idx});
 local personal=MySQL.single.await('SELECT id FROM cm_parking_spaces WHERE character_id=? AND (expires_at IS NULL OR expires_at > NOW()) LIMIT 1',{tostring(c)});
 local assigned=MySQL.single.await('SELECT id,parking_id,spot_index FROM cm_parking_spaces WHERE vehicle_id=? AND (expires_at IS NULL OR expires_at > NOW()) LIMIT 1',{vehicleId});
 local row=MySQL.single.await('SELECT id,model,plate FROM cm_owned_vehicles WHERE id=? AND owner_character_id=? LIMIT 1',{vehicleId,tostring(c)});
 if exists then
  notify(s,'That parking space is already taken.')
 elseif personal then
  notify(s,'You already have a parking space. Cancel it before buying another.')
 elseif assigned then
  notify(s,'This vehicle already has a parking space. Cancel it before buying another.')
 elseif not row or not allowedModel(row.model) then
  notify(s,'Select a normal car. Boats and aircraft are not allowed.')
 else
  local lot = MySQL.single.await('SELECT * FROM cm_parking_lots WHERE parking_id = ? LIMIT 1', { g.id })
  local activePrice = lot and tonumber(lot.price_per_spot) or Config.Price or 2500
  local ok=exports['cm-playerdata']:RemoveBank(s,activePrice,'parking-space');
  if ok then
   pcall(function() return exports['cm-vehicles']:DeleteSpawnedVehicle(row.plate) end)
   local inserted=MySQL.insert.await('INSERT INTO cm_parking_spaces (character_id,parking_id,spot_index,vehicle_id,price_paid) VALUES (?,?,?,?,?)',{tostring(c),g.id,idx,vehicleId,activePrice});
   if not inserted then
    exports['cm-playerdata']:AddBank(s,activePrice,'parking-space-failed');
    notify(s,'Parking could not be assigned.')
   else
    local spot=g.spots[idx];
    local spawned,reason=exports['cm-vehicles']:SpawnVehicleFromParking(s,vehicleId,g.id,{x=spot.x,y=spot.y,z=spot.z,w=spot.w},{warp=false,engineOn=false});
    if spawned then
     notify(s,'Parking purchased and vehicle called.')
     TriggerClientEvent('cm-parking-v2:trackVehicle',s,row.plate,{x=spot.x,y=spot.y,z=spot.z})
     if lot and lot.owner_character_id then
      local revenuePercent = (Config.Ownership and Config.Ownership.ownerRevenuePercent) or 80
      local ownerCut = math.floor(activePrice * (revenuePercent / 100))
      MySQL.query.await([[
       UPDATE cm_parking_lots
       SET business_balance = business_balance + ?,
           daily_income = daily_income + ?,
           weekly_income = weekly_income + ?
       WHERE parking_id = ?
      ]], { ownerCut, ownerCut, ownerCut, g.id })
     end
    else
     MySQL.update.await('DELETE FROM cm_parking_spaces WHERE id=? AND character_id=?',{inserted,tostring(c)});
     exports['cm-playerdata']:AddBank(s,activePrice,'parking-space-failed');
     notify(s,tostring(reason or 'Vehicle could not be spawned.'))
    end
   end
  else
   notify(s,'Not enough money in your bank account.')
  end
 end;
 TriggerClientEvent('cm-parking-v2:refresh',s,pid,data(s,pid));
 unlock(s)
end)

RegisterNetEvent('cm-parking-v2:getLotInfo', function(pid)
 local s = source
 local c = cid(s)
 local g = garage(pid)
 if not g then return end
 local lot = MySQL.single.await('SELECT * FROM cm_parking_lots WHERE parking_id = ? LIMIT 1', { g.id })
 local isOwner = c and lot and lot.owner_character_id and tostring(lot.owner_character_id) == tostring(c)
 local stateValue = (Config.Ownership and Config.Ownership.purchasePrice) or 250000
 local activePrice = lot and tonumber(lot.price_per_spot) or 2500

 local spacesCount = MySQL.scalar.await('SELECT COUNT(*) FROM cm_parking_spaces WHERE parking_id = ? AND (expires_at IS NULL OR expires_at > NOW())', { g.id }) or 0

 TriggerClientEvent('cm-parking-v2:lotInfoResult', s, {
  parkingId = g.id,
  parkingName = g.label,
  ownerName = lot and lot.owner_name or 'City of Los Santos',
  isOwned = lot and lot.owner_character_id ~= nil,
  isOwner = isOwner == true,
  priceTier = lot and lot.price_tier or 'normal',
  pricePerSpot = activePrice,
  stateValue = stateValue,
  businessBalance = isOwner and (tonumber(lot.business_balance) or 0) or 0,
  dailyIncome = isOwner and (tonumber(lot.daily_income) or 0) or 0,
  weeklyIncome = isOwner and (tonumber(lot.weekly_income) or 0) or 0,
  totalSpots = #g.spots,
  occupiedSpots = tonumber(spacesCount) or 0
 })
end)

RegisterNetEvent('cm-parking-v2:buyBusiness', function(pid)
 local s = source
 if not withLock(s) then return end
 local c = cid(s)
 local g = garage(pid)
 if not c or not g then unlock(s); return end

 local price = (Config.Ownership and Config.Ownership.purchasePrice) or 250000
 local lot = MySQL.single.await('SELECT * FROM cm_parking_lots WHERE parking_id = ? LIMIT 1', { g.id })
 if lot and lot.owner_character_id then
  notify(s, 'This parking lot is already privately owned.', 'error')
  unlock(s); return
 end

 local ok = exports['cm-playerdata']:RemoveBank(s, price, 'buy-parking-business')
 if not ok then
  notify(s, ('You do not have enough money ($%s) in your bank account.'):format(price), 'error')
  unlock(s); return
 end

 local charName = getCharacterName(s, c)
 MySQL.query.await([[
  INSERT INTO cm_parking_lots (parking_id, owner_character_id, owner_name, price_tier, price_per_spot, business_balance, purchased_at)
  VALUES (?, ?, ?, 'normal', 2500, 0, NOW())
  ON DUPLICATE KEY UPDATE
    owner_character_id = VALUES(owner_character_id),
    owner_name = VALUES(owner_name),
    purchased_at = NOW()
 ]], { g.id, tostring(c), charName })

 notify(s, ('Congratulations! You are now the owner of %s.'):format(g.label), 'success')
 TriggerClientEvent('cm-parking-v2:refresh', s, pid, data(s, pid))
 unlock(s)
end)

RegisterNetEvent('cm-parking-v2:setPriceTier', function(pid, tier)
 local s = source
 local c = cid(s)
 local g = garage(pid)
 tier = tostring(tier or ''):lower()
 local prices = { low = 1000, normal = 2500, high = 5000 }
 local spotPrice = prices[tier]
 if not c or not g or not spotPrice then return end

 local lot = MySQL.single.await('SELECT * FROM cm_parking_lots WHERE parking_id = ? LIMIT 1', { g.id })
 if not lot or not lot.owner_character_id or tostring(lot.owner_character_id) ~= tostring(c) then
  notify(s, 'You do not own this parking business.', 'error')
  return
 end

 MySQL.query.await([[
  UPDATE cm_parking_lots
  SET price_tier = ?, price_per_spot = ?
  WHERE parking_id = ?
 ]], { tier, spotPrice, g.id })

 notify(s, ('Parking rental rate updated to %s tier ($%d/day).'):format(tier:upper(), spotPrice), 'success')
 TriggerClientEvent('cm-parking-v2:refresh', s, pid, data(s, pid))
end)

RegisterNetEvent('cm-parking-v2:withdrawRevenue', function(pid)
 local s = source
 if not withLock(s) then return end
 local c = cid(s)
 local g = garage(pid)
 if not c or not g then unlock(s); return end

 local lot = MySQL.single.await('SELECT * FROM cm_parking_lots WHERE parking_id = ? LIMIT 1', { g.id })
 if not lot or not lot.owner_character_id or tostring(lot.owner_character_id) ~= tostring(c) then
  notify(s, 'You do not own this parking business.', 'error')
  unlock(s); return
 end

 local balance = tonumber(lot.business_balance) or 0
 if balance <= 0 then
  notify(s, 'There are no funds available in the business vault to withdraw.', 'warning')
  unlock(s); return
 end

 MySQL.query.await('UPDATE cm_parking_lots SET business_balance = 0 WHERE parking_id = ?', { g.id })
 exports['cm-playerdata']:AddBank(s, balance, 'parking-business-withdrawal')
 notify(s, ('Withdrew $%s from %s business vault into your bank account.'):format(balance, g.label), 'success')
 TriggerClientEvent('cm-parking-v2:refresh', s, pid, data(s, pid))
 unlock(s)
end)

local function cancelParking(s,pid,idx)
 if not withLock(s) then return end
 local c=cid(s); local g=garage(pid); idx=tonumber(idx)
 local atNpc=g and near(s,g.npc,25.0)
 local atSpot=g and idx and g.spots[idx] and near(s,g.spots[idx],Config.VehicleDistance)
 if not c or not g or (not atNpc and not atSpot) then unlock(s); return end
 local space=MySQL.single.await('SELECT p.id,p.vehicle_id,p.price_paid,p.parking_id,v.plate FROM cm_parking_spaces p LEFT JOIN cm_owned_vehicles v ON v.id=p.vehicle_id WHERE p.character_id=? AND (p.expires_at IS NULL OR p.expires_at > NOW()) ORDER BY p.id DESC LIMIT 1',{tostring(c)})
 if not space then
  space=MySQL.single.await('SELECT p.id,p.vehicle_id,p.price_paid,p.parking_id,v.plate FROM cm_parking_spaces p LEFT JOIN cm_owned_vehicles v ON v.id=p.vehicle_id WHERE p.character_id=? ORDER BY p.id DESC LIMIT 1',{tostring(c)})
 end
 if not space then
  notify(s,'Parking is already cancelled.')
  TriggerClientEvent('cm-parking-v2:closeMenu',s)
  TriggerClientEvent('cm-parking-v2:refresh',s,pid,data(s,pid))
  unlock(s)
  return
 end
 local vehicleId=tonumber(space.vehicle_id)
 local vehicleLock=vehicleId and lockVehicle(vehicleId) or nil
 if vehicleId and not vehicleLock then
  notify(s,'This vehicle is being moved to a house garage. Try again shortly.')
  unlock(s)
  return
 end
 if space.vehicle_id then
  TriggerClientEvent('cm-parking-v2:removeVehicle',s,vehicleId,space.plate)
  pcall(function() return exports['cm-vehicles']:DeleteSpawnedVehicle(vehicleId) end)
  if space.plate then
   pcall(function() return exports['cm-vehicles']:DeleteSpawnedVehicle(space.plate) end)
  end
 end
 local n=MySQL.update.await('DELETE FROM cm_parking_spaces WHERE character_id=?',{tostring(c)})
 if n and tonumber(n)>0 then
  if space.vehicle_id then
   pcall(function()
    return exports['cm-vehicles']:TransitionVehicleLocation(vehicleId,'OUTSIDE',{reason='public_parking_cancelled',actorCharacterId=c})
   end)
  end
  local refund=tonumber(space.price_paid) or Config.Price
  if refund>0 then
   exports['cm-playerdata']:AddBank(s,refund,'parking-space-refund')
  end
  notify(s,'Parking cancelled and vehicle removed from the world.')
  TriggerClientEvent('cm-parking-v2:closeMenu',s)
  TriggerClientEvent('cm-parking-v2:refresh',s,pid,data(s,pid))
 else
  notify(s,'Parking could not be cancelled due to a database error. Please try again.')
 end
 if vehicleLock then unlockVehicle(vehicleId,vehicleLock) end
 unlock(s)
end

RegisterNetEvent('cm-parking-v2:cancel',function(pid,idx) cancelParking(source,pid,idx) end)
RegisterNetEvent('cm-parking-v2:store',function(pid,idx,vehicleId,netId)
 local s=source; local c=cid(s); local g=garage(pid); idx=tonumber(idx); vehicleId=tonumber(vehicleId)
 if not c or not g or not g.spots[idx] or not vehicleId or not near(s,g.spots[idx],Config.VehicleDistance) then return end
 local own=MySQL.single.await('SELECT id FROM cm_parking_spaces WHERE character_id=? AND parking_id=? AND spot_index=?',{tostring(c),g.id,idx})
 if not own then notify(s,'You do not own this parking space.') return end
 local token=lockVehicle(vehicleId)
 if not token then notify(s,'This vehicle is being moved to a house garage. Try again shortly.') return end
 local ok,reason=exports['cm-vehicles']:StoreVehicle(s,vehicleId,g.id,{netId=tonumber(netId),slot=idx,reason='public_parking'})
 unlockVehicle(vehicleId,token)
 if ok then notify(s,'Vehicle parked.') else notify(s,tostring(reason or 'Vehicle could not be parked.')) end
end)

RegisterNetEvent('cm-parking-v2:call',function(pid,idx,vehicleId)
 local s=source; local c=cid(s); local g=garage(pid); idx=tonumber(idx); vehicleId=tonumber(vehicleId)
 if not c or not g or not g.spots[idx] then return end
 if not nearParkingInteraction(s,g,idx) then notify(s,'Move closer to the parking attendant or selected parking space.'); return end
 local own=MySQL.single.await('SELECT id,vehicle_id,parking_id,spot_index FROM cm_parking_spaces WHERE character_id=? AND parking_id=? AND spot_index=? LIMIT 1',{tostring(c),g.id,idx})
 if not own then notify(s,'You do not own this parking space.'); return end
 vehicleId=vehicleId or tonumber(own.vehicle_id)
 if tonumber(own.vehicle_id)~=vehicleId then notify(s,'This parking space can only recall its assigned vehicle.'); return end
 local token=lockVehicle(vehicleId)
 if not token then notify(s,'This vehicle is being moved to a house garage. Try again shortly.'); return end
 local row=MySQL.single.await('SELECT model,plate,is_stored FROM cm_owned_vehicles WHERE id=? AND owner_character_id=? LIMIT 1',{vehicleId,tostring(c)})
 if not row or not allowedModel(row.model) then
  unlockVehicle(vehicleId,token); notify(s,'Boats and aircraft cannot use public parking.'); return
 end
 if tonumber(row.is_stored)~=1 then
  local removed=exports['cm-vehicles']:DeleteSpawnedVehicle(row.plate)
  if removed==false then unlockVehicle(vehicleId,token); notify(s,'The existing vehicle could not be removed.'); return end
 end
 local spot=g.spots[idx]
 local ok,reason=exports['cm-vehicles']:SpawnVehicleFromParking(s,vehicleId,g.id,{x=spot.x,y=spot.y,z=spot.z,w=spot.w},{warp=false,engineOn=false})
 unlockVehicle(vehicleId,token)
 if not ok then
  notify(s,tostring(reason or 'Vehicle could not be called.'))
 else
  notify(s,'Vehicle called to your parking space.')
  TriggerClientEvent('cm-parking-v2:trackVehicle',s,row.plate,{x=spot.x,y=spot.y,z=spot.z})
 end
end)
AddEventHandler('playerDropped',function()
 local s=source; locks[s]=nil
 local transferPending=false
 for _,transfer in pairs(houseTransfers) do if transfer.source==s then transferPending=true break end end
 local c=cid(s)
 if c then
  local row=MySQL.single.await('SELECT vehicle_id FROM cm_parking_spaces WHERE character_id=? LIMIT 1',{tostring(c)})
  if row and row.vehicle_id and not transferPending and not vehicleLocks[tonumber(row.vehicle_id)] then
   pcall(exports['cm-vehicles'].DeleteSpawnedVehicle,tonumber(row.vehicle_id))
  end
 end
end)
AddEventHandler('cm-playerdata:server:characterLoaded',function(src)
 src=tonumber(src); if not src then return end
 SetTimeout(3000,function()
  if not GetPlayerName(src) then return end
  releaseExpired()
  local c=cid(src); if not c then return end
  local row=MySQL.single.await('SELECT vehicle_id,parking_id FROM cm_parking_spaces WHERE character_id=? AND vehicle_id IS NOT NULL AND (expires_at IS NULL OR expires_at > NOW()) LIMIT 1',{tostring(c)})
  if row then
   local ok,reason=exports['cm-vehicles']:SpawnVehicleFromParking(src,tonumber(row.vehicle_id),row.parking_id,nil,{warp=false,engineOn=false})
   if not ok then notify(src,tostring(reason or 'Your parking vehicle could not be restored.')) end
  end
 end)
end)
RegisterNetEvent('cm-parking-v2:cancelForce',function(pid,idx) cancelParking(source,pid,idx) end)
local function isAdmin(src)
 local permission='parking.reset'
 if GetResourceState('cm-core')=='started' then
  local ok,allowed=pcall(function() return exports['cm-core']:ACLCheck(src,permission) end)
  if ok and allowed==true then return true end
 end
 if GetResourceState('cm-admin')=='started' then
  local ok,allowed=pcall(function() return exports['cm-admin']:HasPermission(src,permission) end)
  if ok and allowed==true then return true end
 end
 return IsPlayerAceAllowed(src,'cmparking.reset')
end
local function feedback(src,msg)
 if src>0 then notify(src,msg) else print('[CM-PARKING-V2] '..msg) end
end
RegisterCommand('parkingclear',function(src,args)
 if src>0 and not isAdmin(src) then feedback(src,'You do not have permission to do that.') return end
 local target=tonumber(args[1]) or src
 if target<=0 then print('[CM-PARKING-V2] Usage: parkingclear <serverId>') return end
 local c=cid(target)
 if not c then feedback(src,'That player\'s character is not loaded.') return end
 local space=MySQL.single.await('SELECT id,vehicle_id,price_paid FROM cm_parking_spaces WHERE character_id=? ORDER BY id DESC LIMIT 1',{tostring(c)})
 if not space then feedback(src,('No parking record found for character %s.'):format(tostring(c))) return end
 local vehicleId=tonumber(space.vehicle_id)
 local vehicleLock=vehicleId and lockVehicle(vehicleId) or nil
 if vehicleId and not vehicleLock then feedback(src,'That vehicle is being moved to a house garage. Try again shortly.') return end
 if vehicleId then pcall(exports['cm-vehicles'].DeleteSpawnedVehicle,vehicleId) end
 local n=MySQL.update.await('DELETE FROM cm_parking_spaces WHERE character_id=?',{tostring(c)})
 if n and tonumber(n)>0 then
  exports['cm-playerdata']:AddBank(target,tonumber(space.price_paid) or Config.Price,'parking-space-admin-refund')
  feedback(src,('Cleared the stuck parking record for character %s and refunded $%d.'):format(tostring(c),tonumber(space.price_paid) or Config.Price))
  if target~=src and target>0 then notify(target,'An admin cleared a stuck parking record for you and refunded your deposit.') end
  TriggerClientEvent('cm-parking-v2:closeMenu',target)
 else
  feedback(src,'Could not clear that parking record.')
 end
 if vehicleLock then unlockVehicle(vehicleId,vehicleLock) end
end,false)

-- Server-only integration used by cm-house when an owner moves a car out of
-- public parking. Export contract (cm-house only):
--   GetCharacterVehicleAssignments(characterId) -> assignment array
--   BeginHouseGarageTransfer(vehicleId, characterId, source) -> ok, token, assignment
--   CompleteHouseGarageTransfer(token, source, characterId) -> ok, refund details
--   AbortHouseGarageTransfer(token, source, characterId) -> ok
-- cm-parking-v2 remains the owner of its reservation and refund.
local function houseIntegrationCaller()
 return GetInvokingResource()=='cm-house'
end

exports('GetCharacterVehicleAssignments',function(characterId)
 if not houseIntegrationCaller() then return nil end
 characterId=tostring(characterId or '')
 if characterId=='' or #characterId>100 then return nil end
 local rows=MySQL.query.await([[
  SELECT vehicle_id,parking_id,spot_index
  FROM cm_parking_spaces
  WHERE character_id=? AND vehicle_id IS NOT NULL
    AND (expires_at IS NULL OR expires_at > NOW())
 ]],{characterId}) or {}
 local out={}
 for _,row in ipairs(rows) do
  local parking=garage(row.parking_id)
  out[#out+1]={
   vehicleId=tonumber(row.vehicle_id),
   parkingId=tostring(row.parking_id or ''),
   spotIndex=tonumber(row.spot_index),
   parkingLabel=tostring(parking and parking.label or row.parking_id or 'Public parking'),
  }
 end
 return out
end)

exports('BeginHouseGarageTransfer',function(vehicleId,characterId,src)
 if not houseIntegrationCaller() then return false,'resource_not_authorized' end
 vehicleId,src=tonumber(vehicleId),tonumber(src)
 characterId=tostring(characterId or '')
 if not vehicleId or not src or not GetPlayerName(src) or characterId=='' then
  return false,'invalid_request'
 end
 local activeCharacter=cid(src)
 if not activeCharacter or tostring(activeCharacter)~=characterId then
  return false,'character_mismatch'
 end
 local row=MySQL.single.await([[
  SELECT p.id,p.character_id,p.parking_id,p.spot_index,p.vehicle_id,p.price_paid
  FROM cm_parking_spaces p
  INNER JOIN cm_owned_vehicles v ON v.id=p.vehicle_id
  WHERE p.vehicle_id=? AND p.character_id=? AND v.owner_character_id=?
    AND (p.expires_at IS NULL OR p.expires_at > NOW())
  LIMIT 1
 ]],{vehicleId,characterId,characterId})
 if not row then return false,'public_parking_not_assigned' end
 local token=lockVehicle(vehicleId)
 if not token then return false,'vehicle_operation_in_progress' end
 houseTransfers[token]={
  vehicleId=vehicleId,characterId=characterId,source=src,rowId=tonumber(row.id),
  parkingId=tostring(row.parking_id or ''),spotIndex=tonumber(row.spot_index),
 }
 SetTimeout(120000,function()
  local transfer=houseTransfers[token]
  if transfer then
   houseTransfers[token]=nil
   unlockVehicle(transfer.vehicleId,token)
   print(('[CM-PARKING-V2] Released timed-out house transfer lock for vehicle %s.'):format(tostring(transfer.vehicleId)))
  end
 end)
 local parking=garage(row.parking_id)
 return true,token,{
  vehicleId=vehicleId,parkingId=tostring(row.parking_id or ''),spotIndex=tonumber(row.spot_index),
  parkingLabel=tostring(parking and parking.label or row.parking_id or 'Public parking'),
 }
end)

exports('CompleteHouseGarageTransfer',function(token,src,characterId)
 if not houseIntegrationCaller() then return false,'resource_not_authorized' end
 token=tostring(token or '')
 src=tonumber(src)
 characterId=tostring(characterId or '')
 local transfer=houseTransfers[token]
 if not transfer or transfer.source~=src or transfer.characterId~=characterId then
  return false,'transfer_not_found'
 end
 local activeCharacter=src and cid(src)
 if not activeCharacter or tostring(activeCharacter)~=characterId then
  return false,'character_mismatch'
 end
 local row=MySQL.single.await([[
  SELECT id,parking_id,spot_index,vehicle_id,price_paid
  FROM cm_parking_spaces
  WHERE id=? AND character_id=? AND vehicle_id=?
  LIMIT 1
 ]],{transfer.rowId,characterId,transfer.vehicleId})
 if not row then return false,'public_parking_assignment_changed' end

 local refund=tonumber(row.price_paid) or Config.Price or 0
 if refund>0 then
  local bankOk,credited=pcall(function()
   return exports['cm-playerdata']:AddBank(src,refund,'parking-space-refund')
  end)
  if not bankOk or credited~=true then return false,'parking_refund_failed' end
 end
 local deleteOk,deleted=pcall(function()
  return MySQL.update.await([[
   DELETE FROM cm_parking_spaces
   WHERE id=? AND character_id=? AND vehicle_id=?
  ]],{transfer.rowId,characterId,transfer.vehicleId})
 end)
 if not deleteOk or not deleted or tonumber(deleted)<=0 then
  if refund>0 then
   local compensationOk,compensated=pcall(function()
    return exports['cm-playerdata']:RemoveBank(src,refund,'parking-space-transfer-rollback')
   end)
   if not compensationOk or compensated~=true then
    print(('[CM-PARKING-V2] Could not reverse parking refund after transfer delete failed for vehicle %s.'):format(tostring(transfer.vehicleId)))
   end
  end
  return false,'public_parking_assignment_changed'
 end

 houseTransfers[token]=nil
 unlockVehicle(transfer.vehicleId,token)
 return true,{refunded=refund,parkingId=tostring(row.parking_id or ''),spotIndex=tonumber(row.spot_index)}
end)

exports('AbortHouseGarageTransfer',function(token,src,characterId)
 if not houseIntegrationCaller() then return false,'resource_not_authorized' end
 token=tostring(token or '')
 src=tonumber(src)
 characterId=tostring(characterId or '')
 local transfer=houseTransfers[token]
 if not transfer or transfer.source~=src or transfer.characterId~=characterId then
  return false,'transfer_not_found'
 end
 houseTransfers[token]=nil
 unlockVehicle(transfer.vehicleId,token)
 return true
end)

CreateThread(function() while true do Wait(60000); releaseExpired() end end)
