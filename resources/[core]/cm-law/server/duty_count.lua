-- cm-law/server/duty_count.lua
-- Authoritative read-only on-duty count for the `GetOnDutyCount(orgId)` export (wired in server/main.lua).
-- Pure factory: no FiveM globals, so tests/duty_count_selftest.lua exercises exactly this code with doubles for the database and connection state.
--
-- WHO IS COUNTED (law owns every one of these facts; nothing is cached or duplicated here):
--   * a member row of the REQUESTED organization with an existing rank (central cm_legal_members, or the embedded legacy `police` cm_police_members),
--   * whose persisted `on_duty` flag is set,
--   * who is not suspended (same rule the member APIs use: central = any suspended_until, legacy = suspended_until in the future),
--   * and whose CHARACTER IS CURRENTLY LOADED on a connected player. Duty is ended by law on disconnect / character unload / death, but a crash or a
--     law restart can leave a stale on_duty=1 row; those rows are ignored (never counted) until the character is loaded again.
-- NOT counted: off-duty or suspended members, other organizations, civilians, EMS/gang/family, admins who only hold permissions, anyone without a member row.
-- Each character counts at most once. Only a number is returned: no names, character ids, ranks or positions.
LawDutyCount = {}

LawDutyCount.LEGACY_ORG = 'police'   -- the embedded police organization (not part of Config.Organizations)

-- deps:
--   callers            table  [resourceName] = true   (read-only server consumers)
--   isCentralOrg(id)   -> bool                         (Config.Organizations[id] ~= nil)
--   lawReady()         -> bool                         (central law tables are ready)
--   legacyReady()      -> bool                         (embedded police tables are ready)
--   queryCentral(id)   -> rows { character_id }        (on duty, ranked, not suspended)
--   queryLegacy()      -> rows { character_id }
--   isLoaded(cid)      -> bool                         (character is loaded on a connected player)
function LawDutyCount.New(d)
    local self = {}

    local function normalize(orgId)
        if type(orgId) ~= 'string' then return nil end
        local id = orgId:match('^%s*(.-)%s*$'):lower()
        if id == '' or #id > 32 or not id:match('^[a-z0-9_]+$') then return nil end
        return id
    end

    -- count(orgId, invoker) -> number | nil, 'forbidden' | 'invalid_organization' | 'unavailable'
    -- 0 means the law system is healthy and nobody is on duty; nil means law cannot answer authoritatively.
    function self.count(orgId, invoker)
        if invoker == nil or not (d.callers or {})[invoker] then return nil, 'forbidden' end
        local id = normalize(orgId)
        if not id then return nil, 'invalid_organization' end
        local rows
        if id == LawDutyCount.LEGACY_ORG then
            if not d.legacyReady() then return nil, 'unavailable' end
            local ok, res = pcall(d.queryLegacy)
            if not ok or type(res) ~= 'table' then return nil, 'unavailable' end
            rows = res
        elseif d.isCentralOrg(id) then
            if not d.lawReady() then return nil, 'unavailable' end
            local ok, res = pcall(d.queryCentral, id)
            if not ok or type(res) ~= 'table' then return nil, 'unavailable' end
            rows = res
        else
            return nil, 'invalid_organization'
        end
        local seen, n = {}, 0
        for _, row in ipairs(rows) do
            local cid = row and row.character_id ~= nil and tostring(row.character_id) or nil
            if cid and cid ~= '' and not seen[cid] then
                seen[cid] = true
                local okL, loaded = pcall(d.isLoaded, cid)
                if okL and loaded == true then n = n + 1 end
            end
        end
        return n
    end

    return self
end
