CM = CM or {}
CM.ClientReady = false

CreateThread(function()
    Wait(500)
    CM.ClientReady = true
    TriggerEvent('cm-core:client:ready')
end)

exports('IsClientReady', function()
    return CM.ClientReady == true
end)
