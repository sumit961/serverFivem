-- Classifieds: short public text adverts. The posting fee is charged server-side, once, under an
-- operation lock; a failed insert refunds the exact amount to the same account. No money is ever created.
local S = CMPhone.Server
local Config = CMPhone.Config
local A = Config.Adverts

-- Money adapter (replaceable by the dev self-test so the charge path can be verified without a live player).
S.Money = {
    Charge = function(src, amount, reason)
        local api = S.playerData()
        if not api then return false end
        local mode = A.account
        local function try(account)
            local ok, result = pcall(function()
                if account == 'cash' then return api:RemoveCash(src, amount, reason) end
                return api:RemoveBank(src, amount, reason)
            end)
            return ok and result == true
        end
        if mode == 'cash' or mode == 'bank' then
            if try(mode) then return true, mode end
            return false
        end
        if try('cash') then return true, 'cash' end
        if try('bank') then return true, 'bank' end
        return false
    end,
    Refund = function(src, account, amount, reason)
        local api = S.playerData()
        if not api then return false end
        local ok, result = pcall(function()
            if account == 'cash' then return api:AddCash(src, amount, reason) end
            return api:AddBank(src, amount, reason)
        end)
        return ok and result == true
    end,
}

function S.ListAdverts()
    local rows = MySQL.query.await([[SELECT id, author_number, body, UNIX_TIMESTAMP(created_at) AS at
        FROM cm_phone_adverts WHERE expires_at > CURRENT_TIMESTAMP ORDER BY id DESC LIMIT ?]], { A.feedSize }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { id = r.id, number = r.author_number, body = r.body, at = tonumber(r.at) or 0 }
    end
    return out
end

local function doPost(src, cid, number, text)
    local since = MySQL.scalar.await('SELECT TIMESTAMPDIFF(SECOND, MAX(created_at), CURRENT_TIMESTAMP) FROM cm_phone_adverts WHERE author_character_id = ?', { cid })
    if since ~= nil and tonumber(since) and tonumber(since) < A.cooldownSeconds then
        return false, 'cooldown', A.cooldownSeconds - tonumber(since)
    end

    local fee = math.max(0, math.floor(tonumber(A.fee) or 0))
    local paid, account = true, nil
    if fee > 0 then
        paid, account = S.Money.Charge(src, fee, 'cm-phone-advert')
        if not paid then return false, 'insufficient_funds' end
    end

    local ok, id = pcall(function()
        return MySQL.insert.await(
            'INSERT INTO cm_phone_adverts (author_character_id, author_number, body, fee_paid, expires_at) VALUES (?, ?, ?, ?, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? HOUR))',
            { cid, number, text, fee, A.expireHours })
    end)
    if not ok or not id then
        if fee > 0 then S.Money.Refund(src, account, fee, 'cm-phone-advert-refund') end
        return false, 'internal_error'
    end
    return true, { id = id, fee = fee }
end

function S.PostAdvert(src, cid, number, rawText)
    local text = S.cleanText(rawText, A.textMax, false)
    if not text or #text < A.textMin then return false, 'invalid_message' end
    return S.WithLock(cid, 'advert', doPost, src, cid, number, text)
end

function S.PurgeExpiredAdverts()
    MySQL.update.await('DELETE FROM cm_phone_adverts WHERE expires_at <= CURRENT_TIMESTAMP')
end
