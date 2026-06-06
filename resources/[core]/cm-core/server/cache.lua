CM.Cache = {
    Store = {}, AccessOrder = {}, MaxSize = 500,
    DefaultTTL = 300, Hits = 0, Misses = 0,
}

local function UpdateAccess(key)
    for i, k in ipairs(CM.Cache.AccessOrder) do
        if k == key then table.remove(CM.Cache.AccessOrder, i); break end
    end
    table.insert(CM.Cache.AccessOrder, 1, key)
end

local function EvictIfNeeded()
    while #CM.Cache.AccessOrder > CM.Cache.MaxSize do
        local oldest = table.remove(CM.Cache.AccessOrder)
        CM.Cache.Store[oldest] = nil
    end
end

exports('CacheSet', function(key, value, ttl)
    ttl = ttl or CM.Cache.DefaultTTL
    CM.Cache.Store[key] = {value = value, expires = os.time() + ttl, created = os.time()}
    UpdateAccess(key)
    EvictIfNeeded()
    return true
end)

exports('CacheGet', function(key)
    local entry = CM.Cache.Store[key]
    if not entry then CM.Cache.Misses = CM.Cache.Misses + 1; return nil end
    if os.time() > entry.expires then CM.Cache.Store[key] = nil; CM.Cache.Misses = CM.Cache.Misses + 1; return nil end
    CM.Cache.Hits = CM.Cache.Hits + 1
    UpdateAccess(key)
    return entry.value
end)

exports('CacheDelete', function(key)
    CM.Cache.Store[key] = nil
    for i, k in ipairs(CM.Cache.AccessOrder) do if k == key then table.remove(CM.Cache.AccessOrder, i); break end end
end)

exports('CacheInvalidate', function(pattern)
    local deleted = 0
    for key, _ in pairs(CM.Cache.Store) do
        if string.find(key, pattern) then
            exports['cm-core']:CacheDelete(key)
            deleted = deleted + 1
        end
    end
    return deleted
end)

exports('CacheRemember', function(key, ttl, computeFn)
    local cached = exports['cm-core']:CacheGet(key)
    if cached ~= nil then return cached end
    local ok, result = pcall(computeFn)
    if ok and result ~= nil then
        exports['cm-core']:CacheSet(key, result, ttl)
        return result
    end
    return nil
end)

exports('CacheStats', function()
    local total = CM.Cache.Hits + CM.Cache.Misses
    return {
        size = #CM.Cache.AccessOrder, maxSize = CM.Cache.MaxSize,
        hits = CM.Cache.Hits, misses = CM.Cache.Misses,
        hitRate = total > 0 and (CM.Cache.Hits / total) or 0,
    }
end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        local expired = {}
        for key, entry in pairs(CM.Cache.Store) do if now > entry.expires then table.insert(expired, key) end end
        for _, key in ipairs(expired) do exports['cm-core']:CacheDelete(key) end
    end
end)