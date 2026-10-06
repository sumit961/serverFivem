-- cm-tuning FiveM wiring for the mechanic-mediated tuning service (server/service_core.lua). See docs/SERVICE_INTEGRATION.md.
-- cm-tuning stays the price/validation/mutation owner. cm-mechanic (the ONLY trusted caller) owns the work order, the customer's approval and
-- the cm-billing invoice; money never moves here. Mode is server state: a client can neither create nor flag a service session.
local Config = CMTuning.Config
local I = CMTuning.Internal
local Core, Store = CMTuning.ServiceCore, CMTuning.ServiceStore
local SC = Config.Service or {}

local function jsonEncode(t) local ok, s = pcall(json.encode, t); return ok and s or '' end
local function jsonDecode(s) if type(s) ~= 'string' or s == '' then return nil end local ok, t = pcall(json.decode, s); return ok and t or nil end

-- ------------------------------------------------------------------ adapters
local vehicles = {}
function vehicles.get(vehicleId)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return nil end
    if GetResourceState('cm-vehicles') ~= 'started' then return nil end
    local ok, row = pcall(function() return exports['cm-vehicles']:GetVehicleById(vehicleId) end)
    if not ok or type(row) ~= 'table' or not row.id then return nil end
    local okM, raw = pcall(function() return MySQL.scalar.await('SELECT mods FROM cm_owned_vehicles WHERE id = ?', { vehicleId }) end)
    if not okM then return nil end
    return {
        id = tonumber(row.id), plate = I.normalizePlate(row.plate), mods = raw,
        ownerKey = tostring(row.owner_type or 'character') .. ':' .. tostring(row.owner_character_id or ''),
    }
end
-- Compare-and-swap on the stored tuning state: a concurrent writer (self-service purchase, another service) makes this return false.
function vehicles.casMods(vehicleId, oldRaw, newRaw)
    local ok, n = pcall(function() return MySQL.update.await('UPDATE cm_owned_vehicles SET mods = ? WHERE id = ? AND mods <=> ?', { newRaw, tonumber(vehicleId), oldRaw }) end)
    return ok and tonumber(n) == 1
end
function vehicles.lock(vehicleId)
    local v = vehicles.get(vehicleId)
    if not v then return function() end end    -- no vehicle: _apply reports vehicle_unavailable itself
    return I.lockPlate(v.plate)
end

local MOD_LABELS = {}
for _, def in ipairs(Config.Performance or {}) do MOD_LABELS[tostring(def.modType)] = def.label end
for _, def in ipairs(Config.Visual or {}) do MOD_LABELS[tostring(def.modType)] = def.label end
local SET_LABELS = { primaryColor = 'Primary colour', secondaryColor = 'Secondary colour', wheelColor = 'Wheel colour', pearlColor = 'Pearl', windowTint = 'Window tint',
    plateIndex = 'Plate style', turbo = 'Turbo', xenon = 'Xenon lights', headlightColor = 'Headlight colour', neons = 'Neon', neonColor = 'Neon colour',
    tyreLevel = 'Tyres', bulletproofTyres = 'Tyre armour', livery = 'Livery', wheelType = 'Wheel type', customWheels = 'Custom wheels' }

local mods = {
    default = function(raw) return I.defaultMods(raw) end,
    quote = function(shop, raw, caps, changes)
        local clean = I.cleanCaps(caps, shop)
        local session = { shop = shop, baseMods = I.defaultMods(raw), caps = clean, liveryNative = shop == 'livery' and clean.liveryNative == true }
        local approved, price, err = I.calculatePurchase(session, changes)
        if not approved then return nil, nil, err end
        return approved, price, nil, clean
    end,
    describe = function(diff)
        local names, seen = {}, {}
        local function add(n) if n and not seen[n] then seen[n] = true; names[#names + 1] = n end end
        for mk in pairs(diff.slots or {}) do add(MOD_LABELS[tostring(mk)] or ('Part ' .. tostring(mk))) end
        for k in pairs(diff.set or {}) do add(SET_LABELS[k]) end
        table.sort(names)
        return table.concat(names, ', ')
    end,
}

local billing = {
    status = function(ref)
        if GetResourceState('cm-billing') ~= 'started' then return nil end
        local ok, st = pcall(function() return exports['cm-billing']:GetInvoiceStatus(ref) end)
        return ok and type(st) == 'string' and st or nil
    end,
}

local function sync(row, merged)
    if GetResourceState('cm-vehicles') ~= 'started' then return end
    local ok, success, info = pcall(function() return exports['cm-vehicles']:GetSpawnedVehicleInfo(tonumber(row.vehicle_id)) end)
    if ok and success == true and type(info) == 'table' and tonumber(info.netId) then
        TriggerClientEvent('cm-tuning:client:serviceApplied', -1, tonumber(info.netId), merged)
    end
end

local core = Core.New({
    cfg = SC, store = Store, now = os.time, rand = math.random, encode = jsonEncode, decode = jsonDecode,
    vehicles = vehicles, mods = mods, billing = billing, sync = sync,
    log = function(level, msg) print(('[cm-tuning] ^1service %s: %s^7'):format(level, tostring(msg))) end,
    audit = function(kind, detail) TriggerEvent('cm-admin:server:addLog', 0, kind, { category = 'tuning', detail = detail or {} }) end,
})
CMTuning.ServiceEngine = core
local ready = false

-- ------------------------------------------------------------------ exports (trusted callers only)
local function trusted()
    return type(SC.Trusted) == 'table' and SC.Trusted[GetInvokingResource() or ''] == true
end
local function guard(fn)
    return function(...)
        if not trusted() then return false, 'forbidden' end
        if SC.Enabled == false or not ready then return false, 'service_unavailable' end
        return fn(...)
    end
end

exports('CreateMechanicTuningAuthorization', guard(function(ctx) return core:Authorize(ctx) end))
exports('GetMechanicTuningQuote', guard(function(ref) return core:GetQuote(ref) end))
exports('ValidateMechanicTuningQuote', guard(function(ref) return core:Revalidate(ref) end))
exports('BindMechanicTuningInvoice', guard(function(ref, invoiceRef) return core:BindInvoice(ref, invoiceRef) end))
exports('ReleaseMechanicTuningInvoice', guard(function(ref) return core:ReleaseInvoice(ref) end))
exports('MarkMechanicTuningPaid', guard(function(ref, invoiceRef) return core:MarkPaid(ref, invoiceRef) end))
exports('ExecuteMechanicTuning', guard(function(ref) return core:Execute(ref) end))
exports('GetMechanicTuningStatus', guard(function(ref) return core:Status(ref) end))
exports('CancelMechanicTuning', guard(function(ref, reason) return core:Cancel(ref, reason) end))

-- Opens the existing tuning UI for the MECHANIC on the authorized vehicle. The session is bound to the authorization (mechanic character,
-- vehicle_id, shop) and has no charge path: its only effect is to record a server-priced proposal for the customer to approve.
exports('OpenMechanicTuningSession', guard(function(ref, mechanicSrc, netId)
    mechanicSrc, netId = tonumber(mechanicSrc), tonumber(netId)
    if not mechanicSrc or mechanicSrc <= 0 or not GetPlayerName(mechanicSrc) or not netId or netId <= 0 then return false, 'invalid_request' end
    local row = core:Get(ref)
    if not row then return false, 'not_found' end
    if row.status ~= 'created' and row.status ~= 'quoted' then return false, 'invalid_state' end
    if (tonumber(row.expires_at) or 0) < os.time() then return false, 'expired' end
    local pd = I.playerdata()
    local okC, cid = false, nil
    if pd then okC, cid = pcall(function() return pd:GetCharacterId(mechanicSrc) end) end
    if not okC or tostring(cid) ~= tostring(row.mechanic_cid) then return false, 'wrong_mechanic' end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return false, 'vehicle_not_found' end
    local stateId
    pcall(function() stateId = tonumber(Entity(entity).state.cmVehicleId) end)
    if stateId ~= tonumber(row.vehicle_id) then return false, 'wrong_vehicle' end
    local ped = GetPlayerPed(mechanicSrc)
    if not ped or ped == 0 then return false, 'player_unavailable' end
    local okB, sameBucket = pcall(function() return GetPlayerRoutingBucket(mechanicSrc) == GetEntityRoutingBucket(entity) end)
    if not okB or not sameBucket then return false, 'wrong_bucket' end
    if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > (tonumber(SC.maxMechanicDistance) or 10.0) then return false, 'too_far' end
    local v = vehicles.get(row.vehicle_id)
    if not v then return false, 'vehicle_not_found' end
    local lockedBy = I.lockedBy(v.plate)
    if lockedBy and lockedBy ~= mechanicSrc then return false, 'vehicle_busy' end
    local token = I.createToken(mechanicSrc, netId)
    I.openServiceSession(mechanicSrc, {
        mode = 'service', ref = row.reference, token = token, plate = v.plate, netId = netId, vehicleId = tonumber(row.vehicle_id), shop = row.shop,
        expiresAt = GetGameTimer() + (tonumber(SC.sessionTimeoutMs) or 300000), busy = false,
    })
    TriggerClientEvent('cm-tuning:client:openService', mechanicSrc, { token = token, shop = row.shop, netId = netId, savedMods = I.defaultMods(v.mods), balances = { cash = 0 } })
    return true
end))

-- ------------------------------------------------------------------ client event: the mechanic submits the selection (a PROPOSAL, never a purchase)
RegisterNetEvent('cm-tuning:server:servicePropose', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local deny = function(msg) I.sendDenied(src, 'cm-tuning:client:purchaseDenied', msg) end
    if not I.cooldown(src, 'servicePropose', tonumber(Config.Security and Config.Security.purchaseCooldownMs) or 2000) then return deny('Please wait before submitting again.') end
    local session = I.getSession(src)
    if not session or session.mode ~= 'service' or tostring(session.token) ~= tostring(data.token or '') then return deny('Your tuning session is no longer valid.') end
    if session.expiresAt < GetGameTimer() then I.releaseSession(src, 'expired'); return deny('Your tuning session expired.') end
    if session.busy then return deny('A proposal is already processing.') end
    session.busy = true
    -- the vehicle must still be the authorized one (entity identity re-checked from server state)
    local entity = NetworkGetEntityFromNetworkId(session.netId)
    local stateId
    if entity and entity ~= 0 and DoesEntityExist(entity) then pcall(function() stateId = tonumber(Entity(entity).state.cmVehicleId) end) end
    if stateId ~= session.vehicleId then session.busy = false; return deny('The authorized vehicle is no longer here.') end
    local ok, a = core:Quote(session.ref, data.caps, data.changes)
    session.busy = false
    if not ok then
        local messages = { amount_over_limit = 'This job is above the maximum invoice amount. Remove some upgrades or split it into separate jobs.',
            expired = 'This authorization expired.', ownership_changed = 'The vehicle changed hands.', nothing_billable = 'Select at least one paid modification.',
            no_changes = 'No changes selected.', invalid_state = 'This authorization can no longer be changed.', busy = 'Please wait.' }
        return deny(messages[a] or tostring(a))
    end
    local netId = session.netId
    I.releaseSession(src, 'service_proposed')
    TriggerClientEvent('cm-tuning:client:serviceProposed', src, { netId = netId, amount = a.amount })
    TriggerEvent('cm-tuning:service:quoted', session.ref)     -- server-local (NOT a net event): cm-mechanic pulls the quote through its trusted export
end)

-- ------------------------------------------------------------------ lifecycle
CreateThread(function()
    local ok, err = pcall(function() Store.EnsureSchema() end)
    if not ok then print(('[cm-tuning] ^1service journal schema error: %s^7'):format(tostring(err))); return end
    ready = true
    while true do
        Wait(30000)
        pcall(function() core:ExpireSweep() end)
    end
end)
