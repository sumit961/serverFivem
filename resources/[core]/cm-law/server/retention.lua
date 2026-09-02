-- cm-law/server/retention.lua
-- Periodic pruning for the tables in this resource that grow without limit.
--
--   cm_legal_activity_logs
--       The dashboard only ever reads the newest Config.LogLimit rows, so
--       anything older is unreachable dead weight in the table and in backups.
--
--   cm_legal_incidents
--       Dispatch calls were only ever status-flipped to resolved/expired,
--       never removed, which made this the fastest-growing table on a busy
--       server -- every 911 call ever taken was still in it. Only closed
--       calls are pruned; anything still waiting or active is left alone
--       regardless of age.

local LOG_RETENTION_DAYS = math.max(1, math.floor(tonumber(Config.LogRetentionDays) or 90))
local INCIDENT_RETENTION_DAYS = math.max(1, math.floor(tonumber(Config.IncidentRetentionDays) or 30))
local SWEEP_INTERVAL_MS = math.max(600000, math.floor(tonumber(Config.RetentionSweepMs) or 21600000))

local function pruneActivity()
    local ok, deleted = pcall(function()
        return MySQL.update.await([[
            DELETE FROM cm_legal_activity_logs WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)
        ]], { LOG_RETENTION_DAYS })
    end)
    if not ok then
        print(('[cm-law] retention: activity sweep failed: %s'):format(tostring(deleted)))
        return 0
    end
    return tonumber(deleted) or 0
end

local function pruneIncidents()
    local ok, deleted = pcall(function()
        return MySQL.update.await([[
            DELETE FROM cm_legal_incidents
            WHERE status IN ('resolved', 'expired', 'cancelled', 'closed')
              AND created_at < DATE_SUB(NOW(), INTERVAL ? DAY)
        ]], { INCIDENT_RETENTION_DAYS })
    end)
    if not ok then
        print(('[cm-law] retention: incident sweep failed: %s'):format(tostring(deleted)))
        return 0
    end
    return tonumber(deleted) or 0
end

local function sweep()
    local logs = pruneActivity()
    if logs > 0 then
        print(('[cm-law] retention: removed %d activity rows older than %d days')
            :format(logs, LOG_RETENTION_DAYS))
    end

    local incidents = pruneIncidents()
    if incidents > 0 then
        print(('[cm-law] retention: removed %d closed dispatch calls older than %d days')
            :format(incidents, INCIDENT_RETENTION_DAYS))
    end
end

CreateThread(function()
    -- Let schema creation settle before the first sweep.
    Wait(60000)
    while true do
        sweep()
        Wait(SWEEP_INTERVAL_MS)
    end
end)

-- Manual trigger for admins who want to reclaim space without waiting.
RegisterCommand('lawretention', function(src)
    if src ~= 0 then
        print('[cm-law] retention: console only.')
        return
    end
    sweep()
end, true)
