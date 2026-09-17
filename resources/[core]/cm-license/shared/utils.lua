-- CM License System — Shared Utilities

Utils = {}

-- Convert timestamp to readable date string
function Utils.FormatDate(timestamp)
    timestamp = tonumber(timestamp)
    if not timestamp or timestamp == 0 then
        return 'Never'
    end
    return os.date('%d %B %Y', timestamp)
end

-- Calculate remaining days until expiration
function Utils.CalculateRemainingDays(expiresAt)
    expiresAt = tonumber(expiresAt)
    if not expiresAt then
        return 0
    end
    local secondsLeft = expiresAt - os.time()
    if secondsLeft <= 0 then
        return 0
    end
    return math.ceil(secondsLeft / 86400)
end

-- Check if license is expired
function Utils.IsExpired(expiresAt)
    expiresAt = tonumber(expiresAt)
    if not expiresAt then
        return true
    end
    return os.time() >= expiresAt
end

-- Calculate expiration timestamp from days
function Utils.CalculateExpiration(validDays)
    return os.time() + ((tonumber(validDays) or 30) * 86400)
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

-- Squared distance between a vector and a table of {x, y, z}
function Utils.DistanceSquared(coords, point)
    if not coords or not point then return math.huge end
    local dx = coords.x - point.x
    local dy = coords.y - point.y
    local dz = coords.z - point.z
    return (dx * dx) + (dy * dy) + (dz * dz)
end

-- Check if player is in range of coordinates
function Utils.IsPlayerNear(playerCoords, targetCoords, distance)
    return Utils.Distance(playerCoords, targetCoords) <= distance
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
    if type(coords) ~= 'table' then return false end
    return type(coords.x) == 'number' and type(coords.y) == 'number' and type(coords.z) == 'number'
end

-- Decode a value that may already be a table or may be a JSON string
function Utils.DecodeObject(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' then return nil end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or nil
end

-- The client touch radius for a vehicle category
function Utils.TouchRadius(category)
    local touch = CMLicenseConfig and CMLicenseConfig.Checkpoint and CMLicenseConfig.Checkpoint.Touch
    if not touch then return 4.0 end
    return touch[tostring(category or 'ground')] or touch.ground or 4.0
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

return Utils
