-- CM License System — Admin Setup System

Admin = {}
Admin.Sessions = {}

-- Check admin permission
function Admin.HasPermission(src, permission)
    if src == 0 then return true end  -- Console
    return exports['cm-admin']:HasPermission(src, permission)
end

-- List all license types
function Admin.GetAllLicenseTypes()
    return MySQL.query.await([[SELECT lt.*,
        (SELECT COUNT(*) FROM cm_license_checkpoints cp JOIN cm_license_routes r ON r.id=cp.route_id WHERE r.license_type_id=lt.id) checkpoint_count,
        EXISTS(SELECT 1 FROM cm_license_routes r WHERE r.license_type_id=lt.id) route_configured
        FROM cm_license_types lt ORDER BY lt.label]]) or {}
end

local function cleanText(value, maxLength, pattern)
    local text = tostring(value or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, maxLength)
    if pattern and not text:match(pattern) then return nil end
    return text ~= '' and text or nil
end

local function normalizeTypeData(data)
    data = type(data) == 'table' and data or {}
    local category = tostring(data.vehicle_category or ''):lower()
    if category ~= 'ground' and category ~= 'boat' and category ~= 'air' then return nil, 'invalid_vehicle_category' end
    local normalized = {
        license_type = cleanText(data.license_type, 50, '^[a-z][a-z0-9_]*$'),
        label = cleanText(data.label, 100),
        item_name = cleanText(data.item_name, 50, '^[a-z0-9_]+$'),
        price = math.floor(tonumber(data.price) or -1),
        valid_days = math.floor(tonumber(data.valid_days) or 0),
        vehicle_model = cleanText(data.vehicle_model, 50, '^[%w_]+$'),
        vehicle_category = category,
        npc_model = cleanText(data.npc_model, 50, '^[%w_]+$'),
        enabled = data.enabled ~= false,
    }
    if not normalized.license_type or not normalized.label or not normalized.item_name or not normalized.vehicle_model
        or normalized.price < 0 or normalized.price > 10000000 or normalized.valid_days < 1 or normalized.valid_days > 3650 then
        return nil, 'invalid_test_details'
    end
    local item = exports['cm-items']:GetItem(normalized.item_name, true)
    if type(item) ~= 'table' then return nil, 'inventory_item_not_found' end
    return normalized
end

-- Create new license type
function Admin.CreateLicenseType(data)
    data = type(data) == 'table' and data or {}
    local normalized, validationError = normalizeTypeData(data)
    if not normalized then return false, validationError end
    
    local result = MySQL.insert.await(
        'INSERT INTO cm_license_types (license_type, label, item_name, price, valid_days, vehicle_model, vehicle_category, npc_model, npc_coords, enabled) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {
            normalized.license_type, normalized.label, normalized.item_name, normalized.price,
            normalized.valid_days, normalized.vehicle_model, normalized.vehicle_category, normalized.npc_model,
            data.npc_coords and json.encode(data.npc_coords) or nil,
            normalized.enabled
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
    local normalized, validationError = normalizeTypeData(data)
    if not normalized then return false, validationError end
    local fields = {}
    local values = {}
    local allowed = { license_type=true, label=true, item_name=true, price=true, valid_days=true,
        vehicle_model=true, vehicle_category=true, npc_model=true, enabled=true, npc_coords=true }
    for key, value in pairs(normalized) do
        if allowed[key] then
            table.insert(fields, key .. ' = ?')
            table.insert(values, value)
        end
    end
    if type(data.npc_coords) == 'table' then
        local value = data.npc_coords
        if not Utils.IsValidCoords(value) then return false, 'invalid_npc_coords' end
        table.insert(fields, 'npc_coords = ?')
        table.insert(values, json.encode(value))
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
    local used = MySQL.scalar.await('SELECT COUNT(*) FROM cm_character_licenses WHERE license_type_id = ?', { typeId }) or 0
    if tonumber(used) > 0 then return false, 'license_type_in_use' end
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

function Admin.SaveFullRoute(licenseTypeId, vehicleSpawn, checkpoints)
    licenseTypeId = tonumber(licenseTypeId)
    if not licenseTypeId or not Utils.IsValidCoords(vehicleSpawn) or type(checkpoints) ~= 'table' or #checkpoints < 2 then
        return false, 'invalid_route'
    end
    if #checkpoints > 500 then return false, 'too_many_checkpoints' end
    local statements = {}
    local route = Cache.GetRoute(licenseTypeId)
    local routeId = route and tonumber(route.id) or nil
    if routeId then
        statements[#statements+1] = { query='UPDATE cm_license_routes SET vehicle_spawn=?,updated_at=NOW() WHERE id=?', values={json.encode(vehicleSpawn),routeId} }
        statements[#statements+1] = { query='DELETE FROM cm_license_checkpoints WHERE route_id=?', values={routeId} }
    else
        routeId = MySQL.insert.await('INSERT INTO cm_license_routes (license_type_id,vehicle_spawn) VALUES (?,?)', {licenseTypeId,json.encode(vehicleSpawn)})
        if not routeId then return false, 'route_create_failed' end
    end
    for sequence, cp in ipairs(checkpoints) do
        if not Utils.IsValidCoords(cp) then return false, 'invalid_checkpoint' end
        local pointType = sequence == 1 and 'start' or sequence == #checkpoints and 'finish' or 'checkpoint'
        statements[#statements+1] = { query=[[INSERT INTO cm_license_checkpoints
            (route_id,sequence,point_type,x,y,z,heading,radius,max_speed,min_altitude,max_altitude,metadata)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)]], values={routeId,sequence,pointType,cp.x,cp.y,cp.z,cp.heading or 0,
            math.max(2,math.min(tonumber(cp.radius) or 20,100)),tonumber(cp.max_speed),tonumber(cp.min_altitude),tonumber(cp.max_altitude),json.encode(cp.metadata or {})} }
    end
    local ok = #statements == 0 or MySQL.transaction.await(statements)
    if ok then Cache.InvalidateLicenseType(licenseTypeId) end
    return ok == true, ok == true and routeId or 'route_save_failed'
end

local function entityCoords(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local coords = GetEntityCoords(entity)
    return { x=coords.x+0.0, y=coords.y+0.0, z=coords.z+0.0, heading=GetEntityHeading(entity)+0.0 }
end

function Admin.BeginBuilder(src, licenseTypeId)
    licenseTypeId = tonumber(licenseTypeId)
    local licenseType = licenseTypeId and Cache.GetLicenseType(licenseTypeId) or nil
    if not licenseType or not licenseType.vehicle_model then return false, 'license_type_not_found' end
    Admin.CancelBuilder(src)
    local ped = GetPlayerPed(src)
    local coords = entityCoords(ped)
    if not coords then return false, 'player_position_unavailable' end
    -- GetEntityForwardVector is client-only on this runtime. Derive the
    -- forward offset from the authoritative server-side ped heading.
    local radians = math.rad(coords.heading or 0.0)
    coords.x = coords.x + (-math.sin(radians) * 5.0)
    coords.y = coords.y + (math.cos(radians) * 5.0)
    local kind = licenseType.vehicle_category == 'boat' and 'boat'
        or licenseType.vehicle_category == 'air' and 'helicopter' or 'car'
    local result = exports['cm-vehicles']:SpawnAdminVehicle(src, licenseType.vehicle_model, coords, {
        placementKind=kind, warp=true, invincible=false, label='License route builder'
    })
    if type(result) ~= 'table' or result.ok ~= true then return false, result and result.error or 'preview_spawn_failed' end
    Admin.Sessions[src] = { licenseTypeId=licenseTypeId, entity=result.entity, netId=result.netId,
        plate=result.plate, stage='vehicle_spawn', checkpoints={} }
    return true, { netId=result.netId, stage='vehicle_spawn', licenseTypeId=licenseTypeId }
end

function Admin.BuilderAction(src, action)
    local session = Admin.Sessions[src]
    if not session then return false, 'no_builder_session' end
    local ped = GetPlayerPed(src)
    local vehicle = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if vehicle == 0 or vehicle ~= tonumber(session.entity) then return false, 'enter_builder_vehicle' end
    local point = entityCoords(vehicle)
    if not point then return false, 'vehicle_unavailable' end
    if action == 'save_spawn' and session.stage == 'vehicle_spawn' then
        session.vehicleSpawn, session.stage = point, 'route'
        return true, { stage='route', count=0, message='Vehicle spawn saved. Drive to the route start and press E.' }
    elseif action == 'add_point' and session.stage == 'route' then
        session.checkpoints[#session.checkpoints+1] = point
        return true, { stage='route', count=#session.checkpoints, message=#session.checkpoints == 1 and 'Start point saved.' or ('Checkpoint %d saved.'):format(#session.checkpoints-1) }
    elseif action == 'undo' and session.stage == 'route' then
        if #session.checkpoints > 0 then table.remove(session.checkpoints) end
        return true, { stage='route', count=#session.checkpoints, message='Last route point removed.' }
    elseif action == 'finish' and session.stage == 'route' then
        if #session.checkpoints < 1 then return false, 'set_start_first' end
        session.checkpoints[#session.checkpoints+1] = point
        local ok, result = Admin.SaveFullRoute(session.licenseTypeId, session.vehicleSpawn, session.checkpoints)
        if not ok then table.remove(session.checkpoints); return false, result end
        local preview = { vehicleSpawn=session.vehicleSpawn, checkpoints=session.checkpoints }
        Admin.CancelBuilder(src)
        return true, { stage='complete', count=#preview.checkpoints, preview=preview, message='Route saved.' }
    end
    return false, 'invalid_builder_action'
end

function Admin.CancelBuilder(src)
    local session = Admin.Sessions[src]
    if not session then return true end
    if session.plate then pcall(function() exports['cm-vehicles']:DeleteAdminVehicle(session.plate) end) end
    Admin.Sessions[src] = nil
    return true
end

function Admin.SaveNpcAtPlayer(src, licenseTypeId, model, scenario)
    local coords = entityCoords(GetPlayerPed(src))
    model = cleanText(model, 50, '^[%w_]+$')
    scenario = cleanText(scenario, 80, '^[%w_]+$')
    if not coords or not model then return false, 'invalid_npc_configuration' end
    coords.scenario = scenario
    local affected = MySQL.update.await('UPDATE cm_license_types SET npc_model=?,npc_coords=?,updated_at=NOW() WHERE id=?',
        { model, json.encode(coords), tonumber(licenseTypeId) })
    if tonumber(affected) ~= 1 then return false, 'license_type_not_found' end
    Cache.InvalidateLicenseType(tonumber(licenseTypeId))
    return true, coords
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
    return Licenses.RevokeLicense(characterId, licenseTypeId, adminCharId, reason)
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
