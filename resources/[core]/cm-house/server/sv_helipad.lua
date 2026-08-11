local helipadCalls = {}
local activeHelipadVehicles = {}

local function nearHelipad(src, house)
    local pad = house and house.helipad_coords
    local ped = GetPlayerPed(src)
    if not pad or not ped or ped == 0 or GetPlayerRoutingBucket(src) ~= 0 then return false end
    local ok, distance = pcall(function()
        return #(GetEntityCoords(ped) - vector3(pad.x, pad.y, pad.z))
    end)
    return ok and distance <= 8.0
end

local function isHelicopter(row)
    local kind = tostring(row.vehicle_type or ''):lower()
    if kind == 'heli' or kind == 'helicopter' then return true end
    if type(GetVehicleTypeFromName) == 'function' then
        local ok, resolved = pcall(GetVehicleTypeFromName, joaat(tostring(row.model or '')))
        return ok and tostring(resolved):lower() == 'heli'
    end
    return false
end

local function canUseHelipad(src, houseId)
    local cid = GetCid(src)
    local house = Houses[tonumber(houseId)]
    if not cid or not house or not house.helipad_coords then
        return false, 'This house has no helipad.', nil, nil
    end
    local allowed, why = CanAccessProperty(cid, house.id, ACTIONS.HELIPAD_USE)
    if not allowed then return false, why, nil, nil end
    if not nearHelipad(src, house) then return false, 'Stand on this house helipad.', nil, nil end
    return true, nil, cid, house
end

lib.callback.register('cm-house:server:visibleHelipads', function(src)
    local cid = GetCid(src)
    if not cid then return {} end

    local visible = {}
    for houseId, house in pairs(Houses) do
        if house.helipad_coords then
            local allowed = CanAccessProperty(cid, houseId, ACTIONS.HELIPAD_USE, false)
            if allowed == true then visible[#visible + 1] = tonumber(houseId) end
        end
    end
    return visible
end)

lib.callback.register('cm-house:server:helipadVehicles', function(src, houseId)
    local allowed, why, cid, house = canUseHelipad(src, houseId)
    if not allowed then return nil, why end

    local rows
    if house.family_id and GetResourceState('cm-family') == 'started' then
        rows = MySQL.query.await([[
            SELECT DISTINCT vehicle.*
            FROM cm_owned_vehicles vehicle
            LEFT JOIN cm_family_vehicle_access family_vehicle
              ON family_vehicle.vehicle_id = vehicle.id AND family_vehicle.family_id = ?
            LEFT JOIN cm_house_vehicle_slots family_slot
              ON family_slot.vehicle_id = vehicle.id
             AND family_slot.house_id = ? AND family_slot.owner_class = 'family'
            WHERE vehicle.owner_character_id = ?
               OR family_vehicle.vehicle_id IS NOT NULL
               OR family_slot.vehicle_id IS NOT NULL
            ORDER BY vehicle.id DESC
            LIMIT 200
        ]], { tonumber(house.family_id), tonumber(house.id), tostring(cid) }) or {}
    else
        rows = MySQL.query.await([[
            SELECT * FROM cm_owned_vehicles
            WHERE owner_character_id = ?
            ORDER BY id DESC
            LIMIT 200
        ]], { tostring(cid) }) or {}
    end

    local vehicles = {}
    for _, row in ipairs(rows) do
        if isHelicopter(row) then
            local canDrive, accessKind = exports['cm-vehicles']:CanUseVehicle(src, tonumber(row.id), 'vehicle.drive')
            if canDrive == true then
                vehicles[#vehicles + 1] = {
                    id = tonumber(row.id), plate = tostring(row.plate or ''),
                    model = tostring(row.model or ''), label = tostring(row.label or row.model or 'Helicopter'),
                    family = tostring(row.owner_character_id) ~= tostring(cid) or accessKind == 'family',
                }
            end
        end
    end
    return vehicles
end)

lib.callback.register('cm-house:server:callHelicopter', function(src, houseId, vehicleId)
    local allowed, why, cid, house = canUseHelipad(src, houseId)
    if not allowed then return false, why end
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return false, 'Invalid helicopter.' end

    local now = os.time()
    if helipadCalls[src] and now - helipadCalls[src] < 5 then
        return false, 'Please wait before calling another helicopter.'
    end

    local canDrive, _, row = exports['cm-vehicles']:CanUseVehicle(src, vehicleId, 'vehicle.drive')
    if canDrive ~= true or type(row) ~= 'table' then return false, 'You cannot use that helicopter.' end
    if not isHelicopter(row) then return false, 'Only helicopters can use this helipad.' end
    if activeHelipadVehicles[vehicleId] then return false, 'That helicopter is already being called.' end

    helipadCalls[src] = now
    activeHelipadVehicles[vehicleId] = true
    local pad = house.helipad_coords
    local okCall, ok, message = pcall(function()
        return exports['cm-vehicles']:SpawnVehicleFromParking(src, vehicleId,
            ('house_helipad:%s'):format(house.id), pad, {
                allowAuthorizedAccess = true,
                unlockOnRetrieve = true,
                engineOn = false,
                warp = false,
                vehicleType = 'heli',
            })
    end)
    activeHelipadVehicles[vehicleId] = nil
    if not okCall or ok ~= true then
        return false, tostring(message or ok or 'The helicopter could not be called.')
    end

    LogHouse(house.id, house.family_id, cid, 'heli_take', { vehicleId = vehicleId })
    return true, ('%s is ready on the helipad.'):format(tostring(row.label or row.model or 'Helicopter'))
end)

AddEventHandler('playerDropped', function()
    helipadCalls[source] = nil
end)
