local U = CMVehicles.Utils
CMVehicles.API = CMVehicles.API or {}
local A = CMVehicles.API

local ownerOnly = {
    ['vehicle.sell'] = true,
    ['vehicle.keys.manage'] = true,
    ['vehicle.family.share'] = true,
    ['vehicle.delete'] = true,
}

local keyActions = {
    ['vehicle.drive'] = true,
    ['vehicle.lock'] = true,
    ['vehicle.engine'] = true,
    ['vehicle.store'] = true,
    ['vehicle.trunk.open'] = true,
    ['vehicle.trunk.deposit'] = true,
    ['vehicle.trunk.withdraw'] = true,
    ['vehicle.info'] = true,
}

local function resolve(identity)
    local id = tonumber(identity)
    if id then return CMVehicles.Server.GetVehicleById(id) end
    return CMVehicles.Server.GetVehicleByPlate(identity)
end

local function familyDecision(src, row, action)
    if GetResourceState('cm-family') ~= 'started' then
        return false, 'family_resource_not_started', nil
    end
    local charId = CMVehicles.Server.GetCharacterId(src)
    if not charId then return false, 'character_not_loaded', nil end

    local ok, allowed, reason, context = pcall(function()
        return exports['cm-family']:GetFamilyVehicleAccessDecision(
            tostring(charId), tonumber(row.id), tostring(action or 'vehicle.drive'))
    end)
    if not ok then return false, 'family_export_failed', nil end
    return allowed == true, tostring(reason or (allowed and 'allowed' or 'denied')), context
end

local function assignmentFamilyContext(row)
    if GetResourceState('cm-house') ~= 'started' then return nil end
    local okAssignment, assignment = pcall(function()
        return exports['cm-house']:GetVehicleAssignment(tonumber(row.id))
    end)
    if not okAssignment or type(assignment) ~= 'table'
        or tostring(assignment.owner_class or '') ~= 'family' then
        return nil
    end

    local familyId = tonumber(assignment.family_id)
    if not familyId and tonumber(assignment.house_id) then
        local okDb, dbFamilyId = pcall(function()
            return MySQL.scalar.await(
                'SELECT family_id FROM cm_houses WHERE id = ? LIMIT 1',
                { tonumber(assignment.house_id) })
        end)
        if okDb then familyId = tonumber(dbFamilyId) end
    end

    local family
    if familyId and GetResourceState('cm-family') == 'started' then
        local okFamily, result = pcall(function()
            return exports['cm-family']:GetFamilyById(familyId)
        end)
        if okFamily and type(result) == 'table' then family = result end
    end

    return {
        familyId = familyId,
        familyName = family and tostring(family.name or 'Family') or 'Family',
        familyTag = family and tostring(family.tag or '') or '',
        houseId = tonumber(assignment.house_id),
        vehicleId = tonumber(row.id),
        ownerClass = 'family',
        shared = true,
    }
end

function A.GetFamilyVehicleContext(src, identity, action)
    local row = type(identity) == 'table' and identity or resolve(identity)
    if not row then return nil end

    local allowed, reason, context = familyDecision(src, row, action or 'vehicle.info')
    if type(context) == 'table' then
        context.allowed = allowed == true
        context.reason = reason
        context.ownerClass = 'family'
        context.shared = true
        return context
    end

    local assigned = assignmentFamilyContext(row)
    if assigned then
        assigned.allowed = false
        assigned.reason = reason
    end
    return assigned
end

function A.GrantFamilySessionKey(src, identity, action)
    src = tonumber(src)
    local row = resolve(identity)
    if not src or not row then return false, 'vehicle_not_found' end

    local allowed, reason, context = familyDecision(src, row, action or 'vehicle.drive')
    if allowed ~= true or type(context) ~= 'table' then
        return false, reason or 'family_access_denied'
    end
    if GetResourceState('cm-vehiclekeys') ~= 'started' then
        return false, 'vehiclekeys_not_started'
    end

    local ok, granted, grantError = pcall(function()
        return exports['cm-vehiclekeys']:GrantFamilyKey(src, row.plate, {
            familyId = context.familyId,
            familyName = context.familyName,
            vehicleId = tonumber(row.id),
            requiredTier = context.requiredTier,
            action = action or 'vehicle.drive',
        })
    end)
    if not ok then return false, 'family_key_export_failed' end
    if granted ~= true then return false, tostring(grantError or 'family_key_not_granted') end
    return true, 'family_key', context
end

function A.RevokeFamilyVehicleKeys(identity, familyId, reason)
    local row = resolve(identity)
    local vehicleId = row and tonumber(row.id) or tonumber(identity)
    if not vehicleId or GetResourceState('cm-vehiclekeys') ~= 'started' then return 0 end
    local ok, removed = pcall(function()
        return exports['cm-vehiclekeys']:RevokeFamilyKeysForVehicle(
            vehicleId, tonumber(familyId), reason or 'vehicle-returned')
    end)
    return ok and tonumber(removed) or 0
end

function A.CanUseVehicle(src, identity, action)
    src = tonumber(src)
    action = tostring(action or 'vehicle.drive')
    local row = resolve(identity)
    if not row then return false, 'vehicle_not_found' end
    local charId = CMVehicles.Server.GetCharacterId(src)
    if not charId then return false, 'character_not_loaded' end
    if tostring(row.owner_character_id) == tostring(charId) then return true, 'owner', row end
    if ownerOnly[action] then return false, 'owner_only', row end

    -- Manual keys and already-issued family keys are checked first. Family keys
    -- are revalidated by cm-vehiclekeys against cm-family on every action.
    if keyActions[action] and CMVehicles.Server.HasTempKey(src, row.plate, action) then
        local record = CMVehicles.Server.GetVehicleKeyRecord
            and CMVehicles.Server.GetVehicleKeyRecord(src, row.plate, action) or nil
        return true, record and record.kind == 'family' and 'family_key' or 'temporary_key', row, record
    end

    if keyActions[action] then
        local granted, why, context = A.GrantFamilySessionKey(src, row.id, action)
        if granted == true then return true, 'family', row, context end
        -- Family denial is not final: police/admin integrations may still allow.
    end

    if GetResourceState('cm-police') == 'started' then
        local okPolice, allowed = pcall(function()
            return exports['cm-police']:CanUseVehicle(src, tonumber(row.id), action)
        end)
        if okPolice and allowed == true then return true, 'police', row end
    end

    if GetResourceState('cm-admin') == 'started' then
        local okAdmin, allowed = pcall(function()
            return exports['cm-admin']:HasPermission(src, 'vehicle.override')
        end)
        if okAdmin and allowed == true then return true, 'admin', row end
    end
    if IsPlayerAceAllowed(src, 'cmvehicles.override') then return true, 'admin', row end
    return false, 'no_access', row
end

function A.GetVehiclesByOwner(characterId, options)
    options = type(options) == 'table' and options or {}
    local limit = math.max(1, math.min(500, tonumber(options.limit) or 200))
    local rows = MySQL.query.await(([[
        SELECT * FROM cm_owned_vehicles WHERE owner_character_id = ?
        ORDER BY id DESC LIMIT %d
    ]]):format(limit), { tostring(characterId) }) or {}
    for _, row in ipairs(rows) do
        row.plate = U.NormalizePlate(row.plate)
        row.metadata = U.Decode(row.metadata)
        row.mods = U.Decode(row.mods)
        row.conditionState = U.Decode(row.condition_state)
        if CMVehicles.Location then row.location = CMVehicles.Location.Get(row.id) end
    end
    return rows
end

function A.GetIntegrationContract()
    return {
        version = '2.2.0',
        authority = {
            vehicleRecord = 'cm-vehicles', physicalEntity = 'cm-vehicles',
            houseAssignment = 'cm-house', inventory = 'cm-inventory', keys = 'cm-vehiclekeys',
        },
        capabilities = {
            scopedHousePlacementVehicles = true,
            placementRoutingBucketAware = true,
            placementKinds = { 'car', 'helicopter' },
        },
        locationStates = CMVehicles.Location and CMVehicles.Location.States or {},
        accessActions = {
            'vehicle.drive', 'vehicle.lock', 'vehicle.engine', 'vehicle.store', 'vehicle.info',
            'vehicle.trunk.open', 'vehicle.trunk.deposit', 'vehicle.trunk.withdraw',
            'vehicle.keys.manage', 'vehicle.family.share', 'vehicle.sell',
            'vehicle.tune', 'vehicle.repair', 'vehicle.track', 'vehicle.delete',
        },
        serverExports = {
            records = {
                'CreateOwnedVehicle', 'GetVehicleById', 'GetVehicleByPlate',
                'GetVehiclesByOwner', 'GetCharacterId', 'PlayerOwnsVehicle',
                'HasVehicleAccess', 'CanUseVehicle', 'GetFamilyVehicleContext', 'GrantFamilySessionKey', 'GetVehicleIntegrationContract',
            },
            spawn = {
                'CreateVehicleForPlayer', 'SpawnVehicleFromParking', 'CreateGarageVehicle',
                'DeleteSpawnedVehicle', 'GetSpawnedVehicleInfo', 'GetSpawnedVehicleCondition',
                'ConfigureHouseGarageVehicle', 'SetSpawnContext',
                'PromoteHouseGarageVehicle', 'RecallWorldVehicle', 'ReturnHouseGarageVehicle',
                'CleanupHouseGarageVehicles', 'RemoveDuplicateVehicleEntities',
                'ReconcileSpawnRegistry', 'IsPlayerDrivingSpawnedVehicle',
            },
            persistence = {
                'PersistVehicleState', 'CaptureVehicleState', 'FlushVehicleState',
                'FlushAllVehicleStates', 'GetVehiclePersistenceStatus',
            },
            location = {
                'GetVehicleLocation', 'GetVehicleLocationStates', 'TransitionVehicleLocation',
                'ReconcileVehicleLocation', 'ReconcileAllVehicleLocations',
            },
            operations = {
                'BeginVehicleOperation', 'AdvanceVehicleOperation', 'CompleteVehicleOperation',
                'FailVehicleOperation', 'IsVehicleOperationActive', 'GetVehicleOperations',
                'RecoverInterruptedVehicleOperations',
            },
            recovery = {
                'GetVehicleDiagnostics', 'ListVehicleRecoveryProblems',
                'DeleteDuplicateVehicleEntities', 'RunVehicleRecoveryAction',
                'IsVehicleRecoveryAdmin',
            },
            serviceAndKeys = {
                'ServiceVehicle', 'GetLentKeys', 'HasRacingHarness',
                'InstallRacingHarness', 'SaveVehicleModsAuthorized',
            },
            adminVehicles = {
                'SpawnAdminVehicle', 'DeleteAdminVehicle', 'DeleteAllAdminVehicles',
                'IsAdminVehicle', 'SetAdminVehicleAccess', 'ListAdminVehicles',
            },
        },
        clientExports = {
            'TryOpenNearbyTrunkInventory', 'HasRacingHarness', 'GetVehicleFuel',
            'AddFuel', 'SetFuelExact', 'RepairVehicle', 'WashVehicle',
            'SaveVehicleMods', 'ApplyVehicleMods', 'ApplyPerformance',
            'GetTuningMultiplier', 'ApplyTyreLevel', 'GetTyreLevel',
            'EstimateTopSpeed', 'RunServiceProgress', 'ShowServiceProgress',
            'UpdateServiceProgress', 'HideServiceProgress', 'FlushCurrentVehicle',
            'IsAdminVehicleClient',
        },
    }
end

exports('GetVehicleById', CMVehicles.Server.GetVehicleById)
exports('GetVehiclesByOwner', A.GetVehiclesByOwner)
exports('CanUseVehicle', A.CanUseVehicle)
exports('GetFamilyVehicleContext', A.GetFamilyVehicleContext)
exports('GrantFamilySessionKey', A.GrantFamilySessionKey)
exports('RevokeFamilyVehicleKeys', A.RevokeFamilyVehicleKeys)
exports('GetVehicleIntegrationContract', A.GetIntegrationContract)
