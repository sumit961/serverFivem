-- Vehicle legal state (registration + insurance): FiveM wiring for
-- server/legal_core.lua. cm-vehicles remains the single authority; cm-law only
-- consumes these exports (read) or calls the trusted mutation exports (write)
-- after doing its own officer / duty / permission validation.
--
-- Public server exports (documented in docs/API_LEGAL.md):
--   GetVehicleLegalStatus(vehicleId, { includeOwner })
--   GetVehicleLegalStatusByRegistration(number, { includeOwner })
--   IssueVehicleLicense(plate)                      -- trusted law resources
--   RevokeVehicleRegistration(vehicleId, reason, actorCid)   -- trusted law resources
--   ReinstateVehicleRegistration(vehicleId, reason, actorCid) -- trusted law resources
--   OnVehicleOwnershipChanged(vehicleId, reason)    -- trusted ownership resources
--   QuoteVehicleLegalServices(src, vehicleId)       -- trusted service resources
--   GetPlayerVehicleLegalOverview(src)              -- trusted service resources
--   PurchaseVehicleLegalService(src, vehicleId, service, opts) -- trusted service resources
local Config = CMVehicles.Config
local U = CMVehicles.Utils
local Core = CMVehicles.LegalCore

CMVehicles.Legal = CMVehicles.Legal or {}
local L = CMVehicles.Legal
local cfg = Config.Legal or {}

local function normalizeRow(row)
    if not row then return nil end
    row.plate = U.NormalizePlate(row.plate)
    row.metadata = U.Decode(row.metadata)
    return row
end

local COLUMNS = {
    registration_expires_at = true, registration_revoked_at = true,
    insurance_expires_at = true, insurance_owner_id = true,
}

local store = {}

function store.getById(id)
    id = tonumber(id)
    if not id then return nil end
    return normalizeRow(MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE id = ? LIMIT 1', { id }))
end

function store.getByLicense(number)
    number = tostring(number or ''):upper():gsub('%s+', '')
    if number == '' or #number > 20 or number:find('[^%w%-]') then return nil end
    return normalizeRow(MySQL.single.await('SELECT * FROM cm_owned_vehicles WHERE license_number = ? LIMIT 1', { number }))
end

function store.catalogPrice(model)
    local ok, price = pcall(function()
        return MySQL.scalar.await('SELECT price FROM cm_vehicle_catalog WHERE LOWER(model) = ? LIMIT 1', { tostring(model) })
    end)
    return ok and tonumber(price) or nil
end

-- The UNIQUE index on license_number is the collision guard: a duplicate
-- candidate raises inside pcall and the core retries with a new number.
function store.claimLicense(id, candidate, expiresAt, guard)
    local sql = 'UPDATE cm_owned_vehicles SET license_number = ?, registration_expires_at = ?, registration_revoked_at = NULL '
        .. 'WHERE id = ? AND license_number IS NULL AND sale_pending_token IS NULL'
    local values = { candidate, expiresAt, id }
    if guard and guard.owner_character_id then
        sql = sql .. " AND owner_type = 'character' AND owner_character_id = ?"
        values[#values + 1] = tostring(guard.owner_character_id)
    end
    local ok, affected = pcall(function() return MySQL.update.await(sql, values) end)
    return ok and tonumber(affected) == 1
end

-- Guarded write: never applies to a row with a pending state sale, and (when a
-- guard owner is given) never applies if ownership changed since validation.
function store.applyLegal(id, guard, fields)
    local sets, values = {}, {}
    for column, value in pairs(fields) do
        if not COLUMNS[column] then return 0 end
        if value == false then
            sets[#sets + 1] = ('`%s` = NULL'):format(column)
        else
            sets[#sets + 1] = ('`%s` = ?'):format(column)
            values[#values + 1] = value
        end
    end
    if #sets == 0 then return 1 end
    local where = 'id = ? AND sale_pending_token IS NULL'
    values[#values + 1] = id
    if guard and guard.owner_character_id then
        where = where .. " AND owner_type = 'character' AND owner_character_id = ?"
        values[#values + 1] = tostring(guard.owner_character_id)
    end
    local ok, affected = pcall(function()
        return MySQL.update.await(('UPDATE cm_owned_vehicles SET %s WHERE %s'):format(table.concat(sets, ', '), where), values)
    end)
    return ok and tonumber(affected) or 0
end

function store.insertEvent(e)
    MySQL.insert.await([[INSERT INTO cm_vehicle_legal_events
        (vehicle_id, event, actor_character_id, source, registration, amount, details) VALUES (?, ?, ?, ?, ?, ?, ?)]], {
        e.vehicleId, e.event, e.actorCid, e.source and tostring(e.source):sub(1, 32) or nil, e.registration,
        math.floor(tonumber(e.amount) or 0), U.Encode(e.details or {}),
    })
    -- Mirror into the vehicle audit trail (plate-keyed, existing tooling).
    local row = store.getById(e.vehicleId)
    CMVehicles.Server.Audit(e.actorCid, row and row.plate or '', 'legal_' .. e.event, {
        vehicleId = e.vehicleId, registration = e.registration, amount = e.amount, source = e.source,
    })
end

-- Failed refunds are journaled in the existing payout table and paid by the
-- existing pending-payout processor the next time the character is online.
function store.queueRefund(r)
    local row = store.getById(r.vehicleId)
    MySQL.insert.await([[INSERT IGNORE INTO cm_vehicle_pending_payouts
        (sale_token, vehicle_id, character_id, plate, amount, account, reason, status, last_error)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 'immediate_refund_failed')]], {
        ('legal-refund:%s:%s:%s'):format(r.vehicleId, os.time(), math.random(100000, 999999)),
        r.vehicleId, tostring(r.characterId or ''), row and row.plate or '', r.amount, r.account or 'cash', r.reason })
end

local money = {
    remove = function(src, amount, reason, account) return CMVehicles.Server.RemoveMoney(src, amount, reason, account) end,
    add = function(src, amount, reason, account) return CMVehicles.Server.AddMoney(src, amount, reason, account) end,
}

-- A just-registered vehicle that is already in the world should show its new
-- public registration immediately (same call spawn.lua uses on spawn).
local function refreshLivePlate(row, service)
    if service ~= 'registration' or not row.license_number or not CMVehicles.Spawn
        or not CMVehicles.Spawn.GetSpawnedVehicleInfo then return end
    local ok, active, info = pcall(CMVehicles.Spawn.GetSpawnedVehicleInfo, tonumber(row.id))
    local entity = ok and active == true and type(info) == 'table' and tonumber(info.entity) or nil
    if entity and DoesEntityExist(entity) then pcall(SetVehicleNumberPlateText, entity, tostring(row.license_number)) end
end

L.Core = Core.New({ cfg = cfg, store = store, money = money, onApplied = refreshLivePlate })

-- ------------------------------------------------------------ trust helpers

local function trusted(invoking, set)
    if invoking == nil or invoking == GetCurrentResourceName() then return true end
    return type(set) == 'table' and set[invoking] == true
end

local function deny(name, invoking)
    print(('[cm-vehicles] ^3legal export %s rejected for resource %s^7'):format(name, tostring(invoking)))
end

-- Legal-state lookups used internally (recovery fee, G-menu info).
function L.IsInsured(row) return row ~= nil and L.Core:IsInsured(row) end

function L.RecoveryFee(row, baseFee)
    baseFee = math.max(0, math.floor(tonumber(baseFee) or 0))
    if baseFee > 0 and L.IsInsured(row) then
        local discount = math.max(0, math.min(1, tonumber((cfg.Insurance or {}).recoveryDiscount) or 0))
        return math.floor(baseFee * (1 - discount)), true
    end
    return baseFee, false
end

function L.IssueByPlate(plate, invoking)
    if not trusted(invoking, cfg.TrustedLawResources) then deny('IssueVehicleLicense', invoking); return false, 'Not permitted.' end
    plate = U.NormalizePlate(plate)
    if plate == '' then return false, 'Invalid plate.' end
    local id = MySQL.scalar.await('SELECT id FROM cm_owned_vehicles WHERE plate = ? LIMIT 1', { plate })
    if not id then return false, 'That vehicle does not exist.' end
    return L.Core:IssueRegistration(id, nil, invoking or 'cm-vehicles')
end

function L.OnOwnershipChanged(vehicleId, reason, source)
    return L.Core:OnOwnershipChanged(vehicleId, reason, source)
end

-- Recorded when a vehicle row is permanently removed (state sale). Legal state
-- lives on the row, so it is already gone; this keeps the history readable.
function L.OnVehicleRemoved(row, reason, actorCid)
    if type(row) ~= 'table' or not row.id then return end
    pcall(store.insertEvent, { vehicleId = tonumber(row.id), event = 'legal_state_removed', actorCid = actorCid,
        source = reason, registration = row.license_number and tostring(row.license_number) or nil, amount = 0,
        details = { registrationStatus = L.Core:registrationStatus(row, os.time()),
            insuranceStatus = L.Core:insuranceStatus(row, os.time()), reason = reason } })
end

-- ---------------------------------------------------------- player service

local function characterVehicles(cid)
    return MySQL.query.await(
        "SELECT * FROM cm_owned_vehicles WHERE owner_type = 'character' AND owner_character_id = ? ORDER BY id DESC LIMIT 100",
        { tostring(cid) }) or {}
end

function L.GetOverview(src)
    local cid = CMVehicles.Server.GetCharacterId(src)
    if not cid then return { ok = false, error = 'no_character' } end
    local list = {}
    for _, row in ipairs(characterVehicles(cid)) do
        normalizeRow(row)
        local q = L.Core:quote(row)
        q.label = tostring(row.label or row.model or '')
        q.model = tostring(row.model or '')
        q.image = CMVehicles.Server.GetVehicleCatalogImage and CMVehicles.Server.GetVehicleCatalogImage(row.model) or nil
        list[#list + 1] = q
    end
    return { ok = true, vehicles = list, now = os.time() }
end

function L.Quote(src, vehicleId)
    local cid = CMVehicles.Server.GetCharacterId(src)
    local row = store.getById(vehicleId)
    if not cid or not row then return { ok = false, error = 'vehicle_not_found' } end
    if tostring(row.owner_type or 'character') ~= 'character' or tostring(row.owner_character_id) ~= tostring(cid) then
        return { ok = false, error = 'not_owner' }
    end
    return { ok = true, quote = L.Core:quote(row) }
end

function L.Purchase(src, vehicleId, service, opts)
    local cid = CMVehicles.Server.GetCharacterId(src)
    if not cid then return { ok = false, error = 'no_character', message = 'Character is not loaded.' } end
    return L.Core:Purchase({ src = src, cid = cid, source = 'player' }, vehicleId, service, opts)
end

-- --------------------------------------------------------------- exports

exports('GetVehicleLegalStatus', function(vehicleId, opts)
    local includeOwner = type(opts) == 'table' and opts.includeOwner == true
        and trusted(GetInvokingResource(), cfg.TrustedOwnerLookupResources)
    return L.Core:GetLegalStatus(vehicleId, { includeOwner = includeOwner })
end)

exports('GetVehicleLegalStatusByRegistration', function(number, opts)
    local includeOwner = type(opts) == 'table' and opts.includeOwner == true
        and trusted(GetInvokingResource(), cfg.TrustedOwnerLookupResources)
    return L.Core:LookupByRegistration(number, { includeOwner = includeOwner })
end)

exports('RevokeVehicleRegistration', function(vehicleId, reason, actorCid)
    local invoking = GetInvokingResource()
    if not trusted(invoking, cfg.TrustedLawResources) then deny('RevokeVehicleRegistration', invoking); return false, 'untrusted_resource' end
    return L.Core:RevokeRegistration(vehicleId, actorCid, reason, invoking)
end)

exports('ReinstateVehicleRegistration', function(vehicleId, reason, actorCid)
    local invoking = GetInvokingResource()
    if not trusted(invoking, cfg.TrustedLawResources) then deny('ReinstateVehicleRegistration', invoking); return false, 'untrusted_resource' end
    return L.Core:ReinstateRegistration(vehicleId, actorCid, reason, invoking)
end)

exports('OnVehicleOwnershipChanged', function(vehicleId, reason)
    local invoking = GetInvokingResource()
    if not trusted(invoking, cfg.TrustedOwnershipResources) then deny('OnVehicleOwnershipChanged', invoking); return false, 'untrusted_resource' end
    return L.Core:OnOwnershipChanged(vehicleId, reason, invoking)
end)

local function serviceGuard(name)
    local invoking = GetInvokingResource()
    if trusted(invoking, cfg.TrustedServiceResources) then return true end
    deny(name, invoking)
    return false
end

exports('QuoteVehicleLegalServices', function(src, vehicleId)
    if not serviceGuard('QuoteVehicleLegalServices') then return { ok = false, error = 'untrusted_resource' } end
    return L.Quote(tonumber(src), vehicleId)
end)
exports('GetPlayerVehicleLegalOverview', function(src)
    if not serviceGuard('GetPlayerVehicleLegalOverview') then return { ok = false, error = 'untrusted_resource' } end
    return L.GetOverview(tonumber(src))
end)
exports('PurchaseVehicleLegalService', function(src, vehicleId, service, opts)
    if not serviceGuard('PurchaseVehicleLegalService') then return { ok = false, error = 'untrusted_resource' } end
    return L.Purchase(tonumber(src), vehicleId, service, type(opts) == 'table' and opts or nil)
end)

-- Client-facing contract for a future registry UI host (no UI ships in this
-- resource: its single ui_page is the protected G-menu). Source is always the
-- authenticated event source; vehicle id / service / price are inputs to be
-- validated, never trusted.
local lastCall = {}
local function throttled(src, key, ms)
    local now = GetGameTimer()
    local k = ('%s:%s'):format(src, key)
    if lastCall[k] and now - lastCall[k] < ms then return true end
    lastCall[k] = now
    return false
end

RegisterNetEvent('cm-vehicles:legal:requestOverview', function()
    local src = source
    if throttled(src, 'overview', 1000) then return end
    TriggerClientEvent('cm-vehicles:legal:overview', src, L.GetOverview(src))
end)

RegisterNetEvent('cm-vehicles:legal:requestPurchase', function(vehicleId, service, requestId, expectedPrice)
    local src = source
    if type(vehicleId) ~= 'number' or type(service) ~= 'string' then return end
    if requestId ~= nil and type(requestId) ~= 'string' then return end
    if throttled(src, 'purchase', 750) then return end
    local result = L.Purchase(src, vehicleId, service, {
        requestId = requestId, expectedPrice = type(expectedPrice) == 'number' and expectedPrice or nil })
    result.detail = nil -- never leak internals to a client
    TriggerClientEvent('cm-vehicles:legal:purchaseResult', src, result)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for k in pairs(lastCall) do if k:find('^' .. src .. ':') then lastCall[k] = nil end end
end)
