CM.Plugins = {
    Registry = {},
    Hooks = {
        ['core:ready'] = {},
        ['core:shutdown'] = {},
        ['player:connecting'] = {},
        ['player:loaded'] = {},
        ['player:unloaded'] = {},
        ['player:death'] = {},
        ['money:changed'] = {},
        ['rank:changed'] = {},
        ['command:executed'] = {},
    },
}

exports('RegisterPlugin', function(resourceName, metadata)
    metadata = metadata or {}
    CM.Plugins.Registry[resourceName] = {
        name = resourceName, version = metadata.version or '1.0.0',
        minCoreVersion = metadata.minCoreVersion or '1.0.0',
        author = metadata.author or 'Unknown', hooks = {}, registeredAt = os.time(),
    }
    print(('[CM-CORE] Plugin registered: %s v%s'):format(resourceName, metadata.version))
    return true
end)

exports('RegisterHook', function(resourceName, hookName, callback, priority)
    priority = priority or 50
    if not CM.Plugins.Hooks[hookName] then CM.Plugins.Hooks[hookName] = {} end
    table.insert(CM.Plugins.Hooks[hookName], {resource = resourceName, callback = callback, priority = priority})
    table.sort(CM.Plugins.Hooks[hookName], function(a, b) return a.priority < b.priority end)
    if CM.Plugins.Registry[resourceName] then
        table.insert(CM.Plugins.Registry[resourceName].hooks, hookName)
    end
    return true
end)

function CM.TriggerHook(hookName, ...)
    local hooks = CM.Plugins.Hooks[hookName] or {}
    local results = {}
    for _, hook in ipairs(hooks) do
        local ok, result = pcall(hook.callback, ...)
        if not ok then
            exports['cm-core']:Log('cm-core', 'error', ('Hook failed: %s in %s'):format(hookName, hook.resource), {error = result})
        else
            table.insert(results, result)
        end
    end
    return results
end

exports('IsPluginActive', function(resourceName) return CM.Plugins.Registry[resourceName] ~= nil end)
exports('GetActivePlugins', function() return CM.Plugins.Registry end)

CreateThread(function()
    Wait(5000)
    CM.TriggerHook('core:ready')
    print('[CM-CORE] All plugins initialized. Core ready.')
end)

AddEventHandler('onResourceStop', function(res)
    if res == 'cm-core' then CM.TriggerHook('core:shutdown') end
end)