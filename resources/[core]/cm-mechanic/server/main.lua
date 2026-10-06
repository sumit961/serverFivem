-- cm-mechanic FiveM wiring for server/core.lua. See docs/README.md.
-- Authority map: this resource owns mechanic REQUESTS and WORK ORDERS. cm-phone is the frontend, cm-contracts the broker,
-- cm-commercial-ownership the business (owner/employees/permissions/balance), cm-billing the invoice, cm-vehicles the vehicle.
local Config = CMMechanic.Config
local Core, Store = CMMechanic.Core, CMMechanic.Store
local RESOURCE = GetCurrentResourceName()

-- ---------------------------------------------------------------- cross-resource

-- pcall'd, fail-closed call: false when the resource is not started or the export errors.
local function xcall(resource, name, ...)
    if GetResourceState(resource) ~= 'started' then return false, 'resource_unavailable' end
    local args = table.pack(...)
    local res = table.pack(pcall(function() return exports[resource][name](exports[resource], table.unpack(args, 1, args.n)) end))
    if not res[1] then return false, 'call_failed' end
    return true, table.unpack(res, 2, res.n)
end

local srcCache = {}   -- source -> character id, only used to resolve a dropping player
local function charOf(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local ok, cid = xcall('cm-playerdata', 'GetCharacterId', src)
    if ok and cid ~= nil and tostring(cid) ~= '' then srcCache[src] = tostring(cid); return tostring(cid) end
    return nil
end

local function sourceOf(cid)
    local ok, src = xcall('cm-playerdata', 'GetSourceByCharId', tonumber(cid))
    src = ok and tonumber(src) or nil
    if src and src > 0 and GetPlayerName(src) then return src end
    return nil
end

local function jsonEncode(t) local ok, s = pcall(json.encode, t); return ok and s or '' end
local function jsonDecode(s) if type(s) ~= 'string' or s == '' then return nil end local ok, t = pcall(json.decode, s); return ok and t or nil end

local function cleanText(value, max)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%z\1-\31\127]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end
    local count, cut = 0, #value
    for pos in value:gmatch('()[\0-\127\194-\244][\128-\191]*') do
        count = count + 1
        if count > max then cut = pos - 1 break end
    end
    if count > max then value = value:sub(1, cut) end
    return value
end

-- ---------------------------------------------------------------- rate limiting

local hits = {}
local function rate(cid, bucket)
    local cfg = Config.RateLimits[bucket]
    if not cfg then return true end
    local key, now = tostring(cid) .. ':' .. bucket, os.time()
    local kept = {}
    for _, t in ipairs(hits[key] or {}) do if now - t < cfg[2] then kept[#kept + 1] = t end end
    if #kept >= cfg[1] then hits[key] = kept; return false end
    kept[#kept + 1] = now
    hits[key] = kept
    return true
end

-- ------------------------------------------------------------------- adapters

local shopLabels = {}
for _, s in ipairs(Config.Shops) do shopLabels[s.id] = s.label end

local adapters = {}

adapters.chars = {
    sourceOf = sourceOf,
    position = function(src)
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return nil end
        local c = GetEntityCoords(ped)
        local okB, bucket = pcall(GetPlayerRoutingBucket, src)
        return { x = c.x, y = c.y, z = c.z, bucket = okB and bucket or 0 }
    end,
    isDead = function(src)
        local ok, dead = xcall('cm-playerdata', 'IsDead', src)
        return ok and dead == true
    end,
}

local function spawnedInfo(vehicleId)
    local ok, success, info = xcall('cm-vehicles', 'GetSpawnedVehicleInfo', vehicleId)
    if ok and success == true and type(info) == 'table' then return info end
    return nil
end

adapters.vehicles = {
    -- Server-observed entity -> persistent vehicle_id. The id comes from cm-vehicles' own entity state AND is confirmed by its
    -- spawn registry; the client-supplied netId is only a handle, never an identity.
    fromNet = function(netId)
        netId = tonumber(netId)
        if not netId or netId <= 0 or netId ~= math.floor(netId) then return nil, 'vehicle_not_found' end
        local entity = NetworkGetEntityFromNetworkId(netId)
        if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil, 'vehicle_not_found' end
        local okS, vehicleId = pcall(function() return tonumber(Entity(entity).state.cmVehicleId) end)
        if not okS or not vehicleId then return nil, 'vehicle_not_persistent' end
        local info = spawnedInfo(vehicleId)
        if not info or tonumber(info.entity) ~= entity then return nil, 'vehicle_not_registered' end
        return vehicleId
    end,
    get = function(vehicleId)
        local ok, row = xcall('cm-vehicles', 'GetVehicleById', vehicleId)
        if not ok or type(row) ~= 'table' then return nil end
        local okA, isAdmin = xcall('cm-vehicles', 'IsAdminVehicle', row.plate)
        return {
            id = tonumber(row.id), plate = row.plate, model = tostring(row.model or ''), label = tostring(row.label or row.model or ''),
            ownerType = tostring(row.owner_type or 'character'), ownerCharacterId = row.owner_character_id,
            stored = row.is_stored == true or tonumber(row.is_stored) == 1, admin = okA and isAdmin == true, raw = row,
        }
    end,
    position = function(vehicleId)
        local info = spawnedInfo(vehicleId)
        local entity = info and tonumber(info.entity)
        if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
        local c = GetEntityCoords(entity)
        local okB, bucket = pcall(GetEntityRoutingBucket, entity)
        return { x = c.x, y = c.y, z = c.z, bucket = okB and bucket or 0 }
    end,
    netIdOf = function(vehicleId)
        local info = spawnedInfo(vehicleId)
        return info and tonumber(info.netId) or nil
    end,
    -- Authoritative persistent condition: the spawned vehicle's replicated state, falling back to the stored row (cm-vehicles' own rule).
    -- A condition that is not initialised yet is reported as unavailable, never as "full health".
    condition = function(vehicleId, vehicle)
        local ok, success, cond = xcall('cm-vehicles', 'GetSpawnedVehicleCondition', vehicleId, vehicle and vehicle.raw or {})
        if not ok or success ~= true or type(cond) ~= 'table' then return nil, 'condition_unavailable' end
        if cond.conditionReady ~= true then return nil, 'condition_pending' end
        return { engine = cond.engine, body = cond.body, tank = cond.tank, conditionState = cond.conditionState }
    end,
    value = function(model)
        local okQ, price = pcall(function()
            return MySQL.scalar.await('SELECT price FROM cm_vehicle_catalog WHERE LOWER(model) = ? LIMIT 1', { tostring(model or ''):lower() })
        end)
        return okQ and tonumber(price) or nil
    end,
    canUse = function(src, vehicleId, level)
        if level == 'owner' then
            local row = adapters.vehicles.get(vehicleId)
            if not row then return false end
            local ok, owns = xcall('cm-vehicles', 'PlayerOwnsVehicle', src, row.plate)
            return ok and owns == true
        end
        local ok, allowed = xcall('cm-vehicles', 'CanUseVehicle', src, vehicleId, 'vehicle.info')
        return ok and allowed == true
    end,
    -- cm-vehicles' trusted service export, keyed by the persistent vehicle_id (cm-mechanic is allowlisted in
    -- cm-vehicles Config.Service.TrustedCallers for condition fields only). It owns persistence + the replicated condition apply.
    apply = function(vehicleId, patch)
        local ok, done = xcall('cm-vehicles', 'ServiceVehicleById', tonumber(vehicleId), patch, -1)
        return ok and done == true
    end,
}

adapters.business = {
    get = function(t, i)
        local ok, biz = xcall('cm-commercial-ownership', 'GetBusiness', t, i)
        if not ok or type(biz) ~= 'table' then return nil end
        if t == Config.BusinessType and shopLabels[i] then biz.label = shopLabels[i] end
        return biz
    end,
    has = function(t, i, cid, perm)
        local ok, yes = xcall('cm-commercial-ownership', 'HasBusinessPermission', t, i, tonumber(cid), perm)
        return ok and yes == true
    end,
    list = function(cid)
        local ok, list = xcall('cm-commercial-ownership', 'GetPlayerBusinesses', tonumber(cid))
        return ok and type(list) == 'table' and list or {}
    end,
}

adapters.billing = {
    create = function(data) local ok, a, b = xcall('cm-billing', 'CreateInvoice', data); if not ok then return false, 'unavailable' end return a, b end,
    status = function(ref) local ok, st = xcall('cm-billing', 'GetInvoiceStatus', ref); return ok and st or nil end,
    -- cm-billing's creation limit for THIS provider (single source of truth; nil when billing is unavailable).
    limit = function() local ok, p = xcall('cm-billing', 'GetProviderPolicy'); local n = ok and type(p) == 'table' and tonumber(p.maxInvoiceAmount) or nil return n and n >= 1 and n or nil end,
    void = function(ref, reason) local ok, a = xcall('cm-billing', 'VoidInvoice', ref, reason); return ok and a == true end,
}

-- cm-tuning (price + modification owner). Every call is `ok, data|reason`; ok is true ONLY when cm-tuning answered true.
-- cm-tuning only accepts this resource (its own trust list); the client never reaches these.
local function tuningCall(name)
    return function(...)
        local ok, a, b = xcall('cm-tuning', name, ...)
        if not ok then return false, 'unavailable' end
        return a == true, b
    end
end
adapters.tuning = {
    authorize = tuningCall('CreateMechanicTuningAuthorization'),
    open = tuningCall('OpenMechanicTuningSession'),
    quote = tuningCall('GetMechanicTuningQuote'),
    validate = tuningCall('ValidateMechanicTuningQuote'),
    bind = tuningCall('BindMechanicTuningInvoice'),
    release = tuningCall('ReleaseMechanicTuningInvoice'),
    paid = tuningCall('MarkMechanicTuningPaid'),
    execute = tuningCall('ExecuteMechanicTuning'),
    cancel = tuningCall('CancelMechanicTuning'),
    status = tuningCall('GetMechanicTuningStatus'),
}

adapters.contracts = {
    create = function(d) local ok, a, b = xcall('cm-contracts', 'CreateContract', d); if not ok then return false, a end return a, b end,
    cancel = function(t, ref, why) local ok, a, b = xcall('cm-contracts', 'CancelContract', t, ref, why); if not ok then return false, a end return a, b end,
    get = function(t, ref) local ok, a, b = xcall('cm-contracts', 'GetSourceContract', t, ref); if not ok then return false, a end return a, b end,
    claim = function(ref, cid, opts) local ok, a, b, c = xcall('cm-contracts', 'ClaimContract', ref, cid, opts); if not ok then return false, a end return a, b, c end,
    active = function(ref, cid) local ok, a, b = xcall('cm-contracts', 'MarkContractActive', ref, cid); if not ok then return false, a end return a, b end,
    complete = function(ref, cid, opts) local ok, a, b = xcall('cm-contracts', 'CompleteContract', ref, cid, opts); if not ok then return false, a end return a, b end,
    release = function(ref, cid, why) local ok, a, b = xcall('cm-contracts', 'ReleaseContract', ref, cid, why); if not ok then return false, a end return a, b end,
    list = function(filters, cid) local ok, a, b = xcall('cm-contracts', 'ListAvailableContracts', Config.ProviderType, filters, cid); if not ok then return false, a end return a, b end,
    disconnected = function(cid) local ok, a, b = xcall('cm-contracts', 'ReportWorkerDisconnected', Config.ProviderType, cid); if not ok then return false, a end return a, b end,
}

local function notify(cid, kind, payload)
    if kind == 'phone' then
        xcall('cm-phone', 'PushPhoneServiceStatus', tostring(cid), Config.PhoneService, payload)
        return
    end
    local src = sourceOf(cid)
    if not src then return end
    if kind == 'quote' then TriggerClientEvent('cm-mechanic:client:quote', src, payload)
    elseif kind == 'invoice' then TriggerClientEvent('cm-hud:client:notify', src, 'Invoice sent - open Bills to pay', 'info')
    elseif kind == 'mechanic' then TriggerClientEvent('cm-mechanic:client:update', src, payload) end
end

local function audit(kind, detail)
    TriggerEvent('cm-admin:server:addLog', 0, kind, { category = 'mechanic', detail = detail or {} })
end

local core = Core.New({
    cfg = Config, store = Store, now = os.time, rand = math.random, encode = jsonEncode, decode = jsonDecode, clean = cleanText,
    chars = adapters.chars, vehicles = adapters.vehicles, business = adapters.business, billing = adapters.billing, contracts = adapters.contracts, tuning = adapters.tuning,
    notify = notify, audit = audit, rate = rate,
    log = function(level, msg) print(('[cm-mechanic] ^1%s: %s^7'):format(level, tostring(msg))) end,
})
CMMechanic.Engine = core
local ready = false
local sweepHot = true

-- ------------------------------------------------------------ phone adapter (cm-phone only)

local function phoneOnly() return GetInvokingResource() == 'cm-phone' end

exports('PhoneServiceCreate', function(cid, service, fields, ctx)
    if not phoneOnly() then return false, 'not_allowed' end
    if not ready or service ~= Config.PhoneService then return false, 'service_unavailable' end
    sweepHot = true
    return core:CreateRequest(cid, fields, ctx)
end)
exports('PhoneServiceStatus', function(cid, service)
    if not phoneOnly() then return false end
    if not ready then return true, nil end
    return core:RequestStatus(cid)
end)
exports('PhoneServiceCancel', function(cid, service, ref)
    if not phoneOnly() then return false, 'not_allowed' end
    if not ready then return false, 'service_unavailable' end
    return core:CancelRequest(cid, ref)
end)
exports('PhoneServiceAvailability', function()
    if not phoneOnly() then return false end
    return ready and core:Availability() or false
end)

-- ------------------------------------------------- cm-contracts source / provider callbacks

local function brokerOnly(fn)
    return function(...)
        if GetInvokingResource() ~= 'cm-contracts' then return false, 'forbidden' end
        if not ready then return false, 'not_ready' end
        return fn(...)
    end
end
exports('ContractSourceComplete', brokerOnly(function(ctx) return core:SourceComplete(ctx or {}) end))
exports('ContractSourceFallback', brokerOnly(function(ctx) return core:SourceFallback(ctx or {}) end))
exports('ContractSourceCancel', brokerOnly(function(ctx) return core:SourceCancel(ctx or {}) end))
exports('ContractSourceEvent', brokerOnly(function(ctx) return core:SourceEvent(ctx or {}) end))
exports('ContractEligible', brokerOnly(function(cid, view) return core:Eligible(cid, view) end))
exports('ContractEvent', function() return true end) -- provider notices are informational; state is derived from the source events

local function registerWithPhone()
    if GetResourceState('cm-phone') ~= 'started' then return end
    local ok, a, b = xcall('cm-phone', 'RegisterPhoneService', Config.PhoneService, {
        create = 'PhoneServiceCreate', status = 'PhoneServiceStatus', cancel = 'PhoneServiceCancel', availability = 'PhoneServiceAvailability' })
    if not ok or a ~= true then print(('[cm-mechanic] phone service not registered: %s'):format(tostring(b or a))) end
end

local function registerWithBroker()
    if GetResourceState('cm-contracts') ~= 'started' then return end
    local ok, a, b = xcall('cm-contracts', 'RegisterProvider', Config.ProviderType, {
        types = { Config.ContractType }, eligibilityExport = 'ContractEligible', eventExport = 'ContractEvent',
        disconnectPolicy = 'grace', graceSeconds = 120, leaseSeconds = 600 })
    if not ok or a ~= true then print(('[cm-mechanic] contract provider not registered: %s'):format(tostring(b or a))) end
end

AddEventHandler('cm-phone:server:serviceRegistryReady', registerWithPhone)
AddEventHandler('cm-contracts:server:providerRegistryReady', registerWithBroker)
AddEventHandler('onResourceStart', function(resource)
    if resource == 'cm-phone' then SetTimeout(1500, registerWithPhone)
    elseif resource == 'cm-contracts' then SetTimeout(1500, registerWithBroker) end
end)

-- cm-tuning recorded a server-priced proposal for an authorization of ours. LOCAL server event (not a net event: clients cannot trigger it);
-- the quote is pulled through cm-tuning's trusted export and validated against the work order, so a forged trigger can bind nothing.
AddEventHandler('cm-tuning:service:quoted', function(ref)
    if not ready or type(ref) ~= 'string' then return end
    local ok, err = pcall(function() return core:OnTuningQuoted(ref) end)
    if not ok then print(('[cm-mechanic] tuning quote error: %s'):format(tostring(err))) end
end)

-- ------------------------------------------------ NUI / client callbacks (ox_lib)
-- The mechanic's order is ALWAYS resolved from their own character id; the client never names a work order, business, price or worker.

local function reply(ok, a, b)
    if ok == true then return { ok = true, data = a } end
    return { ok = false, error = type(a) == 'string' and a or 'failed' }
end

local function activeWork(cid) return Store.woActiveByMechanic(cid) end

lib.callback.register('cm-mechanic:state', function(src)
    local cid = charOf(src); if not cid or not ready then return reply(false, 'not_ready') end
    return reply(core:Board(cid))
end)
lib.callback.register('cm-mechanic:claim', function(src, contractRef, businessId)
    local cid = charOf(src); if not cid or not ready then return reply(false, 'not_ready') end
    return reply(core:Claim(cid, contractRef, type(businessId) == 'string' and businessId or nil))
end)
lib.callback.register('cm-mechanic:diagnose', function(src, netId)
    local cid = charOf(src); if not cid or not ready then return reply(false, 'not_ready') end
    local wo = activeWork(cid); if not wo then return reply(false, 'not_found') end
    return reply(core:BeginDiagnosis(cid, wo.reference, netId))
end)
lib.callback.register('cm-mechanic:quote', function(src, serviceId, netId)
    local cid = charOf(src); if not cid or not ready then return reply(false, 'not_ready') end
    local wo = activeWork(cid); if not wo then return reply(false, 'not_found') end
    return reply(core:CreateQuote(cid, wo.reference, serviceId, netId))
end)
lib.callback.register('cm-mechanic:startTuning', function(src, netId, shop)
    local cid = charOf(src); if not cid or not ready then return reply(false, 'not_ready') end
    local wo = activeWork(cid); if not wo then return reply(false, 'not_found') end
    return reply(core:StartTuning(cid, wo.reference, netId, type(shop) == 'string' and shop or '', src))
end)
lib.callback.register('cm-mechanic:abandon', function(src)
    local cid = charOf(src); if not cid or not ready then return reply(false, 'not_ready') end
    local wo = activeWork(cid); if not wo then return reply(false, 'not_found') end
    return reply(core:AbandonWork(cid, wo.reference))
end)
lib.callback.register('cm-mechanic:startService', function(src, netId)
    local cid = charOf(src); if not cid or not ready then return reply(false, 'not_ready') end
    local wo = activeWork(cid); if not wo then return reply(false, 'not_found') end
    return reply(core:StartService(cid, wo.reference, netId))
end)
lib.callback.register('cm-mechanic:finishService', function(src, netId)
    local cid = charOf(src); if not cid or not ready then return reply(false, 'not_ready') end
    local wo = activeWork(cid); if not wo then return reply(false, 'not_found') end
    return reply(core:FinishService(cid, wo.reference, netId))
end)
lib.callback.register('cm-mechanic:respondQuote', function(src, approve)
    local cid = charOf(src); if not cid or not ready then return reply(false, 'not_ready') end
    return reply(core:RespondQuote(cid, approve == true))
end)
lib.callback.register('cm-mechanic:pendingQuote', function(src)
    local cid = charOf(src); if not cid or not ready then return nil end
    return core:PendingQuote(cid)
end)

-- --------------------------------------------------------------- admin / recovery

local function adminOnly(fn)
    return function(...)
        if not Config.AdminCallers[GetInvokingResource() or ''] then return false, 'forbidden' end
        if not ready then return false, 'not_ready' end
        return fn(...)
    end
end
exports('AdminInspectMechanic', adminOnly(function(ref) return core:AdminInspect(ref) end))
exports('AdminCancelMechanic', adminOnly(function(ref, label) return core:AdminCancel(ref, label) end))
exports('AdminReconcileMechanic', adminOnly(function(ref, label) if ref then return core:AdminReconcile(ref, label) end return core:Reconcile() end))
exports('AdminSetMechanicShopOwner', adminOnly(function(shopId, characterId, label)
    if not shopLabels[tostring(shopId)] then return false, 'unknown_shop' end
    characterId = tonumber(characterId)
    if not characterId then return false, 'invalid_character' end
    Store.SetShopOwner(tostring(shopId), characterId, cleanText(label or '', 100))
    audit('mechanic_shop_owner_set', { shop = shopId, owner = characterId })
    return true
end))

local function consoleOnly(name, fn)
    RegisterCommand(name, function(src, args)
        if src ~= 0 then return end
        local ok, a, b = pcall(fn, args)
        print(('[cm-mechanic] %s -> %s'):format(name, ok and jsonEncode({ a, b }) or tostring(a)))
    end, true)
end
consoleOnly('cm_mechanic_inspect', function(a) return core:AdminInspect(a[1]) end)
consoleOnly('cm_mechanic_cancel', function(a) return core:AdminCancel(a[1], 'console') end)
consoleOnly('cm_mechanic_reconcile', function(a) if a[1] then return core:AdminReconcile(a[1], 'console') end return core:Reconcile() end)
consoleOnly('cm_mechanic_setowner', function(a)
    if not shopLabels[tostring(a[1])] then return false, 'unknown_shop' end
    local cid = tonumber(a[2]); if not cid then return false, 'invalid_character' end
    Store.SetShopOwner(tostring(a[1]), cid, a[3] and cleanText(a[3], 100) or nil)
    audit('mechanic_shop_owner_set', { shop = a[1], owner = cid, by = 'console' })
    return true
end)

-- ------------------------------------------------------------------- lifecycle

AddEventHandler('playerDropped', function()
    local src = source
    local cid = srcCache[src]; srcCache[src] = nil
    if cid and ready then pcall(function() core:OnMechanicDropped(cid) end) end
end)

CreateThread(function()
    local ok, err = pcall(function() Store.EnsureSchema(); Store.SeedShops(Config.Shops) end)
    if not ok then print(('[cm-mechanic] ^1schema error: %s^7'):format(tostring(err))); return end
    ready = true
    Wait(2000)
    registerWithPhone()
    registerWithBroker()
    -- restart recovery: payments detected, interrupted commits replayed (absolute patches), stale orders released
    local rok, rerr = pcall(function() return core:Reconcile() end)
    if not rok then print(('[cm-mechanic] reconcile error: %s'):format(tostring(rerr))) end
    while true do
        -- adaptive: fast while work is open, slow when idle
        Wait((sweepHot and Config.SweepSeconds or 15) * 1000)
        local okS, _, stats = pcall(function() return core:Reconcile() end)
        if not okS then print(('[cm-mechanic] reconcile error: %s'):format(tostring(_))) end
        sweepHot = #Store.reqListOpen(1) > 0
    end
end)
