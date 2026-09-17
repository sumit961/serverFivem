-- CM License System — Cache Management
--
-- License types, routes and checkpoints change only when an admin edits them,
-- so they are cached wholesale and invalidated explicitly. The TTL is a
-- backstop for edits made directly in the database.

Cache = {
    LicenseTypes = {},      -- All enabled license types
    Routes = {},            -- List of enabled routes, by license_type_id
    Checkpoints = {},       -- Checkpoints by route_id
    UpdatedAt = 0,
    CacheTTL = 3600,
}

-- Refresh all cached data
function Cache.Refresh()
    Cache.LicenseTypes = Database.GetLicenseTypes() or {}
    Cache.Routes = {}
    Cache.Checkpoints = {}

    for _, licenseType in ipairs(Cache.LicenseTypes) do
        local typeId = tonumber(licenseType.id)
        licenseType.id = typeId

        local routes = {}
        for _, route in ipairs(Database.GetRoutes(typeId)) do
            route.id = tonumber(route.id)
            local checkpoints = Database.GetCheckpoints(route.id) or {}
            Cache.Checkpoints[route.id] = checkpoints
            -- A route with fewer than two points cannot be examined on.
            if #checkpoints >= 2 then
                routes[#routes + 1] = route
            end
        end
        Cache.Routes[typeId] = routes
    end

    Cache.UpdatedAt = os.time()
    CMLog('Cache refreshed')
end

function Cache.Init()
    print('^2[CM-License]^7 Initializing cache...')
    Cache.Refresh()
    print('^2[CM-License]^7 Cache initialized with ' .. #Cache.LicenseTypes .. ' license type(s)')
end

function Cache.IsStale()
    return (os.time() - Cache.UpdatedAt) > Cache.CacheTTL
end

local function ensureFresh()
    if Cache.IsStale() then Cache.Refresh() end
end

function Cache.GetLicenseTypes()
    ensureFresh()
    return Cache.LicenseTypes
end

function Cache.GetLicenseType(typeId)
    ensureFresh()
    typeId = tonumber(typeId)
    if not typeId then return nil end
    for _, lt in ipairs(Cache.LicenseTypes) do
        if tonumber(lt.id) == typeId then
            return lt
        end
    end
    return nil
end

function Cache.GetLicenseTypeByName(licenseType)
    ensureFresh()
    licenseType = tostring(licenseType or ''):lower()
    for _, lt in ipairs(Cache.LicenseTypes) do
        if tostring(lt.license_type):lower() == licenseType then
            return lt
        end
    end
    return nil
end

-- Every usable route for a type.
function Cache.GetRoutes(licenseTypeId)
    ensureFresh()
    return Cache.Routes[tonumber(licenseTypeId)] or {}
end

-- Draw a route for an exam. With several recorded, players cannot memorise
-- one circuit; with one, this is just that route.
function Cache.GetRandomRoute(licenseTypeId)
    local routes = Cache.GetRoutes(licenseTypeId)
    if #routes == 0 then return nil end
    if #routes == 1 then return routes[1] end
    return routes[math.random(#routes)]
end

function Cache.GetRouteById(routeId)
    ensureFresh()
    routeId = tonumber(routeId)
    for _, routes in pairs(Cache.Routes) do
        for _, route in ipairs(routes) do
            if route.id == routeId then return route end
        end
    end
    return nil
end

function Cache.GetCheckpoints(routeId)
    ensureFresh()
    return Cache.Checkpoints[tonumber(routeId)] or {}
end

-- Invalidate everything; the next read reloads from the database.
function Cache.Invalidate()
    CMLog('Cache invalidated, will refresh on next access')
    Cache.UpdatedAt = 0
end

Cache.InvalidateLicenseType = Cache.Invalidate

function Cache.GetStats()
    local routes, checkpoints = 0, 0
    for _, list in pairs(Cache.Routes) do routes = routes + #list end
    for _, list in pairs(Cache.Checkpoints) do checkpoints = checkpoints + #list end
    return {
        licenseTypes = #Cache.LicenseTypes,
        routes = routes,
        checkpoints = checkpoints,
        lastUpdated = Cache.UpdatedAt,
        isStale = Cache.IsStale(),
        ttl = Cache.CacheTTL,
    }
end

return Cache
