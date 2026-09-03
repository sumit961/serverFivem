-- CM License System — Shared Utilities

local Utils = {}

-- Convert timestamp to readable date string
function Utils.FormatDate(timestamp)
    if not timestamp or timestamp == 0 then
        return 'Never'
    end
    return os.date('%d %B %Y', timestamp)
end

-- Calculate remaining days until expiration
function Utils.CalculateRemainingDays(expiresAt)
    if not expiresAt then
        return 0
    end
    local now = os.time()
    local secondsLeft = expiresAt - now
    if secondsLeft <= 0 then
        return 0
    end
    return math.ceil(secondsLeft / 86400)
end

-- Check if license is expired
function Utils.IsExpired(expiresAt)
    if not expiresAt then
        return true
    end
    return os.time() >= expiresAt
end

-- Calculate expiration timestamp from days
function Utils.CalculateExpiration(validDays)
    return os.time() + (validDays * 86400)
end

-- Format money with commas
function Utils.FormatMoney(amount)
    if not amount then return '$0' end
    return '$' .. tostring(tonumber(amount) or 0):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

-- Get distance between two vectors
function Utils.Distance(v1, v2)
    if not v1 or not v2 then return 999999 end
    return #(v1 - v2)
end

-- Check if player is in range of coordinates
function Utils.IsPlayerNear(playerCoords, targetCoords, distance)
    return Utils.Distance(playerCoords, targetCoords) <= distance
end

-- Merge two tables
function Utils.MergeTables(t1, t2)
    local result = {}
    for k, v in pairs(t1 or {}) do
        result[k] = v
    end
    for k, v in pairs(t2 or {}) do
        result[k] = v
    end
    return result
end

-- Deep copy a table
function Utils.DeepCopy(t)
    if type(t) ~= 'table' then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = Utils.DeepCopy(v)
    end
    return copy
end

-- Table contains value
function Utils.TableContains(tbl, value)
    if not tbl then return false end
    for _, v in pairs(tbl) do
        if v == value then return true end
    end
    return false
end

-- Validate coordinates format
function Utils.IsValidCoords(coords)
    if not coords then return false end
    if type(coords) == 'table' then
        return coords.x and coords.y and coords.z and
               type(coords.x) == 'number' and
               type(coords.y) == 'number' and
               type(coords.z) == 'number'
    end
    return false
end

-- Get vehicle category from model
function Utils.GetVehicleCategory(modelName)
    -- This would need to be expanded with actual vehicle model lists
    -- For now, basic categorization
    local boatModels = {'dinghy', 'jetmax', 'speeder', 'tug', 'trash', 'trflat', 'tugboat', 'predator', 'seashark', 'squalo', 'coastguard'}
    local airModels = {'frogger', 'maverick', 'swift', 'annihilator', 'cargobob', 'buzzard', 'police_maverick', 'volatus', 'akula', 'hunter', 'lazer', 'jet', 'p996lazer', 'dodo', 'mallard', 'luxor', 'vestra', 'velum', 'shamal'}

    local model = string.lower(modelName or '')
    for _, boatModel in pairs(boatModels) do
        if string.find(model, boatModel) then
            return 'boat'
        end
    end

    for _, airModel in pairs(airModels) do
        if string.find(model, airModel) then
            return 'air'
        end
    end

    return 'ground'
end

-- Clamp number between min and max
function Utils.Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

-- Round number to decimal places
function Utils.Round(num, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- Generate unique ID
function Utils.GenerateId()
    return math.random(100000, 999999)
end

-- Check if player is in vehicle
function Utils.IsPlayerInVehicle(ped)
    return IsPedInAnyVehicle(ped, false)
end

-- Get player's current vehicle
function Utils.GetPlayerVehicle(ped)
    if not Utils.IsPlayerInVehicle(ped) then
        return nil
    end
    return GetVehiclePedIsIn(ped, false)
end

return Utils
