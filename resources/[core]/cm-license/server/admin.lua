-- CM License System — Admin Setup System

Admin = {}
Admin.Sessions = {}

function Admin.HasPermission(src, permission)
    if src == 0 then return true end  -- Console
    return exports['cm-admin']:HasPermission(src, permission)
end

function Admin.ValidateAdminAction(src, permission)
    if src == 0 then return true end

    if not Admin.HasPermission(src, permission) then
        TriggerClientEvent('chat:addMessage', src, {
            args = { 'License System', 'You do not have permission for this action' },
            color = { 255, 0, 0 }
        })
        return false
    end

    return true
end

-- List all license types, including disabled ones, with route status.
function Admin.GetAllLicenseTypes()
    local rows = MySQL.query.await([[SELECT lt.*,
        (SELECT COUNT(*) FROM cm_license_checkpoints cp JOIN cm_license_routes r ON r.id=cp.route_id WHERE r.license_type_id=lt.id) checkpoint_count,
        (SELECT COUNT(*) FROM cm_license_routes r WHERE r.license_type_id=lt.id) route_count,
        (SELECT COUNT(*) FROM cm_license_routes r WHERE r.license_type_id=lt.id AND r.enabled=true) active_route_count
        FROM cm_license_types lt ORDER BY lt.label]]) or {}

    -- The instructor scenario lives inside npc_coords; surface it so the
    -- editor can show and round-trip it.
    for _, row in ipairs(rows) do
        local coords = Utils.DecodeObject(row.npc_coords)
        row.npc_scenario = coords and coords.scenario or nil
        row.npc_position = coords or nil
        row.route_configured = tonumber(row.active_route_count or 0) > 0
    end

    return rows
end

local function cleanText(value, maxLength, pattern)
    local text = tostring(value or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, maxLength)
    if pattern and not text:match(pattern) then return nil end
    return text ~= '' and text or nil
end

-- The NUI form uses camelCase field names; direct callers (and older payloads)
-- use the column names. Accept both.
local function field(data, columnName, camelName)
    local value = data[columnName]
    if value == nil then value = data[camelName] end
    return value
end

local CATEGORY_ALIASES = {
    ground = 'ground', car = 'ground', driver = 'ground',
    boat = 'boat',
    air = 'air', helicopter = 'air', airplane = 'air', plane = 'air',
}

local function normalizeTypeData(data)
    data = type(data) == 'table' and data or {}

    local category = CATEGORY_ALIASES[tostring(field(data, 'vehicle_category', 'vehicleCategory') or ''):lower()]
    if not category then return nil, 'invalid_vehicle_category' end

    local normalized = {
        license_type = cleanText(field(data, 'license_type', 'licenseType'), 50, '^[a-z][a-z0-9_]*$'),
        label = cleanText(data.label, 100),
        item_name = cleanText(field(data, 'item_name', 'itemName'), 50, '^[a-z0-9_]+$'),
        price = math.floor(tonumber(data.price) or -1),
        valid_days = math.floor(tonumber(field(data, 'valid_days', 'validDays')) or 0),
        vehicle_model = cleanText(field(data, 'vehicle_model', 'vehicleModel'), 50, '^[%w_]+$'),
        vehicle_category = category,
        npc_model = cleanText(field(data, 'npc_model', 'npcModel'), 50, '^[%w_]+$'),
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

-- Build the npc_coords JSON from an explicit coords payload plus a scenario.
local function npcCoordsJson(data, scenario)
    local coords = Utils.DecodeObject(field(data, 'npc_coords', 'npcCoords'))
    if not Utils.IsValidCoords(coords) then return nil end
    return json.encode({
        x = coords.x, y = coords.y, z = coords.z,
        heading = tonumber(coords.heading) or 0.0,
        scenario = scenario or coords.scenario,
    })
end

function Admin.CreateLicenseType(data)
    local normalized, validationError = normalizeTypeData(data)
    if not normalized then return false, validationError end

    local scenario = cleanText(field(data, 'npc_scenario', 'npcScenario'), 80, '^[%w_]+$')
    local result = MySQL.insert.await([[INSERT INTO cm_license_types
        (license_type, label, item_name, price, valid_days, vehicle_model, vehicle_category, npc_model, npc_coords, enabled)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        {
            normalized.license_type, normalized.label, normalized.item_name, normalized.price,
            normalized.valid_days, normalized.vehicle_model, normalized.vehicle_category, normalized.npc_model,
            npcCoordsJson(data, scenario), normalized.enabled
        })

    if not result then
        return false, 'database_error'
    end

    Cache.Invalidate()
    return true, result
end

function Admin.UpdateLicenseType(typeId, data)
    typeId = tonumber(typeId)
    if not typeId then return false, 'license_type_not_found' end

    local existing = Database.GetLicenseType(typeId)
    if not existing then return false, 'license_type_not_found' end

    local normalized, validationError = normalizeTypeData(data)
    if not normalized then return false, validationError end

    local fields, values = {}, {}
    for key, value in pairs(normalized) do
        fields[#fields + 1] = key .. ' = ?'
        values[#values + 1] = value
    end

    -- Keep the recorded instructor position; only replace it when the caller
    -- actually sent one. The scenario can be changed on its own.
    local scenario = cleanText(field(data, 'npc_scenario', 'npcScenario'), 80, '^[%w_]+$')
    local coordsJson = npcCoordsJson(data, scenario)
    if not coordsJson and scenario then
        local current = Utils.DecodeObject(existing.npc_coords)
        if current then
            current.scenario = scenario
            coordsJson = json.encode(current)
        end
    end
    if coordsJson then
        fields[#fields + 1] = 'npc_coords = ?'
        values[#values + 1] = coordsJson
    end

    values[#values + 1] = typeId
    local query = 'UPDATE cm_license_types SET ' .. table.concat(fields, ', ') .. ' WHERE id = ?'
    MySQL.update.await(query, values)

    -- An UPDATE that changes nothing reports zero affected rows, so success is
    -- judged by the row existing, not by the row count.
    Cache.Invalidate()
    return true, typeId
end

function Admin.DeleteLicenseType(typeId)
    typeId = tonumber(typeId)
    if not typeId then return false, 'license_type_not_found' end

    local used = MySQL.scalar.await('SELECT COUNT(*) FROM cm_character_licenses WHERE license_type_id = ?', { typeId }) or 0
    if tonumber(used) > 0 then return false, 'license_type_in_use' end

    -- Routes cascade from the type, but drop them first so a failed type
    -- delete does not leave a half-removed configuration behind.
    MySQL.query.await('DELETE FROM cm_license_routes WHERE license_type_id = ?', { typeId })

    local affected = MySQL.update.await('DELETE FROM cm_license_types WHERE id = ?', { typeId })
    if tonumber(affected or 0) <= 0 then
        return false, 'license_type_not_found'
    end

    Cache.Invalidate()
    return true
end

-- Records a NEW route for the type. Types may own several; the exam draws one
-- at random. Pass replaceRouteId to overwrite an existing one instead.
function Admin.SaveFullRoute(licenseTypeId, vehicleSpawn, checkpoints, label, replaceRouteId)
    licenseTypeId = tonumber(licenseTypeId)
    if not licenseTypeId or not Utils.IsValidCoords(vehicleSpawn) or type(checkpoints) ~= 'table' or #checkpoints < 2 then
        return false, 'invalid_route'
    end
    if #checkpoints > 500 then return false, 'too_many_checkpoints' end

    local bounds = CMLicenseConfig.Checkpoint
    local statements = {}
    local routeId = tonumber(replaceRouteId)

    if routeId then
        local existing = Database.GetRouteById(routeId)
        if not existing or tonumber(existing.license_type_id) ~= licenseTypeId then return false, 'route_not_found' end
        statements[#statements+1] = { query='UPDATE cm_license_routes SET vehicle_spawn=?, label=COALESCE(?, label) WHERE id=?', values={json.encode(vehicleSpawn),label,routeId} }
        statements[#statements+1] = { query='DELETE FROM cm_license_checkpoints WHERE route_id=?', values={routeId} }
    else
        local existingCount = #Database.GetRoutesWithCounts(licenseTypeId)
        label = label or ('Route %d'):format(existingCount + 1)
        routeId = Database.CreateRoute(licenseTypeId, label, vehicleSpawn)
        if not routeId then return false, 'route_create_failed' end
    end

    for sequence, cp in ipairs(checkpoints) do
        if not Utils.IsValidCoords(cp) then return false, 'invalid_checkpoint' end
        local pointType = sequence == 1 and 'start' or sequence == #checkpoints and 'finish' or 'checkpoint'
        local radius = math.max(bounds.MinRadius, math.min(tonumber(cp.radius) or bounds.DefaultRadius, bounds.MaxRadius))
        statements[#statements+1] = { query=[[INSERT INTO cm_license_checkpoints
            (route_id,sequence,point_type,x,y,z,heading,radius,max_speed,min_altitude,max_altitude,metadata)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)]], values={routeId,sequence,pointType,cp.x,cp.y,cp.z,cp.heading or 0,
            radius,tonumber(cp.max_speed),tonumber(cp.min_altitude),tonumber(cp.max_altitude),json.encode(cp.metadata or {})} }
    end

    local ok = MySQL.transaction.await(statements)
    if ok == true then Cache.Invalidate() end
    return ok == true, ok == true and routeId or 'route_save_failed'
end

function Admin.GetRoutes(licenseTypeId)
    licenseTypeId = tonumber(licenseTypeId)
    if not licenseTypeId then return {} end
    return Database.GetRoutesWithCounts(licenseTypeId)
end

function Admin.DeleteRoute(routeId)
    routeId = tonumber(routeId)
    local route = routeId and Database.GetRouteById(routeId)
    if not route then return false, 'route_not_found' end

    if not Database.DeleteRoute(routeId) then return false, 'route_not_found' end
    Cache.Invalidate()
    return true, tonumber(route.license_type_id)
end

function Admin.SetRouteEnabled(routeId, enabled)
    routeId = tonumber(routeId)
    local route = routeId and Database.GetRouteById(routeId)
    if not route then return false, 'route_not_found' end

    Database.SetRouteEnabled(routeId, enabled)
    Cache.Invalidate()
    return true, tonumber(route.license_type_id)
end

local function entityCoords(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local coords = GetEntityCoords(entity)
    return { x=coords.x+0.0, y=coords.y+0.0, z=coords.z+0.0, heading=GetEntityHeading(entity)+0.0 }
end

function Admin.BeginBuilder(src, licenseTypeId, replaceRouteId)
    licenseTypeId = tonumber(licenseTypeId)
    -- Read through the database, not the cache: a disabled type still needs a
    -- route before it can be turned on.
    local licenseType = licenseTypeId and Database.GetLicenseType(licenseTypeId) or nil
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
        plate=result.plate, stage='vehicle_spawn', checkpoints={}, replaceRouteId=tonumber(replaceRouteId) }
    return true, { netId=result.netId, stage='vehicle_spawn', licenseTypeId=licenseTypeId,
        replacing=tonumber(replaceRouteId), existingRoutes=#Database.GetRoutesWithCounts(licenseTypeId) }
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
        local ok, result = Admin.SaveFullRoute(session.licenseTypeId, session.vehicleSpawn, session.checkpoints,
            nil, session.replaceRouteId)
        if not ok then table.remove(session.checkpoints) return false, result end
        local count = #session.checkpoints
        local licenseTypeId = session.licenseTypeId
        Admin.CancelBuilder(src)
        local routes = Admin.GetRoutes(licenseTypeId)
        return true, { stage='complete', count=count, routeId=result, routeTotal=#routes,
            message=('Route saved. This test now has %d route(s).'):format(#routes) }
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
    licenseTypeId = tonumber(licenseTypeId)
    if not licenseTypeId or not Database.GetLicenseType(licenseTypeId) then return false, 'license_type_not_found' end

    local coords = entityCoords(GetPlayerPed(src))
    model = cleanText(model, 50, '^[%w_]+$') or CMLicenseConfig.NPC.Model
    scenario = cleanText(scenario, 80, '^[%w_]+$') or CMLicenseConfig.NPC.Scenario
    if not coords then return false, 'invalid_npc_configuration' end

    coords.scenario = scenario
    MySQL.update.await('UPDATE cm_license_types SET npc_model=?,npc_coords=? WHERE id=?',
        { model, json.encode(coords), licenseTypeId })

    Cache.Invalidate()
    return true, coords
end

-- Character license history (admin view)
function Admin.GetCharacterLicenseHistory(characterId)
    return Database.GetCharacterLicenses(characterId)
end

return Admin
