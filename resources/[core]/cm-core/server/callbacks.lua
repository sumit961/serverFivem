-- CM-Core v1.1 Safe Patch: Server Callback System

CM = CM or {}
CM.ServerCallbacks = CM.ServerCallbacks or {}

exports('CreateCallback', function(name, cb)
    if type(name) ~= 'string' or type(cb) ~= 'function' then return false end
    CM.ServerCallbacks[name] = cb
    return true
end)

exports('RemoveCallback', function(name)
    CM.ServerCallbacks[name] = nil
    return true
end)

RegisterNetEvent('cm-core:server:triggerCallback', function(name, requestId, ...)
    local src = source
    if type(name) ~= 'string' then return end

    local cb = CM.ServerCallbacks[name]
    if not cb then
        TriggerClientEvent('cm-core:client:callbackResult', src, requestId, nil, 'callback_not_found')
        return
    end

    local args = { ... }
    local ok, err = pcall(function()
        cb(src, function(result, errorMessage)
            TriggerClientEvent('cm-core:client:callbackResult', src, requestId, result, errorMessage)
        end, table.unpack(args))
    end)

    if not ok then
        print(('[CM-CORE] Callback failed %s: %s'):format(name, tostring(err)))
        TriggerClientEvent('cm-core:client:callbackResult', src, requestId, nil, 'callback_error')
    end
end)
