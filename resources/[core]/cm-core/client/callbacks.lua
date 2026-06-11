-- CM-Core v1.1 Safe Patch: Client Callback System

CM = CM or {}
CM.ClientCallbacks = CM.ClientCallbacks or {}
CM.CallbackRequestId = CM.CallbackRequestId or 0

exports('TriggerCallback', function(name, cb, ...)
    if type(name) ~= 'string' or type(cb) ~= 'function' then return false end

    CM.CallbackRequestId = CM.CallbackRequestId + 1
    local requestId = CM.CallbackRequestId
    CM.ClientCallbacks[requestId] = cb

    TriggerServerEvent('cm-core:server:triggerCallback', name, requestId, ...)
    return true
end)

RegisterNetEvent('cm-core:client:callbackResult', function(requestId, result, errorMessage)
    local cb = CM.ClientCallbacks[requestId]
    if not cb then return end
    CM.ClientCallbacks[requestId] = nil
    cb(result, errorMessage)
end)
