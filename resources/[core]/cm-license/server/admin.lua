-- CM License System — Admin Setup System

local Database = require 'server.database'
local Cache = require 'server.cache'
local Constants = require 'shared.constants'
local Utils = require 'shared.utils'

local Admin = {}

-- Check admin permission
function Admin.HasPermission(src, permission)
    if src == 0 then return true end  -- Console
    return exports['cm-admin']:HasPermission(src, permission)
end

-- List all license types
function Admin.GetAllLicenseTypes()
    return Database.GetLicenseTypes()
end

-- Create new license type
function Admin.CreateLicenseType(data)
    if not data.license_type or not data.label or not data.item_name then
        return false, 'missing_required_fields'
    end

    local result = MySQL.insert.await(
        'INSERT INTO cm_license_types (license_type, label, item_name, price, valid_days, vehicle_model, vehicle_category, npc_model, npc_coords, enabled) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {
            data.license_type,
            data.label,
            data.item_name,
            data.price or 0,
            data.valid_days or 30,
            data.vehicle_model,
            data.vehicle_category,
            data.npc_model,
            data.npc_coords and json.encode(data.npc_coords) or nil,
            data.enabled ~= false
        }
    )

    if not result then
        return false, 'database_error'
    end

    Cache.Invalidate()
    return true, result
end

-- Update license type
function Admin.UpdateLicenseType(typeId, data)
    local fields = {}
    local values = {}

    for key, value in pairs(data or {}) do
        if key == 'npc_coords' then
            table.insert(fields, 'npc_coords = ?')
            table.insert(values, value and json.encode(value) or nil)
        elseif key ~= 'id' then
            table.insert(fields, key .. ' = ?')
            table.insert(values, value)
        end
    end

    table.insert(values, typeId)

    local query = 'UPDATE cm_license_types SET ' .. table.concat(fields, ', ') .. ', updated_at = NOW() WHERE id = ?'
    local ok = MySQL.update.await(query, values)

    if ok then
        Cache.InvalidateLicenseType(typeId)
    end

    return ok
end

-- Delete license type
function Admin.DeleteLicenseType(typeId)
    -- Check if route exists
    local route = Cache.GetRoute(typeId)
    if route then
        -- Delete route (cascade deletes checkpoints)
        MySQL.delete.await('DELETE FROM cm_license_routes WHERE license_type_id = ?', { typeId })
    end

    -- Delete license type
    local ok = MySQL.delete.await('DELETE FROM cm_license_types WHERE id = ?', { typeId })

    if ok then
        Cache.InvalidateLicenseType(typeId)
    end

    return ok
end

-- Create or update route
function Admin.SaveRoute(licenseTypeId, vehicleSpawn)
    if not licenseTypeId or not vehicleSpawn then
        return false, 'invalid_params'
    end

    -- Check if route exists
    local existingRoute = Cache.GetRoute(licenseTypeId)

    if existingRoute then
        -- Update existing route
        local ok = MySQL.update.await(
            'UPDATE cm_license_routes SET vehicle_spawn = ?, updated_at = NOW() WHERE license_type_id = ?',
            { json.encode(vehicleSpawn), licenseTypeId }
        )
        if ok then
            Cache.InvalidateLicenseType(licenseTypeId)
        end
        return ok
    else
        -- Create new route
        local result = MySQL.insert.await(
            'INSERT INTO cm_license_routes (license_type_id, vehicle_spawn) VALUES (?, ?)',
            { licenseTypeId, json.encode(vehicleSpawn) }
        )

        if result then
            Cache.InvalidateLicenseType(licenseTypeId)
        end

        return result
    end
end

-- Add checkpoint to route
function Admin.AddCheckpoint(routeId, pointType, coords, data)
    if not routeId or not pointType or not coords then
        return false, 'invalid_params'
    end

    -- Get next sequence number
    local lastCp = MySQL.single.await(
        'SELECT MAX(sequence) as max_seq FROM cm_license_checkpoints WHERE route_id = ?',
        { routeId }
    )

    local nextSeq = (lastCp and lastCp.max_seq or 0) + 1

    -- If this is a finish point, it goes at the end
    if pointType == Constants.CHECKPOINT_TYPE.FINISH then
        -- Check if finish already exists
        local existingFinish = MySQL.single.await(
            'SELECT id FROM cm_license_checkpoints WHERE route_id = ? AND point_type = "finish"',
            { routeId }
        )

        if existingFinish then
            return false, 'finish_already_exists'
        end
    end

    local result = MySQL.insert.await(
        'INSERT INTO cm_license_checkpoints (route_id, sequence, point_type, x, y, z, heading, radius, max_speed, min_altitude, max_altitude, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {
            routeId,
            nextSeq,
            pointType,
            coords.x,
            coords.y,
            coords.z,
            coords.heading or 0.0,
            data and data.radius or 20.0,
            data and data.max_speed or nil,
            data and data.min_altitude or nil,
            data and data.max_altitude or nil,
            data and json.encode(data.metadata) or nil
        }
    )

    return result, nextSeq
end

-- Update checkpoint
function Admin.UpdateCheckpoint(checkpointId, data)
    local fields = {}
    local values = {}

    for key, value in pairs(data or {}) do
        if key == 'metadata' then
            table.insert(fields, 'metadata = ?')
            table.insert(values, value and json.encode(value) or nil)
        elseif key ~= 'id' then
            table.insert(fields, key .. ' = ?')
            table.insert(values, value)
        end
    end

    table.insert(values, checkpointId)

    local query = 'UPDATE cm_license_checkpoints SET ' .. table.concat(fields, ', ') .. ', updated_at = NOW() WHERE id = ?'
    return MySQL.update.await(query, values)
end

-- Delete checkpoint
function Admin.DeleteCheckpoint(checkpointId)
    local checkpoint = Database.GetCheckpoint(checkpointId)
    if not checkpoint then
        return false, 'checkpoint_not_found'
    end

    -- Delete the checkpoint
    local ok = MySQL.delete.await('DELETE FROM cm_license_checkpoints WHERE id = ?', { checkpointId })

    if ok then
        -- Renumber remaining checkpoints
        Admin.RenumberCheckpoints(checkpoint.route_id)
    end

    return ok
end

-- Renumber checkpoints after deletion
function Admin.RenumberCheckpoints(routeId)
    local checkpoints = MySQL.query.await(
        'SELECT id FROM cm_license_checkpoints WHERE route_id = ? ORDER BY sequence',
        { routeId }
    )

    if not checkpoints then
        return false
    end

    for seq, cp in ipairs(checkpoints) do
        MySQL.update.await(
            'UPDATE cm_license_checkpoints SET sequence = ? WHERE id = ?',
            { seq, cp.id }
        )
    end

    return true
end

-- Get character's license history (admin view)
function Admin.GetCharacterLicenseHistory(characterId)
    return Database.GetCharacterLicenses(characterId)
end

-- Revoke license (admin)
function Admin.RevokeLicense(characterId, licenseTypeId, adminCharId, reason)
    return require('server.licenses').RevokeLicense(characterId, licenseTypeId, adminCharId, reason)
end

-- Validate admin action
function Admin.ValidateAdminAction(src, permission)
    if src == 0 then return true end

    local hasPerms = Admin.HasPermission(src, permission)
    if not hasPerms then
        TriggerClientEvent('chat:addMessage', src, {
            args = { 'License System', 'You do not have permission for this action' },
            color = { 255, 0, 0 }
        })
        return false
    end

    return true
end

-- Test route (admin can test without paying)
function Admin.TestRoute(adminCharId, licenseTypeId)
    -- Create a test session but skip payment
    local Tests = require 'server.tests'

    local session = Tests.ActiveSessions[adminCharId]
    if session then
        return false, 'already_in_test'
    end

    local licenseType = Cache.GetLicenseType(licenseTypeId)
    if not licenseType then
        return false, 'license_type_not_found'
    end

    local route = Cache.GetRoute(licenseTypeId)
    if not route then
        return false, 'route_not_configured'
    end

    local checkpoints = Cache.GetCheckpoints(route.id)
    if not checkpoints or #checkpoints == 0 then
        return false, 'route_not_configured'
    end

    -- Create test session
    local testId = Database.CreateTestSession(adminCharId, licenseTypeId, #checkpoints, 0)
    if not testId then
        return false, 'database_error'
    end

    Tests.ActiveSessions[adminCharId] = {
        testId = testId,
        licenseTypeId = licenseTypeId,
        characterId = adminCharId,
        isAdminTest = true,
        routeId = route.id,
        totalCheckpoints = #checkpoints,
        currentCheckpoint = 0,
        status = Constants.TEST_STATUS.WAITING_START,
        startedAt = os.time(),
        vehicleNetId = nil,
        mistakes = 0,
        maxMistakes = 0
    }

    return true, {
        testId = testId,
        vehicleModel = licenseType.vehicle_model,
        vehicleSpawn = route.vehicle_spawn
    }
end

return Admin
