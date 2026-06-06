CM.Scheduler = {Jobs = {}, LastRun = {}, TickCount = 0}

exports('Schedule', function(name, interval, callback, options)
    options = options or {}
    local intervalSeconds
    if interval == 'every15min' then intervalSeconds = 900
    elseif interval == 'hourly' then intervalSeconds = 3600
    elseif interval == 'daily' then intervalSeconds = 86400
    elseif type(interval) == 'number' then intervalSeconds = interval
    else return false, 'Invalid interval' end
    
    CM.Scheduler.Jobs[name] = {
        name = name, interval = intervalSeconds, callback = callback,
        lastRun = 0, runOnStart = options.runOnStart or false,
        requireOnline = options.requireOnline ~= false,
    }
    
    if options.runOnStart then
        CreateThread(function()
            Wait(5000)
            CM.Scheduler.Jobs[name].callback()
            CM.Scheduler.Jobs[name].lastRun = os.time()
        end)
    end
    print(('[CM-CORE] Scheduled: %s every %ds'):format(name, intervalSeconds))
    return true
end)

exports('Unschedule', function(name) CM.Scheduler.Jobs[name] = nil end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        CM.Scheduler.TickCount = CM.Scheduler.TickCount + 1
        for name, job in pairs(CM.Scheduler.Jobs) do
            if (now - job.lastRun) >= job.interval then
                if job.requireOnline and #GetPlayers() == 0 then goto continue end
                local ok, err = pcall(job.callback)
                if ok then
                    job.lastRun = now
                    CM.Scheduler.LastRun[name] = now
                else
                    exports['cm-core']:Log('cm-core', 'error', ('Job %s failed: %s'):format(name, tostring(err)))
                    job.lastRun = now
                end
                ::continue::
            end
        end
    end
end)

exports('GetSchedulerHealth', function()
    local health = {}
    for name, job in pairs(CM.Scheduler.Jobs) do
        health[name] = {lastRun = CM.Scheduler.LastRun[name], nextRun = job.lastRun + job.interval, overdue = (os.time() - job.lastRun) > job.interval}
    end
    return health
end)