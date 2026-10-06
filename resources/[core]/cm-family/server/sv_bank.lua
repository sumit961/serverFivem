-- ============================================================
--  cm-family | sv_bank.lua
--  The family bank. Deposits move money player -> family; withdrawals move
--  family -> player. Balance mutations are atomic (conditional UPDATE) and every
--  movement is logged. Withdrawals respect the member's per-rank daily limit.
-- ============================================================

local B = CMFamilyBridge

local function today()
    return os.date('%Y-%m-%d')
end

-- Track per-character withdrawals for the current day.
local function withdrawnToday(cid)
    local curDay = today()
    local rec = WithdrawnToday[cid]
    if not rec or rec.day ~= curDay then
        local sum = 0
        local ok, res = pcall(function()
            return MySQL.scalar.await([[
                SELECT COALESCE(SUM(amount), 0)
                FROM cm_family_bank_log
                WHERE character_id = ?
                  AND direction = 'withdraw'
                  AND created_at >= CURDATE()
            ]], { tostring(cid) })
        end)
        if ok and res ~= nil then
            sum = math.max(0, math.floor(tonumber(res) or 0))
        end
        rec = { day = curDay, amount = sum }
        WithdrawnToday[cid] = rec
    end
    return rec
end

local function logBank(familyId, cid, direction, amount, balanceAfter, reason, category)
    category = tostring(category or direction or 'deposit')
    MySQL.insert('INSERT INTO cm_family_bank_log (family_id, character_id, direction, category, amount, balance_after, reason) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { tonumber(familyId), cid and tostring(cid) or nil, direction, category, amount, balanceAfter, reason })
end

local treasuryLocks = {}

function AcquireTreasuryLock(familyId, maxWaitMs)
    familyId = tonumber(familyId)
    if not familyId then return false, 'invalid_family_id' end
    maxWaitMs = tonumber(maxWaitMs) or 5000
    local elapsed = 0
    while treasuryLocks[familyId] do
        Wait(10)
        elapsed = elapsed + 10
        if elapsed >= maxWaitMs then
            return false, 'treasury_lock_timeout'
        end
    end
    treasuryLocks[familyId] = true
    return true
end

function ReleaseTreasuryLock(familyId)
    familyId = tonumber(familyId)
    if familyId then
        treasuryLocks[familyId] = nil
    end
end

-- Centralized Authoritative Treasury Credit Service
function CreditFamilyTreasuryAtomic(familyId, amount, opts)
    familyId = tonumber(familyId)
    if not familyId then return false, 'invalid_family_id' end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    opts = type(opts) == 'table' and opts or {}

    local lockHeld = opts.lockAlreadyHeld == true
    if not lockHeld then
        local lockOk, lockErr = AcquireTreasuryLock(familyId)
        if not lockOk then return false, lockErr or 'treasury_lock_timeout' end
    end

    local function done(ok, res)
        if not lockHeld then ReleaseTreasuryLock(familyId) end
        return ok, res
    end

    local curBal = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { familyId }))
    if not curBal then
        return done(false, 'family_not_found')
    end

    local maxBal = tonumber(Config.Bank and Config.Bank.maxBalance) or 2000000000
    local availableSpace = math.max(0, maxBal - curBal)

    if amount > 0 and availableSpace <= 0 and not opts.allowZero then
        return done(false, 'family_bank_full')
    end

    local acceptedAmount = math.min(amount, availableSpace)
    local rejectedAmount = amount - acceptedAmount
    local newBalance = curBal + acceptedAmount

    local statements = {}
    if type(opts.extraStatements) == 'table' then
        for _, stmt in ipairs(opts.extraStatements) do
            statements[#statements + 1] = stmt
        end
    end

    if acceptedAmount > 0 then
        statements[#statements + 1] = {
            query = 'UPDATE cm_families SET bank_balance = bank_balance + ? WHERE id = ?',
            values = { acceptedAmount, familyId }
        }

        local actorCid = opts.actorCid and tostring(opts.actorCid) or nil
        local category = tostring(opts.category or 'deposit')
        local reason = tostring(opts.reason or 'deposit')

        statements[#statements + 1] = {
            query = [[
                INSERT INTO cm_family_bank_log (family_id, character_id, direction, category, amount, balance_after, reason)
                VALUES (?, ?, 'deposit', ?, ?, ?, ?)
            ]],
            values = { familyId, actorCid, category, acceptedAmount, newBalance, reason }
        }
    end

    if #statements > 0 then
        local txOk = MySQL.transaction.await(statements)
        if not txOk then
            return done(false, 'transaction_failed')
        end
    end

    local fam = GetFamilyById and GetFamilyById(familyId)
    if fam then fam.bank_balance = newBalance end

    return done(true, {
        familyId = familyId,
        requested = amount,
        accepted = acceptedAmount,
        rejected = rejectedAmount,
        balance = newBalance,
        bank_balance = newBalance,
    })
end
exports('CreditFamilyTreasuryAtomic', CreditFamilyTreasuryAtomic)

-- Trusted exact-once treasury debit (invoice refunds). Owner-local journal: cm_family_treasury_operations, UNIQUE(reference).
-- The guarded balance UPDATE, the journal row and the bank-log row commit in ONE SQL transaction; the journal insert only happens when the
-- balance UPDATE changed a row (ROW_COUNT() = 1) and a duplicate reference aborts the whole transaction. Correctness is therefore decided by the
-- database, not by the in-process treasury lock (kept only to serialize in-memory cache refreshes) and not by cm_family_bank_log.
--   same reference + same payload  -> true, { replayed = true }
--   same reference + other payload -> false, 'idempotency_conflict'
--   treasury short of funds        -> false, 'insufficient_funds' (nothing journaled: the same reference stays retryable)
-- `opts.reason` is the operation reference. Only cm-billing may call the export. Returns true, { familyId, amount, balance, replayed } | false, reason
local TREASURY_OP_SQL = {
    read = 'SELECT reference, family_id, direction, amount, fingerprint FROM cm_family_treasury_operations WHERE reference = ? LIMIT 1',
    debit = 'UPDATE cm_families SET bank_balance = bank_balance - ? WHERE id = ? AND bank_balance >= ?',
    journal = [[INSERT INTO cm_family_treasury_operations (reference, family_id, direction, amount, fingerprint)
        SELECT ?, ?, 'debit', ?, ? FROM DUAL WHERE ROW_COUNT() = 1]],
    log = [[INSERT INTO cm_family_bank_log (family_id, character_id, direction, category, amount, balance_after, reason)
        SELECT ?, NULL, 'withdraw', ?, ?, (SELECT bank_balance FROM cm_families WHERE id = ?), ? FROM DUAL WHERE ROW_COUNT() = 1]],
}

local function readTreasuryOp(reference)
    local ok, row = pcall(function() return MySQL.single.await(TREASURY_OP_SQL.read, { reference }) end)
    if not ok then return nil, 'unavailable' end
    return row or false
end

function DebitFamilyTreasuryAtomic(familyId, amount, opts)
    familyId = tonumber(familyId)
    if not familyId then return false, 'invalid_family_id' end
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount < 1 then return false, 'invalid_amount' end
    opts = type(opts) == 'table' and opts or {}
    local reference = type(opts.reason) == 'string' and opts.reason or ''
    if reference == '' or #reference > 128 then return false, 'invalid_reason' end
    local fingerprint = ('debit|%d|%d'):format(familyId, amount)

    local function balance() return tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { familyId })) end
    local function verdict(row, bal)
        if row.fingerprint ~= fingerprint then return false, 'idempotency_conflict' end
        return true, { familyId = familyId, amount = amount, balance = bal, replayed = true }
    end

    -- Process-local lock: serializes cache refresh only; the database unique key below is the authority.
    local lockOk, lockErr = AcquireTreasuryLock(familyId)
    if not lockOk then return false, lockErr or 'treasury_lock_timeout' end
    local function done(ok, res)
        ReleaseTreasuryLock(familyId)
        return ok, res
    end

    local existing, why = readTreasuryOp(reference)
    if existing == nil then return done(false, why) end
    local bal = balance()
    if not bal then return done(false, 'family_not_found') end
    if existing then return done(verdict(existing, bal)) end
    if bal < amount then return done(false, 'insufficient_funds') end

    local okCall, txRes = pcall(function()
        return MySQL.transaction.await({
            { query = TREASURY_OP_SQL.debit, values = { amount, familyId, amount } },
            { query = TREASURY_OP_SQL.journal, values = { reference, familyId, amount, fingerprint } },
            { query = TREASURY_OP_SQL.log, values = { familyId, tostring(opts.category or 'refund'):sub(1, 32), amount, familyId, reference } },
        })
    end)
    local committed = okCall and txRes == true   -- the transaction result, not just 'did not throw'
    local row = readTreasuryOp(reference)
    if row == nil then return done(false, 'unavailable') end
    local after = balance()
    if not row then return done(false, committed and 'insufficient_funds' or 'transaction_failed') end
    if row.fingerprint ~= fingerprint then return done(false, 'idempotency_conflict') end

    local fam = GetFamilyById and GetFamilyById(familyId)
    if fam and after then fam.bank_balance = after end
    return done(true, { familyId = familyId, amount = amount, balance = after, replayed = not committed })
end
exports('DebitFamilyTreasuryAtomic', function(familyId, amount, opts)
    if GetInvokingResource() ~= 'cm-billing' then return false, 'forbidden' end
    return DebitFamilyTreasuryAtomic(familyId, amount, opts)
end)

-- Trusted exact-once treasury CREDIT (invoice payment settlement). Same owner journal as the debit (cm_family_treasury_operations, UNIQUE(reference)).
-- The treasury may accept less than requested (capacity): the journal row records the ACCEPTED amount (authoritative paid amount) and the fingerprint
-- records the REQUESTED amount, so a replay returns the original accepted amount and a different request is a conflict. The guarded balance UPDATE,
-- the journal row and the bank-log row commit in ONE transaction; correctness is decided by the database, never by the bank log.
--   same reference + same request  -> true, { accepted, requested, balance, replayed = true }
--   same reference + other request -> false, 'idempotency_conflict'
--   no capacity                    -> false, 'family_bank_full' (nothing journaled: retryable)
-- Only cm-billing may call the export. `opts.reference` is the operation reference.
local TREASURY_CREDIT_SQL = {
    credit = 'UPDATE cm_families SET bank_balance = bank_balance + ? WHERE id = ? AND bank_balance + ? <= ?',
    journal = [[INSERT INTO cm_family_treasury_operations (reference, family_id, direction, amount, fingerprint)
        SELECT ?, ?, 'credit', ?, ? FROM DUAL WHERE ROW_COUNT() = 1]],
    log = [[INSERT INTO cm_family_bank_log (family_id, character_id, direction, category, amount, balance_after, reason)
        SELECT ?, NULL, 'deposit', ?, ?, (SELECT bank_balance FROM cm_families WHERE id = ?), ? FROM DUAL WHERE ROW_COUNT() = 1]],
}

function CreditFamilyTreasuryOnce(familyId, amount, opts)
    familyId = tonumber(familyId)
    if not familyId then return false, 'invalid_family_id' end
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount < 1 then return false, 'invalid_amount' end
    opts = type(opts) == 'table' and opts or {}
    local reference = type(opts.reference) == 'string' and opts.reference or ''
    if reference == '' or #reference > 128 then return false, 'invalid_reason' end
    local fingerprint = ('credit|%d|%d'):format(familyId, amount)

    local function balance() return tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { familyId })) end
    local lockOk, lockErr = AcquireTreasuryLock(familyId)
    if not lockOk then return false, lockErr or 'treasury_lock_timeout' end
    local function done(ok, res)
        ReleaseTreasuryLock(familyId)
        return ok, res
    end

    local existing, why = readTreasuryOp(reference)
    if existing == nil then return done(false, why) end
    local bal = balance()
    if not bal then return done(false, 'family_not_found') end
    if existing then
        if existing.fingerprint ~= fingerprint then return done(false, 'idempotency_conflict') end
        return done(true, { familyId = familyId, requested = amount, accepted = tonumber(existing.amount), balance = bal, replayed = true })
    end

    local maxBal = tonumber(Config.Bank and Config.Bank.maxBalance) or 2000000000
    local accepted = math.min(amount, math.max(0, maxBal - bal))
    if accepted < 1 then return done(false, 'family_bank_full') end

    local okCall, txRes = pcall(function()
        return MySQL.transaction.await({
            { query = TREASURY_CREDIT_SQL.credit, values = { accepted, familyId, accepted, maxBal } },
            { query = TREASURY_CREDIT_SQL.journal, values = { reference, familyId, accepted, fingerprint } },
            { query = TREASURY_CREDIT_SQL.log, values = { familyId, tostring(opts.category or 'invoice'):sub(1, 32), accepted, familyId, reference } },
        })
    end)
    local committed = okCall and txRes == true   -- the transaction result, not just 'did not throw'
    local row = readTreasuryOp(reference)
    if row == nil then return done(false, 'unavailable') end
    local after = balance()
    if not row then return done(false, 'transaction_failed') end
    if row.fingerprint ~= fingerprint then return done(false, 'idempotency_conflict') end

    local fam = GetFamilyById and GetFamilyById(familyId)
    if fam and after then fam.bank_balance = after end
    return done(true, { familyId = familyId, requested = amount, accepted = tonumber(row.amount), balance = after, replayed = not committed })
end
exports('CreditFamilyTreasuryOnce', function(familyId, amount, opts)
    if GetInvokingResource() ~= 'cm-billing' then return false, 'forbidden' end
    return CreditFamilyTreasuryOnce(familyId, amount, opts)
end)

-- Authoritative owner status for ANY treasury operation reference: { direction, familyId, amount } | false (never applied) | error when the
-- journal cannot answer (the caller must not assume "not applied"). `amount` is the amount the treasury actually moved. cm-billing only.
exports('GetFamilyTreasuryOperation', function(reference)
    if GetInvokingResource() ~= 'cm-billing' then return nil end
    if type(reference) ~= 'string' or reference == '' or #reference > 128 then return nil end
    local row, why = readTreasuryOp(reference)
    if row == nil then error('treasury journal ' .. tostring(why)) end
    if not row then return false end
    return { direction = row.direction, familyId = tonumber(row.family_id), amount = tonumber(row.amount) }
end)

-- Authoritative owner status (journal-backed): true when a debit with this reference was committed for this family, false when it never was,
-- error/nil when the owner database cannot answer (the caller must not assume "not applied"). cm-billing only.
exports('HasFamilyTreasuryEntry', function(familyId, direction, reference)
    if GetInvokingResource() ~= 'cm-billing' then return false end
    if direction ~= 'withdraw' and direction ~= 'debit' then return false end
    local row, why = readTreasuryOp(tostring(reference or ''))
    if row == nil then error('treasury journal ' .. tostring(why)) end
    return row ~= false and tonumber(row.family_id) == tonumber(familyId) and row.direction == 'debit'
end)

-- Deposit: take from player, add to family.
-- Accurately calculates available space; charges player ONLY the accepted amount.
-- Returns error and charges $0 if bank is full.
function BankDeposit(actorCid, amount)
    local rank, fam = GetRankForCid(actorCid)
    if not rank or not fam then return false, 'not_in_family' end
    if not RankHasPermission(rank, 'bank.deposit') then return false, 'no_permission' end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end

    local src = B.GetSrcByCid(actorCid)
    if not src then return false, 'player_not_online' end
    local playerCash = B.GetMoney(src)
    if playerCash < amount then return false, 'You do not have that much.' end

    local lockOk, lockErr = AcquireTreasuryLock(fam.id)
    if not lockOk then
        return false, lockErr or 'Another bank transaction is currently processing. Please try again.'
    end

    local curBal = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { fam.id })) or 0
    local maxBal = tonumber(Config.Bank and Config.Bank.maxBalance) or 2000000000
    local availableSpace = math.max(0, maxBal - curBal)

    if availableSpace <= 0 then
        ReleaseTreasuryLock(fam.id)
        return false, 'family_bank_full'
    end

    local acceptedAmount = math.min(amount, availableSpace)
    local rejectedAmount = amount - acceptedAmount

    local charged = B.RemoveMoney(src, acceptedAmount, 'family_bank_deposit')
    if not charged then
        ReleaseTreasuryLock(fam.id)
        return false, 'The bank could not take the funds.'
    end

    local creditOk, creditRes = CreditFamilyTreasuryAtomic(fam.id, acceptedAmount, {
        actorCid = actorCid,
        category = 'deposit',
        reason = 'deposit',
        lockAlreadyHeld = true,
    })

    ReleaseTreasuryLock(fam.id)

    if not creditOk or not creditRes then
        B.AddMoney(src, acceptedAmount, 'family_bank_deposit_refund')
        return false, 'Deposit failed and your money was returned.'
    end

    LogFamily(fam.id, actorCid, 'bank_deposit', {
        requested = amount,
        amount = acceptedAmount,
        rejected = rejectedAmount,
        balance = creditRes.balance
    })

    -- Track member financial contribution using actual accepted money
    if type(RecordFinancialContribution) == 'function' then
        RecordFinancialContribution(actorCid, fam.id, acceptedAmount)
    end

    -- Advance weekly objectives using actual accepted money
    if type(AdvanceFamilyObjective) == 'function' then
        AdvanceFamilyObjective(fam.id, 'net_deposits', acceptedAmount, actorCid)
    end

    return true, {
        requested = amount,
        accepted = acceptedAmount,
        rejected = rejectedAmount,
        balance = creditRes.balance,
        bank_balance = creditRes.balance,
    }
end
exports('BankDeposit', BankDeposit)

-- Withdraw: check daily limit + balance, debit family atomically, then pay the
-- player. The atomic UPDATE with a balance guard prevents two concurrent
-- withdrawals from overdrawing the family balance; withdrawLocks additionally
-- serialize a single character's own requests so two near-simultaneous
-- withdrawals can't both read the same stale daily-limit counter.
local withdrawLocks = {}

function BankWithdraw(actorCid, amount)
    actorCid = tostring(actorCid)
    if withdrawLocks[actorCid] then return false, 'A withdrawal is already being processed.' end
    withdrawLocks[actorCid] = true

    local ok, resultA, resultB = xpcall(function()
        local rank, fam = GetRankForCid(actorCid)
        if not rank or not fam then return false, 'not_in_family' end
        if not RankHasPermission(rank, 'bank.withdraw') then return false, 'no_permission' end
        amount = math.floor(tonumber(amount) or 0)
        if amount <= 0 then return false, 'invalid_amount' end

        -- Daily limit: 0 = no withdrawals, <0 = unlimited (founder default).
        local limit = rank.bank_daily_limit or 0
        if not rank.is_founder and limit == 0 then return false, 'Your rank cannot withdraw.' end
        if limit >= 0 and not rank.is_founder then
            local rec = withdrawnToday(actorCid)
            if rec.amount + amount > limit then
                return false, ('Daily withdrawal limit reached ($%d of $%d used today).'):format(rec.amount, limit)
            end
        end

        local src = B.GetSrcByCid(actorCid)
        if not src then return false, 'player_not_online' end

        -- Atomic debit guarded by sufficient balance.
        local affected
        local dbOk = pcall(function()
            affected = MySQL.update.await(
                'UPDATE cm_families SET bank_balance = bank_balance - ? WHERE id = ? AND bank_balance >= ?',
                { amount, fam.id, amount })
        end)
        if not dbOk or not affected or affected == 0 then
            return false, 'The family bank does not have that much.'
        end

        -- Reserve the daily-limit allowance before paying out, while still
        -- holding the per-character lock, so a second call sees the reservation.
        if not rank.is_founder and limit > 0 then
            local rec = withdrawnToday(actorCid)
            rec.amount = rec.amount + amount
        end

        local paid = B.AddMoney(src, amount, 'family_bank_withdraw')
        if not paid then
            -- Roll back both the family balance and the daily-limit reservation.
            pcall(function()
                MySQL.update.await('UPDATE cm_families SET bank_balance = LEAST(bank_balance + ?, ?) WHERE id = ?',
                    { amount, Config.Bank.maxBalance, fam.id })
            end)
            if not rank.is_founder and limit > 0 then
                local rec = withdrawnToday(actorCid)
                rec.amount = math.max(0, rec.amount - amount)
            end
            return false, 'Payout failed; the withdrawal was cancelled.'
        end

        local newBalance = MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { fam.id })
        fam.bank_balance = tonumber(newBalance) or math.max(0, fam.bank_balance - amount)

        logBank(fam.id, actorCid, 'withdraw', amount, fam.bank_balance, 'withdraw', 'withdraw')
        LogFamily(fam.id, actorCid, 'bank_withdraw', { amount = amount })
        return true, fam.bank_balance
    end, debug.traceback)

    withdrawLocks[actorCid] = nil
    if not ok then
        -- Keep the stack trace server-side only; never surface internal
        -- file/line detail to the player-facing error toast.
        print(('[cm-family] BankWithdraw error for cid %s: %s'):format(actorCid, tostring(resultA)))
        return false, 'Withdrawal failed unexpectedly. Please try again.'
    end
    return resultA, resultB
end

function GetBankLog(familyId, limit)
    limit = math.max(1, math.min(100, tonumber(limit) or 30))
    local rows = MySQL.query.await([[
        SELECT id, family_id, character_id, direction, category, amount, balance_after, reason, created_at
        FROM cm_family_bank_log
        WHERE family_id = ?
        ORDER BY created_at DESC
        LIMIT ?
    ]], { tonumber(familyId), limit }) or {}

    for _, row in ipairs(rows) do
        if row.character_id then
            row.characterName = B.GetCharName(row.character_id)
        end
        row.category = row.category or row.direction or 'deposit'
    end
    return rows
end

function GetTreasuryOverview(familyId)
    familyId = tonumber(familyId)
    if not familyId then return nil end

    local fam = GetFamilyById(familyId)
    local balance = fam and tonumber(fam.bank_balance) or 0

    local weekStats = MySQL.single.await([[
        SELECT
            COALESCE(SUM(CASE WHEN direction = 'deposit' THEN amount ELSE 0 END), 0) AS income7d,
            COALESCE(SUM(CASE WHEN direction = 'withdraw' THEN amount ELSE 0 END), 0) AS expenses7d,
            COUNT(*) AS transactions7d
        FROM cm_family_bank_log
        WHERE family_id = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
    ]], { familyId }) or {}

    local topContributors = MySQL.query.await([[
        SELECT c.character_id, c.money_contributed
        FROM cm_family_member_contributions c
        WHERE c.family_id = ? AND c.money_contributed > 0
        ORDER BY c.money_contributed DESC
        LIMIT 5
    ]], { familyId }) or {}

    local formattedContributors = {}
    for idx, row in ipairs(topContributors) do
        formattedContributors[#formattedContributors + 1] = {
            position = idx,
            cid = row.character_id,
            name = B.GetCharName(row.character_id),
            amount = tonumber(row.money_contributed) or 0,
        }
    end

    local recentTransactions = GetBankLog(familyId, 25)

    return {
        balance = balance,
        income7d = tonumber(weekStats.income7d) or 0,
        expenses7d = tonumber(weekStats.expenses7d) or 0,
        transactions7d = tonumber(weekStats.transactions7d) or 0,
        topContributors = formattedContributors,
        recentTransactions = recentTransactions,
    }
end
exports('GetTreasuryOverview', GetTreasuryOverview)

-- Allow other CM resources (e.g. a business or shop) to spend from the family
-- bank with an atomic guard. Returns (ok, newBalance|reason).
exports('FamilyBankCharge', function(familyId, amount, reason)
    local invoking = GetInvokingResource()
    if invoking and invoking ~= 'cm-family'
        and not (Config.Bank.authorizedExternalResources and Config.Bank.authorizedExternalResources[invoking])
    then
        return false, 'resource_not_authorized'
    end
    familyId = tonumber(familyId)
    amount = math.floor(tonumber(amount) or 0)
    if not familyId or amount <= 0 then return false, 'invalid_arguments' end
    local affected = MySQL.update.await(
        'UPDATE cm_families SET bank_balance = bank_balance - ? WHERE id = ? AND bank_balance >= ?',
        { amount, familyId, amount })
    if not affected or affected == 0 then return false, 'insufficient_funds' end
    local fam = Families[familyId]
    local newBalance = MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { familyId })
    if fam then fam.bank_balance = tonumber(newBalance) or fam.bank_balance end
    local finalBalance = tonumber(newBalance) or 0
    logBank(familyId, nil, 'withdraw', amount, finalBalance, reason or 'external_charge', 'external_charge')
    LogFamily(familyId, nil, 'bank_external_charge', {
        amount = amount,
        reason = tostring(reason or 'external_charge'):sub(1, 128),
        balance = finalBalance,
    }, { amount = amount, sourceResource = GetInvokingResource() or GetCurrentResourceName() })
    return true, finalBalance
end)
