-- ============================================================
-- cm-house | Phase 2 integration and recovery API
--
-- This file intentionally exposes stable, server-side contracts for cm-admin,
-- cm-family and future property resources. Physical vehicle operations remain
-- owned by cm-vehicles; house/slot/access ownership remains here.
-- ============================================================

CMHousePhase2 = CMHousePhase2 or {}
local P2 = CMHousePhase2

local function decode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, result = pcall(json.decode, value)
    return ok and type(result) == 'table' and result or {}
end

local function integrationAllowed(scope)
    local invoker = GetInvokingResource()
    if not invoker or invoker == GetCurrentResourceName() then return true end
    local configured = Config.Integration and Config.Integration.authorizedResources or {}
    local grants = configured[invoker]
    if grants == true then return true end
    if type(grants) ~= 'table' then return false end
    return grants['*'] == true or grants[tostring(scope or '')] == true
end

local function invokingHasScope(scope)
    local invoker = GetInvokingResource()
    if not invoker or invoker == GetCurrentResourceName() then return true end
    local configured = Config.Integration and Config.Integration.authorizedResources or {}
    local grants = configured[invoker]
    if grants == true then return true end
    return type(grants) == 'table'
        and (grants['*'] == true or grants[tostring(scope or '')] == true)
end

-- Shared by later server files such as sv_weapon_storage.lua. Keeping the
-- allowlist resolution in one place avoids slightly different security rules
-- across writable exports.
CMHouseIntegrationAllowed = integrationAllowed
CMHouseInvokingHasScope = invokingHasScope

local function actorAllowed(src, permission)
    src = tonumber(src)
    if not src or src <= 0 then
        return integrationAllowed('admin')
    end
    permission = tostring(permission or 'house.admin')
    if GetResourceState('cm-core') == 'started' then
        local ok, allowed = pcall(function() return exports['cm-core']:ACLCheck(src, permission) end)
        if ok and allowed == true then return true end
    end
    if GetResourceState('cm-admin') == 'started' then
        local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(src, permission) end)
        if ok and allowed == true then return true end
    end
    return IsPlayerAceAllowed(src, 'cm-house.admin') or IsPlayerAceAllowed(src, 'cmvehicles.recovery')
end

function P2.GetVehicleAssignment(vehicleId)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return nil end
    local row = MySQL.single.await([[
        SELECT s.house_id, s.slot_index, s.vehicle_id, s.owner_class,
               s.assigned_by, s.assigned_at, s.updated_at,
               h.label AS house_label, h.house_number, h.owner_cid, h.family_id,
               v.plate, v.label AS vehicle_label, v.owner_character_id,
               v.is_stored, v.garage, v.location_state, v.location_ref, v.location_slot
        FROM cm_house_vehicle_slots s
        INNER JOIN cm_houses h ON h.id = s.house_id
        INNER JOIN cm_owned_vehicles v ON v.id = s.vehicle_id
        WHERE s.vehicle_id = ? LIMIT 1
    ]], { vehicleId })
    if not row then return nil end
    row.house_id = tonumber(row.house_id)
    row.slot_index = tonumber(row.slot_index)
    row.vehicle_id = tonumber(row.vehicle_id)
    return row
end

function P2.ClearVehicleAssignment(vehicleId, reason, actorCid)
    if not integrationAllowed('garage') then return false, 'resource_not_authorized' end
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'invalid_vehicle_id' end
    local assignment = P2.GetVehicleAssignment(vehicleId)
    if not assignment then return true, 'no_assignment' end
    local tx = {
        {
            query = 'DELETE FROM cm_house_shared_vehicles WHERE vehicle_id = ?',
            values = { vehicleId },
        },
        {
            query = [[
                UPDATE cm_house_vehicle_slots
                SET vehicle_id = NULL, owner_class = 'personal', assigned_by = NULL, assigned_at = NULL
                WHERE vehicle_id = ?
            ]],
            values = { vehicleId },
        },
    }
    local ok, committed = pcall(function() return MySQL.transaction.await(tx) end)
    if not ok or committed ~= true then return false, 'assignment_transaction_failed' end

    if GetResourceState('cm-vehicles') == 'started' then
        pcall(function() exports['cm-vehicles']:ReconcileVehicleLocation(vehicleId) end)
    end
    LogHouse(assignment.house_id, assignment.family_id, actorCid, 'garage_assignment_cleared', {
        vehicleId = vehicleId, slot = assignment.slot_index, reason = tostring(reason or 'integration'),
    })
    if BroadcastGarage then BroadcastGarage(assignment.house_id) end
    return true, { houseId = assignment.house_id, slotIndex = assignment.slot_index }
end

function P2.MoveVehicleAssignment(vehicleId, houseId, slotIndex, actorCid, ownerClass)
    if not integrationAllowed('garage') then return false, 'resource_not_authorized' end
    vehicleId, houseId, slotIndex = tonumber(vehicleId), tonumber(houseId), tonumber(slotIndex)
    if not vehicleId or not houseId or not slotIndex then return false, 'invalid_arguments' end
    local validSlot, why = ValidSlot(houseId, slotIndex)
    if not validSlot then return false, why end
    local target = MySQL.single.await(
        'SELECT vehicle_id FROM cm_house_vehicle_slots WHERE house_id = ? AND slot_index = ? LIMIT 1',
        { houseId, slotIndex })
    if not target then return false, 'slot_not_found' end
    if target.vehicle_id and tonumber(target.vehicle_id) ~= vehicleId then return false, 'slot_occupied' end

    local previous = P2.GetVehicleAssignment(vehicleId)
    local tx = {
        {
            query = [[
                UPDATE cm_house_vehicle_slots
                SET vehicle_id = NULL, owner_class = 'personal', assigned_by = NULL, assigned_at = NULL
                WHERE vehicle_id = ? AND NOT (house_id = ? AND slot_index = ?)
            ]],
            values = { vehicleId, houseId, slotIndex },
        },
        {
            query = [[
                UPDATE cm_house_vehicle_slots
                SET vehicle_id = ?, owner_class = ?, assigned_by = ?, assigned_at = COALESCE(assigned_at, NOW())
                WHERE house_id = ? AND slot_index = ? AND (vehicle_id IS NULL OR vehicle_id = ?)
            ]],
            values = { vehicleId, ownerClass == 'family' and 'family' or 'personal', actorCid, houseId, slotIndex, vehicleId },
        },
    }
    local ok, committed = pcall(function() return MySQL.transaction.await(tx) end)
    if not ok or committed ~= true then return false, 'assignment_move_failed' end

    local confirmed = MySQL.single.await([[
        SELECT house_id, slot_index FROM cm_house_vehicle_slots
        WHERE vehicle_id = ? LIMIT 1
    ]], { vehicleId })
    if not confirmed or tonumber(confirmed.house_id) ~= houseId
        or tonumber(confirmed.slot_index) ~= slotIndex then
        -- A second writer may have occupied the target after the initial read.
        -- Restore the previous reservation when it is still available rather
        -- than leaving this vehicle without a home slot.
        if previous then
            pcall(function()
                MySQL.update.await([[
                    UPDATE cm_house_vehicle_slots
                    SET vehicle_id = ?, owner_class = ?, assigned_by = ?,
                        assigned_at = COALESCE(assigned_at, NOW())
                    WHERE house_id = ? AND slot_index = ? AND vehicle_id IS NULL
                ]], {
                    vehicleId, previous.owner_class == 'family' and 'family' or 'personal',
                    previous.assigned_by or actorCid, previous.house_id, previous.slot_index,
                })
            end)
        end
        return false, 'target_slot_changed'
    end

    if GetResourceState('cm-vehicles') == 'started' then
        pcall(function() exports['cm-vehicles']:ReconcileVehicleLocation(vehicleId) end)
    end
    if previous and BroadcastGarage then BroadcastGarage(previous.house_id) end
    if BroadcastGarage then BroadcastGarage(houseId) end
    return true, { previous = previous, houseId = houseId, slotIndex = slotIndex }
end

function P2.GetHouseIntegrationSnapshot(houseId)
    houseId = tonumber(houseId)
    local house = houseId and Houses[houseId]
    if not house then return nil, 'house_not_found' end
    local access = MySQL.query.await('SELECT * FROM cm_house_access WHERE house_id = ? ORDER BY id', { houseId }) or {}
    local family = house.family_id and Families[tonumber(house.family_id)] or nil
    local garage = GarageState and GarageState(houseId) or nil
    return {
        house = house,
        interior = house.interior_template_id and InteriorTemplates[tonumber(house.interior_template_id)] or nil,
        garageTemplate = house.garage_template_id and GarageTemplates[tonumber(house.garage_template_id)] or nil,
        garage = garage,
        access = access,
        family = family,
        permissions = Config.Permissions,
        ownerOnlyPermissions = Config.OwnerOnly,
    }
end

function P2.GetGarageDiagnostics(houseId)
    houseId = tonumber(houseId)
    local state = GarageState and GarageState(houseId) or nil
    if not state then return nil, 'garage_not_found' end
    local assignments = MySQL.query.await([[
        SELECT s.*, v.plate, v.label, v.owner_character_id, v.is_stored, v.garage,
               v.location_state, v.location_ref, v.location_slot
        FROM cm_house_vehicle_slots s
        LEFT JOIN cm_owned_vehicles v ON v.id = s.vehicle_id
        WHERE s.house_id = ? ORDER BY s.slot_index
    ]], { houseId }) or {}
    return { state = state, assignments = assignments }
end

local function verifyOwnerFamilyMembership(actorCid, familyId)
    local familyResource = tostring(Config.Family and Config.Family.resource or 'cm-family')
    if GetResourceState(familyResource) ~= 'started' then
        return false, 'cm_family_not_running'
    end

    -- cm-family creates the membership and then calls this export. Calling back
    -- into cm-family from this same export stack is re-entrant and can return a
    -- stale/nil cache result even though the INSERT already committed. When the
    -- authoritative family resource is the direct caller, verify the exact row
    -- in the shared database instead of creating a circular export call.
    local invoker = GetInvokingResource()
    if invoker == familyResource then
        local okDb, found = pcall(function()
            return MySQL.scalar.await([[
                SELECT 1
                FROM cm_family_members
                WHERE character_id = ? AND family_id = ?
                LIMIT 1
            ]], { tostring(actorCid), familyId })
        end)
        if not okDb then
            print(('[cm-house] family membership DB verification failed for cid %s / family %s: %s')
                :format(tostring(actorCid), tostring(familyId), tostring(found)))
            return false, 'family_membership_check_failed'
        end
        if tonumber(found) == 1 then return true end
        return false, 'property_owner_is_not_in_that_family'
    end

    -- Other explicitly authorized integrations must still prove membership
    -- through cm-family's public read contract. Admin-scope callers are handled
    -- separately by SetFamilyHouseLink and never reach this function.
    local exportName = tostring(Config.Family and Config.Family.getFamilyForCharacterExport or 'GetFamilyForCharacter')
    local okFamily, family = pcall(function()
        return exports[familyResource][exportName](actorCid)
    end)
    if okFamily and type(family) == 'table' and tonumber(family.id) == familyId then
        return true
    end
    return false, 'property_owner_is_not_in_that_family'
end

function P2.SetFamilyHouseLink(houseId, familyId, actorCid)
    if not integrationAllowed('family') then return false, 'resource_not_authorized' end
    houseId = tonumber(houseId)
    familyId = familyId == nil and nil or tonumber(familyId)
    local house = houseId and Houses[houseId]
    if not house then return false, 'house_not_found' end

    actorCid = tonumber(actorCid)
    local adminOverride = invokingHasScope('admin')
    if not adminOverride then
        if not actorCid or tonumber(house.owner_cid) ~= actorCid then
            return false, 'only_property_owner_can_change_family_link'
        end
        if familyId then
            local memberOk, memberWhy = verifyOwnerFamilyMembership(actorCid, familyId)
            if not memberOk then return false, memberWhy end
        end
    end

    if familyId and tostring(house.house_type or '') == 'apartment' then
        return false, 'apartments_cannot_be_family_houses'
    end
    if familyId and house.family_eligible ~= true then
        return false, 'property_is_not_family_eligible'
    end

    local previousFamilyId = tonumber(house.family_id)
    if familyId and previousFamilyId and previousFamilyId ~= familyId then
        return false, 'property_is_already_a_family_house'
    end

    if familyId then
        local familyRow = MySQL.single.await(
            'SELECT id, house_id FROM cm_families WHERE id = ? LIMIT 1', { familyId })
        if not familyRow then return false, 'family_not_found' end
        local existingHouseId = tonumber(familyRow.house_id)
        if existingHouseId and existingHouseId ~= houseId then
            return false, 'family_already_has_another_house'
        end
    end

    local statements = {}
    if familyId then
        statements[#statements + 1] = {
            query = 'UPDATE cm_houses SET family_id = ? WHERE id = ?',
            values = { familyId, houseId },
        }
        statements[#statements + 1] = {
            query = 'UPDATE cm_families SET house_id = ? WHERE id = ?',
            values = { houseId, familyId },
        }
    else
        statements[#statements + 1] = {
            query = 'UPDATE cm_houses SET family_id = NULL WHERE id = ?',
            values = { houseId },
        }
        if previousFamilyId then
            statements[#statements + 1] = {
                query = 'UPDATE cm_families SET house_id = NULL WHERE id = ? AND house_id = ?',
                values = { previousFamilyId, houseId },
            }
        end
    end

    local committed = MySQL.transaction.await(statements)
    if committed ~= true then return false, 'family_link_update_failed' end

    local verifiedHouseFamily = MySQL.scalar.await(
        'SELECT family_id FROM cm_houses WHERE id = ? LIMIT 1', { houseId })
    if familyId then
        if tonumber(verifiedHouseFamily) ~= familyId then return false, 'family_link_verification_failed' end
        local verifiedFamilyHouse = MySQL.scalar.await(
            'SELECT house_id FROM cm_families WHERE id = ? LIMIT 1', { familyId })
        if tonumber(verifiedFamilyHouse) ~= houseId then return false, 'family_record_link_verification_failed' end
    elseif DbPositiveInteger(verifiedHouseFamily) then
        return false, 'family_unlink_verification_failed'
    end

    house.family_id = familyId
    LogHouse(houseId, familyId or previousFamilyId, actorCid,
        familyId and 'family_house_linked' or 'family_house_unlinked', {
            previousFamilyId = previousFamilyId,
            familyId = familyId,
            familyStorageEnabled = familyId ~= nil,
            familyGarageEnabled = familyId ~= nil,
            familyWeaponStorageEnabled = familyId ~= nil,
        })
    TriggerClientEvent('cm-house:client:syncHouse', -1, BuildClientHouse(house))

    if previousFamilyId and P2.RefreshFamilyMembers then
        pcall(P2.RefreshFamilyMembers, previousFamilyId)
    end
    if familyId and P2.RefreshFamilyMembers then
        pcall(P2.RefreshFamilyMembers, familyId)
    end
    if house.owner_cid and PushOwnership then PushOwnership(house.owner_cid) end
    return true
end

function P2.GetFamilyHouses(familyId)
    familyId = tonumber(familyId)
    if not familyId then return {} end
    local result = {}
    for _, house in pairs(Houses) do
        if tonumber(house.family_id) == familyId then result[#result + 1] = house end
    end
    table.sort(result, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
    return result
end

function P2.GetFamilyImportContract()
    return {
        version = '1.7.10',
        resource = tostring(Config.Family and Config.Family.resource or 'cm-family'),
        requiredImport = {
            name = tostring(Config.Family and Config.Family.permissionExport or 'HasHousePermission'),
            signature = 'HasHousePermission(characterId, familyId, houseId, permissionKey, internalAction) -> boolean',
            failClosed = true,
        },
        compatibilityImport = {
            name = tostring(Config.Family and Config.Family.legacyPermissionExport or 'HasPermission'),
            signature = 'HasPermission(characterId, familyId, permissionKey) -> boolean',
        },
        optionalImports = {
            {
                name = tostring(Config.Family and Config.Family.getFamilyExport or 'GetFamilyById'),
                signature = 'GetFamilyById(familyId) -> family|nil',
            },
            {
                name = tostring(Config.Family and Config.Family.getFamilyForCharacterExport or 'GetFamilyForCharacter'),
                signature = 'GetFamilyForCharacter(characterId) -> family|nil',
            },
            {
                name = tostring(Config.Family and Config.Family.getMemberCharacterIdsExport or 'GetFamilyMemberCharacterIds'),
                signature = 'GetFamilyMemberCharacterIds(familyId) -> characterId[]',
            },
        },
        houseExports = {
            'CanFamilyAccessProperty', 'GetFamilyPermissionForAction',
            'SetFamilyHouseLink', 'GetFamilyHouses', 'GetFamilyDisplay',
            'GetFamilyForCharacter', 'GetFamilyVehicles', 'SetVehicleFamilyShared',
            'RefreshFamilyAccess', 'RefreshFamilyMembers',
            'GetFamilyHouseContract', 'GetFamilyImportContract',
            'GetHouseWeaponStorageContract', 'CanUseHouseWeaponStorage',
            'GetHouseWeaponStorage', 'GetHouseWeaponStorageCount',
            'GetHouseWeaponStoragePointCount', 'GetHouseWeaponStorageTransfers',
        },
    }
end

function P2.RefreshFamilyAccess(characterId)
    if not integrationAllowed('family') then return false, 'resource_not_authorized' end
    characterId = tonumber(characterId) or characterId
    if not characterId then return false, 'invalid_character_id' end
    if PushOwnership then PushOwnership(characterId) end
    return true
end


function P2.RefreshFamilyMembers(familyId)
    if not integrationAllowed('family') then return false, 'resource_not_authorized' end
    familyId = tonumber(familyId)
    if not familyId then return false, 'invalid_family_id' end

    local resource = tostring(Config.Family and Config.Family.resource or 'cm-family')
    if GetResourceState(resource) ~= 'started' then return false, 'cm_family_not_running' end
    local exportName = tostring(Config.Family and Config.Family.getMemberCharacterIdsExport or 'GetFamilyMemberCharacterIds')
    local ok, members = pcall(function()
        return exports[resource][exportName](familyId)
    end)
    if not ok or type(members) ~= 'table' then members = {} end

    -- Direct DB fallback keeps the client access map correct even if cm-family
    -- has just restarted or its cache refresh is still in progress.
    if #members == 0 then
        local dbOk, rows = pcall(function()
            return MySQL.query.await(
                'SELECT character_id FROM cm_family_members WHERE family_id = ?',
                { familyId }) or {}
        end)
        if dbOk and type(rows) == 'table' then
            for _, row in ipairs(rows) do
                if row.character_id ~= nil then members[#members + 1] = row.character_id end
            end
        end
    end
    if #members == 0 then return false, 'family_has_no_committed_members' end

    local refreshed = 0
    local seen = {}
    for _, cid in pairs(members) do
        cid = tonumber(cid) or cid
        if cid and not seen[tostring(cid)] and PushOwnership then
            seen[tostring(cid)] = true
            PushOwnership(cid)
            refreshed = refreshed + 1
        end
    end
    return true, refreshed
end

function P2.GetFamilyHouseContract()
    return {
        version = '1.7.10',
        accessExport = 'CanAccessProperty',
        linkExport = 'SetFamilyHouseLink',
        snapshotExport = 'GetHouseIntegrationSnapshot',
        assignmentExport = 'GetVehicleAssignment',
        familyAccessExport = 'CanFamilyAccessProperty',
        familyHousesExport = 'GetFamilyHouses',
        refreshExport = 'RefreshFamilyAccess',
        refreshMembersExport = 'RefreshFamilyMembers',
        weaponStorageContractExport = 'GetHouseWeaponStorageContract',
        weaponStorageExports = {
            'CanUseHouseWeaponStorage', 'GetHouseWeaponStorage',
            'GetHouseWeaponStorageCount', 'GetHouseWeaponStoragePointCount',
            'GetHouseWeaponStorageTransfers', 'OpenHouseWeaponStorageForPlayer',
        },
        importContract = P2.GetFamilyImportContract(),
        permissionKeys = Config.Permissions,
        ownerOnly = Config.OwnerOnly,
        supportedActions = ACTIONS,
    }
end

function P2.AdminRecoverAssignedVehicle(vehicleId, src)
    if not integrationAllowed('recovery') then return false, 'resource_not_authorized' end
    vehicleId, src = tonumber(vehicleId), tonumber(src)
    if src and src > 0 and not actorAllowed(src, 'vehicle.recovery') then return false, 'not_authorized' end
    local assignment = P2.GetVehicleAssignment(vehicleId)
    if not assignment then return false, 'vehicle_has_no_house_assignment' end
    local house = Houses[assignment.house_id]
    local template = house and GarageTemplates[tonumber(house.garage_template_id)]
    local slot = template and template.slots and template.slots[assignment.slot_index]
    if not slot or not slot.coords then return false, 'garage_slot_not_configured' end

    if GetResourceState('cm-vehicles') ~= 'started' then return false, 'cm_vehicles_not_running' end
    local activeOk, active = exports['cm-vehicles']:GetSpawnedVehicleInfo(vehicleId)
    if activeOk and active and tostring(active.context or '') == 'world' then
        local entity = tonumber(active.entity) or 0
        if entity ~= 0 and DoesEntityExist(entity) then
            local max = 6
            pcall(function() max = math.max(0, GetVehicleMaxNumberOfPassengers(entity)) end)
            for seat = -1, max do
                local ped = 0
                pcall(function() ped = GetPedInVehicleSeat(entity, seat) end)
                if ped and ped ~= 0 then return false, 'vehicle_is_occupied' end
            end
        end
    end

    pcall(function() exports['cm-vehicles']:CaptureVehicleState(vehicleId, 'admin_house_recovery') end)
    local deleted, why = exports['cm-vehicles']:DeleteSpawnedVehicle(vehicleId)
    if deleted ~= true then return false, why or 'entity_delete_failed' end

    local affected = MySQL.update.await([[
        UPDATE cm_owned_vehicles
        SET is_stored = 1, garage = ?, parking_id = ?, parked_at = NOW(), is_locked = 0
        WHERE id = ?
    ]], { ('house:%d'):format(assignment.house_id), assignment.slot_index, vehicleId })
    if not affected or tonumber(affected) <= 0 then return false, 'vehicle_update_failed' end

    pcall(function()
        exports['cm-vehicles']:TransitionVehicleLocation(vehicleId, 'HOUSE_GARAGE', {
            ref = tostring(assignment.house_id), slot = assignment.slot_index,
            reason = 'admin_house_recovery', actorCharacterId = src and GetCid(src) or nil,
        })
    end)
    if BroadcastGarage then BroadcastGarage(assignment.house_id) end
    return true, { houseId = assignment.house_id, slotIndex = assignment.slot_index }
end

-- Durable operation bridge used by sv_garage.lua. The in-memory rollback token
-- remains fast, while this journal survives a resource/server restart.
function P2.BeginOperation(vehicleId, action, src, token, details)
    if GetResourceState('cm-vehicles') ~= 'started' then return false end
    local ok, accepted = pcall(function()
        return exports['cm-vehicles']:BeginVehicleOperation(vehicleId, action, src, {
            token = token, ttl = 45, stage = 'house_started',
            targetState = details and details.targetState,
            targetRef = details and details.targetRef,
            targetSlot = details and details.targetSlot,
            house = details,
        })
    end)
    return ok and accepted == true
end

function P2.AdvanceOperation(vehicleId, token, stage, details)
    if GetResourceState('cm-vehicles') ~= 'started' then return false end
    local ok, result = pcall(function()
        return exports['cm-vehicles']:AdvanceVehicleOperation(vehicleId, token, stage, details or {})
    end)
    return ok and result == true
end

function P2.CompleteOperation(vehicleId, token, stage, details)
    if GetResourceState('cm-vehicles') ~= 'started' then return false end
    local ok, result = pcall(function()
        return exports['cm-vehicles']:CompleteVehicleOperation(vehicleId, token, stage or 'house_completed', details or {})
    end)
    return ok and result == true
end

function P2.FailOperation(vehicleId, token, stage, details)
    if GetResourceState('cm-vehicles') ~= 'started' then return false end
    local ok, result = pcall(function()
        return exports['cm-vehicles']:FailVehicleOperation(vehicleId, token, stage or 'house_failed', details or {})
    end)
    return ok and result == true
end

function P2.GetAdminContract()
    return {
        version = '1.2.0',
        permission = tostring(Config.AdminPermission or 'house.create'),
        permissions = Config.AdminPermissions or {},
        aceFallback = tostring(Config.AdminAce or 'cm-house.create'),
        aces = Config.AdminAces or {},
        legacyFallbackEnabled = Config.AdminUseLegacyFallback == true,
        failClosed = true,
        rankReady = true,
        preferredAuthority = {
            resource = 'cm-core',
            export = 'ACLCheck',
            signature = 'ACLCheck(source, permissionKey) -> boolean',
        },
        directAuthority = {
            resource = 'cm-admin',
            export = 'HasPermission',
            signature = 'HasPermission(source, permissionKey) -> boolean',
        },
        panelTabs = {
            { id = 'houses', label = 'Properties', permission = (Config.AdminPermissions or {}).properties },
            { id = 'interiors', label = 'Interior layouts', permission = (Config.AdminPermissions or {}).interiors },
            { id = 'garages', label = 'Garage layouts', permission = (Config.AdminPermissions or {}).garages },
            { id = 'recovery', label = 'Vehicle recovery', permission = (Config.AdminPermissions or {}).recovery },
        },
        serverExports = { 'OpenAdminPanel', 'OpenHouseCreator', 'GetHouseAdminPanelTabs' },
        clientExports = { 'OpenAdminPanel', 'OpenHouseCreator', 'IsHouseAdminPanelOpen' },
        writableScope = 'admin',
    }
end

function P2.GetIntegrationContract()
    return {
        version = '3.2.0',
        authority = {
            properties = 'cm-house', access = 'cm-house', familyHouseLink = 'cm-house',
            garageAssignment = 'cm-house', physicalVehicle = 'cm-vehicles',
            vehicleLocation = 'cm-vehicles', inventory = 'cm-inventory',
            weaponStorage = 'cm-house', weaponCatalog = 'cm-weapons/cm-gunstore',
        },
        capabilities = {
            multiGarageExits = true,
            maxGarageExits = tonumber(Config.GarageTemplate and Config.GarageTemplate.maxVehicleExits) or 8,
            garagePlacementVehicle = true,
            adminOnlyTemplates = true,
            houseWizardCreatesTemplates = false,
            garageCapacityFromPlacedSlots = true,
        },
        actions = ACTIONS,
        permissions = Config.Permissions,
        ownerOnlyPermissions = Config.OwnerOnly,
        writableResourceScopes = Config.Integration and Config.Integration.authorizedResources or {},
        serverExports = {
            property = {
                'GetHouse', 'GetHouses', 'GetHousesForCharacter', 'GetPropertyPhoto',
                'GetPropertyPhotoFile', 'GetPropertyPhotoData', 'DeleteHousePhoto',
                'GetInteriorTemplate', 'GetGarageTemplate', 'GetGarageCapacity',
                'GetHouseBucket', 'GetGarageBucket', 'WhereIsPlayer',
                'DeriveProperty', 'FeatureSignature', 'PushOwnership', 'LogHouse',
            },
            access = {
                'CanAccessProperty', 'CanFamilyAccessProperty', 'GetFamilyPermissionForAction',
                'GrantHouseAccess', 'RevokeHouseAccess',
                'GetHouseAccessList', 'GetPropertyPermissionCatalog',
            },
            family = {
                'GetFamily', 'GetFamilyOfCid', 'IsFamilyHouse', 'SetFamilyHouseLink',
                'CanFamilyAccessProperty', 'GetFamilyHouses', 'GetFamilyVehicles',
                'SetVehicleFamilyShared', 'RefreshFamilyAccess', 'RefreshFamilyMembers',
                'GetFamilyHouseContract', 'GetFamilyImportContract',
                'GetHouseWeaponStorageContract', 'CanUseHouseWeaponStorage',
                'GetHouseWeaponStorage', 'GetHouseWeaponStorageCount',
                'GetHouseWeaponStoragePointCount', 'GetHouseWeaponStorageTransfers',
            },
            garage = {
                'GetGarageState', 'GetGarageDiagnostics', 'GetVehicleAssignment',
                'ClearVehicleAssignment', 'MoveVehicleAssignment',
                    'IsGarageVehicleOperationActive', 'AdminRecoverAssignedVehicle',
            },
            weaponStorage = {
                'GetWeaponStorageCatalog', 'GetHouseWeaponStorage',
                'GetHouseWeaponStorageCount', 'GetHouseWeaponStoragePointCount',
                'GetHouseWeaponStorageTransfers', 'RefreshWeaponStorageCatalog',
                'CanUseHouseWeaponStorage', 'OpenHouseWeaponStorageForPlayer',
                'GetHouseWeaponStorageContract',
            },
            admin = {
                'OpenAdminPanel', 'OpenHouseCreator', 'GetHouseAdminPanelTabs',
                'GetHouseAdminContract', 'IsHouseIntegrationAdmin',
            },
            integration = {
                'GetHouseIntegrationSnapshot', 'GetHouseIntegrationContract',
                'IsHouseIntegrationAdmin',
            },
        },
        clientExports = {
            'RequestInteraction', 'ClearInteraction', 'SuppressInteractions',
            'OpenAdminPanel', 'OpenHouseCreator', 'IsHouseAdminPanelOpen',
            'OpenWeaponStorage', 'CloseWeaponStorage', 'IsWeaponStorageOpen',
        },
    }
end

exports('GetHouseIntegrationContract', P2.GetIntegrationContract)
exports('GetHouseAdminContract', P2.GetAdminContract)
exports('GetVehicleAssignment', P2.GetVehicleAssignment)
exports('ClearVehicleAssignment', P2.ClearVehicleAssignment)
exports('MoveVehicleAssignment', P2.MoveVehicleAssignment)
exports('GetHouseIntegrationSnapshot', P2.GetHouseIntegrationSnapshot)
exports('GetGarageDiagnostics', P2.GetGarageDiagnostics)
exports('SetFamilyHouseLink', P2.SetFamilyHouseLink)
exports('GetFamilyHouseContract', P2.GetFamilyHouseContract)
exports('GetFamilyImportContract', P2.GetFamilyImportContract)
exports('GetFamilyHouses', P2.GetFamilyHouses)
exports('RefreshFamilyAccess', P2.RefreshFamilyAccess)
exports('RefreshFamilyMembers', P2.RefreshFamilyMembers)
exports('AdminRecoverAssignedVehicle', P2.AdminRecoverAssignedVehicle)
exports('IsHouseIntegrationAdmin', actorAllowed)
exports('GrantHouseAccess', function(houseId, cid, kind, byCid, expiresAt)
    if not integrationAllowed('access') then return false, 'resource_not_authorized' end
    GrantAccess(tonumber(houseId), tostring(cid), tostring(kind or 'guest'), byCid, expiresAt)
    return true
end)
exports('RevokeHouseAccess', function(houseId, cid, byCid)
    if not integrationAllowed('access') then return false, 'resource_not_authorized' end
    RevokeAccess(tonumber(houseId), tostring(cid), byCid)
    return true
end)
exports('GetHouseAccessList', function(houseId)
    return MySQL.query.await('SELECT * FROM cm_house_access WHERE house_id = ? ORDER BY id', { tonumber(houseId) }) or {}
end)

function P2.SetVehicleFamilyShared(vehicleId, shared, actorCid)
    if not integrationAllowed('family') then return false, 'resource_not_authorized' end
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'invalid_vehicle_id' end
    local assignment = P2.GetVehicleAssignment(vehicleId)
    if not assignment then return false, 'vehicle_has_no_house_assignment' end
    if not assignment.family_id then return false, 'property_is_not_a_family_house' end

    actorCid = tonumber(actorCid)
    if not invokingHasScope('admin') then
        if not actorCid or tonumber(assignment.owner_character_id) ~= actorCid then
            return false, 'only_vehicle_owner_can_change_family_sharing'
        end
        local allowed = CanAccessProperty(actorCid, assignment.house_id, ACTIONS.GARAGE_MANAGE_SLOTS, false)
        if not allowed then return false, 'family_permission_denied' end
    end

    local tx = {}
    if shared == true then
        tx[#tx + 1] = {
            query = [[
                INSERT INTO cm_house_shared_vehicles (house_id, vehicle_id, shared_by)
                VALUES (?, ?, ?)
                ON DUPLICATE KEY UPDATE house_id = VALUES(house_id), shared_by = VALUES(shared_by)
            ]],
            values = { assignment.house_id, vehicleId, tonumber(actorCid) or 0 },
        }
        tx[#tx + 1] = {
            query = "UPDATE cm_house_vehicle_slots SET owner_class = 'family' WHERE vehicle_id = ?",
            values = { vehicleId },
        }
    else
        tx[#tx + 1] = {
            query = 'DELETE FROM cm_house_shared_vehicles WHERE vehicle_id = ?',
            values = { vehicleId },
        }
        tx[#tx + 1] = {
            query = "UPDATE cm_house_vehicle_slots SET owner_class = 'personal' WHERE vehicle_id = ?",
            values = { vehicleId },
        }
    end
    local ok, committed = pcall(function() return MySQL.transaction.await(tx) end)
    if not ok or committed ~= true then return false, 'family_share_transaction_failed' end
    LogHouse(assignment.house_id, assignment.family_id, actorCid,
        shared and 'garage_share' or 'garage_unshare', { vehicleId = vehicleId })
    if BroadcastGarage then BroadcastGarage(assignment.house_id) end
    return true
end


function P2.GetFamilyVehicleManagementList(familyId, ownerCid)
    if not integrationAllowed('family') then return {} end
    familyId = tonumber(familyId)
    ownerCid = ownerCid ~= nil and tostring(ownerCid) or nil
    if not familyId then return {} end

    -- Shared cars are visible to every member. Private cars are included only
    -- for their actual owner so the family menu can offer an explicit Share
    -- toggle without leaking another player's vehicle list.
    return MySQL.query.await([[
        SELECT v.*, s.house_id, s.slot_index, s.owner_class, h.label AS house_label,
               CASE WHEN sh.vehicle_id IS NULL THEN 0 ELSE 1 END AS shared,
               CASE WHEN h.family_id = ? THEN 1 ELSE 0 END AS family_house_eligible
        FROM cm_owned_vehicles v
        LEFT JOIN cm_house_vehicle_slots s ON s.vehicle_id = v.id
        LEFT JOIN cm_houses h ON h.id = s.house_id
        LEFT JOIN cm_house_shared_vehicles sh ON sh.vehicle_id = v.id AND sh.house_id = h.id
        WHERE CAST(v.owner_character_id AS CHAR) = ?
           OR (h.family_id = ? AND sh.vehicle_id IS NOT NULL)
        ORDER BY shared DESC, family_house_eligible DESC, v.plate
    ]], { familyId, ownerCid or '', familyId }) or {}
end

function P2.GetFamilyVehicles(familyId)
    familyId = tonumber(familyId)
    if not familyId then return {} end
    return MySQL.query.await([[
        SELECT v.*, s.house_id, s.slot_index, s.owner_class, h.label AS house_label
        FROM cm_house_vehicle_slots s
        INNER JOIN cm_houses h ON h.id = s.house_id
        INNER JOIN cm_owned_vehicles v ON v.id = s.vehicle_id
        WHERE h.family_id = ? AND s.owner_class = 'family'
        ORDER BY s.house_id, s.slot_index
    ]], { familyId }) or {}
end

function P2.GetHousesForCharacter(cid)
    cid = tonumber(cid) or cid
    if not cid then return {} end
    local result = {}
    for _, house in pairs(Houses) do
        local allowed = CanAccessProperty(cid, house.id, ACTIONS.HOUSE_ENTER, false)
        if allowed then
            local copy = {}
            for key, value in pairs(house) do copy[key] = value end
            copy.access_kind = tonumber(house.owner_cid) == tonumber(cid) and 'owner' or 'family'
            result[#result + 1] = copy
        end
    end
    table.sort(result, function(a, b) return tonumber(a.id) > tonumber(b.id) end)
    return result
end

exports('SetVehicleFamilyShared', P2.SetVehicleFamilyShared)
exports('GetFamilyVehicles', P2.GetFamilyVehicles)
exports('GetFamilyVehicleManagementList', P2.GetFamilyVehicleManagementList)
exports('GetHousesForCharacter', P2.GetHousesForCharacter)
exports('GetPropertyPermissionCatalog', function()
    return { permissions = Config.Permissions, ownerOnly = Config.OwnerOnly, actions = ACTIONS }
end)


-- cm-inventory may call this after a committed general-storage item movement.
-- It is intentionally a server export (not a net event) and validates that the
-- supplied house is still linked to the supplied family before writing audit.
exports('AuditFamilyStorageTransfer', function(houseId, familyId, actorCid, direction, itemName, quantity, storageIndex, metadata)
    local invoker = GetInvokingResource()
    if invoker ~= 'cm-inventory' and invoker ~= GetCurrentResourceName() then
        return false, 'resource_not_authorized'
    end
    houseId, familyId = tonumber(houseId), tonumber(familyId)
    local house = houseId and Houses[houseId] or nil
    if not house or not familyId or tonumber(house.family_id) ~= familyId then
        return false, 'family_house_mismatch'
    end
    direction = tostring(direction or ''):lower()
    if direction ~= 'deposit' and direction ~= 'withdraw' then return false, 'invalid_direction' end
    local detail = type(metadata) == 'table' and metadata or {}
    detail.item = tostring(itemName or ''):sub(1, 96)
    detail.quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    detail.point = tonumber(storageIndex)
    LogHouse(houseId, familyId, actorCid, 'storage_' .. direction, detail)
    return true
end)
