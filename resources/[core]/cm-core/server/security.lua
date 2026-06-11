-- CM-Core v1.1 Safe Patch: Security Helpers and Rate-Limited Net Events

CM = CM or {}
CM.Security = CM.Security or {}
CM.Security.RateLimits = CM.Security.RateLimits or {}

local function isLoggedIn(src)
    local ok, value = pcall(function() return Player(src).state.isLoggedIn end)
    if ok and value then return true end
    return exports['cm-core']:GetPlayer(src) ~= nil
end

local function rateLimit(src, key, maxCount, seconds)
    src = tonumber(src)
    maxCount = tonumber(maxCount) or 5
    seconds = tonumber(seconds) or 10

    local now = os.time()
    local id = tostring(src) .. ':' .. tostring(key)
    local bucket = CM.Security.RateLimits[id]

    if not bucket or now >= bucket.reset then
        bucket = { count = 0, reset = now + seconds }
        CM.Security.RateLimits[id] = bucket
    end

    bucket.count = bucket.count + 1
    if bucket.count > maxCount then
        pcall(function()
            exports['cm-core']:Log('cm-core', 'warn', 'Rate limit triggered', {
                category = 'security',
                player_src = src,
                event = key
            })
        end)
        return false
    end
    return true
end

exports('IsRateLimited', function(src, key, maxCount, seconds)
    return not rateLimit(src, key, maxCount, seconds)
end)

exports('SecureNetEvent', function(eventName, options, handler)
    if type(eventName) ~= 'string' or type(handler) ~= 'function' then return false end
    options = options or {}

    RegisterNetEvent(eventName, function(data)
        local src = source

        if options.requireLogin and not isLoggedIn(src) then
            return
        end

        if options.rateLimit then
            local maxCount = options.rateLimit.max or options.rateLimit[1] or 5
            local seconds = options.rateLimit.seconds or options.rateLimit[2] or 10
            if not rateLimit(src, eventName, maxCount, seconds) then return end
        end

        local ok, err = pcall(function()
            handler(src, data or {})
        end)

        if not ok then
            print(('[CM-CORE] SecureNetEvent error %s: %s'):format(eventName, tostring(err)))
            pcall(function()
                exports['cm-core']:Log('cm-core', 'error', 'SecureNetEvent failed', {
                    category = 'security',
                    player_src = src,
                    event = eventName,
                    error = tostring(err)
                })
            end)
        end
    end)

    return true
end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for key, bucket in pairs(CM.Security.RateLimits) do
            if now >= bucket.reset + 60 then
                CM.Security.RateLimits[key] = nil
            end
        end
    end
end)
