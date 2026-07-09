CM = CM or {}
CM.ClientCallbacks = CM.ClientCallbacks or {}
CM.CallbackRequestId = CM.CallbackRequestId or 0

exports('TriggerCallback', function(name, cb, ...)
    if type(name) ~= 'string' or type(cb) ~= 'function' then return false end

    CM.CallbackRequestId = CM.CallbackRequestId + 1
    if CM.CallbackRequestId > 999999 then CM.CallbackRequestId = 1 end

    local requestId = CM.CallbackRequestId
    CM.ClientCallbacks[requestId] = cb

    TriggerServerEvent('cm-core:server:triggerCallback', name, requestId, ...)

    SetTimeout(15000, function()
        if CM.ClientCallbacks[requestId] then
            local pending = CM.ClientCallbacks[requestId]
            CM.ClientCallbacks[requestId] = nil
            pending(nil, 'callback_timeout')
        end
    end)

    return true
end)

RegisterNetEvent('cm-core:client:callbackResult', function(requestId, result, errorMessage)
    requestId = tonumber(requestId)
    if not requestId then return end

    local cb = CM.ClientCallbacks[requestId]
    if not cb then return end
    CM.ClientCallbacks[requestId] = nil
    cb(result, errorMessage)
end)
