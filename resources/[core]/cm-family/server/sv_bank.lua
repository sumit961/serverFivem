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
    local rec = WithdrawnToday[cid]
    if not rec or rec.day ~= today() then
        rec = { day = today(), amount = 0 }
        WithdrawnToday[cid] = rec
    end
    return rec
end

local function logBank(familyId, cid, direction, amount, balanceAfter, reason)
    MySQL.insert('INSERT INTO cm_family_bank_log (family_id, character_id, direction, amount, balance_after, reason) VALUES (?, ?, ?, ?, ?, ?)',
        { tonumber(familyId), cid and tostring(cid) or nil, direction, amount, balanceAfter, reason })
end

-- Deposit: take from player, add to family. Player charge happens FIRST and is
-- confirmed before the family balance is credited, so a failed charge never
-- creates money.
function BankDeposit(actorCid, amount)
    local rank, fam = GetRankForCid(actorCid)
    if not rank or not fam then return false, 'not_in_family' end
    if not RankHasPermission(rank, 'bank.deposit') then return false, 'no_permission' end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end

    local src = B.GetSrcByCid(actorCid)
    if not src then return false, 'player_not_online' end
    if B.GetMoney(src) < amount then return false, 'You do not have that much.' end

    local charged = B.RemoveMoney(src, amount, 'family_bank_deposit')
    if not charged then return false, 'The bank could not take the funds.' end

    -- Credit the family atomically.
    local newBalance
    local ok = pcall(function()
        MySQL.update.await('UPDATE cm_families SET bank_balance = LEAST(bank_balance + ?, ?) WHERE id = ?',
            { amount, Config.Bank.maxBalance, fam.id })
        newBalance = MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { fam.id })
    end)
    if not ok or newBalance == nil then
        -- Refund the player if the credit failed.
        B.AddMoney(src, amount, 'family_bank_deposit_refund')
        return false, 'Deposit failed and your money was returned.'
    end

    fam.bank_balance = tonumber(newBalance) or (fam.bank_balance + amount)
    logBank(fam.id, actorCid, 'deposit', amount, fam.bank_balance, 'deposit')
    LogFamily(fam.id, actorCid, 'bank_deposit', { amount = amount })
    return true, fam.bank_balance
end

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

        logBank(fam.id, actorCid, 'withdraw', amount, fam.bank_balance, 'withdraw')
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
    return MySQL.query.await(
        'SELECT * FROM cm_family_bank_log WHERE family_id = ? ORDER BY created_at DESC LIMIT ?',
        { tonumber(familyId), limit }) or {}
end

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
    logBank(familyId, nil, 'withdraw', amount, finalBalance, reason or 'external_charge')
    LogFamily(familyId, nil, 'bank_external_charge', {
        amount = amount,
        reason = tostring(reason or 'external_charge'):sub(1, 128),
        balance = finalBalance,
    }, { amount = amount, sourceResource = GetInvokingResource() or GetCurrentResourceName() })
    return true, finalBalance
end)
