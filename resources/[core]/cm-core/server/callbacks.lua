CM = CM or {}
CM.ServerCallbacks = CM.ServerCallbacks or {}

exports('CreateCallback', function(name, cb)
    if type(name) ~= 'string' or type(cb) ~= 'function' then return false end
    CM.ServerCallbacks[name] = cb
    return true
end)

exports('RemoveCallback', function(name)
    if type(name) ~= 'string' then return false end
    CM.ServerCallbacks[name] = nil
    return true
end)

RegisterNetEvent('cm-core:server:triggerCallback', function(name, requestId, ...)
    local src = source
    if type(name) ~= 'string' then return end
    requestId = tonumber(requestId)
    if not requestId then return end

    local cb = CM.ServerCallbacks[name]
    if not cb then
        TriggerClientEvent('cm-core:client:callbackResult', src, requestId, nil, 'callback_not_found')
        return
    end

    if exports['cm-core']:IsRateLimited(src, 'callback:' .. name, 30, 10) then
        TriggerClientEvent('cm-core:client:callbackResult', src, requestId, nil, 'rate_limited')
        return
    end

    local args = { ... }
    local responded = false

    local ok, err = pcall(function()
        cb(src, function(result, errorMessage)
            if responded then return end
            responded = true
            TriggerClientEvent('cm-core:client:callbackResult', src, requestId, result, errorMessage)
        end, table.unpack(args))
    end)

    if not ok then
        exports['cm-core']:Log('cm-core', 'error', ('Callback failed %s: %s'):format(name, tostring(err)), {
            category = 'callback',
            player_src = src,
        })
        TriggerClientEvent('cm-core:client:callbackResult', src, requestId, nil, 'callback_error')
    end
end)
