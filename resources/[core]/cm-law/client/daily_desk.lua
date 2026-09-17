local function dailyDesk(data, cb)
    local ok, result = pcall(lib.callback.await, 'cm-law:server:dailyDesk', false, data)
    cb(ok and result or { ok = false, error = 'Daily desk is unavailable. Please try again.' })
end
RegisterNUICallback('dailyDesk', dailyDesk)
RegisterNUICallback('police_dailyDesk', dailyDesk)
