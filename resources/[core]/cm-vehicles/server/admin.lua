--- ═══════════════════════════════════════════════════════════════════════
---  cm-vehicles | server/admin.lua
---  ADMIN & TEMPORARY VEHICLES
---
---  The gap this fills:
---    Every access check in cm-vehicles resolves a plate to a row in
---    cm_owned_vehicles. A car with no row is therefore undrivable --
---    "Vehicle not found." That is correct for a stolen NPC car, but wrong for
---    a car an admin deliberately spawned: a test vehicle, a prop for an event,
---    a placement marker.
---
---  So: a REGISTRY of vehicles that exist in the world but not in anyone's
---  garage. They are real, drivable, and disappear when the server restarts.
---  Spawning one does NOT give anybody a car -- nothing is written to
---  cm_owned_vehicles, and nothing survives a restart.
---
---  Three access modes:
---    'public'   anyone may drive it
---    'owner'    only the character it was spawned for
---    'admin'    only staff
---
---  Additive: nothing in this file edits an existing function. The only hook
---  is CMVehicles.Server.HasAdminAccess, which main.lua consults.
--- ═══════════════════════════════════════════════════════════════════════

CMVehicles = CMVehicles or {}
CMVehicles.Server = CMVehicles.Server or {}
CMVehicles.Admin = CMVehicles.Admin or {}

local U = CMVehicles.Utils

--- Vehicles that exist in the world but in no database.
--- [plate] = { entity, netId, model, access, ownerCid, spawnedBy, label, at }
CMVehicles.Server.AdminVehicles = CMVehicles.Server.AdminVehicles or {}

local ADMIN_PLATE_PREFIX = 'ADM'
local plateCounter = 0

--- A plate that can never collide with a real one. Real plates are player
--- text; these are stamped so a glance tells you the car is not owned.
local function nextAdminPlate()
    plateCounter = plateCounter + 1
    return ('%s%05d'):format(ADMIN_PLATE_PREFIX, plateCounter % 100000)
end

--- Is this a temporary vehicle rather than an owned one?
function CMVehicles.Admin.IsAdminVehicle(plate)
    plate = U.NormalizePlate(plate)
    return CMVehicles.Server.AdminVehicles[plate] ~= nil
end

function CMVehicles.Admin.Get(plate)
    return CMVehicles.Server.AdminVehicles[U.NormalizePlate(plate)]
end

--- A row that looks enough like a real vehicle for the rest of cm-vehicles to
--- work with -- engine start, locks, fuel, damage all read these fields.
---
--- It is NEVER saved. `id` is negative precisely so that any code which tries
--- to UPDATE ... WHERE id = ? touches nothing: there is no row -1 in
--- cm_owned_vehicles. A temporary car cannot leak into somebody's garage.
function CMVehicles.Admin.SyntheticRow(plate)
    local rec = CMVehicles.Admin.Get(plate)
    if not rec then return nil end

    return {
        id                 = -1,          -- negative: matches no real row, ever
        owner_character_id = rec.ownerCid and tostring(rec.ownerCid) or '__admin__',
        model              = rec.model,
        label              = rec.label or rec.model,
        plate              = plate,
        trunk_level        = 0,           -- no trunk: it is not a real car
        fuel               = 100,
        engine_health      = 1000.0,
        body_health        = 1000.0,
        tank_health        = 1000.0,
        dirt_level         = 0.0,
        is_locked          = false,       -- unlocked, or nobody can get in
        is_stored          = false,
        garage             = nil,
        parking_id         = nil,
        last_position      = nil,
        metadata           = { admin = true, access = rec.access },
        mods               = nil,

        -- The flag every save path checks. Anything that persists a vehicle
        -- must look for this and refuse.
        __admin            = true,
    }
end

--- Should this plate be persisted at all?
--- Every save path in cm-vehicles calls this. A temporary vehicle has no row,
--- so writing is pointless -- and worse, a bug that DID create a row would
--- quietly give somebody a free car.
function CMVehicles.Admin.IsPersistable(plate)
    return not CMVehicles.Admin.IsAdminVehicle(plate)
end

--- THE HOOK. main.lua's HasAccess calls this before giving up.
--- Without it every admin-spawned car reports "Vehicle not found."
function CMVehicles.Server.HasAdminAccess(src, plate)
    local rec = CMVehicles.Admin.Get(plate)
    if not rec then return false end

    if rec.access == 'public' then
        return true
    end

    if rec.access == 'admin' then
        return CMVehicles.Admin.IsStaff(src)
    end

    if rec.access == 'owner' then
        -- Staff can always drive what they spawned, or they could strand
        -- themselves with a car they cannot move.
        if CMVehicles.Admin.IsStaff(src) then return true end

        local charId = CMVehicles.Server.GetCharacterId(src)
        return charId ~= nil and tostring(charId) == tostring(rec.ownerCid)
    end

    return false
end

--- Staff check. Uses cm-core's ACL when present, native ACE otherwise, so
--- this works on a server with no admin resource at all.
function CMVehicles.Admin.IsStaff(src)
    src = tonumber(src)
    if not src or src == 0 then return true end   -- console

    if GetResourceState('cm-core') == 'started' then
        local ok, allowed = pcall(function()
            return exports['cm-core']:ACLCheck(src, 'vehicles.admin')
        end)
        if ok and allowed ~= nil then return allowed == true end
    end

    return IsPlayerAceAllowed(src, 'cm-vehicles.admin')
end

-- ═══════════════════════════════════════════════════════════════════════
--  Spawn
-- ═══════════════════════════════════════════════════════════════════════

--- Spawn a vehicle that exists in the world but belongs to no one's garage.
---
--- @param src      number   who is spawning it
--- @param model    string   'sultan'
--- @param coords   table    { x, y, z, h }
--- @param opts     table    {
---                            access   = 'public' | 'owner' | 'admin',
---                            ownerCid = number,   -- required when access='owner'
---                            label    = string,
---                            plate    = string,   -- optional, auto otherwise
---                            warp     = boolean,  -- put the spawner in it
---                            engineOn = boolean,
---                            frozen   = boolean,
---                            invincible = boolean,
---                          }
--- @return boolean ok, table|string result   -- { plate, netId, entity } or an error
function CMVehicles.Admin.Spawn(src, model, coords, opts)
    opts = type(opts) == 'table' and opts or {}

    if opts.__trustedPlacement ~= true and not CMVehicles.Admin.IsStaff(src) then
        return false, 'You cannot spawn vehicles.'
    end

    if type(model) ~= 'string' or model == '' then
        return false, 'Give a vehicle model.'
    end

    if type(coords) ~= 'table' or type(coords.x) ~= 'number' then
        return false, 'Give valid coordinates.'
    end

    local access = tostring(opts.access or 'public'):lower()
    if access ~= 'public' and access ~= 'owner' and access ~= 'admin' then
        return false, 'Access must be public, owner or admin.'
    end

    -- Character IDs are framework identities, not guaranteed numeric values.
    -- Keep them as strings so placement vehicles also work on servers whose
    -- character IDs contain prefixes, underscores or other non-numeric data.
    local ownerCid = opts.ownerCid ~= nil and tostring(opts.ownerCid) or nil
    if ownerCid == '' then ownerCid = nil end
    if access == 'owner' and not ownerCid then
        return false, 'Spawning for a specific player needs a character id.'
    end

    local plate = opts.plate and U.NormalizePlate(opts.plate) or nextAdminPlate()

    -- Never shadow a real vehicle: an admin car wearing a real plate would let
    -- someone drive a car they do not own.
    if CMVehicles.Server.GetVehicleByPlate(plate) then
        return false, ('Plate %s belongs to a real vehicle.'):format(plate)
    end

    -- Reusing a plate would orphan the previous car.
    if CMVehicles.Server.AdminVehicles[plate] then
        CMVehicles.Admin.Delete(plate)
    end

    local hash = GetHashKey(model)

    local entity = CreateVehicle(hash, coords.x, coords.y, coords.z, coords.h or 0.0, true, true)
    if not entity or entity == 0 then
        return false, ('Could not create "%s". Is the model streamed?'):format(model)
    end

    -- Wait for the entity to actually exist before touching it, or the state
    -- bag write silently does nothing.
    local t = GetGameTimer()
    while not DoesEntityExist(entity) and GetGameTimer() - t < 2000 do Wait(0) end
    if not DoesEntityExist(entity) then
        return false, 'The vehicle failed to spawn.'
    end

    -- Placement vehicles must exist in the same routing bucket as the layout
    -- creator. Without this, an admin walking a private/reused interior sees
    -- no car even though the server successfully created it in bucket 0.
    local targetBucket = tonumber(opts.routingBucket)
    if targetBucket == nil and tonumber(src) and tonumber(src) > 0 then
        targetBucket = GetPlayerRoutingBucket(tonumber(src))
    end
    if targetBucket and targetBucket >= 0 then
        SetEntityRoutingBucket(entity, targetBucket)
    end

    SetVehicleNumberPlateText(entity, plate)

    -- cm-vehicles resolves a car's identity through this state bag, NOT
    -- through the physical plate text -- which a client can forge. Setting it
    -- is what makes the car recognisable to every other part of the resource.
    local state = Entity(entity).state
    state:set('cmPlate', plate, true)
    state:set('cmAdmin', true, true)
    state:set('cmAccess', access, true)

    -- Temporary/admin vehicles do not use the owned-vehicle bootstrap/finalize
    -- pipeline. Mark their known-good condition ready immediately; otherwise
    -- the global engine safety code waits forever for finalizeSpawn, an event
    -- that is intentionally never sent for placement/test vehicles.
    state:set('cmFuel', 100.0, true)
    state:set('cmEngineHealth', 1000.0, true)
    state:set('cmBodyHealth', 1000.0, true)
    state:set('cmTankHealth', 1000.0, true)
    state:set('cmDirtLevel', 0.0, true)
    state:set('cmConditionState', {}, true)
    state:set('cmEngineDestroyed', false, true)
    state:set('cmConditionReady', true, true)
    state:set('cmAdminAutoEngine', opts.engineOn ~= false, true)

    -- Apply the same healthy baseline to the physical entity as well as its
    -- state bag. These calls are guarded because native availability can vary
    -- slightly between artifacts/server builds.
    pcall(function() SetVehicleEngineHealth(entity, 1000.0) end)
    pcall(function() SetVehicleBodyHealth(entity, 1000.0) end)
    pcall(function() SetVehiclePetrolTankHealth(entity, 1000.0) end)
    pcall(function() SetVehicleFuelLevel(entity, 100.0) end)
    pcall(function() SetVehicleUndriveable(entity, false) end)

    if opts.frozen then FreezeEntityPosition(entity, true) end
    if opts.invincible then SetEntityInvincible(entity, true) end

    local netId = NetworkGetNetworkIdFromEntity(entity)

    CMVehicles.Server.AdminVehicles[plate] = {
        entity    = entity,
        netId     = netId,
        model     = model,
        label     = opts.label or model,
        access    = access,
        ownerCid  = ownerCid,
        spawnedBy = CMVehicles.Server.GetCharacterId(src),
        spawnedAt = os.time(),
        at        = coords,
        routingBucket = targetBucket or 0,
        placementKind = opts.placementKind,
    }

    if opts.warp and src and src > 0 then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            SetPedIntoVehicle(ped, entity, -1)
        end
    end

    if opts.engineOn ~= false then
        TriggerClientEvent('cm-vehicles:client:adminEngine', -1, netId, true)
    end

    print(('[cm-vehicles] admin spawn: %s (%s) access=%s%s')
        :format(model, plate, access,
                ownerCid and (' owner=' .. ownerCid) or ''))

    return true, { plate = plate, netId = netId, entity = entity }
end

--- Remove a temporary vehicle. Nothing is saved -- it never existed in a
--- garage, so there is nothing to write back.
function CMVehicles.Admin.Delete(plate)
    plate = U.NormalizePlate(plate)
    local rec = CMVehicles.Server.AdminVehicles[plate]
    if not rec then return false end

    if rec.entity and DoesEntityExist(rec.entity) then
        DeleteEntity(rec.entity)
    end
    CMVehicles.Server.AdminVehicles[plate] = nil
    return true
end

--- Clear everything an admin spawned. Used on restart, and by /dvall.
function CMVehicles.Admin.DeleteAll(spawnedBy)
    local n = 0
    for plate, rec in pairs(CMVehicles.Server.AdminVehicles) do
        if not spawnedBy or tostring(rec.spawnedBy) == tostring(spawnedBy) then
            if rec.entity and DoesEntityExist(rec.entity) then
                DeleteEntity(rec.entity)
            end
            CMVehicles.Server.AdminVehicles[plate] = nil
            n = n + 1
        end
    end
    return n
end

--- Change who may drive an already-spawned car.
function CMVehicles.Admin.SetAccess(plate, access, ownerCid)
    local rec = CMVehicles.Admin.Get(plate)
    if not rec then return false, 'That vehicle is not admin-spawned.' end

    access = tostring(access or 'public'):lower()
    if access ~= 'public' and access ~= 'owner' and access ~= 'admin' then
        return false, 'Access must be public, owner or admin.'
    end

    if access == 'owner' and not tonumber(ownerCid) then
        return false, 'Owner access needs a character id.'
    end

    rec.access   = access
    rec.ownerCid = tonumber(ownerCid)

    if rec.entity and DoesEntityExist(rec.entity) then
        Entity(rec.entity).state:set('cmAccess', access, true)
    end

    return true, ('Access set to %s.'):format(access)
end

function CMVehicles.Admin.List()
    local out = {}
    for plate, rec in pairs(CMVehicles.Server.AdminVehicles) do
        out[#out + 1] = {
            plate    = plate,
            model    = rec.model,
            label    = rec.label,
            access   = rec.access,
            ownerCid = rec.ownerCid,
            netId    = rec.netId,
            alive    = rec.entity and DoesEntityExist(rec.entity) or false,
        }
    end
    table.sort(out, function(a, b) return a.plate < b.plate end)
    return out
end

-- ═══════════════════════════════════════════════════════════════════════
--  Housekeeping
-- ═══════════════════════════════════════════════════════════════════════

--- A car destroyed or streamed away leaves a dead record behind. Sweep them,
--- or the registry grows forever and a plate can never be reused.
CreateThread(function()
    while true do
        Wait(60000)
        local dead = {}
        for plate, rec in pairs(CMVehicles.Server.AdminVehicles) do
            if not rec.entity or not DoesEntityExist(rec.entity) then
                dead[#dead + 1] = plate
            end
        end
        for _, plate in ipairs(dead) do
            CMVehicles.Server.AdminVehicles[plate] = nil
        end
    end
end)

--- Temporary means temporary. Nothing survives a restart, so nothing is left
--- lying around the map after a resource reload.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    CMVehicles.Admin.DeleteAll()
end)

-- ═══════════════════════════════════════════════════════════════════════
--  Exports
-- ═══════════════════════════════════════════════════════════════════════

--- Returns a SINGLE table, not (ok, result). FiveM's export bridge only
--- reliably carries the first return value, so two-value returns get silently
--- truncated across the resource boundary.
---   { ok = true,  plate = 'ADM00001', netId = 12, entity = 34 }
---   { ok = false, error = 'why it failed' }
exports('SpawnAdminVehicle', function(src, model, coords, opts)
    opts = type(opts) == 'table' and opts or {}
    local invoker = GetInvokingResource()
    local allowlist = CMVehicles.Config.Placement
        and CMVehicles.Config.Placement.authorizedResources or {}
    local trustedKinds = { car = true, boat = true, helicopter = true, airplane = true }
    local trustedPlacement = invoker and allowlist[invoker] == true
        and trustedKinds[tostring(opts.placementKind or '')] == true
    -- Never trust a caller-supplied internal flag. It is derived only from the
    -- invoking server resource allowlist above.
    opts.__trustedPlacement = trustedPlacement == true
    if trustedPlacement then
        -- A house layout designer may have only house.garages permission, not
        -- the broad cm-vehicles admin permission. Owner access tied to the
        -- current character keeps the temporary car drivable without granting
        -- any general vehicle-admin power.
        local placementCid = CMVehicles.Server.GetCharacterId(tonumber(src))
        opts.access = placementCid and 'owner' or 'public'
        opts.ownerCid = placementCid
        opts.invincible = false
        opts.routingBucket = GetPlayerRoutingBucket(tonumber(src))
    end

    local ok, res = CMVehicles.Admin.Spawn(src, model, coords, opts)
    if not ok then
        return { ok = false, error = tostring(res) }
    end
    return {
        ok     = true,
        plate  = res.plate,
        netId  = res.netId,
        entity = res.entity,
    }
end)

exports('DeleteAdminVehicle', function(plate)
    return CMVehicles.Admin.Delete(plate)
end)

exports('DeleteAllAdminVehicles', function(spawnedBy)
    return CMVehicles.Admin.DeleteAll(spawnedBy)
end)

exports('IsAdminVehicle', function(plate)
    return CMVehicles.Admin.IsAdminVehicle(plate)
end)

exports('SetAdminVehicleAccess', function(plate, access, ownerCid)
    return CMVehicles.Admin.SetAccess(plate, access, ownerCid)
end)

exports('ListAdminVehicles', function()
    return CMVehicles.Admin.List()
end)

-- ═══════════════════════════════════════════════════════════════════════
--  Commands
-- ═══════════════════════════════════════════════════════════════════════

--- /adminveh <model> [public|owner|admin] [charId]
RegisterCommand('adminveh', function(src, args)
    if src == 0 then
        print('[cm-vehicles] /adminveh must be run in-game.')
        return
    end
    if not CMVehicles.Admin.IsStaff(src) then
        U.Notify(src, 'You cannot spawn vehicles.', 'error')
        return
    end

    local model = args[1]
    if not model then
        U.Notify(src, 'Use: /adminveh <model> [public|owner|admin] [charId]', 'inform')
        return
    end

    local ped = GetPlayerPed(src)
    local c   = GetEntityCoords(ped)
    local h   = GetEntityHeading(ped)

    -- Two metres ahead, so it does not spawn on top of the player.
    local rad = math.rad(h)
    local coords = {
        x = c.x - math.sin(rad) * 3.0,
        y = c.y + math.cos(rad) * 3.0,
        z = c.z,
        h = h,
    }

    local ok, res = CMVehicles.Admin.Spawn(src, model, coords, {
        access   = args[2] or 'public',
        ownerCid = tonumber(args[3]),
        warp     = true,
        engineOn = true,
    })

    if ok then
        U.Notify(src, ('Spawned %s (%s).'):format(model, res.plate), 'success')
    else
        U.Notify(src, res, 'error')
    end
end, false)

--- /dv -- delete the vehicle you are in or looking at, admin-spawned or not.
RegisterCommand('dvadmin', function(src)
    if not CMVehicles.Admin.IsStaff(src) then return end

    local ped = GetPlayerPed(src)
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        U.Notify(src, 'Get in the vehicle first.', 'error')
        return
    end

    local plate = ''
    pcall(function() plate = U.NormalizePlate(Entity(veh).state.cmPlate) end)

    if plate ~= '' and CMVehicles.Admin.Delete(plate) then
        U.Notify(src, 'Vehicle deleted.', 'success')
        return
    end

    DeleteEntity(veh)
    U.Notify(src, 'Vehicle deleted.', 'success')
end, false)

--- /dvall -- clear every temporary vehicle on the map.
RegisterCommand('dvall', function(src)
    if not CMVehicles.Admin.IsStaff(src) then return end
    local n = CMVehicles.Admin.DeleteAll()
    U.Notify(src, ('Removed %d temporary vehicle%s.'):format(n, n == 1 and '' or 's'), 'success')
end, false)
