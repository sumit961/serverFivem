RegisterNUICallback('getProgression', function(_, callback)
    if not lib or not lib.callback then
        callback({ ok = false, reason = 'callback_unavailable' })
        return
    end

    local ok, result = pcall(function()
        return lib.callback.await('cm-gang:server:getMyProgression', false)
    end)
    if not ok or type(result) ~= 'table' then
        callback({ ok = false, reason = 'progression_unavailable' })
        return
    end

    callback(result)
end)
