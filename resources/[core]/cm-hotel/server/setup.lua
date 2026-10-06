CMHotelSetup = CMHotelSetup or {}

local RESOURCE = GetCurrentResourceName()
local SETUP_PERMISSION = 'hotel.setup'
local SESSION_LIFETIME_MS = 30 * 60 * 1000
local sessions = {}
local saved = {}
local runtime = {}

local function finite(value)
    local result = tonumber(value)
    if not result or result ~= result or result == math.huge or result == -math.huge then return nil end
    return result
end

local function cleanModel(value)
    if type(value) ~= 'string' then return nil end
    value = value:lower():gsub('%s+', ''):sub(1, 64)
    if value == '' or not value:match('^[%w_%-]+$') then return nil end
    return value
end

local function readPoint(value, withHeading)
    if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'vector4' then return nil end
    local x = finite(value.x or value[1])
    local y = finite(value.y or value[2])
    local z = finite(value.z or value[3])
    local w = finite(value.w or value.heading or value.h or value[4] or 0.0) or 0.0
    if not x or not y or not z then return nil end
    if x < -10000 or x > 10000 or y < -10000 or y > 10000 or z < -1000 or z > 5000 then return nil end
    if withHeading and (w < -360 or w > 360) then return nil end
    return {
        x = x,
        y = y,
        z = z,
        w = withHeading and w or nil
    }
end

local function pointCopy(point, withHeading)
    local value = readPoint(point, withHeading)
    if not value then return nil end
    if not withHeading then value.w = nil end
    return value
end

local function choosePoint(savedPoint, fallbackPoint, withHeading)
    return pointCopy(savedPoint, withHeading) or pointCopy(fallbackPoint, withHeading)
end

local function chooseConfigPoint(configPoint, savedPoint, withHeading)
    return pointCopy(configPoint, withHeading) or pointCopy(savedPoint, withHeading)
end

local function getNested(root, key)
    return type(root) == 'table' and type(root[key]) == 'table' and root[key] or nil
end

local function loadSaved()
    local raw = LoadResourceFile(RESOURCE, 'data/hotel_setup.json')
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then
        print(('[CM-HOTEL] Ignoring invalid data/hotel_setup.json; Config fallback remains active.'))
        return {}
    end
    return decoded
end

local function configFloor(floors, id)
    for _, floor in ipairs(floors or {}) do
        if type(floor) == 'table' and tostring(floor.id or '') == id then return floor end
    end
    return nil
end

local function buildRuntime()
    local hotel = Config.Hotel or {}
    local receptionist = hotel.receptionist or {}
    local rental = hotel.rental or {}
    local helpConfig = Config.HelpLocations or {}
    local savedHelp = getNested(saved, 'help') or {}
    local savedModels = getNested(saved, 'models') or {}
    local savedRental = getNested(saved, 'rental') or {}
    local savedNpc = getNested(saved, 'receptionist')
    local savedRentalNpc = getNested(saved, 'rentalNpc')
    local savedVehicleSpawn = saved.rentalVehicleSpawn or savedRental.vehicleSpawn
    local configLift = hotel.lifts and hotel.lifts.main or {}
    local savedLifts = getNested(saved, 'lifts') or {}

    local function model(configuredModel, savedModel)
        return cleanModel(configuredModel) or cleanModel(savedModel)
    end

    local function floor(id, fallbackLabel)
        local configured = configFloor(configLift.floors, id) or {}
        local stored = getNested(savedLifts, id) or {}
        local arrival = chooseConfigPoint(configured.arrival or configured.destination, stored.arrival or stored.destination, true)
        return {
            id = id,
            label = tostring(configured.label or fallbackLabel),
            interaction = chooseConfigPoint(configured.interaction, stored.interaction, true),
            arrival = arrival,
            destination = arrival,
            interactionDistance = configured.interactionDistance or configLift.interactionDistance
        }
    end

    local result = {
        enabled = hotel.enabled == true,
        firstSpawn = chooseConfigPoint(hotel.firstSpawn, saved.firstSpawn, true),
        receptionist = {
            model = model(receptionist.model, savedModels.receptionist or (savedNpc and savedNpc.model)),
            coords = chooseConfigPoint(receptionist.coords, savedNpc and savedNpc.coords, true),
            interactionDistance = receptionist.interactionDistance or 2.0
        },
        rental = {
            model = model(rental.model, savedModels.rental or (savedRentalNpc and savedRentalNpc.model)),
            coords = chooseConfigPoint(rental.coords, savedRentalNpc and savedRentalNpc.coords, true),
            vehicleSpawn = chooseConfigPoint(rental.vehicleSpawn, savedVehicleSpawn, true),
            interactionDistance = rental.interactionDistance or 2.0,
            returnDistance = rental.returnDistance or 12.0
        },
        lifts = {
            main = {
                label = tostring(configLift.label or 'Hotel Elevator'),
                floors = {
                    floor('rooms', 'Hotel Rooms'),
                    floor('lobby', 'Ground Floor')
                }
            }
        },
        help = {},
        blip = {
            enabled = Config.Blip and Config.Blip.enabled == true,
            sprite = Config.Blip and Config.Blip.sprite,
            colour = Config.Blip and Config.Blip.colour,
            scale = Config.Blip and Config.Blip.scale,
            coords = choosePoint(saved.blip, Config.Blip and Config.Blip.coords, false)
        }
    }

    for _, key in ipairs({ 'rental', 'license', 'jobCentre', 'hospital', 'bank', 'clothingStore' }) do
        local fallback = helpConfig[key]
        if key == 'rental' then fallback = fallback or result.rental.coords end
        result.help[key] = choosePoint(savedHelp[key], fallback, false)
    end

    return result
end

local function statusFor()
    local rooms = runtime.lifts.main.floors[1]
    local lobby = runtime.lifts.main.floors[2]
    return {
        firstSpawn = runtime.firstSpawn ~= nil,
        receptionist = runtime.receptionist.coords ~= nil and runtime.receptionist.model ~= nil,
        rentalNpc = runtime.rental.coords ~= nil and runtime.rental.model ~= nil,
        rentalNpcPosition = runtime.rental.coords ~= nil,
        rentalNpcModel = runtime.rental.model ~= nil,
        rentalVehicleSpawn = runtime.rental.vehicleSpawn ~= nil,
        liftRooms = rooms.interaction ~= nil and rooms.destination ~= nil,
        liftLobby = lobby.interaction ~= nil and lobby.destination ~= nil,
        license = runtime.help.license ~= nil,
        jobCentre = runtime.help.jobCentre ~= nil,
        hospital = runtime.help.hospital ~= nil,
        blip = runtime.blip.coords ~= nil
    }
end

local function runtimePayload()
    local options = {}
    for _, option in ipairs(Config.RentalVehicles or {}) do
        if type(option) == 'table' and cleanModel(option.model) then
            options[#options + 1] = {
                id = tostring(option.id or ''),
                label = tostring(option.label or option.id or 'Rental'),
                model = cleanModel(option.model)
            }
        end
    end
    return {
        setup = runtime,
        status = statusFor(),
        rentalModels = options
    }
end

local function writeSaved()
    local encoded = json.encode(saved or {})
    if not encoded then return false end
    local ok = pcall(function()
        SaveResourceFile(RESOURCE, 'data/hotel_setup.json', encoded, -1)
    end)
    return ok
end

local function reloadSetup(broadcast)
    saved = loadSaved()
    runtime = buildRuntime()
    if broadcast then
        TriggerClientEvent('cm-hotel:client:setupUpdated', -1, runtimePayload())
        TriggerEvent('cm-hotel:server:setupReloaded', runtimePayload())
    end
end

local function canSetup(src)
    src = tonumber(src) or 0
    if src <= 0 then return true end
    if GetResourceState('cm-admin') ~= 'started' then return false end
    local ok, allowed = pcall(function()
        return exports['cm-admin']:HasPermission(src, SETUP_PERMISSION)
    end)
    return ok and allowed == true
end

local function notify(src, message, notifyType)
    if src and src > 0 and GetResourceState('cm-core') == 'started' then
        pcall(function() exports['cm-core']:Notify(src, message, notifyType or 'error', 4500) end)
    elseif src and src > 0 then
        TriggerClientEvent('chat:addMessage', src, { args = { 'CM HOTEL', message } })
    end
end

local function token(src)
    return ('hotel-setup:%s:%s'):format(tostring(src), tostring(GetGameTimer()))
end

local function sessionValid(src, supplied)
    local session = sessions[src]
    if not session or session.token ~= supplied or GetGameTimer() > session.expiresAt then return false end
    if not canSetup(src) then sessions[src] = nil return false end
    session.expiresAt = GetGameTimer() + SESSION_LIFETIME_MS
    return true
end

local function logAction(src, action, data)
    if GetResourceState('cm-admin') == 'started' then
        pcall(function() exports['cm-admin']:AddLog(src, action, data or {}) end)
    end
end

local function pointTarget(pointId)
    local vector4Points = {
        firstSpawn = true,
        receptionist = true,
        rentalNpc = true,
        rentalVehicleSpawn = true,
        liftRoomsInteraction = true,
        liftRoomsArrival = true,
        liftLobbyInteraction = true,
        liftLobbyArrival = true
    }
    local xyzPoints = { license = true, jobCentre = true, hospital = true, blip = true }
    if vector4Points[pointId] then return true end
    if xyzPoints[pointId] then return false end
    return nil
end

local function savePoint(pointId, coords)
    local withHeading = pointTarget(pointId)
    if withHeading == nil then return false end
    local point = readPoint(coords, withHeading)
    if not point then return false end

    if pointId == 'firstSpawn' then saved.firstSpawn = point
    elseif pointId == 'receptionist' then saved.receptionist = { coords = point }
    elseif pointId == 'rentalNpc' then saved.rentalNpc = { coords = point }
    elseif pointId == 'rentalVehicleSpawn' then saved.rentalVehicleSpawn = point
    elseif pointId == 'license' or pointId == 'jobCentre' or pointId == 'hospital' then
        saved.help = saved.help or {}; saved.help[pointId] = point
    elseif pointId == 'blip' then saved.blip = point
    elseif pointId == 'liftRoomsInteraction' or pointId == 'liftRoomsArrival' or pointId == 'liftLobbyInteraction' or pointId == 'liftLobbyArrival' then
        local floorId = pointId:find('Rooms') and 'rooms' or 'lobby'
        local field = pointId:find('Interaction') and 'interaction' or 'arrival'
        saved.lifts = saved.lifts or {}; saved.lifts[floorId] = saved.lifts[floorId] or {}; saved.lifts[floorId][field] = point
    end
    return writeSaved()
end

local function saveModel(kind, model)
    if kind ~= 'receptionist' and kind ~= 'rental' then return false end
    model = cleanModel(model)
    if not model then return false end
    saved.models = saved.models or {}
    saved.models[kind] = model
    return writeSaved()
end

function CMHotelSetup.GetRuntime()
    return runtime
end

function CMHotelSetup.GetPayload()
    return runtimePayload()
end

function CMHotelSetup.IsSessionValid(src, supplied)
    return sessionValid(src, supplied)
end

function CMHotelSetup.Permission(src)
    return canSetup(src)
end

exports('GetHotelSetup', function()
    return runtimePayload().setup
end)

exports('GetHotelSetupStatus', function()
    return statusFor()
end)

RegisterCommand('hotelsetup', function(src)
    src = tonumber(src) or 0
    if src <= 0 then print('[CM-HOTEL] /hotelsetup must be used in-game.') return end
    if not canSetup(src) then notify(src, 'NO PERMISSION: HOTEL SETUP', 'error') return end
    local setupToken = token(src)
    sessions[src] = { token = setupToken, expiresAt = GetGameTimer() + SESSION_LIFETIME_MS }
    TriggerClientEvent('cm-hotel:client:setupOpen', src, { token = setupToken, data = runtimePayload() })
    logAction(src, 'hotel_setup_opened', {})
end, false)

RegisterCommand('hotelstatus', function(src)
    src = tonumber(src) or 0
    if not canSetup(src) then
        if src > 0 then notify(src, 'NO PERMISSION: HOTEL SETUP', 'error') end
        return
    end
    local status = statusFor()
    local message = ('FIRST SPAWN=%s RECEPTION=%s RENTAL NPC POS=%s RENTAL NPC MODEL=%s VEHICLE=%s LIFT ROOMS=%s LIFT LOBBY=%s LICENSE=%s JOB=%s HOSPITAL=%s BLIP=%s'):format(
        status.firstSpawn and 'READY' or 'MISSING', status.receptionist and 'READY' or 'MISSING',
        status.rentalNpcPosition and 'READY' or 'MISSING', status.rentalNpcModel and 'READY' or 'MISSING',
        status.rentalVehicleSpawn and 'READY' or 'MISSING',
        status.liftRooms and 'READY' or 'MISSING', status.liftLobby and 'READY' or 'MISSING',
        status.license and 'READY' or 'MISSING', status.jobCentre and 'READY' or 'MISSING',
        status.hospital and 'READY' or 'MISSING', status.blip and 'READY' or 'MISSING')
    print('[CM-HOTEL] ' .. message)
    if src > 0 then notify(src, message, 'inform') end
end, false)

RegisterNetEvent('cm-hotel:server:requestSetup', function()
    TriggerClientEvent('cm-hotel:client:setupUpdated', source, runtimePayload())
end)

RegisterNetEvent('cm-hotel:server:setupClose', function(supplied)
    local src = source
    if sessionValid(src, supplied) then sessions[src] = nil end
end)

RegisterNetEvent('cm-hotel:server:setupSave', function(supplied, pointId, coords)
    local src = source
    if not sessionValid(src, supplied) then notify(src, 'HOTEL SETUP SESSION EXPIRED', 'error') return end
    pointId = type(pointId) == 'string' and pointId:sub(1, 64) or ''
    if not savePoint(pointId, coords) then notify(src, 'INVALID HOTEL SETUP POSITION', 'error') return end
    reloadSetup(true)
    TriggerClientEvent('cm-hotel:client:setupSaved', src, { ok = true, point = pointId, data = runtimePayload() })
    logAction(src, 'hotel_setup_point_saved', { point = pointId })
end)

RegisterNetEvent('cm-hotel:server:setupSaveModel', function(supplied, kind, model)
    local src = source
    if not sessionValid(src, supplied) then notify(src, 'HOTEL SETUP SESSION EXPIRED', 'error') return end
    if not saveModel(kind, model) then notify(src, 'INVALID HOTEL NPC MODEL', 'error') return end
    reloadSetup(true)
    TriggerClientEvent('cm-hotel:client:setupSaved', src, { ok = true, model = kind, data = runtimePayload() })
    logAction(src, 'hotel_setup_model_saved', { modelType = kind })
end)

RegisterNetEvent('cm-hotel:server:setupReset', function(supplied)
    local src = source
    if not sessionValid(src, supplied) then notify(src, 'HOTEL SETUP SESSION EXPIRED', 'error') return end
    saved = {}
    if not writeSaved() then notify(src, 'HOTEL SETUP RESET FAILED', 'error') return end
    reloadSetup(true)
    TriggerClientEvent('cm-hotel:client:setupReset', src, { ok = true, data = runtimePayload() })
    logAction(src, 'hotel_setup_reset', {})
end)

RegisterNetEvent('cm-hotel:server:setupPreviewNpc', function(supplied, kind)
    local src = source
    if not sessionValid(src, supplied) then return end
    local definition = kind == 'receptionist' and runtime.receptionist or kind == 'rental' and runtime.rental or nil
    if not definition or not definition.model or not definition.coords then
        notify(src, 'SAVE THE NPC MODEL AND POSITION FIRST', 'error')
        return
    end
    TriggerClientEvent('cm-hotel:client:setupPreviewNpc', src, { model = definition.model, coords = definition.coords })
end)

RegisterNetEvent('cm-hotel:server:setupPreviewVehicle', function(supplied, optionId)
    local src = source
    if not sessionValid(src, supplied) then return end
    if not runtime.rental.vehicleSpawn then notify(src, 'SAVE THE RENTAL VEHICLE SPAWN FIRST', 'error') return end
    local selected = nil
    for _, option in ipairs(Config.RentalVehicles or {}) do
        if type(option) == 'table' and tostring(option.id or '') == tostring(optionId or '') and cleanModel(option.model) then selected = option break end
    end
    if not selected then
        for _, option in ipairs(Config.RentalVehicles or {}) do
            if type(option) == 'table' and cleanModel(option.model) then selected = option break end
        end
    end
    if not selected then notify(src, 'CONFIGURE A RENTAL VEHICLE MODEL FIRST', 'error') return end
    TriggerClientEvent('cm-hotel:client:setupPreviewVehicle', src, {
        model = cleanModel(selected.model),
        coords = runtime.rental.vehicleSpawn
    })
end)

RegisterNetEvent('cm-hotel:server:setupTestWaypoint', function(supplied, pointId)
    local src = source
    if not sessionValid(src, supplied) then return end
    if pointId ~= 'license' and pointId ~= 'jobCentre' and pointId ~= 'hospital' then return end
    local coords = runtime.help[pointId]
    if not coords then notify(src, 'SAVE THIS HELP LOCATION FIRST', 'error'); return end
    TriggerClientEvent('cm-hotel:client:setupTestWaypoint', src, { point = pointId, coords = coords })
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
end)

reloadSetup(false)
