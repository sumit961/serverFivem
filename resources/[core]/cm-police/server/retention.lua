-- cm-police/server/retention.lua
-- Periodic pruning for the tables in this resource that grow without limit.
--
--   cm_police_activity
--       The dashboard only ever reads the newest Config.LogLimit rows, so
--       anything older is unreachable dead weight in the table and in backups.
--
--   cm_police_incidents
--       Dispatch calls were only ever status-flipped to resolved/expired,
--       never removed, which made this the fastest-growing table on a busy
--       server -- every 911 call ever taken was still in it. Only closed
--       calls are pruned; anything still waiting or active is left alone
--       regardless of age.
--
--   cm_police_evidence + html/img/bodycam/*.jpg
--       screenshot-basic writes captures straight into the resource folder
--       (see cuffs.lua and impound.lua) and nothing ever removed them, so the
--       folder grew forever and every joining player downloaded the whole
--       history through the fxmanifest files{} glob.
--
-- NOTE ON SERVING: FiveM resolves files{} globs when the resource starts, so a
-- capture taken after startup is not servable until the next restart. That is
-- pre-existing behaviour, not something this file changes.

local LOG_RETENTION_DAYS = math.max(1, math.floor(tonumber(Config.LogRetentionDays) or 90))
local INCIDENT_RETENTION_DAYS = math.max(1, math.floor(tonumber(Config.IncidentRetentionDays) or 30))
local SWEEP_INTERVAL_MS = math.max(600000, math.floor(tonumber(Config.RetentionSweepMs) or 21600000))
local EVIDENCE_RETENTION_DAYS = math.max(1, math.floor(tonumber(Config.EvidenceRetentionDays) or 30))
local resourcePath = GetResourcePath(GetCurrentResourceName())

local function pruneActivity()
    local ok, deleted = pcall(function()
        return MySQL.update.await([[
            DELETE FROM cm_police_activity WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)
        ]], { LOG_RETENTION_DAYS })
    end)
    if not ok then
        print(('[cm-police] retention: activity sweep failed: %s'):format(tostring(deleted)))
        return 0
    end
    return tonumber(deleted) or 0
end

local function pruneIncidents()
    local ok, deleted = pcall(function()
        return MySQL.update.await([[
            DELETE FROM cm_police_incidents
            WHERE status IN ('resolved', 'expired', 'cancelled', 'closed')
              AND created_at < DATE_SUB(NOW(), INTERVAL ? DAY)
        ]], { INCIDENT_RETENTION_DAYS })
    end)
    if not ok then
        print(('[cm-police] retention: incident sweep failed: %s'):format(tostring(deleted)))
        return 0
    end
    return tonumber(deleted) or 0
end

-- Same pattern mdt.lua uses to decide a url is a local capture rather than an
-- external link, so we can never be talked into removing an arbitrary path.
local function localCapturePath(url)
    if type(url) ~= 'string' then return nil end
    if not url:match('^img/bodycam/[A-Za-z0-9_-]+%.jpg$') then return nil end
    return ('%s/html/%s'):format(resourcePath, url)
end

local function pruneEvidence()
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT id, url FROM cm_police_evidence
            WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)
        ]], { EVIDENCE_RETENTION_DAYS })
    end)
    if not ok or type(rows) ~= 'table' then
        print(('[cm-police] retention: evidence sweep failed: %s'):format(tostring(rows)))
        return 0, 0
    end

    local removedRows, removedFiles = 0, 0
    for _, row in ipairs(rows) do
        local deleted = MySQL.update.await('DELETE FROM cm_police_evidence WHERE id = ?', { row.id })
        if deleted and deleted > 0 then
            removedRows = removedRows + 1
            local path = localCapturePath(row.url)
            -- Only touch disk after the row is gone: a file with no row is
            -- unreachable anyway, a row with no file renders as a broken image.
            if path and pcall(os.remove, path) then
                removedFiles = removedFiles + 1
            end
        end
    end
    return removedRows, removedFiles
end

local function sweep()
    local evidenceRows, evidenceFiles = pruneEvidence()
    if evidenceRows > 0 then
        print(('[cm-police] retention: removed %d evidence rows, %d files older than %d days')
            :format(evidenceRows, evidenceFiles, EVIDENCE_RETENTION_DAYS))
    end

    local logs = pruneActivity()
    if logs > 0 then
        print(('[cm-police] retention: removed %d activity rows older than %d days')
            :format(logs, LOG_RETENTION_DAYS))
    end

    local incidents = pruneIncidents()
    if incidents > 0 then
        print(('[cm-police] retention: removed %d closed dispatch calls older than %d days')
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
RegisterCommand('policeretention', function(src)
    if src ~= 0 then
        print('[cm-police] retention: console only.')
        return
    end
    sweep()
end, true)
