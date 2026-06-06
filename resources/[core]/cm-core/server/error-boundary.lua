function CM.SafeCall(context, fn, ...)
    local start = GetGameTimer()
    local ok, result = pcall(fn, ...)
    if not ok then
        exports['cm-core']:Log('cm-core', 'error', ('SafeCall failed [%s]: %s'):format(context, tostring(result)), {trace = debug.traceback(), context = context})
        return nil, result
    end
    return result, nil
end

exports('SafeEvent', function(eventName, handler)
    AddEventHandler(eventName, function(...)
        local src = source
        CM.SafeCall(eventName .. ':' .. src, function(...) handler(...) end, ...)
    end)
end)

exports('SafeThread', function(name, interval, fn)
    CreateThread(function()
        while true do
            Wait(interval)
            CM.SafeCall('thread:' .. name, fn)
        end
    end)
end)