local configCache = nil
local configListeners = {}

local function DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in next, orig, nil do
            copy[DeepCopy(k)] = DeepCopy(v)
        end
        setmetatable(copy, DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

local function LoadConfig()
    configCache = DeepCopy(CM.Config)
    for resource, callback in pairs(configListeners) do
        local ok, err = pcall(callback, configCache)
        if not ok then
            print("[CM-CORE] Config reload callback failed for " .. resource .. ": " .. tostring(err))
        end
    end
    print("[CM-CORE] Config loaded | Environment: " .. GetConvar("cm_env", "production"))
end

exports('GetConfig', function(section, key)
    if not configCache then LoadConfig() end
    if not section then return DeepCopy(configCache) end
    if not key then return DeepCopy(configCache[section]) end
    return DeepCopy(configCache[section][key])
end)

exports('OnConfigReload', function(resourceName, callback)
    if type(callback) == 'function' then
        configListeners[resourceName] = callback
    end
end)

CreateThread(function()
    while true do
        Wait(30000)
        if configCache and configCache.Server.devMode then
            LoadConfig()
        end
    end
end)

LoadConfig()