-- cm-mechanic pricing + diagnosis. PURE: no FiveM natives, no database. The server resolves the service, the vehicle row and the
-- authoritative condition, then asks this module for the amount and the (absolute, idempotent) vehicle patch.
-- A client never supplies any value that reaches these functions.
CMMechanic = CMMechanic or {}
local P = {}
CMMechanic.Pricing = P

local function health(v)
    -- nil / non-number = condition MISSING (unknown). A genuine 0 is real damage and is preserved as 0.
    v = tonumber(v)
    if v == nil or v ~= v then return nil end
    return math.max(0.0, math.min(1000.0, v))
end

local function countTable(t, pred)
    local n = 0
    if type(t) ~= 'table' then return 0 end
    for _, v in pairs(t) do if pred(v) then n = n + 1 end end
    return n
end

local function copy(t)
    if type(t) ~= 'table' then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end
P.copy = copy

-- cond = { engine, body, tank, conditionState } (cm-vehicles units: 0..1000). Returns a plain table safe to show a mechanic.
function P.diagnose(cond, cfg)
    cond = type(cond) == 'table' and cond or {}
    local minMissing = tonumber(cfg and cfg.Pricing and cfg.Pricing.minMissingHealth) or 30
    local state = type(cond.conditionState) == 'table' and cond.conditionState or {}
    local function part(value)
        local h = health(value)
        if h == nil then return { known = false, health = nil, missing = 0, needed = false } end
        local missing = math.floor(1000.0 - h + 0.5)
        return { known = true, health = math.floor(h + 0.5), missing = missing, needed = missing >= minMissing }
    end
    local d = { engine = part(cond.engine), tank = part(cond.tank), body = part(cond.body) }
    local windows = countTable(state.brokenWindows, function(v) return v == true end)
    local doors = countTable(state.doors, function(v) return type(v) == 'table' and (v.damaged == true or v.broken == true) end)
    d.cosmetic = { known = true, windows = windows, doors = doors, items = windows + doors, needed = windows + doors > 0 }
    local tyres = countTable(state.tyres, function(v) return type(v) == 'table' and (v.burst == true or v.onRim == true) end)
    d.tyres = { known = true, items = tyres, needed = tyres > 0 }
    return d
end

local function partPrice(cfg, name, d, value)
    local pc = cfg.Pricing.parts[name]
    if not pc or not d or not d.known or not d.needed then return 0 end
    if name == 'cosmetic' or name == 'tyres' then
        return math.floor(math.min(d.items, tonumber(pc.maxItems) or 16) * (tonumber(pc.perItem) or 0))
    end
    local missing = d.missing
    return math.floor((tonumber(pc.base) or 0) + (tonumber(pc.perPoint) or 0) * missing + (tonumber(pc.valuePct) or 0) * value * (missing / 1000.0))
end

-- -> true, { amount, lines = { {part, amount} ... }, parts = { engine = true ... }, unknown = { ... } } | false, reason
function P.quote(cfg, serviceId, diag, vehicleValue)
    local svc = cfg.Services[serviceId]
    if type(serviceId) ~= 'string' or not svc then return false, 'invalid_service' end
    if svc.enabled == false then return false, 'service_unavailable' end
    if svc.authority then return false, 'service_unavailable' end   -- another owner (cm-tuning) prices it; never derived here
    local value = tonumber(vehicleValue)
    if not value or value ~= value or value <= 0 then value = tonumber(cfg.Pricing.fallbackVehicleValue) or 300000 end
    value = math.min(value, tonumber(cfg.Pricing.valueCap) or 20000000)

    local lines, parts, unknown, total = {}, {}, {}, 0
    for _, name in ipairs(svc.parts or {}) do
        local d = diag and diag[name]
        if d and d.known == false then
            unknown[#unknown + 1] = name
        else
            local amount = partPrice(cfg, name, d, value)
            if amount > 0 then lines[#lines + 1] = { part = name, amount = amount }; parts[name] = true; total = total + amount end
        end
    end
    if #(svc.parts or {}) > 0 then
        if #lines == 0 then
            if #unknown == #svc.parts then return false, 'condition_unknown' end
            return false, 'nothing_to_repair'
        end
        total = total + math.floor(tonumber(svc.base) or 0)
    else
        total = math.floor(tonumber(svc.base) or 0)
    end
    local amount = math.max(tonumber(svc.minPrice) or 1, math.min(tonumber(svc.maxPrice) or total, total))
    amount = math.floor(amount)
    if amount < 1 then return false, 'service_unavailable' end
    return true, { amount = amount, lines = lines, parts = parts, unknown = unknown, base = math.floor(tonumber(svc.base) or 0) }
end

-- Absolute target values only (never increments), so re-applying after a crash cannot "repair twice".
-- existingState = the vehicle's current condition_state snapshot (kept for every part that is NOT being repaired).
function P.buildPatch(parts, existingState)
    local patch = {}
    if parts.engine then patch.engineHealth = 1000.0 end
    if parts.tank then patch.tankHealth = 1000.0 end
    if parts.body then patch.bodyHealth = 1000.0 end
    if parts.cosmetic or parts.tyres or parts.engine then
        local state = copy(type(existingState) == 'table' and existingState or {})
        state.windowSchema = state.windowSchema or 2
        state.brokenWindows = state.brokenWindows or {}
        state.doors = state.doors or {}
        state.tyres = state.tyres or {}
        if parts.cosmetic then state.brokenWindows = {}; state.doors = {} end
        if parts.tyres then state.tyres = {} end
        if parts.engine then state.undriveable = false end
        patch.conditionState = state
    end
    return patch
end

function P.hasMutation(parts) return next(parts or {}) ~= nil end

-- Public, mechanic-safe diagnosis summary (no ids, no owner data).
function P.summary(diag)
    local function pct(p) if not p.known then return nil end return math.floor(p.health / 10 + 0.5) end
    return {
        engine = pct(diag.engine), tank = pct(diag.tank), body = pct(diag.body),
        brokenWindows = diag.cosmetic.windows, damagedDoors = diag.cosmetic.doors, damagedTyres = diag.tyres.items,
    }
end
