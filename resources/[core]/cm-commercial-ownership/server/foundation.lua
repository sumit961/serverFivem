-- cm-commercial-ownership/server/foundation.lua
-- Shared business employment foundation: owner resolution, ranks, permissions, employees,
-- invites, activity log, atomic balance contract, bounded manual payroll, business invoices.
--
-- Ownership and business_balance stay in each business's own table (see Config.BusinessTypes).
-- Identity is CHARACTER based; FiveM source ids are never persisted.
-- Every mutation takes the ACTOR (resolved from a server source) and re-checks permission,
-- hierarchy and ownership here. Nothing in this file trusts client-provided state.

CMB = CMB or {}
local C = CMB

local RESOURCE = GetCurrentResourceName()

-- ============================================================
-- Helpers
-- ============================================================

local function playerData()
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    return exports['cm-playerdata']
end

local function cidOfSource(src)
    src = tonumber(src)
    if not src then return nil end
    local api = playerData()
    if api then
        local ok, id = pcall(function() return api:GetCharacterId(src) end)
        if ok and tonumber(id) then return tonumber(id) end
    end
    return nil
end

local function sourceOfCid(cid)
    local api = playerData()
    if not api then return nil end
    local ok, src = pcall(function() return api:GetSourceByCharId(tonumber(cid)) end)
    if ok and tonumber(src) and tonumber(src) > 0 then return tonumber(src) end
    return nil
end

local function fullName(src)
    local api = playerData()
    if not api or not src then return nil end
    local ok, name = pcall(function() return api:GetCharacterFullName(src) end)
    if ok and type(name) == 'string' and name ~= '' then return name:sub(1, 120) end
    return nil
end

local function notifySrc(src, message, kind)
    if not src then return end
    if GetResourceState('cm-hud') == 'started' then
        TriggerClientEvent('cm-hud:client:notify', src, tostring(message or ''), kind or 'info')
    end
end

local function encode(t)
    local ok, s = pcall(json.encode, t or {})
    if not ok then return '{}' end
    return s:sub(1, 480)
end

local function decodeList(text)
    local ok, t = pcall(json.decode, text or '[]')
    return (ok and type(t) == 'table') and t or {}
end

-- ---- Permission catalogue -----------------------------------------------------
C.permSet, C.permOrder = {}, {}
for _, p in ipairs(Config.Permissions) do
    C.permSet[p.id] = true
    C.permOrder[#C.permOrder + 1] = p.id
end

local function permsToSet(list)
    local set = {}
    for _, p in ipairs(list) do
        if type(p) == 'string' and C.permSet[p] then set[p] = true end
    end
    return set
end

local function permsToList(set)
    local list = {}
    for _, id in ipairs(C.permOrder) do
        if set[id] then list[#list + 1] = id end
    end
    return list
end

local OWNER_PERMS = {}
for _, id in ipairs(C.permOrder) do OWNER_PERMS[id] = true end

-- ---- Locks & rate limits -------------------------------------------------------
local locks = {}

local function acquire(key, timeoutMs)
    local waited = 0
    while locks[key] do
        Wait(20)
        waited = waited + 20
        if waited > (timeoutMs or 4000) then return false end
    end
    locks[key] = true
    return true
end

local function release(key) locks[key] = nil end

local function withLock(key, fn, ...)
    if not acquire(key) then return false, 'busy' end
    local res = table.pack(pcall(fn, ...))
    release(key)
    if not res[1] then
        print(('[cm-commercial-ownership] internal error: %s'):format(tostring(res[2])))
        return false, 'internal_error'
    end
    return table.unpack(res, 2, res.n)
end

local hits = {}
local function rateLimited(actor, bucket)
    local cfg = Config.RateLimits[bucket]
    if not cfg then return false end
    local key = tostring(actor) .. ':' .. bucket
    local now = os.time()
    local list = hits[key] or {}
    local kept = {}
    for _, t in ipairs(list) do
        if now - t < cfg[2] then kept[#kept + 1] = t end
    end
    if #kept >= cfg[1] then hits[key] = kept; return true end
    kept[#kept + 1] = now
    hits[key] = kept
    return false
end
C.RateLimited = rateLimited
C.withBusinessLock = withLock
function C.ResetRateLimits() hits = {} end -- development self-test only

-- ============================================================
-- Business identity / registry
-- ============================================================

C.types = {}
for key, def in pairs(Config.BusinessTypes) do
    local ok = true
    for _, f in ipairs({ 'table', 'idColumn', 'ownerColumn', 'balanceColumn', 'nameColumn' }) do
        if type(def[f]) ~= 'string' or not def[f]:match('^[%w_]+$') then ok = false end
    end
    if ok and key:match('^[%w_]+$') then C.types[key] = def end
end

local tableChecked = {}
local function tableAvailable(def)
    if tableChecked[def.table] then return true end
    local ok, row = pcall(function()
        return MySQL.scalar.await('SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ? LIMIT 1', { def.table })
    end)
    if ok and row then tableChecked[def.table] = true; return true end
    return false
end

local function normType(t)
    if type(t) ~= 'string' then return nil end
    t = t:lower()
    return C.types[t] and t or nil
end

local function normId(i)
    if type(i) == 'number' then i = tostring(math.floor(i)) end
    if type(i) ~= 'string' or #i < 1 or #i > 64 or not i:match('^[%w_%-%.]+$') then return nil end
    return i
end

local function readBusiness(t, i)
    t, i = normType(t), normId(i)
    if not t or not i then return nil, 'invalid_business' end
    local def = C.types[t]
    if not tableAvailable(def) then return nil, 'unavailable' end
    local row = MySQL.single.await(('SELECT `%s` AS owner, `%s` AS balance, `%s` AS owner_name FROM `%s` WHERE `%s` = ? LIMIT 1')
        :format(def.ownerColumn, def.balanceColumn, def.nameColumn, def.table, def.idColumn), { i })
    if not row then return nil, 'unknown_business' end
    return {
        type = t, id = i, label = ('%s #%s'):format(def.label, i), typeLabel = def.label,
        ownerCharacterId = tonumber(row.owner), ownerName = row.owner_name,
        balance = math.max(0, math.floor(tonumber(row.balance) or 0)),
    }
end

-- Ownership transition: ownership snapshot differs from the stored one.
-- Policy (documented in docs/CONTRACTS.md): staff records and custom ranks belong to a specific owner
-- tenure. When the owner changes (sale, forfeiture, admin transfer) all employees are removed, ranks
-- are reset to defaults on next use, pending invites die (epoch bump) and the event is audited.
-- Normal restarts never wipe anything: the first observation only records the snapshot.
local invites = {}

local function transition(biz, state)
    local employees = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_business_employees WHERE business_type = ? AND business_id = ?', { biz.type, biz.id })) or 0
    local ranks = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_business_ranks WHERE business_type = ? AND business_id = ?', { biz.type, biz.id })) or 0
    local meta = encode({ from = state.owner_character_id and tonumber(state.owner_character_id) or nil, to = biz.ownerCharacterId, employeesRemoved = employees, ranksReset = ranks })
    local ok = MySQL.transaction.await({
        { query = 'DELETE FROM cm_business_employees WHERE business_type = ? AND business_id = ?', values = { biz.type, biz.id } },
        { query = 'DELETE FROM cm_business_ranks WHERE business_type = ? AND business_id = ?', values = { biz.type, biz.id } },
        { query = 'UPDATE cm_business_state SET owner_character_id = ?, epoch = epoch + 1 WHERE business_type = ? AND business_id = ?', values = { biz.ownerCharacterId, biz.type, biz.id } },
        { query = 'INSERT INTO cm_business_activity (business_type, business_id, action, actor_character_id, target_character_id, metadata) VALUES (?, ?, ?, NULL, ?, ?)',
          values = { biz.type, biz.id, 'ownership_changed', biz.ownerCharacterId, meta } },
    })
    for token, inv in pairs(invites) do
        if inv.type == biz.type and inv.id == biz.id then invites[token] = nil end
    end
    if C.SupplyOwnerChanged then pcall(C.SupplyOwnerChanged, biz) end
    if C.MaterialsOwnerChanged then pcall(C.MaterialsOwnerChanged, biz) end
    return ok == true
end

-- Resolves the business, applies the ownership-change policy and returns it with its epoch.
function C.Resolve(t, i)
    local biz, why = readBusiness(t, i)
    if not biz then return nil, why end
    if not C.EnsureSchema() then return nil, 'unavailable' end
    local epoch, syncWhy = withLock('sync:' .. biz.type .. ':' .. biz.id, function()
        local state = MySQL.single.await('SELECT owner_character_id, epoch FROM cm_business_state WHERE business_type = ? AND business_id = ?', { biz.type, biz.id })
        if not state then
            MySQL.query.await('INSERT IGNORE INTO cm_business_state (business_type, business_id, owner_character_id, epoch) VALUES (?, ?, ?, 1)', { biz.type, biz.id, biz.ownerCharacterId })
            return 1
        end
        if tonumber(state.owner_character_id) ~= biz.ownerCharacterId then
            transition(biz, state)
            state = MySQL.single.await('SELECT epoch FROM cm_business_state WHERE business_type = ? AND business_id = ?', { biz.type, biz.id })
        end
        return tonumber(state and state.epoch) or 1
    end)
    if not epoch then return nil, syncWhy or 'busy' end
    local a = epoch
    biz.epoch = a
    return biz
end

-- ============================================================
-- Activity log
-- ============================================================

local function logActivity(biz, action, actorCid, targetCid, amount, meta, mirror)
    pcall(function()
        MySQL.insert.await('INSERT INTO cm_business_activity (business_type, business_id, action, actor_character_id, target_character_id, amount, metadata) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { biz.type, biz.id, action, actorCid, targetCid, amount, meta and encode(meta) or nil })
    end)
    if mirror and GetResourceState('cm-admin') == 'started' then
        pcall(function()
            exports['cm-admin']:AddLog(sourceOfCid(actorCid) or 0, 'business_' .. action,
                { category = 'business', businessType = biz.type, businessId = biz.id, targetCharacterId = targetCid, amount = amount })
        end)
    end
end
C.LogActivity = logActivity

-- ============================================================
-- Ranks
-- ============================================================

local function ensureRanks(biz)
    local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_business_ranks WHERE business_type = ? AND business_id = ?', { biz.type, biz.id })) or 0
    if count > 0 then return end
    withLock('ranks:' .. biz.type .. ':' .. biz.id, function()
        local again = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_business_ranks WHERE business_type = ? AND business_id = ?', { biz.type, biz.id })) or 0
        if again > 0 then return end
        for _, r in ipairs((Config.TypeDefaultRanks and Config.TypeDefaultRanks[biz.type]) or Config.DefaultRanks) do
            MySQL.insert.await('INSERT IGNORE INTO cm_business_ranks (business_type, business_id, name, tier, permissions, is_entry) VALUES (?, ?, ?, ?, ?, ?)',
                { biz.type, biz.id, r.name, r.tier, json.encode(r.permissions), r.entry and 1 or 0 })
        end
    end)
end

local function rankView(row)
    return {
        id = tonumber(row.id), name = row.name, tier = tonumber(row.tier) or 0,
        permissions = permsToList(permsToSet(decodeList(row.permissions))),
        payAmount = tonumber(row.pay_amount) or 0, isEntry = row.is_entry == 1 or row.is_entry == true,
    }
end

local function getRanksRaw(biz)
    ensureRanks(biz)
    local rows = MySQL.query.await('SELECT id, name, tier, permissions, pay_amount, is_entry FROM cm_business_ranks WHERE business_type = ? AND business_id = ? ORDER BY tier DESC, id ASC', { biz.type, biz.id }) or {}
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = rankView(row) end
    return out
end

local function getRank(biz, rankId)
    rankId = tonumber(rankId)
    if not rankId then return nil end
    ensureRanks(biz)
    local row = MySQL.single.await('SELECT id, name, tier, permissions, pay_amount, is_entry FROM cm_business_ranks WHERE id = ? AND business_type = ? AND business_id = ?', { rankId, biz.type, biz.id })
    return row and rankView(row) or nil
end

local function entryRank(biz, maxTierExclusive)
    local best
    for _, r in ipairs(getRanksRaw(biz)) do
        if r.isEntry and (not maxTierExclusive or r.tier < maxTierExclusive) then
            if not best or r.tier > best.tier then best = r end
        end
    end
    if best then return best end
    -- No flagged entry rank: fall back to the lowest tier rank.
    local ranks = getRanksRaw(biz)
    local low = ranks[#ranks]
    if low and (not maxTierExclusive or low.tier < maxTierExclusive) then return low end
    return nil
end

-- ============================================================
-- Authority context
-- ============================================================

-- Owner: virtual top rank (Config.OwnerTier, every permission). Employee: rank row. Otherwise nil.
local function context(biz, cid)
    cid = tonumber(cid)
    if not cid or not biz or not biz.ownerCharacterId then return nil end
    if cid == biz.ownerCharacterId then
        return { isOwner = true, tier = Config.OwnerTier, perms = OWNER_PERMS, rankName = 'Owner', characterId = cid }
    end
    local e = MySQL.single.await([[SELECT e.id, e.rank_id, e.character_id, e.display_name, e.hired_at, e.last_paid_at,
            r.name AS rank_name, r.tier, r.permissions, r.pay_amount
        FROM cm_business_employees e LEFT JOIN cm_business_ranks r ON r.id = e.rank_id
        WHERE e.business_type = ? AND e.business_id = ? AND e.character_id = ? LIMIT 1]], { biz.type, biz.id, cid })
    if not e then return nil end
    if e.tier == nil then
        return { isOwner = false, tier = 0, perms = {}, rankMissing = true, rankName = 'Unassigned', characterId = cid, employeeId = e.id }
    end
    return {
        isOwner = false, tier = tonumber(e.tier) or 0, perms = permsToSet(decodeList(e.permissions)),
        rankId = tonumber(e.rank_id), rankName = e.rank_name, payAmount = tonumber(e.pay_amount) or 0,
        characterId = cid, employeeId = e.id,
    }
end

local function authorize(actorCid, t, i, perm)
    local biz, why = C.Resolve(t, i)
    if not biz then return nil, nil, why end
    if not biz.ownerCharacterId then return nil, nil, 'no_owner' end
    local ctx = context(biz, actorCid)
    if not ctx then return nil, nil, 'forbidden' end
    if perm and not ctx.perms[perm] then return nil, nil, 'forbidden' end
    return biz, ctx
end

-- ============================================================
-- Public read API
-- ============================================================

function C.GetBusiness(t, i)
    local biz = C.Resolve(t, i)
    if not biz then return nil end
    return { type = biz.type, id = biz.id, label = biz.label, owned = biz.ownerCharacterId ~= nil, ownerCharacterId = biz.ownerCharacterId, balance = biz.balance, epoch = biz.epoch }
end

function C.GetBusinessOwner(t, i)
    local biz = C.Resolve(t, i)
    if not biz or not biz.ownerCharacterId then return nil end
    return biz.ownerCharacterId, biz.ownerName
end

function C.GetEmployee(t, i, cid)
    local biz = C.Resolve(t, i)
    if not biz or not biz.ownerCharacterId then return nil end
    local ctx = context(biz, cid)
    if not ctx then return nil end
    return { characterId = tonumber(cid), isOwner = ctx.isOwner, rankId = ctx.rankId, rankName = ctx.rankName, tier = ctx.tier, rankMissing = ctx.rankMissing == true }
end

function C.IsEmployee(t, i, cid)
    local e = C.GetEmployee(t, i, cid)
    return e ~= nil and not e.isOwner
end

function C.GetEmployeePermissions(t, i, cid)
    local biz = C.Resolve(t, i)
    if not biz or not biz.ownerCharacterId then return {} end
    local ctx = context(biz, cid)
    return ctx and permsToList(ctx.perms) or {}
end

function C.HasBusinessPermission(t, i, cid, perm)
    if type(perm) ~= 'string' or not C.permSet[perm] then return false end
    local biz = C.Resolve(t, i)
    if not biz or not biz.ownerCharacterId then return false end
    local ctx = context(biz, cid)
    return ctx ~= nil and ctx.perms[perm] == true
end

local function listEmployees(biz)
    local rows = MySQL.query.await([[SELECT e.character_id, e.rank_id, e.display_name, e.hired_at, e.last_paid_at, r.name AS rank_name, r.tier, r.pay_amount
        FROM cm_business_employees e LEFT JOIN cm_business_ranks r ON r.id = e.rank_id
        WHERE e.business_type = ? AND e.business_id = ? ORDER BY r.tier DESC, e.id ASC]], { biz.type, biz.id }) or {}
    local out = {}
    for _, e in ipairs(rows) do
        out[#out + 1] = {
            characterId = tonumber(e.character_id), rankId = tonumber(e.rank_id), rankName = e.rank_name or 'Unassigned',
            tier = tonumber(e.tier) or 0, name = e.display_name, hiredAt = tostring(e.hired_at or ''),
            payAmount = tonumber(e.pay_amount) or 0, rankMissing = e.tier == nil,
        }
    end
    return out
end

function C.GetEmployees(t, i)
    local biz = C.Resolve(t, i)
    if not biz or not biz.ownerCharacterId then return {} end
    return listEmployees(biz)
end

function C.GetRanks(t, i)
    local biz = C.Resolve(t, i)
    if not biz or not biz.ownerCharacterId then return {} end
    return getRanksRaw(biz)
end

function C.GetPlayerBusinesses(cid)
    cid = tonumber(cid)
    if not cid then return {} end
    local out = {}
    for t, def in pairs(C.types) do
        if tableAvailable(def) then
            local rows = MySQL.query.await(('SELECT `%s` AS id FROM `%s` WHERE `%s` = ?'):format(def.idColumn, def.table, def.ownerColumn), { cid }) or {}
            for _, r in ipairs(rows) do out[#out + 1] = { type = t, id = tostring(r.id), role = 'owner' } end
        end
    end
    local emp = MySQL.query.await('SELECT business_type, business_id FROM cm_business_employees WHERE character_id = ?', { cid }) or {}
    for _, r in ipairs(emp) do out[#out + 1] = { type = r.business_type, id = r.business_id, role = 'employee' } end
    return out
end

-- ============================================================
-- Rank management
-- ============================================================

local function validName(name)
    if type(name) ~= 'string' then return nil end
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    if #name < 2 or #name > 32 or name:find('[%c<>]') then return nil end
    return name
end

-- A non-owner may only hand out permissions they hold themselves.
local function permsAllowedFor(ctx, set)
    if ctx.isOwner then return true end
    for p in pairs(set) do
        if not ctx.perms[p] then return false end
    end
    return true
end

function C.CreateRank(actorCid, t, i, data)
    data = type(data) == 'table' and data or {}
    local biz, ctx, why = authorize(actorCid, t, i, 'business.manage_ranks')
    if not biz then return false, why end
    local name, tier = validName(data.name), math.floor(tonumber(data.tier) or -1)
    if not name then return false, 'invalid_name' end
    if tier < 1 or tier > Config.MaxRankTier then return false, 'invalid_tier' end
    if not ctx.isOwner and tier >= ctx.tier then return false, 'hierarchy' end
    local set = permsToSet(type(data.permissions) == 'table' and data.permissions or {})
    if next(set) and not (ctx.perms['business.manage_permissions']) then return false, 'forbidden' end
    if not permsAllowedFor(ctx, set) then return false, 'permission_escalation' end
    return withLock('ranks:' .. biz.type .. ':' .. biz.id, function()
        ensureRanks(biz)
        local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_business_ranks WHERE business_type = ? AND business_id = ?', { biz.type, biz.id })) or 0
        if count >= Config.MaxRanksPerBusiness then return false, 'rank_limit' end
        local okI, id = pcall(function()
            return MySQL.insert.await('INSERT INTO cm_business_ranks (business_type, business_id, name, tier, permissions, is_entry) VALUES (?, ?, ?, ?, ?, 0)',
                { biz.type, biz.id, name, tier, json.encode(permsToList(set)) })
        end)
        if not okI or not id then return false, 'duplicate_name' end
        logActivity(biz, 'rank_created', actorCid, nil, nil, { rank = name, tier = tier })
        return true, id
    end)
end

function C.UpdateRank(actorCid, t, i, rankId, data)
    data = type(data) == 'table' and data or {}
    local biz, ctx, why = authorize(actorCid, t, i, 'business.manage_ranks')
    if not biz then return false, why end
    return withLock('ranks:' .. biz.type .. ':' .. biz.id, function()
        local rank = getRank(biz, rankId)
        if not rank then return false, 'rank_not_found' end
        if not ctx.isOwner and rank.tier >= ctx.tier then return false, 'hierarchy' end
        local name, tier, set, pay = rank.name, rank.tier, permsToSet(rank.permissions), rank.payAmount
        local changes = {}
        if data.name ~= nil then
            name = validName(data.name)
            if not name then return false, 'invalid_name' end
            if name ~= rank.name then changes.name = name end
        end
        if data.tier ~= nil then
            tier = math.floor(tonumber(data.tier) or -1)
            if tier < 1 or tier > Config.MaxRankTier then return false, 'invalid_tier' end
            if not ctx.isOwner and tier >= ctx.tier then return false, 'hierarchy' end
            if tier ~= rank.tier then changes.tier = tier end
        end
        if data.permissions ~= nil then
            if not ctx.perms['business.manage_permissions'] then return false, 'forbidden' end
            set = permsToSet(type(data.permissions) == 'table' and data.permissions or {})
            if not permsAllowedFor(ctx, set) then return false, 'permission_escalation' end
            -- A non-owner can never strip or add what they do not hold.
            if not ctx.isOwner then
                for _, p in ipairs(rank.permissions) do
                    if not ctx.perms[p] and not set[p] then return false, 'permission_escalation' end
                end
            end
            changes.permissions = true
        end
        if data.payAmount ~= nil then
            if not (ctx.perms['business.manage_payroll']) then return false, 'forbidden' end
            pay = math.floor(tonumber(data.payAmount) or -1)
            if pay < 0 or pay > Config.Payroll.MaxPayment or (pay > 0 and pay < Config.Payroll.MinPayment) then return false, 'invalid_amount' end
            if pay ~= rank.payAmount then changes.payAmount = pay end
        end
        if next(changes) == nil then return true end
        local okU = pcall(function()
            return MySQL.update.await('UPDATE cm_business_ranks SET name = ?, tier = ?, permissions = ?, pay_amount = ? WHERE id = ? AND business_type = ? AND business_id = ?',
                { name, tier, json.encode(permsToList(set)), pay, rank.id, biz.type, biz.id })
        end)
        if not okU then return false, 'duplicate_name' end
        local action = changes.permissions and 'permissions_changed' or (changes.payAmount and 'rank_pay_changed' or 'rank_edited')
        logActivity(biz, action, actorCid, nil, changes.payAmount, { rank = name, tier = tier, from = rank.name }, changes.permissions == true)
        return true
    end)
end

function C.DeleteRank(actorCid, t, i, rankId)
    local biz, ctx, why = authorize(actorCid, t, i, 'business.manage_ranks')
    if not biz then return false, why end
    return withLock('ranks:' .. biz.type .. ':' .. biz.id, function()
        local rank = getRank(biz, rankId)
        if not rank then return false, 'rank_not_found' end
        if not ctx.isOwner and rank.tier >= ctx.tier then return false, 'hierarchy' end
        local inUse = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_business_employees WHERE rank_id = ?', { rank.id })) or 0
        if inUse > 0 then return false, 'rank_in_use' end
        local total = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_business_ranks WHERE business_type = ? AND business_id = ?', { biz.type, biz.id })) or 0
        if total <= 1 then return false, 'last_rank' end
        MySQL.update.await('DELETE FROM cm_business_ranks WHERE id = ? AND business_type = ? AND business_id = ?', { rank.id, biz.type, biz.id })
        -- Keep an entry rank available: promote the lowest remaining tier if the flagged one was deleted.
        if rank.isEntry then
            MySQL.update.await('UPDATE cm_business_ranks SET is_entry = 1 WHERE business_type = ? AND business_id = ? ORDER BY tier ASC LIMIT 1', { biz.type, biz.id })
        end
        logActivity(biz, 'rank_deleted', actorCid, nil, nil, { rank = rank.name, tier = rank.tier })
        return true
    end)
end

-- ============================================================
-- Employees
-- ============================================================

local function rateKeyFor(cid) return 'c' .. tostring(cid) end

function C.SetEmployeeRank(actorCid, t, i, targetCid, rankId)
    targetCid = tonumber(targetCid)
    if not targetCid then return false, 'invalid_target' end
    if rateLimited(rateKeyFor(actorCid), 'mutate') then return false, 'rate_limited' end
    local biz, ctx, why = authorize(actorCid, t, i, 'business.manage_employees')
    if not biz then return false, why end
    if targetCid == biz.ownerCharacterId then return false, 'owner_protected' end
    if targetCid == tonumber(actorCid) and not ctx.isOwner then return false, 'hierarchy' end
    return withLock('emp:' .. biz.type .. ':' .. biz.id, function()
        local target = context(biz, targetCid)
        if not target then return false, 'not_employee' end
        if not ctx.isOwner and target.tier >= ctx.tier then return false, 'hierarchy' end
        local rank = getRank(biz, rankId)
        if not rank then return false, 'rank_not_found' end
        if not ctx.isOwner and rank.tier >= ctx.tier then return false, 'hierarchy' end
        MySQL.update.await('UPDATE cm_business_employees SET rank_id = ? WHERE business_type = ? AND business_id = ? AND character_id = ?', { rank.id, biz.type, biz.id, targetCid })
        logActivity(biz, 'rank_changed', actorCid, targetCid, nil, { rank = rank.name, tier = rank.tier, previous = target.rankName })
        return true
    end)
end

function C.RemoveEmployee(actorCid, t, i, targetCid, reason)
    targetCid = tonumber(targetCid)
    if not targetCid then return false, 'invalid_target' end
    if rateLimited(rateKeyFor(actorCid), 'mutate') then return false, 'rate_limited' end
    local biz, ctx, why
    if targetCid == tonumber(actorCid) then
        -- Resigning needs no management permission, only membership.
        biz, ctx, why = authorize(actorCid, t, i, nil)
        if biz and ctx.isOwner then return false, 'owner_protected' end
    else
        biz, ctx, why = authorize(actorCid, t, i, 'business.manage_employees')
    end
    if not biz then return false, why end
    if targetCid == biz.ownerCharacterId then return false, 'owner_protected' end
    return withLock('emp:' .. biz.type .. ':' .. biz.id, function()
        local target = context(biz, targetCid)
        if not target then return false, 'not_employee' end
        if targetCid ~= tonumber(actorCid) and not ctx.isOwner and target.tier >= ctx.tier then return false, 'hierarchy' end
        local n = MySQL.update.await('DELETE FROM cm_business_employees WHERE business_type = ? AND business_id = ? AND character_id = ?', { biz.type, biz.id, targetCid })
        if n ~= 1 then return false, 'not_employee' end
        logActivity(biz, targetCid == tonumber(actorCid) and 'employee_resigned' or 'employee_removed', actorCid, targetCid, nil,
            { rank = target.rankName, reason = type(reason) == 'string' and reason:sub(1, 60) or nil })
        return true
    end)
end

-- ============================================================
-- Invites (ephemeral, server-side; accept re-validates everything)
-- ============================================================

local inviteCounter = 0

local function newToken()
    inviteCounter = inviteCounter + 1
    return ('%x%x%d'):format(GetGameTimer(), math.random(0, 0xfffffff), inviteCounter)
end

-- Core invite logic (presence/distance is checked by the export wrapper). Returns true, token | false, reason.
function C.InviteCore(actorCid, targetCid, t, i, rankId, targetSrc)
    actorCid, targetCid = tonumber(actorCid), tonumber(targetCid)
    if not actorCid or not targetCid then return false, 'invalid_target' end
    if actorCid == targetCid then return false, 'invalid_target' end
    local biz, ctx, why = authorize(actorCid, t, i, 'business.invite')
    if not biz then return false, why end
    if targetCid == biz.ownerCharacterId then return false, 'already_employed' end
    if context(biz, targetCid) then return false, 'already_employed' end
    local rank
    if rankId ~= nil then
        rank = getRank(biz, rankId)
        if not rank then return false, 'rank_not_found' end
        if not ctx.isOwner and rank.tier >= ctx.tier then return false, 'hierarchy' end
    else
        rank = entryRank(biz, (not ctx.isOwner) and ctx.tier or nil)
        if not rank then return false, 'rank_not_found' end
    end
    local empCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_business_employees WHERE business_type = ? AND business_id = ?', { biz.type, biz.id })) or 0
    if empCount >= Config.MaxEmployeesPerBusiness then return false, 'employee_limit' end
    local pending = 0
    for _, inv in pairs(invites) do
        if inv.type == biz.type and inv.id == biz.id then
            if inv.targetCid == targetCid then return false, 'invite_pending' end
            pending = pending + 1
        end
    end
    if pending >= Config.Invites.MaxPendingPerBusiness then return false, 'too_many_invites' end
    local token = newToken()
    invites[token] = {
        token = token, type = biz.type, id = biz.id, epoch = biz.epoch, ownerAtInvite = biz.ownerCharacterId,
        inviterCid = actorCid, targetCid = targetCid, targetSrc = targetSrc, rankId = rank.id,
        expires = os.time() + Config.Invites.ExpirySeconds,
    }
    logActivity(biz, 'employee_invited', actorCid, targetCid, nil, { rank = rank.name })
    return true, token, { label = biz.label, rankName = rank.name, expiresIn = Config.Invites.ExpirySeconds }
end

function C.RespondCore(targetCid, token, accept, displayName)
    local inv = type(token) == 'string' and invites[token] or nil
    targetCid = tonumber(targetCid)
    if not inv or inv.targetCid ~= targetCid then return false, 'invalid_invite' end
    invites[token] = nil
    local biz = C.Resolve(inv.type, inv.id)
    if not biz then return false, 'invalid_business' end
    if os.time() > inv.expires then
        logActivity(biz, 'invite_expired', inv.inviterCid, targetCid, nil, nil)
        return false, 'expired'
    end
    if accept ~= true then
        logActivity(biz, 'invite_declined', inv.inviterCid, targetCid, nil, nil)
        return true, 'declined'
    end
    if inv.epoch ~= biz.epoch or inv.ownerAtInvite ~= biz.ownerCharacterId then return false, 'invite_invalid' end
    return withLock('emp:' .. biz.type .. ':' .. biz.id, function()
        local inviter = context(biz, inv.inviterCid)
        if not inviter or not inviter.perms['business.invite'] then return false, 'inviter_unauthorized' end
        local rank = getRank(biz, inv.rankId)
        if not rank or (not inviter.isOwner and rank.tier >= inviter.tier) then return false, 'rank_unavailable' end
        if targetCid == biz.ownerCharacterId or context(biz, targetCid) then return false, 'already_employed' end
        local empCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cm_business_employees WHERE business_type = ? AND business_id = ?', { biz.type, biz.id })) or 0
        if empCount >= Config.MaxEmployeesPerBusiness then return false, 'employee_limit' end
        local id = MySQL.insert.await('INSERT IGNORE INTO cm_business_employees (business_type, business_id, character_id, rank_id, display_name, hired_by) VALUES (?, ?, ?, ?, ?, ?)',
            { biz.type, biz.id, targetCid, rank.id, displayName and tostring(displayName):sub(1, 120) or nil, inv.inviterCid })
        if not id or id == 0 then return false, 'already_employed' end
        logActivity(biz, 'invite_accepted', inv.inviterCid, targetCid, nil, { rank = rank.name })
        return true, 'accepted', { label = biz.label, rankName = rank.name }
    end)
end

function C.PendingInvitesFor(cid)
    local out = {}
    for _, inv in pairs(invites) do
        if inv.targetCid == tonumber(cid) and os.time() <= inv.expires then out[#out + 1] = inv end
    end
    return out
end

CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for token, inv in pairs(invites) do
            if now > inv.expires + 5 then
                invites[token] = nil
                local biz = readBusiness(inv.type, inv.id)
                if biz and C.schemaReady then logActivity(biz, 'invite_expired', inv.inviterCid, inv.targetCid, nil, nil) end
            end
        end
    end
end)

-- ============================================================
-- Business balance contract (adapter over each business's own business_balance column)
-- ============================================================

local BALANCE_CAP = 2000000000
local keyCounter = 0

local function autoKey(prefix)
    keyCounter = keyCounter + 1
    return ('%s:%d:%d:%d'):format(prefix, os.time(), GetGameTimer(), keyCounter)
end

local function ledgerByKey(key)
    return MySQL.single.await('SELECT id, business_type, business_id, direction, amount, status, balance_after FROM cm_business_transactions WHERE idempotency_key = ?', { key })
end

-- opts: { kind, reason, key, actorCid, targetCid, status, metadata }
-- Returns true, { balance, transactionId, replayed } | false, reason
local function moveBalance(direction, t, i, amount, opts)
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount < 1 or amount > BALANCE_CAP then return false, 'invalid_amount' end
    local biz, why = C.Resolve(t, i)
    if not biz then return false, why end
    if not biz.ownerCharacterId then return false, 'no_owner' end
    local def = C.types[biz.type]
    local key = (opts.key and tostring(opts.key):sub(1, 120)) or autoKey(opts.kind or 'tx')
    local existing = ledgerByKey(key)
    if existing then
        if existing.business_type == biz.type and existing.business_id == biz.id and existing.direction == direction and tonumber(existing.amount) == amount then
            return true, { balance = tonumber(existing.balance_after), transactionId = tonumber(existing.id), replayed = true }
        end
        return false, 'idempotency_conflict'
    end
    local balSql
    if direction == 'credit' then
        balSql = ('UPDATE `%s` SET `%s` = `%s` + ? WHERE `%s` = ? AND `%s` = ? AND `%s` + ? <= ?'):format(def.table, def.balanceColumn, def.balanceColumn, def.idColumn, def.ownerColumn, def.balanceColumn)
    else
        balSql = ('UPDATE `%s` SET `%s` = `%s` - ? WHERE `%s` = ? AND `%s` = ? AND `%s` >= ?'):format(def.table, def.balanceColumn, def.balanceColumn, def.idColumn, def.ownerColumn, def.balanceColumn)
    end
    local balParams = direction == 'credit' and { amount, biz.id, biz.ownerCharacterId, amount, BALANCE_CAP } or { amount, biz.id, biz.ownerCharacterId, amount }
    -- One SQL transaction: the guarded balance UPDATE, then a ledger row that only exists when that UPDATE
    -- changed exactly one row (ROW_COUNT()). A duplicate idempotency key aborts the whole transaction,
    -- rolling the balance change back, so replays can never apply twice.
    local insertSql = ('INSERT INTO cm_business_transactions (business_type, business_id, direction, amount, kind, reason, idempotency_key, actor_character_id, target_character_id, status, balance_after, metadata) '
        .. 'SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, (SELECT `%s` FROM `%s` WHERE `%s` = ?), ? FROM DUAL WHERE ROW_COUNT() = 1'):format(def.balanceColumn, def.table, def.idColumn)
    local okTx = pcall(function()
        return MySQL.transaction.await({
            { query = balSql, values = balParams },
            { query = insertSql, values = { biz.type, biz.id, direction, amount, tostring(opts.kind or 'tx'):sub(1, 32), tostring(opts.reason or opts.kind or 'tx'):sub(1, 100), key,
                opts.actorCid, opts.targetCid, opts.status or 'applied', biz.id, opts.metadata and encode(opts.metadata) or nil } },
        })
    end)
    local row = ledgerByKey(key)
    if not okTx or not row then
        -- A concurrent identical request may have won the unique key: that is an idempotent replay.
        if row and row.business_type == biz.type and row.business_id == biz.id and row.direction == direction and tonumber(row.amount) == amount then
            return true, { balance = tonumber(row.balance_after), transactionId = tonumber(row.id), replayed = true }
        end
        if direction == 'debit' then
            local current = readBusiness(biz.type, biz.id)
            if current and current.balance < amount then return false, 'insufficient_funds' end
        end
        return false, 'rejected'
    end
    local txId, after = tonumber(row.id), tonumber(row.balance_after)
    return true, { balance = after, transactionId = txId, replayed = false }
end

C.MoveBalance = moveBalance

local function invoker() return C.TestInvoker or GetInvokingResource() or RESOURCE end

function C.CallerAllowed(kind, caller)
    caller = caller or invoker()
    return (Config.BalanceCallers[kind] or {})[caller] == true, caller
end
local function callerAllowed(kind) return C.CallerAllowed(kind) end

function C.GetBusinessBalance(t, i)
    local biz = C.Resolve(t, i)
    if not biz or not biz.ownerCharacterId then return nil end
    return biz.balance
end

function C.CreditBusinessAtomic(t, i, amount, reason, metadata)
    local allowed, caller = callerAllowed('credit')
    if not allowed then return false, 'forbidden' end
    metadata = type(metadata) == 'table' and metadata or {}
    return moveBalance('credit', t, i, amount, {
        kind = 'credit', reason = reason, key = metadata.idempotencyKey, targetCid = tonumber(metadata.targetCharacterId),
        actorCid = tonumber(metadata.actorCharacterId), metadata = { caller = caller, ref = metadata.reference },
    })
end

function C.DebitBusinessAtomic(t, i, amount, reason, metadata)
    local allowed, caller = callerAllowed('debit')
    if not allowed then return false, 'forbidden' end
    metadata = type(metadata) == 'table' and metadata or {}
    return moveBalance('debit', t, i, amount, {
        kind = 'debit', reason = reason, key = metadata.idempotencyKey, targetCid = tonumber(metadata.targetCharacterId),
        actorCid = tonumber(metadata.actorCharacterId), metadata = { caller = caller, ref = metadata.reference },
    })
end

function C.HasBusinessTransaction(key)
    if not Config.BalanceCallers.credit[invoker()] then return false end
    return type(key) == 'string' and ledgerByKey(key:sub(1, 120)) ~= nil
end

-- ============================================================
-- Manual payroll: BUSINESS FUNDS -> EMPLOYEE bank. Never mints money.
-- ============================================================

function C.PayEmployee(actorCid, t, i, targetCid)
    targetCid = tonumber(targetCid)
    if not Config.Payroll.Enabled then return false, 'payroll_disabled' end
    if not targetCid then return false, 'invalid_target' end
    if rateLimited(rateKeyFor(actorCid), 'payroll') then return false, 'rate_limited' end
    local biz, ctx, why = authorize(actorCid, t, i, 'business.pay_employees')
    if not biz then return false, why end
    if targetCid == tonumber(actorCid) then return false, 'self_payment' end
    if targetCid == biz.ownerCharacterId then return false, 'owner_protected' end
    return withLock('pay:' .. biz.type .. ':' .. biz.id, function()
        local target = context(biz, targetCid)
        if not target then return false, 'not_employee' end
        if target.rankMissing then return false, 'rank_missing' end
        if not ctx.isOwner and target.tier >= ctx.tier then return false, 'hierarchy' end
        local amount = math.floor(tonumber(target.payAmount) or 0)
        if amount < Config.Payroll.MinPayment or amount > Config.Payroll.MaxPayment then return false, 'pay_not_configured' end
        -- Claim the cooldown window atomically first: concurrent requests cannot both pass.
        local prev = MySQL.scalar.await('SELECT last_paid_at FROM cm_business_employees WHERE id = ?', { target.employeeId })
        local claimed = MySQL.update.await('UPDATE cm_business_employees SET last_paid_at = UTC_TIMESTAMP() WHERE id = ? AND (last_paid_at IS NULL OR last_paid_at <= DATE_SUB(UTC_TIMESTAMP(), INTERVAL ? SECOND))',
            { target.employeeId, Config.Payroll.EmployeeCooldownSeconds })
        if claimed ~= 1 then return false, 'cooldown' end
        local function revert()
            MySQL.update.await('UPDATE cm_business_employees SET last_paid_at = ? WHERE id = ?', { prev, target.employeeId })
        end
        local opKey = autoKey(('payroll:%s:%s:%d'):format(biz.type, biz.id, targetCid))
        local ok, res = moveBalance('debit', biz.type, biz.id, amount, {
            kind = 'payroll', reason = 'payroll', key = opKey, actorCid = actorCid, targetCid = targetCid, status = 'pending',
        })
        if not ok then revert(); return false, res end
        local txId = res.transactionId
        local api = playerData()
        local credited = false
        if C.TestCreditCharacter then -- development self-test hook only (set by server/selftest.lua)
            credited = C.TestCreditCharacter(targetCid, amount, txId) == true
        elseif api then
            local okc, r = pcall(function()
                return api:AddMoneyToCharacter(targetCid, Config.Payroll.Account, amount, 'cm-business-payroll:' .. txId, { business = biz.type .. ':' .. biz.id })
            end)
            credited = okc and r == true
        end
        if not credited then
            moveBalance('credit', biz.type, biz.id, amount, { kind = 'payroll_refund', reason = 'payroll refund', key = opKey .. ':refund', actorCid = actorCid, targetCid = targetCid })
            MySQL.update.await("UPDATE cm_business_transactions SET status = 'refunded' WHERE id = ?", { txId })
            revert()
            return false, 'settlement_failed'
        end
        MySQL.update.await("UPDATE cm_business_transactions SET status = 'settled' WHERE id = ?", { txId })
        logActivity(biz, 'payroll_paid', actorCid, targetCid, amount, { rank = target.rankName }, true)
        local tsrc = sourceOfCid(targetCid)
        if tsrc then notifySrc(tsrc, ('You were paid $%d by %s.'):format(amount, biz.label), 'success') end
        return true, { amount = amount, balance = res.balance }
    end)
end

-- Crash recovery: a payroll debit left 'pending' is either settled (credit evidence) or refunded.
function C.ReconcilePayroll()
    if not C.EnsureSchema() then return 0 end
    local rows = MySQL.query.await("SELECT id, business_type, business_id, amount, target_character_id, idempotency_key FROM cm_business_transactions WHERE kind = 'payroll' AND status = 'pending' AND created_at < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 30 SECOND)") or {}
    local fixed = 0
    for _, row in ipairs(rows) do
        local seen = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM economy_transactions WHERE character_id = ? AND action = ? AND reason = ?',
            { row.target_character_id, 'add', 'cm-business-payroll:' .. row.id })) or 0
        if C.TestPayrollEvidence and C.TestPayrollEvidence(row) then seen = 1 end
        if seen > 0 then
            MySQL.update.await("UPDATE cm_business_transactions SET status = 'settled' WHERE id = ?", { row.id })
        else
            moveBalance('credit', row.business_type, row.business_id, tonumber(row.amount), { kind = 'payroll_refund', reason = 'payroll reconcile refund', key = row.idempotency_key .. ':refund', targetCid = tonumber(row.target_character_id) })
            MySQL.update.await("UPDATE cm_business_transactions SET status = 'refunded' WHERE id = ?", { row.id })
        end
        fixed = fixed + 1
    end
    return fixed
end

-- ============================================================
-- Business invoices -> cm-billing (trusted provider path)
-- ============================================================

function C.CreateBusinessInvoice(actorCid, t, i, data, skipPresence)
    data = type(data) == 'table' and data or {}
    if not Config.Invoices.Enabled then return false, 'invoices_disabled' end
    if rateLimited(rateKeyFor(actorCid), 'invoice') then return false, 'rate_limited' end
    local biz, ctx, why = authorize(actorCid, t, i, 'business.create_invoice')
    if not biz then return false, why end
    local amount = math.floor(tonumber(data.amount) or 0)
    if amount < 1 or amount > Config.Invoices.MaxAmount then return false, 'invalid_amount' end
    local recipient = tonumber(data.recipientCharacterId)
    if not recipient or recipient == tonumber(actorCid) then return false, 'invalid_recipient' end
    local label = type(data.label) == 'string' and data.label:sub(1, 80) or ''
    if #label < 2 then return false, 'invalid_label' end
    if GetResourceState('cm-billing') ~= 'started' then return false, 'unavailable' end
    local okc, ok, result = pcall(function()
        return exports['cm-billing']:CreateInvoice({
            recipientCharacterId = tostring(recipient), amount = amount, label = label,
            issuerType = 'business', issuerLabel = biz.label:sub(1, 64), issuerCharacterId = (not C.TestSkipIssuer) and tostring(actorCid) or nil,
            issuerEntityId = biz.type .. ':' .. biz.id,
            destination = { type = 'business', id = biz.type .. ':' .. biz.id },
            expiresInSeconds = 3600,
            idempotencyKey = type(data.idempotencyKey) == 'string' and data.idempotencyKey:sub(1, 80) or nil,
            metadata = { ['business.type'] = biz.type, ['business.id'] = biz.id },
        })
    end)
    if not okc then return false, 'unavailable' end
    if ok ~= true then return false, tostring(result) end
    logActivity(biz, 'invoice_created', actorCid, recipient, amount, { reference = result and result.reference })
    return true, result
end

-- ============================================================
-- Admin recovery contracts (callers allowlisted; cm-admin remains the permission gate)
-- ============================================================

local function adminAllowed()
    return Config.AdminCallers[C.TestInvoker or GetInvokingResource() or RESOURCE] == true
end

function C.AdminInspect(t, i)
    if not adminAllowed() then return nil, 'forbidden' end
    local biz, why = C.Resolve(t, i)
    if not biz then return nil, why end
    return { business = C.GetBusiness(t, i), ranks = getRanksRaw(biz), employees = listEmployees(biz) }
end

function C.AdminGetActivity(t, i, limit)
    if not adminAllowed() then return nil, 'forbidden' end
    local biz, why = C.Resolve(t, i)
    if not biz then return nil, why end
    limit = math.min(200, math.max(1, math.floor(tonumber(limit) or 50)))
    return MySQL.query.await('SELECT id, action, actor_character_id, target_character_id, amount, metadata, created_at FROM cm_business_activity WHERE business_type = ? AND business_id = ? ORDER BY id DESC LIMIT ?', { biz.type, biz.id, limit }) or {}
end

function C.AdminRemoveEmployee(t, i, targetCid, adminLabel)
    if not adminAllowed() then return false, 'forbidden' end
    local biz, why = C.Resolve(t, i)
    if not biz then return false, why end
    targetCid = tonumber(targetCid)
    if not targetCid then return false, 'invalid_target' end
    local n = MySQL.update.await('DELETE FROM cm_business_employees WHERE business_type = ? AND business_id = ? AND character_id = ?', { biz.type, biz.id, targetCid })
    if n ~= 1 then return false, 'not_employee' end
    logActivity(biz, 'admin_employee_removed', nil, targetCid, nil, { admin = tostring(adminLabel or 'admin'):sub(1, 40) }, true)
    return true
end

function C.AdminResetEmployeeRank(t, i, targetCid, rankId, adminLabel)
    if not adminAllowed() then return false, 'forbidden' end
    local biz, why = C.Resolve(t, i)
    if not biz then return false, why end
    targetCid = tonumber(targetCid)
    local rank = rankId and getRank(biz, rankId) or entryRank(biz)
    if not targetCid or not rank then return false, 'rank_not_found' end
    local n = MySQL.update.await('UPDATE cm_business_employees SET rank_id = ? WHERE business_type = ? AND business_id = ? AND character_id = ?', { rank.id, biz.type, biz.id, targetCid })
    if n == nil or n < 0 then return false, 'not_employee' end
    logActivity(biz, 'admin_rank_reset', nil, targetCid, nil, { rank = rank.name, admin = tostring(adminLabel or 'admin'):sub(1, 40) }, true)
    return true
end

-- Re-seeds missing default ranks and re-homes employees whose rank row vanished onto the entry rank.
function C.AdminRepair(t, i, adminLabel)
    if not adminAllowed() then return nil, 'forbidden' end
    local biz, why = C.Resolve(t, i)
    if not biz then return nil, why end
    ensureRanks(biz)
    local entry = entryRank(biz)
    local fixed = 0
    if entry then
        fixed = MySQL.update.await('UPDATE cm_business_employees e LEFT JOIN cm_business_ranks r ON r.id = e.rank_id SET e.rank_id = ? WHERE e.business_type = ? AND e.business_id = ? AND r.id IS NULL',
            { entry.id, biz.type, biz.id }) or 0
    end
    logActivity(biz, 'admin_repair', nil, nil, nil, { employeesRepaired = fixed, admin = tostring(adminLabel or 'admin'):sub(1, 40) }, true)
    return { employeesRepaired = fixed }
end

-- ============================================================
-- Ownership change detection: engine hook + periodic sweep
-- ============================================================

local BOOK_ALIASES = { clothing_store = 'clothing' } -- engine book keys that differ from registry types

function C.NotifyOwnerChange(t, i)
    t = BOOK_ALIASES[t] or t
    CreateThread(function() C.Resolve(t, i) end)
end

CreateThread(function()
    Wait(8000)
    pcall(C.ReconcilePayroll)
    while true do
        Wait(60000)
        if C.schemaReady then
            local rows = MySQL.query.await('SELECT business_type, business_id FROM cm_business_state') or {}
            for _, r in ipairs(rows) do pcall(C.Resolve, r.business_type, r.business_id) end
        end
    end
end)

-- Exposed for the UI layer / self-test.
C.context, C.authorize, C.getRank, C.getRanksRaw, C.listEmployees = context, authorize, getRank, getRanksRaw, listEmployees
C.cidOfSource, C.sourceOfCid, C.fullName, C.notifySrc = cidOfSource, sourceOfCid, fullName, notifySrc
C.invites = function() return invites end
C.readBusiness = readBusiness
C.ledgerByKey = ledgerByKey
