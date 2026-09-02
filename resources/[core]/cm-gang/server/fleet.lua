local RESOURCE = GetCurrentResourceName()
local VEHICLES, SHOP = 'cm-vehicles', 'rn-vehicleshop'
local cooldowns, locks, placements, sourceCharacters = {}, {}, {}, {}

local function cid(src)
    src = tonumber(src)
    if not src then return nil end
    local ok, value = pcall(function() return exports['cm-playerdata']:GetCharacterId(src) end)
    value = ok and tostring(value or '') or ''
    local characterId = value:match('^%d+$') and value or nil
    if characterId then sourceCharacters[src] = characterId end
    return characterId
end

local function actor(src, permission)
    local characterId = cid(src)
    local member = characterId and exports[RESOURCE]:GetGangForCharacter(characterId) or nil
    if not member or member.enabled ~= true then return nil, 'not_in_enabled_gang' end
    if not exports[RESOURCE]:HasPermission(characterId, permission) then return nil, 'no_permission' end
    return { source = tonumber(src), characterId = characterId, gangId = member.gangId, tier = tonumber(member.tier) or 0,
        name = member.displayName, leader = member.isLeader == true }
end

local function throttled(characterId, key)
    local now, id = GetGameTimer(), characterId .. ':' .. key
    if (cooldowns[id] or 0) > now then return true end
    cooldowns[id] = now + ((Config.Security.vehicleCooldownSeconds or 3) * 1000)
    return false
end

local function catalog(model)
    model = tostring(model or ''):lower()
    if model == '' or GetResourceState(SHOP) ~= 'started' then return nil end
    local ok, row = pcall(function() return exports[SHOP]:GetCatalogVehicle(model) end)
    if ok and type(row) == 'table' then return row end
    -- Gang-only catalog rows are intentionally hidden from the public shop
    -- export. Read the same authoritative catalog table server-side so this
    -- integration can validate an assigned gang model without exposing it.
    row = MySQL.single.await([[SELECT model,label,image,gang_id FROM cm_vehicle_catalog
        WHERE model=? LIMIT 1]], { model })
    return type(row) == 'table' and row or nil
end

local function row(gangId, model)
    return MySQL.single.await('SELECT * FROM cm_gang_fleet_vehicles WHERE gang_id=? AND catalog_id=? LIMIT 1',
        { gangId, tostring(model or ''):lower() })
end

local function validCoords(settings)
    return tonumber(settings.x) and tonumber(settings.y) and tonumber(settings.z)
end

local function atFleetFacility(src, gangId)
    local facility = MySQL.single.await([[SELECT enabled,x,y,z,routing_bucket FROM cm_gang_facilities
        WHERE gang_id=? AND facility_type='fleet' LIMIT 1]], { gangId })
    if not facility or not CMGangDbTrue(facility.enabled) or not validCoords(facility) then return false end
    if GetPlayerRoutingBucket(src)~=(tonumber(facility.routing_bucket) or 0) then return false end
    local ped=GetPlayerPed(src)
    if not ped or ped==0 then return false end
    local c=GetEntityCoords(ped)
    local dx,dy,dz=c.x-tonumber(facility.x),c.y-tonumber(facility.y),c.z-tonumber(facility.z)
    return math.sqrt(dx*dx+dy*dy+dz*dz) <= (tonumber(Config.Storage.facilityDistance) or 3.0)
end

local function activity(gangId, action, actorCid, vehicleId, detail)
    local uid = ('fleet:%s:%s:%s:%s'):format(gangId, action, actorCid or 'system', lib.string.random('Aa0', 12))
    MySQL.insert.await([[INSERT IGNORE INTO cm_gang_activity
        (event_uid,gang_id,action,actor_character_id,vehicle_id,detail) VALUES (?,?,?,?,?,?)]],
        { uid, gangId, action, actorCid, tonumber(vehicleId), json.encode(detail or {}) })
end

local function adminAllowed(src)
    if GetInvokingResource() ~= 'cm-admin' or GetResourceState('cm-admin') ~= 'started' then return false end
    local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(tonumber(src), 'gang.admin.manage') end)
    return ok and allowed == true
end

local function adminPermission(src)
    if GetResourceState('cm-admin')~='started' then return false end
    local ok,allowed=pcall(function() return exports['cm-admin']:HasPermission(tonumber(src),'gang.admin.manage') end)
    return ok and allowed==true
end

local function entityStatus(vehicleId, settings)
    if GetResourceState(VEHICLES) ~= 'started' then return 'owner_unavailable', nil end
    local called, active, info = pcall(function() return exports[VEHICLES]:GetSpawnedVehicleInfo(vehicleId) end)
    if not called then return 'owner_unavailable', nil end
    if active ~= true or type(info) ~= 'table' then return 'available', nil end
    local entity = tonumber(info.entity)
    if not entity or not DoesEntityExist(entity) then return 'available', info end
    local occupied = GetPedInVehicleSeat(entity, -1) ~= 0
    -- GetVehicleMaxNumberOfPassengers is not available on every FXServer
    -- artifact. Check a bounded set of passenger seats instead of allowing a
    -- fleet-list request to fail when that client-oriented native is absent.
    if not occupied then
        for seat = 0, 31 do
            if GetPedInVehicleSeat(entity, seat) ~= 0 then
                occupied = true
                break
            end
        end
    end
    if not occupied and validCoords(settings) then
        local c = GetEntityCoords(entity)
        local dx, dy, dz = c.x-tonumber(settings.x), c.y-tonumber(settings.y), c.z-tonumber(settings.z)
        if math.sqrt(dx*dx+dy*dy+dz*dz) <= 4.0 then return 'available', info end
    end
    return occupied and 'occupied' or 'deployed', info
end

local TRUNK_ACTIONS = {
    ['vehicle.trunk.open'] = true, ['vehicle.trunk.deposit'] = true, ['vehicle.trunk.withdraw'] = true,
}

exports('GetVehicleAccessDecision', function(characterId, vehicleId, action)
    vehicleId = tonumber(vehicleId)
    local settings = vehicleId and MySQL.single.await([[SELECT gang_id,minimum_tier,trunk_minimum_tier,enabled
        FROM cm_gang_fleet_vehicles WHERE vehicle_id=? LIMIT 1]], { vehicleId }) or nil
    if not settings then return false, 'not_gang_fleet_vehicle' end
    if not CMGangDbTrue(settings.enabled) then return false, 'gang_vehicle_disabled' end
    action = tostring(action or 'vehicle.drive')
    if action == 'vehicle.sell' or action == 'vehicle.delete' or action == 'vehicle.keys.manage'
        or action == 'vehicle.family.share' then return false, 'gang_fleet_protected' end
    local member = exports[RESOURCE]:GetGangForCharacter(tostring(characterId or ''))
    if not member or member.enabled ~= true or member.gangId ~= settings.gang_id then return false, 'not_gang_member' end

    if TRUNK_ACTIONS[action] then
        if not exports[RESOURCE]:HasPermission(tostring(characterId), 'gang.vehicle_trunk') then return false, 'no_gang_trunk_permission' end
        if not member.isLeader and (tonumber(member.tier) or 0) < (tonumber(settings.trunk_minimum_tier) or 1) then
            return false, 'gang_rank_too_low'
        end
        return true, 'gang_fleet', { gangId=settings.gang_id, vehicleId=vehicleId, requiredTier=tonumber(settings.trunk_minimum_tier) or 1 }
    end

    if not exports[RESOURCE]:HasPermission(tostring(characterId), 'gang.vehicle') then return false, 'no_gang_vehicle_permission' end
    if not member.isLeader and (tonumber(member.tier) or 0) < (tonumber(settings.minimum_tier) or 1) then return false, 'gang_rank_too_low' end
    return true, 'gang_fleet', { gangId=settings.gang_id, vehicleId=vehicleId, requiredTier=tonumber(settings.minimum_tier) or 1 }
end)

local function fleetList(src)
    local a, reason = actor(src, 'gang.vehicle')
    if not a then return { ok=false, reason=reason } end
    local rows = MySQL.query.await('SELECT * FROM cm_gang_fleet_vehicles WHERE gang_id=? ORDER BY catalog_id', { a.gangId }) or {}
    local out = {}
    for _, settings in ipairs(rows) do
        local item = catalog(settings.catalog_id)
        local allowed = a.leader or a.tier >= (tonumber(settings.minimum_tier) or 1)
        if item and (exports[RESOURCE]:HasPermission(a.characterId, 'gang.manage_vehicles') or (CMGangDbTrue(settings.enabled) and allowed)) then
            local status = tonumber(settings.vehicle_id) and entityStatus(tonumber(settings.vehicle_id), settings) or 'not_configured'
            out[#out+1] = { model=settings.catalog_id, label=item.label or settings.catalog_id, image=item.image,
                vehicleId=tonumber(settings.vehicle_id), minimumTier=tonumber(settings.minimum_tier) or 1,
                trunkMinimumTier=tonumber(settings.trunk_minimum_tier) or 1,
                enabled=CMGangDbTrue(settings.enabled), configured=validCoords(settings) and tonumber(settings.vehicle_id)~=nil,
                status=status }
        end
    end
    return { ok=true, vehicles=out }
end

lib.callback.register('cm-gang:server:getFleet', fleetList)

exports('AdminGetFleet', function(src, gangId)
    if not adminAllowed(tonumber(src)) or not Config.IsFixedGangId(gangId) then return {ok=false,error='permission_denied'} end
    local rows=MySQL.query.await('SELECT * FROM cm_gang_fleet_vehicles WHERE gang_id=? ORDER BY catalog_id',{gangId}) or {}
    local out={}
    for _,settings in ipairs(rows) do local item=catalog(settings.catalog_id); if item then out[#out+1]={model=settings.catalog_id,label=item.label or settings.catalog_id,
      vehicleId=tonumber(settings.vehicle_id),minimumTier=tonumber(settings.minimum_tier) or 1,enabled=CMGangDbTrue(settings.enabled),
      configured=validCoords(settings) and tonumber(settings.vehicle_id)~=nil,status=tonumber(settings.vehicle_id) and entityStatus(tonumber(settings.vehicle_id),settings) or 'not_configured'} end end
    return {ok=true,vehicles=out}
end)

exports('AdminResetFleetLocation', function(src, gangId, model)
    if not adminAllowed(tonumber(src)) or not Config.IsFixedGangId(gangId) then return false,'permission_denied' end
    model=tostring(model or ''):lower()
    local settings=row(gangId,model); if not settings then return false,'vehicle_not_configured' end
    local lock=gangId..':'..model
    if locks[lock] then return false,'operation_busy' end
    locks[lock]=true
    local ok, success, reason = xpcall(function()
        settings=row(gangId,model); if not settings then return false,'vehicle_not_configured' end
        local adminCid=cid(src); if not adminCid then return false,'character_not_loaded' end
        MySQL.update.await('UPDATE cm_gang_fleet_vehicles SET enabled=0,x=NULL,y=NULL,z=NULL,heading=NULL,routing_bucket=0,updated_by=? WHERE gang_id=? AND catalog_id=?',
          {adminCid,gangId,model})
        activity(gangId,'vehicle_location_reset',adminCid,tonumber(settings.vehicle_id),{model=settings.catalog_id})
        return true,'Fleet location reset; persistent vehicle retained.'
    end, debug.traceback)
    locks[lock]=nil
    if not ok then print(('[cm-gang] fleet location reset failed: %s'):format(tostring(success))); return false,'internal_error' end
    return success,reason
end)

exports('AdminDeleteFleetVehicle', function(src, gangId, model)
    src, model = tonumber(src), tostring(model or ''):lower()
    if not adminAllowed(src) or not Config.IsFixedGangId(gangId) then return false, 'permission_denied' end
    local settings=row(gangId,model)
    local vehicleId=settings and tonumber(settings.vehicle_id)
    if not settings or not vehicleId then return false,'persistent_vehicle_missing' end
    if GetResourceState(VEHICLES)~='started' then return false,'vehicle_owner_unavailable' end
    local lock=gangId..':'..model
    if locks[lock] then return false,'operation_busy' end
    locks[lock]=true
    local ok,success,reason=xpcall(function()
        local adminCid=cid(src)
        if not adminCid then return false,'character_not_loaded' end
        local deleted,deleteReason=exports[VEHICLES]:DeleteOrganizationVehicle({
            actorSource=src,organizationId=gangId,vehicleId=vehicleId
        })
        if deleted~=true then return false,tostring(deleteReason or 'persistent_delete_failed') end
        local changed=MySQL.update.await('DELETE FROM cm_gang_fleet_vehicles WHERE gang_id=? AND catalog_id=? AND vehicle_id=?',
            {gangId,model,vehicleId})
        if tonumber(changed)~=1 then return false,'fleet_assignment_delete_failed' end
        activity(gangId,'organization_vehicle_deleted',adminCid,vehicleId,{model=model})
        return true,'Gang vehicle deleted.'
    end,debug.traceback)
    locks[lock]=nil
    if not ok then print(('[cm-gang] fleet vehicle deletion failed: %s'):format(tostring(success))); return false,'internal_error' end
    return success,reason
end)

lib.callback.register('cm-gang:server:callFleetVehicle', function(src, model)
    local a, reason = actor(src, 'gang.vehicle')
    if not a then return { ok=false, reason=reason } end
    if GetResourceState(VEHICLES) ~= 'started' then return { ok=false, reason='vehicle_owner_unavailable' } end
    if not atFleetFacility(src, a.gangId) then return { ok=false, reason='not_at_fleet_facility' } end
    if throttled(a.characterId, 'call') then return { ok=false, reason='rate_limited' } end
    local settings = row(a.gangId, model)
    if not settings or not CMGangDbTrue(settings.enabled) or not tonumber(settings.vehicle_id) or not validCoords(settings) then return { ok=false, reason='vehicle_unavailable' } end
    if not a.leader and a.tier < (tonumber(settings.minimum_tier) or 1) then return { ok=false, reason='rank_too_low' } end
    local lock = a.gangId .. ':' .. tostring(settings.catalog_id)
    if locks[lock] then return { ok=false, reason='operation_busy' } end
    locks[lock] = true
    local called, success, response = pcall(function()
        local current, currentReason = actor(src, 'gang.vehicle')
        if not current or current.gangId ~= a.gangId or current.characterId ~= a.characterId then return false, currentReason or 'membership_changed' end
        if not atFleetFacility(src, current.gangId) then return false, 'not_at_fleet_facility' end
        local currentSettings = row(current.gangId, settings.catalog_id)
        if not currentSettings or not CMGangDbTrue(currentSettings.enabled) or not tonumber(currentSettings.vehicle_id) or not validCoords(currentSettings) then
            return false, 'vehicle_unavailable'
        end
        if not current.leader and current.tier < (tonumber(currentSettings.minimum_tier) or 1) then return false, 'rank_too_low' end
        a, settings = current, currentSettings
        local vehicleId = tonumber(settings.vehicle_id)
        if exports[VEHICLES]:EnsureOrganizationOwnership(vehicleId, a.gangId) ~= true then return false, 'ownership_failed' end
        local spawn = { x=tonumber(settings.x), y=tonumber(settings.y), z=tonumber(settings.z), h=tonumber(settings.heading) or 0 }
        local active = exports[VEHICLES]:GetSpawnedVehicleInfo(vehicleId)
        local status = entityStatus(vehicleId, settings)
        if status == 'occupied' then return false, 'vehicle_occupied' end
        local success, response
        if active == true then
            success, response = exports[VEHICLES]:RecallWorldVehicle(vehicleId, src, spawn)
        else
            local vehicle = exports[VEHICLES]:GetVehicleById(vehicleId)
            if not vehicle then return false, 'persistent_vehicle_missing' end
            local created, createdResult = exports[VEHICLES]:CreateGarageVehicle(src, vehicle, spawn, { bucket=tonumber(settings.routing_bucket) or 0 })
            if created == true then success, response = exports[VEHICLES]:PromoteHouseGarageVehicle(vehicleId, src, spawn)
            else success, response = false, createdResult end
        end
        if success ~= true then return false, tostring(response or 'spawn_failed') end
        local vehicle = exports[VEHICLES]:GetVehicleById(vehicleId)
        if vehicle and GetResourceState('cm-vehiclekeys') == 'started' then
            local keyCalled, granted = pcall(function()
                return exports['cm-vehiclekeys']:GrantOrganizationKey(src, vehicle.plate, {
                    vehicleId=vehicleId, organizationId=a.gangId, ownerResource=RESOURCE, action='vehicle.drive'
                })
            end)
            if not keyCalled or granted ~= true then
                -- Best-effort rollback: do not strand a spawned gang vehicle
                -- in the world after reporting that the call failed.
                pcall(function() exports[VEHICLES]:RecallWorldVehicle(vehicleId, src, spawn) end)
                return false, 'key_grant_failed'
            end
        end
        local transitioned = exports[VEHICLES]:TransitionVehicleLocation(vehicleId, 'JOB_GARAGE', { ref=a.gangId, reason='gang_vehicle_called', actorCharacterId=a.characterId })
        if transitioned == false then
            pcall(function() exports[VEHICLES]:RecallWorldVehicle(vehicleId, src, spawn) end)
            return false, 'vehicle_location_transition_failed'
        end
        activity(a.gangId, 'vehicle_called', a.characterId, vehicleId, { model=settings.catalog_id })
        return true, 'vehicle_called'
    end)
    locks[lock] = nil
    if not called then return { ok=false, reason='vehicle_owner_error' } end
    return { ok=success==true, reason=response }
end)

lib.callback.register('cm-gang:server:returnFleetVehicle', function(src, model)
    local a, reason = actor(src, 'gang.vehicle')
    if not a then return { ok=false, reason=reason } end
    if GetResourceState(VEHICLES) ~= 'started' then return { ok=false, reason='vehicle_owner_unavailable' } end
    if throttled(a.characterId, 'return') then return { ok=false, reason='rate_limited' } end
    local settings = row(a.gangId, model)
    if not settings or not tonumber(settings.vehicle_id) or not validCoords(settings) then return { ok=false, reason='vehicle_unavailable' } end
    local vehicleId = tonumber(settings.vehicle_id)
    local drivingCalled, isDriving = pcall(function() return exports[VEHICLES]:IsPlayerDrivingSpawnedVehicle(src, vehicleId) end)
    if not drivingCalled then return { ok=false, reason='vehicle_owner_unavailable' } end
    if isDriving ~= true then return { ok=false, reason='not_driving_vehicle' } end
    local ped, entity = GetPlayerPed(src), GetVehiclePedIsIn(GetPlayerPed(src), false)
    if ped==0 or entity==0 then return { ok=false, reason='vehicle_missing' } end
    local c = GetEntityCoords(entity)
    local dx,dy,dz=c.x-tonumber(settings.x),c.y-tonumber(settings.y),c.z-tonumber(settings.z)
    if math.sqrt(dx*dx+dy*dy+dz*dz)>8.0 or GetPlayerRoutingBucket(src)~=(tonumber(settings.routing_bucket) or 0) then return { ok=false, reason='wrong_return_location' } end
    local lock = a.gangId .. ':' .. tostring(settings.catalog_id)
    if locks[lock] then return { ok=false, reason='operation_busy' } end
    locks[lock] = true
    local completed, success, response = pcall(function()
        local current, currentReason = actor(src, 'gang.vehicle')
        if not current or current.characterId ~= a.characterId or current.gangId ~= a.gangId then return false, currentReason or 'membership_changed' end
        local currentSettings = row(current.gangId, settings.catalog_id)
        if not currentSettings or not tonumber(currentSettings.vehicle_id) or tonumber(currentSettings.vehicle_id) ~= vehicleId or not validCoords(currentSettings) then
            return false, 'vehicle_unavailable'
        end
        local stillDriving = exports[VEHICLES]:IsPlayerDrivingSpawnedVehicle(src, vehicleId)
        if stillDriving ~= true then return false, 'not_driving_vehicle' end
        local currentPed, currentEntity = GetPlayerPed(src), GetVehiclePedIsIn(GetPlayerPed(src), false)
        if currentPed == 0 or currentEntity == 0 then return false, 'vehicle_missing' end
        local currentCoords = GetEntityCoords(currentEntity)
        local rdx,rdy,rdz=currentCoords.x-tonumber(currentSettings.x),currentCoords.y-tonumber(currentSettings.y),currentCoords.z-tonumber(currentSettings.z)
        if math.sqrt(rdx*rdx+rdy*rdy+rdz*rdz)>8.0 or GetPlayerRoutingBucket(src)~=(tonumber(currentSettings.routing_bucket) or 0) then
            return false, 'wrong_return_location'
        end
        a, settings = current, currentSettings
        local recalled, recallReason = exports[VEHICLES]:RecallWorldVehicle(vehicleId, src, {
            x=tonumber(settings.x), y=tonumber(settings.y), z=tonumber(settings.z), h=tonumber(settings.heading) or 0
        })
        if recalled ~= true then return false, tostring(recallReason or 'return_failed') end
        if GetResourceState('cm-vehiclekeys') == 'started' then
            pcall(function() exports['cm-vehiclekeys']:RevokeOrganizationKeys({ vehicleId=vehicleId, organizationId=a.gangId }) end)
        end
        local transitioned = exports[VEHICLES]:TransitionVehicleLocation(vehicleId, 'JOB_GARAGE', {
            ref=a.gangId, reason='gang_vehicle_returned', actorCharacterId=a.characterId
        })
        if transitioned == false then return false, 'vehicle_location_transition_failed' end
        activity(a.gangId, 'vehicle_returned', a.characterId, vehicleId, { model=settings.catalog_id })
        return true
    end)
    locks[lock] = nil
    if not completed then return { ok=false, reason='vehicle_owner_error' } end
    return { ok=success==true, reason=response }
end)

-- Recall: unlike Call (bring to me, preserve condition) and Return (drive
-- it back, preserve condition), Recall always forces the vehicle back to
-- its fixed home location AND restores it to full condition. It refuses an
-- occupied vehicle rather than forcibly evicting anyone from it -- the same
-- conservative rule Call/Return already apply through entityStatus().
lib.callback.register('cm-gang:server:recallFleetVehicle', function(src, model)
    local a, reason = actor(src, 'gang.vehicle')
    if not a then return { ok=false, reason=reason } end
    if GetResourceState(VEHICLES) ~= 'started' then return { ok=false, reason='vehicle_owner_unavailable' } end
    if throttled(a.characterId, 'recall') then return { ok=false, reason='rate_limited' } end
    local settings = row(a.gangId, model)
    if not settings or not CMGangDbTrue(settings.enabled) or not tonumber(settings.vehicle_id) or not validCoords(settings) then return { ok=false, reason='vehicle_unavailable' } end
    if not a.leader and a.tier < (tonumber(settings.minimum_tier) or 1) then return { ok=false, reason='rank_too_low' } end
    local lock = a.gangId .. ':' .. tostring(settings.catalog_id)
    if locks[lock] then return { ok=false, reason='operation_busy' } end
    locks[lock] = true
    local called, success, response = pcall(function()
        local current, currentReason = actor(src, 'gang.vehicle')
        if not current or current.gangId ~= a.gangId or current.characterId ~= a.characterId then return false, currentReason or 'membership_changed' end
        local currentSettings = row(current.gangId, settings.catalog_id)
        if not currentSettings or not CMGangDbTrue(currentSettings.enabled) or not tonumber(currentSettings.vehicle_id) or not validCoords(currentSettings) then
            return false, 'vehicle_unavailable'
        end
        if not current.leader and current.tier < (tonumber(currentSettings.minimum_tier) or 1) then return false, 'rank_too_low' end
        a, settings = current, currentSettings
        local vehicleId = tonumber(settings.vehicle_id)
        if exports[VEHICLES]:EnsureOrganizationOwnership(vehicleId, a.gangId) ~= true then return false, 'ownership_failed' end
        local spawn = { x=tonumber(settings.x), y=tonumber(settings.y), z=tonumber(settings.z), h=tonumber(settings.heading) or 0 }
        local status = entityStatus(vehicleId, settings)
        if status == 'occupied' then return false, 'vehicle_occupied' end
        local active = exports[VEHICLES]:GetSpawnedVehicleInfo(vehicleId)
        local recallSuccess, recallResponse
        if active == true then
            recallSuccess, recallResponse = exports[VEHICLES]:RecallWorldVehicle(vehicleId, src, spawn)
        else
            local vehicle = exports[VEHICLES]:GetVehicleById(vehicleId)
            if not vehicle then return false, 'persistent_vehicle_missing' end
            local created, createdResult = exports[VEHICLES]:CreateGarageVehicle(src, vehicle, spawn, { bucket=tonumber(settings.routing_bucket) or 0 })
            if created == true then recallSuccess, recallResponse = exports[VEHICLES]:PromoteHouseGarageVehicle(vehicleId, src, spawn)
            else recallSuccess, recallResponse = false, createdResult end
        end
        if recallSuccess ~= true then return false, tostring(recallResponse or 'recall_failed') end
        -- Full restore only after the vehicle is confirmed home -- never
        -- silently skip the repair on a partial failure above.
        local vehicle = exports[VEHICLES]:GetVehicleById(vehicleId)
        local plate = vehicle and vehicle.plate
        if plate then
            local repairCalled, repairOk = pcall(function()
                return exports[VEHICLES]:ServiceVehicle(plate, {
                    engineHealth = 1000.0, bodyHealth = 1000.0, tankHealth = 1000.0,
                    fuel = 100, clearVisualDamage = true,
                }, -1)
            end)
            if not repairCalled or repairOk == false then
                print(('[cm-gang] recall repair failed for plate %s'):format(tostring(plate)))
            end
        end
        activity(a.gangId, 'vehicle_recalled', a.characterId, vehicleId, { model=settings.catalog_id })
        return true, 'vehicle_recalled'
    end)
    locks[lock] = nil
    if not called then return { ok=false, reason='vehicle_owner_error' } end
    return { ok=success==true, reason=response }
end)

lib.callback.register('cm-gang:server:recallAllFreeFleetVehicles', function(src)
    local a, reason = actor(src, 'gang.manage_vehicles')
    if not a then return { ok=false, reason=reason } end
    if GetResourceState(VEHICLES) ~= 'started' then return { ok=false, reason='vehicle_owner_unavailable' } end
    if throttled(a.characterId, 'recall_all') then return { ok=false, reason='rate_limited' } end
    local rows = MySQL.query.await([[SELECT * FROM cm_gang_fleet_vehicles
        WHERE gang_id=? AND enabled=1 AND vehicle_id IS NOT NULL
          AND x IS NOT NULL AND y IS NOT NULL AND z IS NOT NULL ORDER BY catalog_id]], { a.gangId }) or {}
    local recalled, skippedOccupied, alreadyHome, failed = 0, 0, 0, 0
    for _, settings in ipairs(rows) do
        local model, vehicleId = tostring(settings.catalog_id or ''):lower(), tonumber(settings.vehicle_id)
        local lock, status = a.gangId .. ':' .. tostring(settings.catalog_id), entityStatus(vehicleId, settings)
        if status == 'occupied' then skippedOccupied = skippedOccupied + 1
        elseif status == 'available' then alreadyHome = alreadyHome + 1
        elseif locks[lock] then failed = failed + 1
        else
            locks[lock] = true
            local ok, success = pcall(function()
                local current = actor(src, 'gang.manage_vehicles')
                local latest = row(a.gangId, model)
                if not current or current.characterId ~= a.characterId or current.gangId ~= a.gangId
                    or not latest or not CMGangDbTrue(latest.enabled) or tonumber(latest.vehicle_id) ~= vehicleId
                    or not validCoords(latest) or entityStatus(vehicleId, latest) == 'occupied' then return false end
                if exports[VEHICLES]:EnsureOrganizationOwnership(vehicleId, a.gangId) ~= true then return false end
                local recalledOk = exports[VEHICLES]:RecallWorldVehicle(vehicleId, src, {
                    x=tonumber(latest.x), y=tonumber(latest.y), z=tonumber(latest.z), h=tonumber(latest.heading) or 0
                })
                if recalledOk ~= true then return false end
                if GetResourceState('cm-vehiclekeys') == 'started' then
                    pcall(function() exports['cm-vehiclekeys']:RevokeOrganizationKeys({ vehicleId=vehicleId, organizationId=a.gangId }) end)
                end
                return exports[VEHICLES]:TransitionVehicleLocation(vehicleId, 'JOB_GARAGE', {
                    ref=a.gangId, reason='gang_fleet_recall_all', actorCharacterId=a.characterId
                }) ~= false
            end)
            locks[lock] = nil
            if ok and success == true then recalled = recalled + 1 else failed = failed + 1 end
        end
    end
    activity(a.gangId, 'fleet_recalled_all', a.characterId, nil, {
        recalled=recalled, skippedOccupied=skippedOccupied, alreadyHome=alreadyHome, failed=failed
    })
    return { ok=true, recalled=recalled, skippedOccupied=skippedOccupied, alreadyHome=alreadyHome, failed=failed }
end)

lib.callback.register('cm-gang:server:configureFleetVehicleRank', function(src, data)
    data = type(data) == 'table' and data or {}
    local a, reason = actor(src, 'gang.manage_vehicles')
    if not a then return { ok=false, reason=reason } end
    local model, minimumTier = tostring(data.model or ''):lower(), tonumber(data.minimumTier)
    if model == '' or not minimumTier or minimumTier % 1 ~= 0 then return { ok=false, reason='invalid_rank' } end
    local rank = MySQL.single.await('SELECT id,tier,name FROM cm_gang_ranks WHERE gang_id=? AND tier=? LIMIT 1',
        { a.gangId, minimumTier })
    if not rank then return { ok=false, reason='rank_not_available' } end
    local settings = row(a.gangId, model)
    if not settings or not tonumber(settings.vehicle_id) then return { ok=false, reason='vehicle_unavailable' } end
    local lock = a.gangId .. ':' .. model
    if locks[lock] then return { ok=false, reason='operation_busy' } end
    locks[lock] = true
    local ok, success, result = xpcall(function()
        local current = actor(src, 'gang.manage_vehicles')
        if not current or current.characterId ~= a.characterId or current.gangId ~= a.gangId then
            return false, 'membership_changed'
        end
        local currentRank = MySQL.single.await('SELECT tier,name FROM cm_gang_ranks WHERE gang_id=? AND tier=? LIMIT 1',
            { current.gangId, minimumTier })
        if not currentRank then return false, 'rank_not_available' end
        if tonumber(settings.minimum_tier) == minimumTier then
            return true, { minimumTier=minimumTier, rankName=tostring(currentRank.name or '') }
        end
        local changed = MySQL.update.await([[UPDATE cm_gang_fleet_vehicles SET minimum_tier=?,updated_by=?
            WHERE gang_id=? AND catalog_id=? AND vehicle_id IS NOT NULL]],
            { minimumTier, current.characterId, current.gangId, model })
        if tonumber(changed) ~= 1 then return false, 'vehicle_rank_update_failed' end
        activity(current.gangId, 'vehicle_access_rank_updated', current.characterId, tonumber(settings.vehicle_id),
            { model=model, minimumTier=minimumTier, rankName=tostring(currentRank.name or '') })
        return true, { minimumTier=minimumTier, rankName=tostring(currentRank.name or '') }
    end, debug.traceback)
    locks[lock] = nil
    if not ok then print(('[cm-gang] vehicle rank update failed: %s'):format(tostring(success))); return {ok=false,reason='internal_error'} end
    return { ok=success==true, reason=success==true and nil or result, data=success==true and result or nil }
end)

exports('AdminConfigureFleetVehicle', function(src, gangId, data)
    src, data = tonumber(src), type(data)=='table' and data or {}
    if not adminAllowed(src) then return false, 'permission_denied' end
    local model=tostring(data.model or ''):lower()
    if not Config.IsFixedGangId(gangId) or not catalog(model) then return false, 'invalid_vehicle' end
    local lock=gangId..':'..model
    if locks[lock] then return false,'operation_busy' end
    locks[lock]=true
    local ok, success, reason = xpcall(function()
        local adminCid=cid(src)
        if not adminCid then return false, 'character_not_loaded' end
        local existing = row(gangId, model)
        if not existing or not tonumber(existing.vehicle_id) or not validCoords(existing) then return false, 'set_location_first' end
        MySQL.update.await('UPDATE cm_gang_fleet_vehicles SET enabled=?,updated_by=? WHERE gang_id=? AND catalog_id=?',
            { data.enabled==true and 1 or 0, adminCid, gangId, model })
        return true,'fleet_vehicle_saved'
    end, debug.traceback)
    locks[lock]=nil
    if not ok then print(('[cm-gang] fleet configuration failed: %s'):format(tostring(success))); return false,'internal_error' end
    return success,reason
end)

exports('AssignCatalogVehicle',function(src,model,gangId)
    if GetInvokingResource()~='rn-vehicleshop' then return false,'untrusted_resource' end
    src,model=tonumber(src),tostring(model or ''):lower()
    -- The invoking resource is deliberately rn-vehicleshop, so adminAllowed()
    -- (which only trusts calls originating from cm-admin) can never succeed here.
    -- Keep the resource boundary above and validate the initiating player directly.
    if not adminPermission(src) or not catalog(model) then return false,'permission_denied' end
    MySQL.update.await('DELETE FROM cm_gang_fleet_vehicles WHERE catalog_id=? AND vehicle_id IS NULL',{model})
    if gangId==nil or gangId=='' then return true end
    if not Config.IsFixedGangId(gangId) then return false,'invalid_gang' end
    MySQL.insert.await([[INSERT IGNORE INTO cm_gang_fleet_vehicles(gang_id,catalog_id,minimum_tier,trunk_minimum_tier,enabled,updated_by) VALUES(?,?,1,1,0,?)]],{gangId,model,cid(src)})
    return true
end)

exports('LinkGrantedOrganizationVehicle', function(src, gangId, model, vehicleId, minimumTier, trunkMinimumTier)
    src, model, vehicleId = tonumber(src), tostring(model or ''):lower(), tonumber(vehicleId)
    minimumTier=math.max(1,math.min(100,math.floor(tonumber(minimumTier) or 1)))
    trunkMinimumTier=math.max(1,math.min(100,math.floor(tonumber(trunkMinimumTier) or minimumTier)))
    if not adminPermission(src) or not Config.IsFixedGangId(gangId) or not vehicleId or not catalog(model) then
        return false, 'permission_or_request_invalid'
    end
    if GetResourceState(VEHICLES) ~= 'started' then return false, 'vehicle_owner_unavailable' end
    local vehicle = exports[VEHICLES]:GetVehicleById(vehicleId)
    if not vehicle or tostring(vehicle.owner_type) ~= 'organization' or tostring(vehicle.owner_id) ~= gangId
        or tostring(vehicle.model):lower() ~= model then return false, 'vehicle_ownership_mismatch' end
    local lock = gangId..':'..model
    if locks[lock] then return false, 'operation_busy' end
    locks[lock] = true
    local ok, success, result = xpcall(function()
        local existing = row(gangId, model)
        if existing and tonumber(existing.vehicle_id) then return false, 'fleet_entry_already_has_vehicle' end
        local actorCharacterId = cid(src)
        local changed
        if existing then
            changed = MySQL.update.await([[UPDATE cm_gang_fleet_vehicles SET vehicle_id=?,minimum_tier=?,trunk_minimum_tier=?,enabled=0,
                x=NULL,y=NULL,z=NULL,heading=NULL,routing_bucket=0,updated_by=?
                WHERE gang_id=? AND catalog_id=? AND vehicle_id IS NULL]],
                {vehicleId,minimumTier,trunkMinimumTier,actorCharacterId,gangId,model})
        else
            changed = MySQL.insert.await([[INSERT INTO cm_gang_fleet_vehicles
                (gang_id,catalog_id,vehicle_id,minimum_tier,trunk_minimum_tier,enabled,updated_by)
                VALUES (?,?,?,?,?,0,?)]], {gangId,model,vehicleId,minimumTier,trunkMinimumTier,actorCharacterId})
        end
        if not tonumber(changed) or tonumber(changed) < 1 then return false, 'fleet_link_failed' end
        activity(gangId,'organization_vehicle_linked',actorCharacterId,vehicleId,{model=model,status='needs_home_location'})
        return true, {vehicleId=vehicleId,status='needs_home_location'}
    end, debug.traceback)
    locks[lock] = nil
    if not ok then print(('[cm-gang] granted vehicle fleet link failed: %s'):format(tostring(success))); return false,'internal_error' end
    return success,result
end)

-- Recover assignments saved while the catalog bridge was rejecting every
-- rn-vehicleshop call. This only creates disabled, unconfigured fleet rows;
-- an admin must still choose the authoritative persistent vehicle spawn.
MySQL.ready(function()
    CreateThread(function()
        local assigned = MySQL.query.await([[SELECT model,gang_id FROM cm_vehicle_catalog
            WHERE gang_id IS NOT NULL AND gang_id<>'' ORDER BY model]]) or {}
        local recovered = 0
        for _, vehicle in ipairs(assigned) do
            local model, gangId = tostring(vehicle.model or ''):lower(), tostring(vehicle.gang_id or '')
            if model ~= '' and Config.IsFixedGangId(gangId) then
                local inserted = MySQL.insert.await([[INSERT IGNORE INTO cm_gang_fleet_vehicles
                    (gang_id,catalog_id,minimum_tier,trunk_minimum_tier,enabled,updated_by)
                    VALUES(?,?,1,1,0,NULL)]], { gangId, model })
                if tonumber(inserted) and tonumber(inserted) > 0 then recovered = recovered + 1 end
            end
        end
        if recovered > 0 then
            print(('[cm-gang] recovered %d gang vehicle catalog assignment(s); set their spawn locations in Gang Admin'):format(recovered))
        end
    end)
end)

local function placementActor(src, gangId)
    local session=placements[tonumber(src)]
    local allowed=adminAllowed(src) or (session and session.gangId==gangId and adminPermission(src))
    if not allowed or not Config.IsFixedGangId(gangId) then return nil end
    local characterId=cid(src)
    if not characterId then return nil end
    local gang=exports[RESOURCE]:GetGang(gangId)
    return gang and {source=src,characterId=characterId,gangId=gangId,name=gang.displayName} or nil
end

local function beginFleetPlacement(src, gangId, model)
    src, model = tonumber(src), tostring(model or ''):lower()
    if GetResourceState(VEHICLES) ~= 'started' then return false, 'vehicle_owner_unavailable' end
    local a = placementActor(src, gangId)
    if not a then return false, 'permission_denied' end
    local item = catalog(model)
    if not item then return false, 'invalid_vehicle' end
    local settings = row(gangId, model)
    if not settings or not tonumber(settings.vehicle_id) then return false, 'give_vehicle_from_vehicle_admin_first' end
    if throttled(a.characterId, 'placement') then return false, 'rate_limited' end
    local old = placements[src]
    placements[src] = nil
    if old then pcall(function() exports[VEHICLES]:DeleteAdminVehicle(old.plate) end) end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'character_not_loaded' end
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local rad = math.rad(h)
    local spawnCalled, result = pcall(function()
        return exports[VEHICLES]:SpawnAdminVehicle(src, model,
            { x=c.x-math.sin(rad)*3.5, y=c.y+math.cos(rad)*3.5, z=c.z+0.25, h=h },
            {
                access='owner', label=('Gang fleet placement: %s'):format(item.label or model),
                engineOn=true, warp=true, placementKind='car'
            })
    end)
    if not spawnCalled then return false, 'vehicle_owner_unavailable' end
    if type(result)~='table' or result.ok~=true then return false, tostring(result and result.error or 'placement_failed') end
    placements[src] = { gangId=gangId, model=model, plate=result.plate, entity=tonumber(result.entity),
        expiresAt=os.time()+300, characterId=a.characterId }
    TriggerClientEvent('cm-admin:client:forceClose',src)
    SetTimeout(750,function()
        local active=placements[src]
        if active and active.model==model then
            TriggerClientEvent('cm-admin:client:gangFleetPlacement',src,{
                model=model,netId=tonumber(result.netId),expiresAt=active.expiresAt
            })
        end
    end)
    return true, { netId=result.netId, model=model, expiresAt=placements[src].expiresAt }
end
exports('BeginFleetPlacement', beginFleetPlacement)

exports('AdminBeginFleetPlacement', function(src, gangId, model)
    return beginFleetPlacement(src, gangId, model)
end)

exports('CancelFleetPlacement', function(src)
    src = tonumber(src)
    local p = placements[src]
    placements[src] = nil
    if p then pcall(function() exports[VEHICLES]:DeleteAdminVehicle(p.plate) end) end
    return p ~= nil
end)

RegisterNetEvent('cm-gang:server:cancelFleetPlacement',function()
    exports[RESOURCE]:CancelFleetPlacement(tonumber(source))
end)

exports('ConfirmFleetPlacement', function(src)
    src = tonumber(src)
    if GetResourceState(VEHICLES) ~= 'started' then return false, 'vehicle_owner_unavailable' end
    local p = placements[src]
    if not p then return false, 'placement_missing_or_expired' end
    if os.time() >= p.expiresAt then
        placements[src] = nil
        pcall(function() exports[VEHICLES]:DeleteAdminVehicle(p.plate) end)
        return false, 'placement_missing_or_expired'
    end
    local a = placementActor(src, p.gangId)
    local ped, entity = GetPlayerPed(src), tonumber(p.entity)
    if not a or not entity or not DoesEntityExist(entity) or GetVehiclePedIsIn(ped,false) ~= entity
        or GetPedInVehicleSeat(entity,-1) ~= ped then return false, 'drive_the_placement_vehicle' end
    if GetEntityModel(entity) ~= GetHashKey(p.model) then return false, 'placement_entity_mismatch' end
    local lock = p.gangId .. ':' .. p.model
    if locks[lock] then return false, 'operation_busy' end
    locks[lock] = true

    local ok, success, result = xpcall(function()
        -- Revalidate the placement session after the lock is acquired.
        local current = placements[src]
        if current ~= p or os.time() >= p.expiresAt then return false, 'placement_missing_or_expired' end
        a = placementActor(src, p.gangId)
        if not a then return false, 'permission_denied' end
        local currentPed = GetPlayerPed(src)
        if currentPed == 0 or not DoesEntityExist(entity) or GetVehiclePedIsIn(currentPed, false) ~= entity
            or GetPedInVehicleSeat(entity, -1) ~= currentPed then return false, 'drive_the_placement_vehicle' end

        local settings = row(p.gangId, p.model)
        local vehicleId = settings and tonumber(settings.vehicle_id) or nil
        if not vehicleId then return false, 'give_vehicle_from_vehicle_admin_first' end
        if exports[VEHICLES]:EnsureOrganizationOwnership(vehicleId,p.gangId)~=true then
            return false, 'ownership_failed'
        end
        local c,h=GetEntityCoords(entity),GetEntityHeading(entity)
        local saved = MySQL.insert.await([[INSERT INTO cm_gang_fleet_vehicles
            (gang_id,catalog_id,vehicle_id,minimum_tier,enabled,x,y,z,heading,routing_bucket,updated_by)
            VALUES (?,?,?,1,1,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE vehicle_id=VALUES(vehicle_id),
            x=VALUES(x),y=VALUES(y),z=VALUES(z),heading=VALUES(heading),routing_bucket=VALUES(routing_bucket),updated_by=VALUES(updated_by)]],
            {p.gangId,p.model,vehicleId,c.x,c.y,c.z,h,GetPlayerRoutingBucket(src),a.characterId})
        if not saved then return false, 'fleet_location_save_failed' end
        local transitioned = exports[VEHICLES]:TransitionVehicleLocation(vehicleId,'JOB_GARAGE',
            {ref=p.gangId,reason='gang_fleet_location_saved',actorCharacterId=a.characterId})
        if transitioned == false then return false, 'vehicle_location_transition_failed' end
        activity(p.gangId,'vehicle_location_saved',a.characterId,vehicleId,{model=p.model})
        return true, {vehicleId=vehicleId}
    end, debug.traceback)

    locks[lock] = nil
    if not ok then
        print(('[cm-gang] fleet placement confirmation failed: %s'):format(tostring(success)))
        return false, 'placement_internal_error'
    end
    if success ~= true then return false, result end

    placements[src] = nil
    pcall(function() exports[VEHICLES]:DeleteAdminVehicle(p.plate) end)
    return true, result
end)

RegisterNetEvent('cm-gang:server:confirmFleetPlacement',function()
    local src=tonumber(source)
    local ok,result=exports[RESOURCE]:ConfirmFleetPlacement(src)
    TriggerClientEvent('cm-gang:client:fleetPlacementResult',src,ok==true,result)
end)

RegisterNetEvent('cm-gang:server:fleetPlacementReady',function(model)
    local src=tonumber(source)
    local p=placements[src]
    if p and p.model==tostring(model or ''):lower() then
        print(('[cm-gang] fleet placement client ready src=%d gang=%s model=%s'):format(src,p.gangId,p.model))
    end
end)

AddEventHandler('cm-playerdata:server:characterLoaded', function(src, data)
    local characterId = data and tostring(data.charId or data.characterId or '') or ''
    if characterId:match('^%d+$') then sourceCharacters[tonumber(src)] = characterId end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    local p = placements[src]
    placements[src]=nil
    if p then pcall(function() exports[VEHICLES]:DeleteAdminVehicle(p.plate) end) end
    local characterId = sourceCharacters[src]
    sourceCharacters[src] = nil
    if characterId then
        local prefix = characterId .. ':'
        for key in pairs(cooldowns) do if key:sub(1, #prefix) == prefix then cooldowns[key] = nil end end
    end
end)
AddEventHandler('onResourceStop', function(name)
    if name~=RESOURCE then return end
    for _,p in pairs(placements) do pcall(function() exports[VEHICLES]:DeleteAdminVehicle(p.plate) end) end
    if GetResourceState('cm-vehiclekeys') == 'started' then
        pcall(function() exports['cm-vehiclekeys']:RevokeOrganizationKeys({ ownerResource=RESOURCE }) end)
    end
    cooldowns,locks,placements,sourceCharacters={},{},{},{}
end)

CreateThread(function()
    while true do
        Wait(30000)
        for src,p in pairs(placements) do
            if os.time() >= p.expiresAt then
                placements[src]=nil
                pcall(function() exports[VEHICLES]:DeleteAdminVehicle(p.plate) end)
            end
        end
    end
end)
