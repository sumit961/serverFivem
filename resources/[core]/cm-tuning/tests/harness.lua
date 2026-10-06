-- Deterministic harness for cm-tuning server code (NO FiveM, NO database).
-- REAL: shared/config.lua, server/service_core.lua, server/main.lua (self-service tuning: sessions, calculatePurchase, direct charge), server/service.lua.
-- DOUBLES (labelled): the FiveM runtime (events, natives, entities, players), cm-vehicles / cm-playerdata / cm-billing export surfaces, the SQL layer
--   for cm_owned_vehicles.mods (with the same `mods <=> ?` compare-and-swap semantics) and an in-memory implementation of the journal store.
-- resolved from THIS file so other resources' tests (cm-mechanic) can load it
local here = (debug.getinfo(1, 'S').source:match('^@(.*)[/\\]tests[/\\]harness%.lua$')) or '.'
local J =dofile(here .. '/../cm-inventory/tests/craft_harness.lua')(here .. '/../cm-inventory')
local json = J.json

local function slurp(path) local f = assert(io.open(path, 'rb')); local s = f:read('a'); f:close(); return s end

-- ---------------------------------------------------------------- vectors
local Vec = {}
Vec.__index = Vec
local function vec(x, y, z) return setmetatable({ x = x, y = y, z = z }, Vec) end
Vec.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
Vec.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end

-- ---------------------------------------------------------------- in-memory journal store (same contract + unique keys as service_store.lua)
local function newStore()
    local S = { rows = {} }
    local function copy(r) if not r then return nil end local o = {} for k, v in pairs(r) do o[k] = v end return o end
    function S.EnsureSchema() return true end
    function S.insert(r)
        for _, x in ipairs(S.rows) do
            if x.reference == r.reference then return nil, 'error' end
            if r.active_key and x.active_key == r.active_key then return nil, 'duplicate_active' end
            if r.vehicle_key and x.vehicle_key == r.vehicle_key then return nil, 'duplicate_vehicle' end
        end
        S.rows[#S.rows + 1] = copy(r); return #S.rows
    end
    function S.get(ref) for _, x in ipairs(S.rows) do if x.reference == ref then return copy(x) end end end
    function S.activeByWork(wo) for _, x in ipairs(S.rows) do if x.active_key == wo then return copy(x) end end end
    function S.activeByVehicle(v) for _, x in ipairs(S.rows) do if x.vehicle_key == tostring(v) then return copy(x) end end end
    function S.cas(ref, from, patch)
        for _, x in ipairs(S.rows) do
            if x.reference == ref then
                local ok = false
                for _, st in ipairs(from) do if x.status == st then ok = true end end
                if not ok then return 0 end
                for k, v in pairs(patch) do
                    if v == false then x[k] = nil else x[k] = v end
                end
                S.writes = (S.writes or 0) + 1
                return 1
            end
        end
        return 0
    end
    function S.listExpirable(now, limit)
        local o = {}
        for _, x in ipairs(S.rows) do if (x.status == 'created' or x.status == 'quoted') and (tonumber(x.expires_at) or 0) < now then o[#o + 1] = copy(x) end end
        return o
    end
    return S
end

-- ---------------------------------------------------------------- world
local function build(opts)
    opts = opts or {}
    local W = {
        invoker = 'cm-mechanic', clock = opts.clock or 1700000000, timer = 1000, source = 0,
        netHandlers = {}, localHandlers = {}, registry = {}, clientEvents = {}, localEvents = {}, audit = {},
        players = {}, entities = {}, vehicles = {}, invoices = {}, cash = {}, charges = {}, refunds = {},
        saved = {}, modWrites = 0, casFailOnce = false, billingDown = false, convars = {},
    }
    W.store = opts.store or newStore()
    W.mem = W.store

    -- players / entities / vehicles ------------------------------------------------
    function W.addPlayer(src, cid, pos) W.players[src] = { cid = cid, pos = pos or vec(0, 0, 0), bucket = 0, ped = 5000 + src, inVeh = nil, seat = nil }; W.cash[cid] = W.cash[cid] or 100000 end
    function W.addVehicle(id, fields)
        local v = { id = id, plate = fields.plate or ('PLT' .. id), model = fields.model or 'sultan', owner_type = fields.owner_type or 'character',
            owner_character_id = fields.owner_character_id or 1, mods = fields.mods, entity = fields.entity or (7000 + id), netId = fields.netId or (900 + id), pos = fields.pos or vec(0, 0, 0), bucket = 0 }
        W.vehicles[id] = v
        W.entities[v.entity] = { type = 2, state = { cmVehicleId = id, cmPlate = v.plate }, pos = v.pos, bucket = 0, model = v.model, vehicleId = id }
        return v
    end
    function W.mods(id) local raw = W.vehicles[id].mods; return raw and json.decode(raw) or {} end

    local noop = function() end
    local entityOfNet = function(netId) for _, v in pairs(W.vehicles) do if v.netId == netId then return v.entity end end return 0 end
    local exportsT = setmetatable({}, {
        __call = function(_, name, fn) W.registry[name] = fn end,
        __index = function(_, resource)
            if resource == 'cm-vehicles' then
                return setmetatable({
                    GetVehicleById = function(_, id) local v = W.vehicles[tonumber(id)]; if not v then return nil end return { id = v.id, plate = v.plate, model = v.model, owner_type = v.owner_type, owner_character_id = v.owner_character_id, mods = v.mods } end,
                    GetVehicleByPlate = function(_, plate) for _, v in pairs(W.vehicles) do if v.plate == plate then return { id = v.id, plate = v.plate, model = v.model, owner_type = v.owner_type, owner_character_id = v.owner_character_id, mods = v.mods } end end end,
                    HasVehicleAccess = function(_, src, plate) local p = W.players[src]; for _, v in pairs(W.vehicles) do if v.plate == plate then return p ~= nil and tostring(v.owner_character_id) == tostring(p.cid) end end return false end,
                    SaveVehicleModsAuthorized = function(_, src, plate, netId, mods) for _, v in pairs(W.vehicles) do if v.plate == plate then v.mods = json.encode(mods); W.saved[#W.saved + 1] = plate; return true end end return false end,
                    GetSpawnedVehicleInfo = function(_, id) local v = W.vehicles[tonumber(id)]; if not v then return false end return true, { entity = v.entity, netId = v.netId } end,
                    HasRacingHarness = function() return false end,
                    InstallRacingHarness = function() return true end,
                }, { __index = function() return noop end })
            elseif resource == 'cm-playerdata' then
                return {
                    GetCharacterId = function(_, src) local p = W.players[tonumber(src)]; return p and p.cid end,
                    GetMoney = function(_, src, account) local p = W.players[tonumber(src)]; if not p or account ~= 'cash' then return 0 end return W.cash[p.cid] end,
                    RemoveMoney = function(_, src, account, amount, reason) local p = W.players[tonumber(src)]; if not p or (W.cash[p.cid] or 0) < amount then return false end
                        W.cash[p.cid] = W.cash[p.cid] - amount; W.charges[#W.charges + 1] = { cid = p.cid, amount = amount, reason = reason }; return true end,
                    AddMoney = function(_, src, account, amount, reason) local p = W.players[tonumber(src)]; if not p then return false end W.cash[p.cid] = W.cash[p.cid] + amount; W.refunds[#W.refunds + 1] = { cid = p.cid, amount = amount, reason = reason }; return true end,
                }
            elseif resource == 'cm-billing' then
                return { GetInvoiceStatus = function(_, ref) if W.billingDown then error('billing unavailable') end return W.invoices[ref] end }
            end
            return setmetatable({}, { __index = function() return noop end })
        end,
    })

    -- SQL double: cm_owned_vehicles.mods (+ the same compare-and-swap) ----------------
    local MySQL = { update = {}, scalar = {}, query = {}, single = {}, insert = {} }
    MySQL.scalar.await = function(sql, p)
        if sql:find('^SELECT mods FROM cm_owned_vehicles WHERE id = %?') then local v = W.vehicles[tonumber(p[1])]; return v and v.mods or nil end
        error('SQL double: unsupported scalar ' .. sql)
    end
    MySQL.update.await = function(sql, p)
        if sql:find('^UPDATE cm_owned_vehicles SET mods = %? WHERE id = %? AND mods <=> %?') then
            local v = W.vehicles[tonumber(p[2])]
            if W.casFailOnce then W.casFailOnce = false; return 0 end
            if not v or v.mods ~= p[3] then return 0 end
            v.mods = p[1]; W.modWrites = W.modWrites + 1; return 1
        end
        if sql:find('^UPDATE cm_owned_vehicles SET mods = %? WHERE id = %? AND plate = %?') then
            local v = W.vehicles[tonumber(p[2])]
            if not v or v.plate ~= p[3] then return 0 end
            v.mods = p[1]; W.modWrites = W.modWrites + 1; return 1
        end
        error('SQL double: unsupported update ' .. sql)
    end

    local env = setmetatable({
        CMTuning = nil, json = json, exports = exportsT, MySQL = MySQL, vector3 = vec,
        GetCurrentResourceName = function() return 'cm-tuning' end,
        GetInvokingResource = function() return W.invoker end,
        GetResourceState = function() return 'started' end,
        GetGameTimer = function() return W.timer end,
        GetConvar = function(k, d) return W.convars[k] or d end,
        -- threads run until their first Wait (startup work such as the schema/ready flag happens; the endless sweeps never loop)
        CreateThread = function(fn) local co = coroutine.create(fn); local ok, err = coroutine.resume(co); if not ok then error(err, 0) end end,
        Wait = function() if coroutine.isyieldable() then coroutine.yield() end end, SetTimeout = noop,
        RegisterNetEvent = function(name, fn) if fn then W.netHandlers[name] = fn end end,
        AddEventHandler = function(name, fn) W.localHandlers[name] = W.localHandlers[name] or {}; table.insert(W.localHandlers[name], fn) end,
        TriggerEvent = function(name, ...)
            W.localEvents[#W.localEvents + 1] = { name = name, args = table.pack(...) }
            for _, fn in ipairs(W.localHandlers[name] or {}) do fn(...) end
        end,
        TriggerClientEvent = function(name, src, ...) W.clientEvents[#W.clientEvents + 1] = { name = name, src = src, args = table.pack(...) } end,
        GetPlayerName = function(src) return W.players[src] and ('player' .. src) or nil end,
        GetPlayerPed = function(src) return W.players[src] and W.players[src].ped or 0 end,
        GetPlayerRoutingBucket = function(src) return W.players[src] and W.players[src].bucket or 0 end,
        GetEntityRoutingBucket = function(e) return W.entities[e] and W.entities[e].bucket or 0 end,
        GetEntityCoords = function(e)
            if W.entities[e] then return W.entities[e].pos end
            for _, p in pairs(W.players) do if p.ped == e then return p.pos end end
            return vec(0, 0, 0)
        end,
        NetworkGetEntityFromNetworkId = entityOfNet,
        DoesEntityExist = function(e) return e ~= nil and e ~= 0 and (W.entities[e] ~= nil or (function() for _, p in pairs(W.players) do if p.ped == e then return true end end return false end)()) end,
        GetEntityType = function(e) return W.entities[e] and W.entities[e].type or 1 end,
        GetEntityModel = function(e) return W.entities[e] and W.entities[e].model end,
        joaat = function(s) return s end,
        Entity = function(e) return { state = W.entities[e] and W.entities[e].state or {} } end,
        GetVehiclePedIsIn = function(ped) for _, p in pairs(W.players) do if p.ped == ped then return p.inVeh or 0 end end return 0 end,
        GetPedInVehicleSeat = function(veh, seat) for _, p in pairs(W.players) do if p.inVeh == veh and p.seat == seat then return p.ped end end return 0 end,
        os = setmetatable({ time = function() return W.clock end }, { __index = os }),
    }, { __index = _G })
    env._G = env
    W.env = env

    local function loadFile(path)
        local src = slurp(here .. '/' .. path)
        local chunk, err = load(src, '@cm-tuning/' .. path, 't', env)
        assert(chunk, err)
        return chunk()
    end
    loadFile('shared/config.lua')
    W.Config = env.CMTuning.Config
    loadFile('server/service_core.lua')
    loadFile('server/main.lua')
    env.CMTuning.ServiceStore = W.store      -- journal store double (same contract + UNIQUE keys as the SQL store)
    loadFile('server/service.lua')
    W.T = env.CMTuning
    W.core = env.CMTuning.ServiceEngine
    W.ready = true

    -- helpers ---------------------------------------------------------------------
    function W.call(name, ...) return W.registry[name](...) end
    function W.as(resource, name, ...) W.invoker = resource; local a, b, c = W.registry[name](...); W.invoker = 'cm-mechanic'; return a, b, c end
    function W.fire(src, name, data) env.source = src; W.netHandlers[name](data); env.source = nil end
    function W.lastClient(name) for i = #W.clientEvents, 1, -1 do if W.clientEvents[i].name == name then return W.clientEvents[i] end end end
    function W.clearEvents() W.clientEvents = {}; W.localEvents = {} end
    return W
end

return { build = build, newStore = newStore, vec = vec, json = json, slurp = slurp, here = here }
