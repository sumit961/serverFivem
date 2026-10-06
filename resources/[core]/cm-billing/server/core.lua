-- cm-billing core: identity, adapters (money, destinations, notifications), locks, rate limits, audit.
-- Character ID is the only persistent identity; FiveM sources only locate the live session.
CMBilling.Server = CMBilling.Server or {}
local S = CMBilling.Server
local Config = CMBilling.Config

function S.dbg(...)
    if Config.Debug then print('[cm-billing]', ...) end
end

function S.playerData()
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    return exports['cm-playerdata']
end

function S.CharacterOf(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local api = S.playerData()
    if not api then return nil end
    local ok, cid = pcall(function() return api:GetCharacterId(src) end)
    if not ok or cid == nil or tostring(cid) == '' then return nil end
    return tostring(cid)
end

function S.SourceOf(cid)
    cid = cid and tostring(cid)
    if not cid then return nil end
    if S.TestOnline and S.TestOnline[cid] then return S.TestOnline[cid] end
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src and S.CharacterOf(src) == cid then return src end
    end
    return nil
end

-- Targeted emit; skips offline/fake (negative) sources so the service layer is testable.
function S.Emit(src, event, ...)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return false end
    TriggerClientEvent(event, src, ...)
    return true
end

function S.json(value)
    local ok, encoded = pcall(json.encode, value)
    return ok and encoded or nil
end

function S.decode(value)
    if type(value) ~= 'string' or value == '' then return nil end
    local ok, decoded = pcall(json.decode, value)
    return ok and decoded or nil
end

function S.cleanText(value, maxLen)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[\0-\31\127]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    local count, cut = 0, #value
    for pos in value:gmatch('()[\0-\127\194-\244][\128-\191]*') do
        count = count + 1
        if count > maxLen then cut = pos - 1 break end
    end
    if count > maxLen then value = value:sub(1, cut) end
    return value
end

function S.money(amount)
    local s = tostring(math.floor(tonumber(amount) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return '$' .. out
end

-- ---------------------------------------------------------------------------
-- Rate limits (per character + bucket) and in-process locks.
-- ---------------------------------------------------------------------------
local rate, locks = {}, {}

function S.RateLimit(cid, bucket)
    local cfg = Config.RateLimits[bucket]
    if not cfg or not cid then return true end
    local now, key = GetGameTimer(), tostring(cid) .. ':' .. bucket
    if rate[key] and now - rate[key] < (cfg.minMs or 0) then return false end
    rate[key] = now
    return true
end

function S.Lock(key)
    if locks[key] then return false end
    locks[key] = GetGameTimer()
    return true
end

function S.Unlock(key) locks[key] = nil end

-- ---------------------------------------------------------------------------
-- Adapters. Defaults use the existing authoritative owners; the dev self-test swaps them.
-- ---------------------------------------------------------------------------
S.Money = {
    -- Debits the payer through the cm-playerdata operation journal (unique reference = exactly once; works online and offline).
    -- Returns true | false, reason. A reason of 'unavailable' means the OUTCOME IS UNKNOWN (never "not charged").
    Debit = function(src, account, amount, reference, cid)
        local api = S.playerData()
        if not api then return false, 'unavailable' end
        if not cid then return false, 'invalid_request' end
        local ok, applied, why = pcall(function() return api:RemoveMoneyFromCharacter(cid, account, amount, reference, { source = 'invoice' }) end)
        if not ok then return false, 'unavailable' end
        if applied == true then return true end
        if why == nil or why == 'unavailable' or why == 'persistence_failed' then return false, 'unavailable' end
        return false, why
    end,
    -- Credits a specific character (online or offline) exactly once per reference. Returns true | false, reason ('unavailable' = unknown).
    CreditCharacter = function(characterId, account, amount, reference, metadata)
        local api = S.playerData()
        if not api then return false, 'unavailable' end
        local ok, applied, why = pcall(function() return api:AddMoneyToCharacterOnce(characterId, account, amount, reference, metadata) end)
        if not ok then return false, 'unavailable' end
        if applied == true then return true end
        if why == nil or why == 'persistence_failed' then return false, 'unavailable' end
        return false, why
    end,
    Balance = function(src, account)
        local api = S.playerData()
        if not api then return 0 end
        local ok, value = pcall(function()
            if account == 'cash' then return api:GetCash(src) end
            return api:GetBank(src)
        end)
        return ok and tonumber(value) or 0
    end,
}

-- Destination settlement. credit(inv, payerAccount) -> true[, acceptedAmount] | false[, reason] (a definitive "not applied"); it RAISES when the
-- owner's outcome is unknown. Must be idempotent per invoice reference. evidence(inv) -> credited[, acceptedAmount]; raises when the owner cannot answer.
-- Unknown owner results never reach the payer refund path.
local UNKNOWN = { unavailable = true, busy = true, treasury_lock_timeout = true, transaction_failed = true, persistence_failed = true }
local function creditKey(inv) return S.PayKeys(inv.public_reference).credit end

S.Destinations = {
    city = {
        available = function() return true end,
        validate = function() return true end,
        credit = function(inv) return true, tonumber(inv.amount) end, -- sink: the money simply leaves circulation
        evidence = function(inv) return true, tonumber(inv.amount) end,
    },
    character = {
        available = function() return true end,
        validate = function(id, recipientCid)
            return id ~= nil and id ~= '' and tostring(id) ~= tostring(recipientCid) and S.CharacterExists(id)
        end,
        credit = function(inv, account)
            local ok, why = S.Money.CreditCharacter(inv.destination_id, account, tonumber(inv.amount), creditKey(inv), { invoice = inv.public_reference })
            if ok == true then return true, tonumber(inv.amount) end
            if UNKNOWN[why] then error('character credit outcome unknown: ' .. tostring(why)) end
            return false, why
        end,
        -- Durable owner journal status (never economy_transactions). Raises when the owner cannot answer.
        evidence = function(inv)
            local api = S.playerData()
            if not api then error('character money journal unavailable') end
            local op, why = api:GetCharacterMoneyOperation(creditKey(inv))
            if op == nil then error('character money journal ' .. tostring(why)) end
            if op == false then return false end
            return op.direction == 'credit' and op.characterId == tostring(inv.destination_id), tonumber(op.amount)
        end,
    },
    family = {
        available = function() return GetResourceState('cm-family') == 'started' end,
        validate = function(id)
            local familyId = tonumber(id)
            if not familyId or GetResourceState('cm-family') ~= 'started' then return false end
            local row = MySQL.scalar.await('SELECT id FROM cm_families WHERE id = ? LIMIT 1', { familyId })
            return row ~= nil
        end,
        -- The family treasury may accept less than requested (capacity); the journal records the ACCEPTED amount and the caller returns the remainder.
        credit = function(inv)
            local ok, applied, info = pcall(function()
                return exports['cm-family']:CreditFamilyTreasuryOnce(tonumber(inv.destination_id), tonumber(inv.amount),
                    { reference = creditKey(inv), category = 'invoice' })
            end)
            if not ok then error('family credit outcome unknown: ' .. tostring(applied)) end
            if applied == true and type(info) == 'table' then return true, tonumber(info.accepted) end
            if applied == nil or UNKNOWN[info] then error('family credit outcome unknown: ' .. tostring(info)) end
            return false, tostring(info)
        end,
        evidence = function(inv)
            local op = exports['cm-family']:GetFamilyTreasuryOperation(creditKey(inv))   -- raises when the journal cannot answer
            if op == nil then error('family treasury journal unavailable') end
            if op == false then return false end
            return op.direction == 'credit' and op.familyId == tonumber(inv.destination_id), tonumber(op.amount)
        end,
    },
    -- Businesses: authoritative balance lives in cm-commercial-ownership (adapter over each business's own table). Already exactly-once.
    business = {
        available = function() return GetResourceState('cm-commercial-ownership') == 'started' end,
        validate = function(id)
            local t, i = tostring(id or ''):match('^([%w_]+):([%w_%-%.]+)$')
            if not t then return false end
            local ok, biz = pcall(function() return exports['cm-commercial-ownership']:GetBusiness(t, i) end)
            return ok and type(biz) == 'table' and biz.owned == true
        end,
        -- Idempotent per invoice reference (the business ledger key is unique).
        credit = function(inv)
            local t, i = tostring(inv.destination_id or ''):match('^([%w_]+):([%w_%-%.]+)$')
            if not t then return false, 'invalid_destination' end
            local ok, credited, info = pcall(function()
                return exports['cm-commercial-ownership']:CreditBusinessAtomic(t, i, tonumber(inv.amount), 'invoice',
                    { idempotencyKey = 'billing-credit:' .. inv.public_reference, reference = inv.public_reference })
            end)
            if not ok then error('business credit outcome unknown: ' .. tostring(credited)) end
            if credited == true then return true, tonumber(inv.amount) end
            if credited == nil then error('business credit outcome unknown') end
            return false, type(info) == 'string' and info or 'rejected'
        end,
        evidence = function(inv)
            local seen = exports['cm-commercial-ownership']:HasBusinessTransaction('billing-credit:' .. inv.public_reference)   -- raises when unavailable
            return seen == true, tonumber(inv.amount)
        end,
    },
}

function S.CharacterExists(cid)
    if S.TestCharacters and S.TestCharacters[tostring(cid)] then return true end
    if not cid or tostring(cid) == '' then return false end
    local row = MySQL.scalar.await('SELECT id FROM characters WHERE id = ? LIMIT 1', { tostring(cid) })
    return row ~= nil
end

-- Best-effort notifications. Failure never changes invoice state.
function S.CreatedMessage(amount)
    return ('New invoice received - %s'):format(S.money(amount))
end

S.Notifier = {
    created = function(cid, inv)
        local src = S.SourceOf(cid)
        if Config.Notify.phone and GetResourceState('cm-phone') == 'started' then
            pcall(function()
                exports['cm-phone']:SendSystemMessage(cid, 'Billing', S.CreatedMessage(inv.amount))
            end)
        end
        if src then S.Emit(src, 'cm-billing:client:changed') end
        if src and Config.Notify.hud and GetResourceState('cm-hud') == 'started' then
            S.Emit(src, 'cm-hud:client:notify', ('New invoice received: %s'):format(S.money(inv.amount)), 'info')
        end
    end,
    paid = function(cid, inv)
        local src = S.SourceOf(cid)
        if src and Config.Notify.hud and GetResourceState('cm-hud') == 'started' then
            S.Emit(src, 'cm-hud:client:notify', ('Invoice paid: %s'):format(S.money(inv.amount)), 'success')
        end
    end,
    refunded = function(cid, inv)
        local src = S.SourceOf(cid)
        if src then S.Emit(src, 'cm-billing:client:changed') end
        if src and Config.Notify.hud and GetResourceState('cm-hud') == 'started' then
            S.Emit(src, 'cm-hud:client:notify', ('Invoice refunded: %s'):format(S.money(inv.amount)), 'success')
        end
    end,
}

function S.audit(kind, detail)
    if GetResourceState('cm-admin') ~= 'started' then return end
    pcall(function()
        TriggerEvent('cm-admin:server:addLog', 0, kind, { category = 'billing', detail = detail or {} })
    end)
end
