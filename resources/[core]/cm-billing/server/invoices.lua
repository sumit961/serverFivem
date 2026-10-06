-- Invoice creation, listing, voiding and expiry. The create/void/read entry points take the CALLING RESOURCE
-- name (resolved by exports.lua with GetInvokingResource()); everything else is derived server-side.
local S = CMBilling.Server
local Config = CMBilling.Config

S.TestProviders = nil -- self-test only

local REF_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

local function newReference()
    local out = {}
    for i = 1, 8 do
        local n = math.random(1, #REF_ALPHABET)
        out[i] = REF_ALPHABET:sub(n, n)
    end
    return 'INV-' .. table.concat(out)
end

function S.ProviderFor(resource)
    if type(resource) ~= 'string' or resource == '' then return nil end
    if S.TestProviders and S.TestProviders[resource] then return S.TestProviders[resource] end
    local provider = Config.Providers[resource]
    if provider and provider.enabled == true then return provider end
    return nil
end

local COLS = [[id, public_reference, recipient_character_id, issuer_type, issuer_label, issuer_character_id, issuer_resource,
    issuer_entity_id, destination_type, destination_id, amount, label, description, status, payment_account,
    UNIX_TIMESTAMP(created_at) AS created_ts, UNIX_TIMESTAMP(due_at) AS due_ts, UNIX_TIMESTAMP(expires_at) AS expires_ts,
    UNIX_TIMESTAMP(paid_at) AS paid_ts, void_reason, settlement_note, metadata,
    refunded_amount, refund_reserved_amount, refund_state, UNIX_TIMESTAMP(refunded_at) AS refunded_ts]]
S.INVOICE_COLUMNS = COLS

function S.EventLog(invoiceId, event, actor, detail)
    pcall(function()
        MySQL.insert.await('INSERT INTO cm_billing_events (invoice_id, event, actor, detail) VALUES (?, ?, ?, ?)',
            { invoiceId, event, tostring(actor or ''):sub(1, 80), tostring(detail or ''):sub(1, 255) })
    end)
end

-- What a recipient may see: no internal ids, resources, destination identity or metadata.
function S.PublicInvoice(row)
    return {
        reference = row.public_reference,
        issuer = row.issuer_label,
        label = row.label,
        description = row.description ~= '' and row.description or nil,
        amount = tonumber(row.amount) or 0,
        status = row.status == 'settling' and 'processing' or row.status,
        createdAt = tonumber(row.created_ts) or 0,
        dueAt = tonumber(row.due_ts),
        expiresAt = tonumber(row.expires_ts),
        paidAt = tonumber(row.paid_ts),
        account = row.payment_account ~= '' and row.payment_account or nil,
        voidReason = row.void_reason ~= '' and row.void_reason or nil,
        -- Refund facts never replace the paid fact: status stays 'paid'; refundState/netPaid carry the refund history.
        refundState = row.refund_state ~= nil and row.refund_state ~= 'none' and row.refund_state or nil,
        refundedAmount = (tonumber(row.refunded_amount) or 0) > 0 and tonumber(row.refunded_amount) or nil,
        refundedAt = tonumber(row.refunded_ts),
        netPaid = row.status == 'paid' and S.NetPaid and S.NetPaid(row) or nil,
    }
end

function S.GetRow(reference)
    if type(reference) ~= 'string' or #reference > 16 then return nil end
    return MySQL.single.await('SELECT ' .. COLS .. ' FROM cm_billing_invoices WHERE public_reference = ? LIMIT 1', { reference })
end

local function validateMetadata(provider, metadata)
    if metadata == nil then return true, nil end
    if type(metadata) ~= 'table' then return false end
    local ns = (provider.metadataNamespace or '') .. '.'
    for key in pairs(metadata) do
        if type(key) ~= 'string' or ns == '.' or key:sub(1, #ns) ~= ns then return false end
    end
    local encoded = S.json(metadata)
    if not encoded or #encoded > 1500 then return false end
    return true, encoded
end

-- Effective CREATION limit of a provider: min(provider.maxAmount, platform HardMaxAmount). Misconfigured => 0 (fail closed).
-- It applies to NEW invoices only: payment, refund and reconcile never re-check it, so a later config change cannot strand an invoice.
function S.ProviderLimit(provider)
    local m = type(provider) == 'table' and tonumber(provider.maxAmount) or nil
    if not m or m ~= m or m < 1 then return 0 end
    return math.min(math.floor(m), Config.HardMaxAmount)
end

local function sortedKeys(map)
    local out = {}
    for k, v in pairs(map or {}) do if v == true then out[#out + 1] = k end end
    table.sort(out)
    return out
end

-- Read-only view of the CALLING provider's own policy (never another provider's).
function S.GetProviderPolicy(caller)
    local provider = S.ProviderFor(caller)
    if not provider then return nil, 'forbidden' end
    return {
        provider = caller,
        maxInvoiceAmount = S.ProviderLimit(provider),
        platformMaxAmount = Config.HardMaxAmount,
        canRefund = provider.canRefund == true,
        canVoid = provider.canVoid == true,
        allowOffline = provider.allowOffline == true,
        issuerTypes = sortedKeys(provider.issuerTypes),
        destinations = sortedKeys(provider.destinations),
    }
end

-- data = { recipientCharacterId, amount, label, description?, issuerType?, issuerLabel, issuerCharacterId?, issuerEntityId?,
--          destination = { type, id? }, expiresInSeconds?, dueInSeconds?, idempotencyKey?, metadata? }
-- Returns true, { reference, id, existing? } or false, reason.
function S.CreateInvoice(caller, data)
    local provider = S.ProviderFor(caller)
    if not provider then return false, 'forbidden' end
    if type(data) ~= 'table' then return false, 'invalid_request' end
    if not S.SchemaReady then return false, 'unavailable' end

    local recipient = data.recipientCharacterId ~= nil and tostring(data.recipientCharacterId) or ''
    if recipient == '' or not S.CharacterExists(recipient) then return false, 'invalid_recipient' end
    if provider.allowOffline ~= true and not S.SourceOf(recipient) then return false, 'recipient_offline' end

    -- Money is a whole number: reject strings (scientific notation such as '1e6'), NaN, infinity, fractions and non-positive values.
    local amount = data.amount
    if type(amount) ~= 'number' or amount ~= amount or amount == math.huge or amount == -math.huge or amount ~= math.floor(amount) or amount < 1 then
        return false, 'invalid_amount'
    end
    amount = math.floor(amount)
    local limit = S.ProviderLimit(provider)
    local function rejected(reason, destType)
        S.audit('cm_billing_invoice_rejected', { provider = caller, reason = reason, amount = amount, limit = limit, destination = destType })
        return false, reason
    end
    if amount > Config.HardMaxAmount then return rejected('amount_exceeds_platform_limit') end
    if amount > limit then return rejected('amount_exceeds_provider_limit') end

    local label = S.cleanText(data.label, 80)
    local issuerLabel = S.cleanText(data.issuerLabel, 64)
    if not label or not issuerLabel then return false, 'invalid_request' end
    local description = S.cleanText(data.description or '', 400) or ''

    local issuerType = tostring(data.issuerType or 'system')
    if not (provider.issuerTypes or {})[issuerType] then return false, 'forbidden_issuer_type' end
    local issuerCharacter = ''
    if data.issuerCharacterId ~= nil and tostring(data.issuerCharacterId) ~= '' then
        issuerCharacter = tostring(data.issuerCharacterId)
        if not S.CharacterExists(issuerCharacter) then return false, 'invalid_issuer' end
    end
    local issuerEntity = S.cleanText(tostring(data.issuerEntityId or ''), 64) or ''

    local dest = type(data.destination) == 'table' and data.destination or { type = 'city' }
    local destType = tostring(dest.type or '')
    local destCfg, adapter = Config.Destinations[destType], S.Destinations[destType]
    if not destCfg or destCfg.available ~= true or not adapter then return false, 'invalid_destination' end
    if not (provider.destinations or {})[destType] then return rejected('destination_not_allowed', destType) end
    if not adapter.available() then return false, 'destination_unavailable' end
    local destId = dest.id ~= nil and tostring(dest.id) or ''
    -- Optional per-provider destination identity prefix (e.g. mechanic invoices may only credit 'mechanic:<shop>').
    local prefix = (provider.destinationIdPrefixes or {})[destType]
    if prefix and destId:sub(1, #prefix) ~= prefix then return rejected('destination_not_allowed', destType) end
    if not adapter.validate(destId, recipient) then return false, 'invalid_destination' end

    local expiresIn = math.floor(tonumber(data.expiresInSeconds) or 0)
    if expiresIn ~= 0 and (expiresIn < 60 or expiresIn > 2592000) then return false, 'invalid_expiry' end
    local dueIn = math.floor(tonumber(data.dueInSeconds) or 0)
    if dueIn < 0 or dueIn > 7776000 then return false, 'invalid_expiry' end

    local metaOk, encodedMeta = validateMetadata(provider, data.metadata)
    if not metaOk then return false, 'invalid_metadata' end

    local idem = data.idempotencyKey ~= nil and S.cleanText(tostring(data.idempotencyKey), 64) or ''
    idem = idem or ''
    if idem ~= '' then
        local existing = MySQL.single.await('SELECT id, public_reference FROM cm_billing_invoices WHERE issuer_resource = ? AND idempotency_key = ? LIMIT 1', { caller, idem })
        if existing then return true, { reference = existing.public_reference, id = existing.id, existing = true } end
    end

    local reference, id
    for _ = 1, 8 do
        reference = newReference()
        local ok, result = pcall(function()
            return MySQL.insert.await([[INSERT INTO cm_billing_invoices
                (public_reference, recipient_character_id, issuer_type, issuer_label, issuer_character_id, issuer_resource, issuer_entity_id,
                 destination_type, destination_id, amount, label, description, idempotency_key, due_at, expires_at, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?, ''),
                        IF(? > 0, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND), NULL),
                        IF(? > 0, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? SECOND), NULL), NULLIF(?, ''))]],
                { reference, recipient, issuerType, issuerLabel, issuerCharacter, caller, issuerEntity, destType, destId, amount, label, description,
                  idem, dueIn, dueIn, expiresIn, expiresIn, encodedMeta or '' })
        end)
        if ok and result then id = result break end
        local err = tostring(result):lower()
        if err:find('idempotency', 1, true) then
            local existing = MySQL.single.await('SELECT id, public_reference FROM cm_billing_invoices WHERE issuer_resource = ? AND idempotency_key = ? LIMIT 1', { caller, idem })
            if existing then return true, { reference = existing.public_reference, id = existing.id, existing = true } end
        end
        if not (err:find('duplicate', 1, true) or err:find('1062', 1, true)) then
            print('[cm-billing] invoice insert failed: ' .. tostring(result))
            return false, 'internal_error'
        end
    end
    if not id then return false, 'internal_error' end

    S.EventLog(id, 'created', caller, ('%s %s'):format(destType, tostring(amount)))
    S.audit('cm_billing_invoice_created', { reference = reference, recipient = recipient, issuerType = issuerType, issuerResource = caller,
        issuerEntity = issuerEntity, amount = amount, destination = destType, destinationId = destId })
    CreateThread(function() pcall(S.Notifier.created, recipient, { amount = amount, reference = reference }) end)
    return true, { reference = reference, id = id }
end

-- tab: 'pending' | 'history'
function S.ListInvoices(cid, tab)
    local statuses = tab == 'history' and "('paid','voided','expired')" or "('pending','settling')"
    local limit = tab == 'history' and Config.HistoryPage or 100
    local rows = MySQL.query.await(('SELECT %s FROM cm_billing_invoices WHERE recipient_character_id = ? AND status IN %s ORDER BY id DESC LIMIT ?'):format(COLS, statuses),
        { tostring(cid), limit }) or {}
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = S.PublicInvoice(row) end
    return out
end

-- Recipient-scoped read: another character's reference returns nil.
function S.GetOwnInvoice(cid, reference)
    local row = S.GetRow(reference)
    if not row or tostring(row.recipient_character_id) ~= tostring(cid) then return nil end
    return S.PublicInvoice(row)
end

-- Void a pending invoice. Only the resource that issued it (with canVoid) may void it.
function S.VoidInvoice(caller, reference, reason)
    local provider = S.ProviderFor(caller)
    if not provider or provider.canVoid ~= true then return false, 'forbidden' end
    local row = S.GetRow(reference)
    if not row then return false, 'not_found' end
    if row.issuer_resource ~= caller then return false, 'forbidden' end
    reason = S.cleanText(tostring(reason or ''), 120)
    if not reason then return false, 'invalid_request' end
    local changed = MySQL.update.await("UPDATE cm_billing_invoices SET status = 'voided', voided_at = CURRENT_TIMESTAMP, void_reason = ? WHERE id = ? AND status = 'pending'",
        { reason, row.id })
    if (tonumber(changed) or 0) < 1 then return false, 'not_pending' end
    S.EventLog(row.id, 'voided', caller, reason)
    S.audit('cm_billing_invoice_voided', { reference = reference, recipient = row.recipient_character_id, issuerResource = caller, amount = tonumber(row.amount) })
    return true
end

-- Issuer-scoped reads for trusted resources.
function S.GetIssuedInvoice(caller, reference)
    local provider = S.ProviderFor(caller)
    if not provider then return nil, 'forbidden' end
    local row = S.GetRow(reference)
    if not row or row.issuer_resource ~= caller then return nil, 'not_found' end
    local view = S.PublicInvoice(row)
    view.recipientCharacterId = row.recipient_character_id
    view.metadata = S.decode(row.metadata)
    return view
end

function S.GetIssuedPending(caller, cid)
    local provider = S.ProviderFor(caller)
    if not provider then return nil, 'forbidden' end
    local rows = MySQL.query.await(("SELECT %s FROM cm_billing_invoices WHERE recipient_character_id = ? AND issuer_resource = ? AND status IN ('pending','settling') ORDER BY id DESC LIMIT 100"):format(COLS),
        { tostring(cid), caller }) or {}
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = S.PublicInvoice(row) end
    return out
end

-- Deterministic expiry: indexed (status, expires_at) sweep, run on a timer.
function S.ExpireDue()
    local rows = MySQL.query.await("SELECT id, public_reference FROM cm_billing_invoices WHERE status = 'pending' AND expires_at IS NOT NULL AND expires_at <= CURRENT_TIMESTAMP LIMIT 200") or {}
    for _, row in ipairs(rows) do
        local changed = MySQL.update.await("UPDATE cm_billing_invoices SET status = 'expired' WHERE id = ? AND status = 'pending'", { row.id })
        if (tonumber(changed) or 0) > 0 then S.EventLog(row.id, 'expired', 'cm-billing', '') end
    end
    return #rows
end
