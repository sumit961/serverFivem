-- cm-trade/server/events.lua
-- Network surface. Every handler resolves the caller from `source` and proves they are a registered participant of
-- the session; nothing the client sends (ids, characters, prices, owners) is trusted beyond a session token + request.

local T = CMTrade

local function say(src, reason, okMessage)
    TriggerClientEvent('cm-trade:client:result', src, { ok = reason == nil, message = reason and (T.MESSAGES[reason] or 'Request failed.') or okMessage })
end

RegisterNetEvent('cm-trade:server:respond', function(id, accept)
    local src = source
    local ok, result = T.Respond(src, id, accept == true)
    if not ok then say(src, result) end
end)

RegisterNetEvent('cm-trade:server:cancel', function(id)
    local src = source
    local ok, why = T.Cancel(src, id)
    if not ok and why then say(src, why) end
end)

RegisterNetEvent('cm-trade:server:offer', function(id, op, a, b)
    local src = source
    local ok, why
    if op == 'cash' then ok, why = T.SetCash(src, id, a)
    elseif op == 'addItem' then ok, why = T.AddItem(src, id, a, b)
    elseif op == 'removeItem' then ok, why = T.RemoveItem(src, id, a)
    else return end
    if not ok then say(src, why) end
end)

RegisterNetEvent('cm-trade:server:confirm', function(id, rev)
    local src = source
    local ok, why = T.Confirm(src, id, rev)
    if not ok and why then say(src, why) end
end)

-- Safe inventory snapshot: only what the picker shows (opaque ref, label, image, quantity, short summary).
RegisterNetEvent('cm-trade:server:inventory', function(id)
    local src = source
    local s, why, cid = T.Participant(src, id, { open = true })
    if not s then return end
    if T.RateLimited(cid, 'inventory') then return say(src, 'rate_limited') end
    local out = {}
    if T.P.items.enabled() then
        for _, r in ipairs(T.P.items.snapshot(cid) or {}) do
            if r.tradeable ~= false and not T.IsDeniedItem(r.item) and #out < 200 then
                out[#out + 1] = { ref = tostring(r.ref), label = tostring(r.label or r.item):sub(1, 60), image = r.image and tostring(r.image) or nil, quantity = tonumber(r.quantity) or 0, summary = r.summary and tostring(r.summary):sub(1, 80) or nil }
            end
        end
    end
    TriggerClientEvent('cm-trade:client:inventory', src, out)
end)

-- ---- Player interaction (G menu) ---------------------------------------------------------------------------
-- Registered through cm-playerdata's public extension contract; the owner resource is not modified.
local ACTION = 'trade_invite'

local function registerAction()
    if GetResourceState(Config.PlayerData) ~= 'started' then return end
    pcall(function()
        exports[Config.PlayerData]:RegisterInteractionAction({ id = ACTION, event = 'cm-trade:server:interactionInvite', resource = 'cm-trade' })
    end)
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == Config.PlayerData then
        SetTimeout(500, registerAction)
    end
end)

-- Local (non-network) event raised by cm-playerdata after it validated range/state of the target.
AddEventHandler('cm-trade:server:interactionInvite', function(src, target)
    local ok, why = T.Invite(src, target)
    if not ok then say(src, why) end
end)

-- Fallback / test path: /trade invites the closest other player within invite range (server-computed, no ids typed).
RegisterCommand('trade', function(src)
    if src == 0 then return end
    local mine = GetPlayerPed(src)
    if not mine or mine == 0 then return end
    local here, best, bestDist = GetEntityCoords(mine), nil, Config.Invite.MaxDistance
    for _, p in ipairs(GetPlayers()) do
        local other = tonumber(p)
        if other and other ~= src then
            local ped = GetPlayerPed(other)
            if ped and ped ~= 0 then
                local d = #(GetEntityCoords(ped) - here)
                if d <= bestDist then best, bestDist = other, d end
            end
        end
    end
    if not best then return say(src, 'too_far') end
    local ok, why = T.Invite(src, best)
    if not ok then say(src, why) end
end, false)

-- ---- Exports ---------------------------------------------------------------------------------------------------
exports('IsTrading', function(src)
    local cid = T.P.presence.cidOf(src)
    return cid ~= nil and T.byCid[cid] ~= nil
end)

local function adminOnly()
    return (GetInvokingResource() or GetCurrentResourceName()) == 'cm-admin' or (T.TestInvoker == 'cm-admin')
end

exports('AdminListTrades', function(filter)
    if not adminOnly() then return nil, 'forbidden' end
    local where = (type(filter) == 'table' and filter.open) and "WHERE status NOT IN ('completed','rolled_back')" or ''
    return MySQL.query.await('SELECT reference, char_a, char_b, cash_a, cash_b, item_lines, status, detail, created_at FROM cm_trade_transactions ' .. where .. ' ORDER BY id DESC LIMIT 100') or {}
end)

exports('AdminInspectTrade', function(ref)
    if not adminOnly() then return nil, 'forbidden' end
    local row = MySQL.single.await('SELECT * FROM cm_trade_transactions WHERE reference = ?', { tostring(ref or '') })
    if not row then return nil, 'not_found' end
    return { trade = row, events = MySQL.query.await('SELECT kind, char_a, char_b, metadata, created_at FROM cm_trade_events WHERE session_ref = ? ORDER BY id', { row.reference }) or {} }
end)

exports('AdminReconcileTrades', function()
    if not adminOnly() then return nil, 'forbidden' end
    return T.Reconcile()
end)
