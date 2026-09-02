-- CM License System — Cache Management

Cache = {
    -- Cached data structures
    LicenseTypes = {},      -- All license types
    Routes = {},            -- Routes by license_type_id
    Checkpoints = {},       -- Checkpoints by route_id
    UpdatedAt = 0,          -- Last cache update time
    CacheTTL = 3600,        -- Cache TTL in seconds (1 hour)
}

-- Initialize cache from database
function Cache.Init()
    print('^2[CM-License]^7 Initializing cache...')
    Cache.Refresh()
    print('^2[CM-License]^7 Cache initialized with ' .. #Cache.LicenseTypes .. ' license types')
end

-- Refresh all cached data
function Cache.Refresh()
    -- Load all license types
    Cache.LicenseTypes = Database.GetLicenseTypes() or {}
    Cache.Routes = {}
    Cache.Checkpoints = {}
    
    -- Load routes and checkpoints
    for _, licenseType in ipairs(Cache.LicenseTypes) do
        local route = Database.GetRoute(licenseType.id)
        if route then
            Cache.Routes[licenseType.id] = route
            Cache.Checkpoints[route.id] = Database.GetCheckpoints(route.id) or {}
        end
    end
    
    Cache.UpdatedAt = os.time()
    print('^2[CM-License]^7 Cache refreshed')
end

-- Check if cache is stale
function Cache.IsStale()
    return (os.time() - Cache.UpdatedAt) > Cache.CacheTTL
end

-- Get all license types from cache
function Cache.GetLicenseTypes()
    if Cache.IsStale() then
        Cache.Refresh()
    end
    return Cache.LicenseTypes
end

-- Get license type by ID
function Cache.GetLicenseType(typeId)
    if Cache.IsStale() then
        Cache.Refresh()
    end
    
    for _, lt in ipairs(Cache.LicenseTypes) do
        if tonumber(lt.id) == tonumber(typeId) then
            return lt
        end
    end
    return nil
end

-- Get license type by license_type string (driver, boat, air)
function Cache.GetLicenseTypeByName(licenseType)
    if Cache.IsStale() then
        Cache.Refresh()
    end
    
    for _, lt in ipairs(Cache.LicenseTypes) do
        if tostring(lt.license_type):lower() == tostring(licenseType):lower() then
            return lt
        end
    end
    return nil
end

-- Get route for license type
function Cache.GetRoute(licenseTypeId)
    if Cache.IsStale() then
        Cache.Refresh()
    end
    return Cache.Routes[licenseTypeId]
end

-- Get checkpoints for route
function Cache.GetCheckpoints(routeId)
    if Cache.IsStale() then
        Cache.Refresh()
    end
    return Cache.Checkpoints[routeId] or {}
end

-- Get checkpoint by sequence
function Cache.GetCheckpointBySequence(routeId, sequence)
    local checkpoints = Cache.GetCheckpoints(routeId)
    for _, cp in ipairs(checkpoints) do
        if cp.sequence == sequence then
            return cp
        end
    end
    return nil
end

-- Invalidate cache (after admin changes)
function Cache.Invalidate()
    print('^3[CM-License]^7 Cache invalidated, will refresh on next access')
    Cache.UpdatedAt = 0
end

-- Invalidate specific license type cache
function Cache.InvalidateLicenseType(typeId)
    Cache.Routes[typeId] = nil
    -- Invalidate all to be safe
    Cache.Invalidate()
end

-- Add license type to cache
function Cache.AddLicenseType(licenseType)
    table.insert(Cache.LicenseTypes, licenseType)
    Cache.InvalidateLicenseType(licenseType.id)
end

-- Update license type in cache
function Cache.UpdateLicenseType(typeId, updates)
    for i, lt in ipairs(Cache.LicenseTypes) do
        if lt.id == typeId then
            for key, value in pairs(updates or {}) do
                lt[key] = value
            end
            Cache.InvalidateLicenseType(typeId)
            return true
        end
    end
    return false
end

-- Remove license type from cache
function Cache.RemoveLicenseType(typeId)
    for i, lt in ipairs(Cache.LicenseTypes) do
        if lt.id == typeId then
            table.remove(Cache.LicenseTypes, i)
            Cache.InvalidateLicenseType(typeId)
            return true
        end
    end
    return false
end

-- Statistics
function Cache.GetStats()
    return {
        licenseTypes = #Cache.LicenseTypes,
        routes = 0,
        checkpoints = 0,
        lastUpdated = Cache.UpdatedAt,
        isStale = Cache.IsStale(),
        ttl = Cache.CacheTTL
    }
end

return Cache
