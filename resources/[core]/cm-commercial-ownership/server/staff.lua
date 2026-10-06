-- cm-commercial-ownership/server/staff.lua
-- Public server exports + the shared staff-panel event layer.
-- The panel is BOUND to the business it was opened for (server-side session); the client never chooses
-- the business, owner, rank tier, permission list, amount or target identity for an action.

local C = CMB

local MESSAGES = {
    forbidden = 'You are not allowed to do that.', hierarchy = 'You cannot manage someone of equal or higher rank.',
    owner_protected = 'The owner cannot be changed here.', not_employee = 'That person does not work here.',
    already_employed = 'That person already works here.', invite_pending = 'An invitation is already pending.',
    too_many_invites = 'Too many pending invitations.', employee_limit = 'This business has reached its staff limit.',
    rank_not_found = 'That rank does not exist.', rank_in_use = 'Employees still hold that rank.', last_rank = 'A business needs at least one rank.',
    invalid_name = 'Rank name must be 2-32 characters.', invalid_tier = 'Invalid rank tier.', duplicate_name = 'That rank name already exists.',
    rank_limit = 'Rank limit reached.', permission_escalation = 'You cannot grant permissions you do not hold.',
    invalid_amount = 'Invalid amount.', pay_not_configured = 'No pay is configured for this rank.', cooldown = 'This employee was paid recently.',
    insufficient_funds = 'The business cannot afford that.', settlement_failed = 'Payment failed and was refunded to the business.',
    self_payment = 'You cannot pay yourself.', rate_limited = 'Slow down.', busy = 'Busy, try again.', no_owner = 'This business has no owner.',
    not_nearby = 'That person is not close enough.', expired = 'The invitation expired.', invite_invalid = 'The invitation is no longer valid.',
    invalid_invite = 'No such invitation.', inviter_unauthorized = 'The inviter no longer has authority.', rank_unavailable = 'That rank is no longer available.',
    invalid_item = 'That item is not available.', invalid_quantity = 'Invalid quantity.', invalid_lines = 'Add at least one item.',
    order_too_large = 'That order is too large.', over_capacity = 'That would exceed the business storage capacity.',
    too_many_orders = 'Too many open orders for this business.', quote_expired = 'The quote expired. Request a new one.',
    invalid_quote = 'That quote is no longer valid.', price_changed = 'Prices changed. Request a new quote.',
    order_not_found = 'Order not found.', invalid_state = 'That order can no longer be changed.', supply_unsupported = 'This business does not order supplies.',
    catalog_unavailable = 'The supplier catalog is unavailable.', payment_failed = 'Payment failed.', supply_disabled = 'Supply orders are disabled.',
    payroll_disabled = 'Payroll is disabled.', rank_missing = 'Fix this employee\'s rank first.', unavailable = 'Unavailable right now.',
}
local function say(reason) return MESSAGES[reason] or 'Request failed.' end

-- ---- Presence ------------------------------------------------------------------
local function distanceBetween(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if not pa or pa == 0 or not pb or pb == 0 then return nil end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

local function nearby(a, b, maxDist)
    if tonumber(a) == tonumber(b) then return false end
    if GetPlayerRoutingBucket(a) ~= GetPlayerRoutingBucket(b) then return false end
    local d = distanceBetween(a, b)
    return d ~= nil and d <= maxDist
end

-- ---- Exports: reads ------------------------------------------------------------
exports('GetBusiness', C.GetBusiness)
exports('GetBusinessOwner', C.GetBusinessOwner)
exports('IsEmployee', C.IsEmployee)
exports('GetEmployee', C.GetEmployee)
exports('GetEmployeePermissions', C.GetEmployeePermissions)
exports('HasBusinessPermission', C.HasBusinessPermission)
exports('GetEmployees', C.GetEmployees)
exports('GetRanks', C.GetRanks)
exports('GetPlayerBusinesses', C.GetPlayerBusinesses)
exports('GetBusinessBalance', C.GetBusinessBalance)
exports('CreditBusinessAtomic', C.CreditBusinessAtomic)
exports('DebitBusinessAtomic', C.DebitBusinessAtomic)
exports('HasBusinessTransaction', C.HasBusinessTransaction)

-- ---- Exports: actor-validated mutations (actor = server source) -----------------
local function actorCid(src) return C.cidOfSource(src) end

exports('InviteEmployee', function(actorSrc, targetSrc, t, i, rankId)
    local a, b = actorCid(actorSrc), actorCid(targetSrc)
    if not a or not b then return false, 'invalid_target' end
    if C.RateLimited('c' .. a, 'invite') then return false, 'rate_limited' end
    if not nearby(actorSrc, targetSrc, Config.Invites.MaxDistance) then return false, 'not_nearby' end
    local ok, token, info = C.InviteCore(a, b, t, i, rankId, targetSrc)
    if not ok then return false, token end
    TriggerClientEvent('cm-commercial-ownership:client:invite', targetSrc, { token = token, label = info.label, rankName = info.rankName, expiresIn = info.expiresIn })
    return true
end)

exports('RespondToInvite', function(src, token, accept)
    local cid = actorCid(src)
    if not cid then return false, 'invalid_invite' end
    local inv = C.invites()[token]
    if accept == true and inv and inv.targetCid == cid then
        local inviterSrc = C.sourceOfCid(inv.inviterCid)
        if not inviterSrc or not nearby(src, inviterSrc, Config.Invites.MaxDistance * 2) then return false, 'not_nearby' end
    end
    local ok, result = C.RespondCore(cid, token, accept == true, C.fullName(src))
    if ok and result == 'accepted' then
        local inviterSrc = inv and C.sourceOfCid(inv.inviterCid)
        C.notifySrc(inviterSrc, 'Your invitation was accepted.', 'success')
    elseif ok and result == 'declined' then
        local inviterSrc = inv and C.sourceOfCid(inv.inviterCid)
        C.notifySrc(inviterSrc, 'Your invitation was declined.', 'info')
    end
    return ok, result
end)

exports('RemoveEmployee', function(actorSrc, t, i, targetCid, reason)
    local a = actorCid(actorSrc)
    if not a then return false, 'forbidden' end
    return C.RemoveEmployee(a, t, i, targetCid, reason)
end)
exports('SetEmployeeRank', function(actorSrc, t, i, targetCid, rankId)
    local a = actorCid(actorSrc)
    if not a then return false, 'forbidden' end
    return C.SetEmployeeRank(a, t, i, targetCid, rankId)
end)
exports('CreateRank', function(actorSrc, t, i, data)
    local a = actorCid(actorSrc)
    if not a then return false, 'forbidden' end
    return C.CreateRank(a, t, i, data)
end)
exports('UpdateRank', function(actorSrc, t, i, rankId, data)
    local a = actorCid(actorSrc)
    if not a then return false, 'forbidden' end
    return C.UpdateRank(a, t, i, rankId, data)
end)
exports('DeleteRank', function(actorSrc, t, i, rankId)
    local a = actorCid(actorSrc)
    if not a then return false, 'forbidden' end
    return C.DeleteRank(a, t, i, rankId)
end)
exports('PayEmployee', function(actorSrc, t, i, targetCid)
    local a = actorCid(actorSrc)
    if not a then return false, 'forbidden' end
    return C.PayEmployee(a, t, i, targetCid)
end)
-- Trusted business-platform path to cm-billing: validates `business.create_invoice` and customer presence.
exports('CreateBusinessInvoice', function(actorSrc, recipientSrc, t, i, data)
    local a, r = actorCid(actorSrc), actorCid(recipientSrc)
    if not a or not r then return false, 'invalid_recipient' end
    if not nearby(actorSrc, recipientSrc, Config.Invoices.MaxDistance) then return false, 'not_nearby' end
    data = type(data) == 'table' and data or {}
    return C.CreateBusinessInvoice(a, t, i, { recipientCharacterId = r, amount = data.amount, label = data.label, idempotencyKey = data.idempotencyKey })
end)

-- ---- Exports: supply (business side; actor = server source) ----------------------
local SUP = C.Supply
exports('GetSupplyCatalog', function(actorSrc, t, i) local a = actorCid(actorSrc); if not a then return false, 'forbidden' end return SUP.GetCatalog(a, t, i) end)
exports('QuoteSupplyOrder', function(actorSrc, t, i, lines) local a = actorCid(actorSrc); if not a then return false, 'forbidden' end return SUP.Quote(a, t, i, lines) end)
exports('PlaceSupplyOrder', function(actorSrc, t, i, opts) local a = actorCid(actorSrc); if not a then return false, 'forbidden' end return SUP.Place(a, t, i, opts) end)
exports('CancelSupplyOrder', function(actorSrc, t, i, ref) local a = actorCid(actorSrc); if not a then return false, 'forbidden' end return SUP.Cancel(a, t, i, ref) end)
exports('GetSupplyOrders', function(actorSrc, t, i, limit) local a = actorCid(actorSrc); if not a then return false, 'forbidden' end return SUP.List(a, t, i, limit) end)

-- ---- Exports: generic broker (cm-contracts) SOURCE callbacks; caller must be cm-contracts ----
-- One set of source callbacks serves every type this resource publishes: business_supply (SUP) and bulk_material_transport (MAT).
local MAT = C.Materials
local function bySource(name, supFn, matFn)
    exports(name, function(ctx)
        if type(ctx) == 'table' and ctx.contractType == 'bulk_material_transport' then return matFn(ctx) end
        return supFn(ctx)
    end)
end
bySource('ContractSourceComplete', SUP.ContractComplete, MAT.ContractComplete)
bySource('ContractSourceFallback', SUP.ContractFallback, MAT.ContractFallback)
bySource('ContractSourceCancel', SUP.ContractCancel, MAT.ContractCancel)
bySource('ContractSourceEvent', SUP.ContractEvent, MAT.ContractEvent)

-- ---- Exports: business materials (server-only; allowlisted callers, see Config.Materials.Callers; no client path, no withdrawal) ----
exports('GetBusinessMaterialStock', function(t, i, materialId) return MAT.GetStock(t, i, materialId) end)
exports('GetBusinessMaterials', function(t, i) return MAT.GetMaterials(t, i) end)
exports('CreditBusinessMaterial', function(reference, t, i, materialId, quantity, context) return MAT.Credit(reference, t, i, materialId, quantity, context) end)
exports('ConsumeBusinessMaterial', function(reference, t, i, requirements, context) return MAT.Consume(reference, t, i, requirements, context) end)
exports('CreateMaterialDemand', function(opts) return MAT.CreateDemand(opts) end)
exports('CancelMaterialDemand', function(ref, reason) return MAT.CancelDemand(ref, reason) end)
exports('GetMaterialDemand', function(ref) return MAT.GetDemand(ref) end)
exports('GetMaterialDemands', function(t, i) return MAT.ListDemands(t, i) end)
exports('DeliverBusinessMaterials', function(reference, demandRef, characterId, quantity, context) return MAT.Deliver(reference, demandRef, characterId, quantity, context) end)
exports('GetMaterialDeliveryStatus', function(reference) return MAT.GetDeliveryStatus(reference) end)
-- Admin / recovery (caller must be cm-admin; UI wiring deferred)
exports('AdminListMaterialDemands', function(filter) return MAT.AdminListDemands(filter) end)
exports('AdminInspectMaterialDemand', function(ref) return MAT.AdminInspectDemand(ref) end)
exports('AdminListMaterialDeliveries', function() return MAT.AdminListDeliveries() end)
exports('AdminGetBusinessMaterials', function(t, i) return MAT.AdminBusinessMaterials(t, i) end)
exports('AdminCancelMaterialDemand', function(ref, reason) return MAT.AdminCancelDemand(ref, reason) end)
exports('AdminReconcileMaterialDeliveries', function() return MAT.AdminReconcile() end)

-- ---- Deprecated provider exports (kept only so a stale caller gets 'deprecated_use_cm-contracts') ----
exports('ListAvailableSupplyContracts', SUP.ListAvailable)
exports('ClaimSupplyOrder', SUP.Claim)
exports('ReleaseSupplyOrder', SUP.Release)
exports('MarkSupplyOrderInTransit', SUP.InTransit)
exports('CompleteSupplyOrder', SUP.Complete)
exports('FailSupplyOrder', SUP.Fail)
exports('GetSupplyOrderStatus', SUP.ProviderStatus)

-- ---- Exports: admin recovery (caller must be cm-admin) --------------------------
exports('AdminInspectBusiness', C.AdminInspect)
exports('AdminGetActivity', C.AdminGetActivity)
exports('AdminRemoveEmployee', C.AdminRemoveEmployee)
exports('AdminResetEmployeeRank', C.AdminResetEmployeeRank)
exports('AdminRepairBusiness', C.AdminRepair)
exports('AdminListSupplyOrders', SUP.AdminList)
exports('AdminInspectSupplyOrder', SUP.AdminInspect)
exports('AdminCancelSupplyOrder', SUP.AdminCancel)
exports('AdminReconcileSupplyOrders', SUP.AdminReconcile)
exports('AdminDeliverSupplyOrder', SUP.AdminDeliver)

-- ============================================================
-- Staff panel
-- ============================================================

local sessions = {}   -- [src] = { type, id }
local candidates = {} -- [src] = { [key] = { src, cid, expires } }

local function snapshot(src, cid, biz, ctx)
    local perms = ctx.perms
    local isOwner = ctx.isOwner
    local caps = {
        viewEmployees = perms['business.view_employees'] == true, invite = perms['business.invite'] == true,
        manageEmployees = perms['business.manage_employees'] == true, manageRanks = perms['business.manage_ranks'] == true,
        managePermissions = perms['business.manage_permissions'] == true, viewActivity = perms['business.view_activity'] == true,
        viewFinance = perms['business.view_finance'] == true, payEmployees = perms['business.pay_employees'] == true,
        managePayroll = perms['business.manage_payroll'] == true, createInvoice = perms['business.create_invoice'] == true,
        manageOrders = perms['business.manage_orders'] == true,
    }
    local names = {}
    if biz.ownerCharacterId then names[biz.ownerCharacterId] = biz.ownerName or 'Owner' end
    local data = {
        business = { type = biz.type, id = biz.id, label = biz.label },
        you = { rank = ctx.rankName, isOwner = isOwner, characterId = cid },
        caps = caps,
        payroll = { enabled = Config.Payroll.Enabled, min = Config.Payroll.MinPayment, max = Config.Payroll.MaxPayment, cooldown = Config.Payroll.EmployeeCooldownSeconds },
    }
    if caps.viewEmployees then
        local employees, ranks = {}, C.getRanksRaw(biz)
        local counts = {}
        for _, e in ipairs(C.listEmployees(biz)) do
            counts[e.rankId] = (counts[e.rankId] or 0) + 1
            names[e.characterId] = e.name
            local lower = isOwner or e.tier < ctx.tier
            employees[#employees + 1] = {
                characterId = e.characterId, name = e.name or ('#' .. e.characterId), rankId = e.rankId, rank = e.rankName, tier = e.tier,
                hiredAt = e.hiredAt, rankMissing = e.rankMissing, payAmount = e.payAmount,
                canManage = caps.manageEmployees and lower and e.characterId ~= cid,
                canPay = caps.payEmployees and lower and e.payAmount > 0 and e.characterId ~= cid,
                isSelf = e.characterId == cid,
            }
        end
        local assignable = {}
        for _, r in ipairs(ranks) do
            r.employees = counts[r.id] or 0
            r.canEdit = caps.manageRanks and (isOwner or r.tier < ctx.tier)
            if isOwner or r.tier < ctx.tier then assignable[#assignable + 1] = { id = r.id, name = r.name, tier = r.tier } end
        end
        data.employees, data.ranks, data.assignable = employees, ranks, assignable
        local catalogue = {}
        for _, p in ipairs(Config.Permissions) do
          if p.types == nil or p.types[biz.type] then -- type-scoped permissions (e.g. mechanic.*) only show for their business type
            catalogue[#catalogue + 1] = { id = p.id, label = p.label, implemented = p.implemented, grantable = isOwner or perms[p.id] == true }
          end
        end
        data.permissions = catalogue
        data.limits = { maxTier = Config.MaxRankTier, maxRanks = Config.MaxRanksPerBusiness }
    end
    if caps.viewFinance then data.balance = biz.balance end
    if caps.manageOrders then
        local okO, orders = SUP.List(cid, biz.type, biz.id, 15)
        data.supply = { supported = okO == true }
        if okO == true then data.orders = orders end
    end
    if caps.viewActivity then
        local rows = MySQL.query.await('SELECT action, actor_character_id, target_character_id, amount, created_at FROM cm_business_activity WHERE business_type = ? AND business_id = ? ORDER BY id DESC LIMIT ?',
            { biz.type, biz.id, Config.ActivityPageSize }) or {}
        local feed = {}
        local function label(c) c = tonumber(c); if not c then return nil end; return names[c] or ('#' .. c) end
        for _, r in ipairs(rows) do
            feed[#feed + 1] = { action = r.action, actor = label(r.actor_character_id), target = label(r.target_character_id), amount = tonumber(r.amount), at = tostring(r.created_at) }
        end
        data.activity = feed
    end
    return data
end

local function push(src, mode)
    local s = sessions[src]
    local cid = actorCid(src)
    if not s or not cid then return end
    local biz, ctx = C.authorize(cid, s.type, s.id, nil)
    if not biz or not ctx then
        sessions[src] = nil
        TriggerClientEvent('cm-commercial-ownership:client:close', src)
        return
    end
    TriggerClientEvent('cm-commercial-ownership:client:state', src, mode or 'update', snapshot(src, cid, biz, ctx))
end

local function open(src, t, i)
    local cid = actorCid(src)
    if not cid then return false, 'forbidden' end
    if C.RateLimited('c' .. cid, 'open') then return false, 'rate_limited' end
    local biz, ctx, why = C.authorize(cid, t, i, 'business.view_employees')
    if not biz then return false, why end
    sessions[src] = { type = biz.type, id = biz.id }
    push(src, 'open')
    return true
end

exports('OpenStaffPanel', function(src, t, i)
    local ok, why = open(src, t, i)
    if not ok then C.notifySrc(src, say(why), 'error') end
    return ok
end)

RegisterNetEvent('cm-commercial-ownership:server:open', function(t, i)
    local src = source
    local ok, why = open(src, t, i)
    if not ok then C.notifySrc(src, say(why), 'error') end
end)

RegisterNetEvent('cm-commercial-ownership:server:close', function()
    sessions[source] = nil
    candidates[source] = nil
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
    candidates[source] = nil
end)

local function result(src, ok, why, extra)
    TriggerClientEvent('cm-commercial-ownership:client:result', src, { ok = ok == true, message = ok and (extra or 'Done.') or say(why) })
end

local function listCandidates(src, cid, biz)
    local out, store = {}, {}
    local api = exports['cm-playerdata']
    local okK, known = pcall(function() return api:GetKnownIdentities(cid) end)
    known = okK and known or {}
    for _, p in ipairs(GetPlayers()) do
        local other = tonumber(p)
        if other and other ~= src and nearby(src, other, Config.Invites.MaxDistance * 1.5) then
            local ocid = actorCid(other)
            if ocid and ocid ~= biz.ownerCharacterId and not C.context(biz, ocid) then
                local key = ('%x%x'):format(math.random(0, 0xffffff), GetGameTimer())
                store[key] = { src = other, cid = ocid, expires = os.time() + 90 }
                local name = known[ocid] and C.fullName(other) or nil
                out[#out + 1] = { key = key, label = name or ('Stranger #' .. ocid) }
            end
        end
    end
    candidates[src] = store
    return out
end

local ACTIONS = {
    refresh = function(src, cid, s) push(src, 'update'); return true end,
    candidates = function(src, cid, s, p)
        local biz, ctx, why = C.authorize(cid, s.type, s.id, 'business.invite')
        if not biz then return false, why end
        TriggerClientEvent('cm-commercial-ownership:client:candidates', src, listCandidates(src, cid, biz))
        return true, nil, true
    end,
    invite = function(src, cid, s, p)
        local c = type(p.candidate) == 'string' and candidates[src] and candidates[src][p.candidate] or nil
        if not c or os.time() > c.expires or actorCid(c.src) ~= c.cid then return false, 'not_nearby' end
        candidates[src][p.candidate] = nil
        local ok, why = exports[GetCurrentResourceName()]:InviteEmployee(src, c.src, s.type, s.id, tonumber(p.rankId))
        return ok, why, nil, 'Invitation sent.'
    end,
    setRank = function(src, cid, s, p)
        local ok, why = C.SetEmployeeRank(cid, s.type, s.id, tonumber(p.characterId), tonumber(p.rankId))
        return ok, why, nil, 'Rank updated.'
    end,
    remove = function(src, cid, s, p)
        local ok, why = C.RemoveEmployee(cid, s.type, s.id, tonumber(p.characterId), 'panel')
        return ok, why, nil, 'Employee removed.'
    end,
    createRank = function(src, cid, s, p)
        if C.RateLimited('c' .. cid, 'rank') then return false, 'rate_limited' end
        local ok, why = C.CreateRank(cid, s.type, s.id, p)
        return ok, ok and nil or why, nil, 'Rank created.'
    end,
    updateRank = function(src, cid, s, p)
        if C.RateLimited('c' .. cid, 'rank') then return false, 'rate_limited' end
        local ok, why = C.UpdateRank(cid, s.type, s.id, tonumber(p.rankId), p)
        return ok, why, nil, 'Rank saved.'
    end,
    deleteRank = function(src, cid, s, p)
        if C.RateLimited('c' .. cid, 'rank') then return false, 'rate_limited' end
        local ok, why = C.DeleteRank(cid, s.type, s.id, tonumber(p.rankId))
        return ok, why, nil, 'Rank deleted.'
    end,
    supplyCatalog = function(src, cid, s)
        local ok, res = SUP.GetCatalog(cid, s.type, s.id)
        if not ok then return false, res end
        TriggerClientEvent('cm-commercial-ownership:client:supply', src, 'catalog', res)
        return true, nil, true
    end,
    supplyQuote = function(src, cid, s, p)
        local ok, res, cap = SUP.Quote(cid, s.type, s.id, p.lines)
        if not ok then return false, res end
        TriggerClientEvent('cm-commercial-ownership:client:supply', src, 'quote', res)
        return true, nil, true
    end,
    supplyPlace = function(src, cid, s, p)
        local ok, res = SUP.Place(cid, s.type, s.id, { token = p.token, idempotencyKey = type(p.key) == 'string' and p.key or nil })
        if not ok then return false, res end
        return true, nil, nil, ('Order %s placed and paid from business funds.'):format(res.reference)
    end,
    supplyCancel = function(src, cid, s, p)
        local ok, res = SUP.Cancel(cid, s.type, s.id, tostring(p.reference or ''))
        if not ok then return false, res end
        return true, nil, nil, 'Order cancelled and refunded.'
    end,
    supplyDetail = function(src, cid, s, p)
        local ok, res = SUP.Detail(cid, s.type, s.id, tostring(p.reference or ''))
        if not ok then return false, res end
        TriggerClientEvent('cm-commercial-ownership:client:supply', src, 'detail', res)
        return true, nil, true
    end,
    pay = function(src, cid, s, p)
        local ok, res = C.PayEmployee(cid, s.type, s.id, tonumber(p.characterId))
        if ok then return true, nil, nil, ('Paid $%d from business funds.'):format(res.amount) end
        return false, res
    end,
}

RegisterNetEvent('cm-commercial-ownership:server:request', function(action, payload)
    local src = source
    local cid = actorCid(src)
    local s = sessions[src]
    if not cid or not s or type(action) ~= 'string' or not ACTIONS[action] then return end
    local p = type(payload) == 'table' and payload or {}
    local ok, why, silent, okMessage = ACTIONS[action](src, cid, s, p)
    if silent then return end
    if action ~= 'refresh' then result(src, ok, why, okMessage) end
    if action ~= 'refresh' and action ~= 'candidates' then push(src, 'update') end
end)

RegisterNetEvent('cm-commercial-ownership:server:respondInvite', function(token, accept)
    local src = source
    if type(token) ~= 'string' then return end
    local ok, why = exports[GetCurrentResourceName()]:RespondToInvite(src, token, accept == true)
    if ok then
        C.notifySrc(src, accept == true and 'You joined the business.' or 'Invitation declined.', accept == true and 'success' or 'info')
    else
        C.notifySrc(src, say(why), 'error')
    end
end)
