-- cm-crafting FiveM wiring for server/core.lua. See docs/README.md.
-- SERVER-TO-SERVER ONLY: no client event, NUI callback or player command exists. Content resources call these exports from their own
-- server code; they own the physical interaction. This resource never removes or adds items itself.
local Config = CMCrafting.Config
local Core, Store = CMCrafting.Core, CMCrafting.Store

local function xcall(resource, name, ...)
    if GetResourceState(resource) ~= 'started' then return false, 'resource_unavailable' end
    local args = table.pack(...)
    local res = table.pack(pcall(function() return exports[resource][name](exports[resource], table.unpack(args, 1, args.n)) end))
    if not res[1] then return false, 'call_failed' end
    return true, table.unpack(res, 2, res.n)
end

local function jsonEncode(t) local ok, s = pcall(json.encode, t); return ok and s or '' end
local function jsonDecode(s) if type(s) ~= 'string' or s == '' then return nil end local ok, t = pcall(json.decode, s); return ok and t or nil end

local chars = {
    sourceOf = function(cid)
        local ok, src = xcall('cm-playerdata', 'GetSourceByCharId', tonumber(cid))
        src = ok and tonumber(src) or nil
        if src and src > 0 and GetPlayerName(src) then return src end
        return nil
    end,
    position = function(src)
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return nil end
        local c = GetEntityCoords(ped)
        local okB, bucket = pcall(GetPlayerRoutingBucket, src)
        return { x = c.x, y = c.y, z = c.z, bucket = okB and tonumber(bucket) or 0 }
    end,
}

-- cm-items is the definition authority. nil = authority unavailable (the core fails closed).
local items = {
    exists = function(name)
        local ok, yes = xcall('cm-items', 'IsInventoryItem', name)
        if not ok then return nil end
        return yes == true
    end,
    validateMetadata = function(name, meta)
        local ok, valid = xcall('cm-items', 'ValidateMetadata', name, meta)
        return ok and valid ~= false
    end,
}

-- cm-inventory SETTLEMENT CONTRACT (docs/README.md; implemented by cm-inventory server/craft.lua).
-- While the owner exports are absent (cm-inventory stopped/older), ready() is false and every Begin/Complete fails closed. There is NO RemoveItem/AddItem fallback.
local capability = { at = 0, ready = false }
local inventory = {
    ready = function()
        local now = os.time()
        if now - capability.at < 30 then return capability.ready end
        capability.at = now
        capability.ready = false
        if GetResourceState('cm-inventory') == 'started' then
            local ok = xcall('cm-inventory', 'GetCraftTransactionStatus', 'CRAFT-PROBE0000')
            capability.ready = ok == true   -- a missing export raises -> call_failed -> not ready
        end
        return capability.ready
    end,
    validate = function(cid, tx)
        local ok, a, b = xcall('cm-inventory', 'ValidateCraftTransaction', tostring(cid), tx)
        if not ok then return false, 'unavailable' end
        return a == true, b
    end,
    execute = function(ref, cid, tx)
        local ok, a, b = xcall('cm-inventory', 'ExecuteCraftTransaction', ref, tostring(cid), tx)
        if not ok then return false, 'unavailable' end
        if a == true then return true, b end
        return false, type(b) == 'string' and b or 'unavailable'
    end,
    status = function(ref)
        local ok, st = xcall('cm-inventory', 'GetCraftTransactionStatus', ref)
        if not ok or (st ~= 'committed' and st ~= 'not_applied') then return 'unknown' end
        return st
    end,
}

local hits = {}
local function rate(key, bucket)
    local cfg = Config.RateLimits[bucket]
    if not cfg then return true end
    local k, now = key .. ':' .. bucket, os.time()
    local kept = {}
    for _, t in ipairs(hits[k] or {}) do if now - t < cfg[2] then kept[#kept + 1] = t end end
    if #kept >= cfg[1] then hits[k] = kept; return false end
    kept[#kept + 1] = now; hits[k] = kept
    return true
end

local core = Core.New({
    cfg = Config, store = Store, now = os.time, rand = math.random, encode = jsonEncode, decode = jsonDecode,
    chars = chars, items = items, inventory = inventory, rate = rate,
    owners = {
        started = function(resource) return GetResourceState(resource) == 'started' end,
        call = function(resource, name, ...) return xcall(resource, name, ...) end,
    },
    audit = function(kind, detail) TriggerEvent('cm-admin:server:addLog', 0, kind, { category = 'crafting', detail = detail or {} }) end,
    log = function(level, msg) print(('[cm-crafting] ^1%s: %s^7'):format(level, tostring(msg))) end,
})
CMCrafting.Engine = core
local ready = false

-- Every mutation is bound to GetInvokingResource(): only the resource that registered a recipe can run crafts of it.
local function owned(fn)
    return function(...)
        local invoker = GetInvokingResource()
        if not invoker or invoker == GetCurrentResourceName() then return false, 'forbidden' end
        if not ready then return false, 'not_ready' end
        return fn(invoker, ...)
    end
end

exports('RegisterCraftRecipe', owned(function(inv, def) return core:RegisterRecipe(inv, def) end))
exports('RegisterCraftStation', owned(function(inv, def) return core:RegisterStation(inv, def) end))
exports('GetRegisteredRecipes', owned(function(inv, filter) return core:GetRecipes(inv, filter) end))
exports('CanCraft', owned(function(inv, cid, recipeId, quantity, stationId) return core:CanCraft(inv, cid, recipeId, quantity, stationId) end))
exports('BeginCraft', owned(function(inv, cid, recipeId, quantity, stationId, ctx) return core:Begin(inv, cid, recipeId, quantity, stationId, ctx) end))
exports('GetCraftSession', owned(function(inv, ref) return core:Get(inv, ref) end))
exports('CompleteCraft', owned(function(inv, ref, cid, ctx) return core:Complete(inv, ref, cid, ctx) end))
exports('CancelCraft', owned(function(inv, ref, cid, reason) return core:Cancel(inv, ref, cid, reason) end))
exports('FailCraft', owned(function(inv, ref, reason) return core:Fail(inv, ref, reason) end))
exports('GetCraftTransactionStatus', owned(function(inv, ref)
    local ok, view = core:Get(inv, ref)
    if not ok then return false, view end
    return true, { status = view.status, transaction = inventory.ready() and inventory.status(ref) or 'unavailable' }
end))
exports('IsCraftingSettlementReady', function() return inventory.ready() end)

local function admin(fn)
    return function(...)
        if not Config.AdminCallers[GetInvokingResource() or ''] then return false, 'forbidden' end
        if not ready then return false, 'not_ready' end
        return fn(...)
    end
end
exports('AdminListCrafts', admin(function() return core:AdminList() end))
exports('AdminInspectCraft', admin(function(ref) return core:AdminInspect(ref) end))
exports('AdminCancelCraft', admin(function(ref, label) return core:AdminCancel(ref, label) end))
exports('AdminReconcileCraft', admin(function(ref, label) return core:AdminReconcile(ref, label) end))

local function consoleOnly(name, fn)
    RegisterCommand(name, function(src, args)
        if src ~= 0 then return end
        local ok, a, b = pcall(fn, args)
        print(('[cm-crafting] %s -> %s'):format(name, ok and jsonEncode({ a, b }) or tostring(a)))
    end, true)
end
consoleOnly('cm_crafting_list', function() return core:AdminList() end)
consoleOnly('cm_crafting_inspect', function(a) return core:AdminInspect(a[1]) end)
consoleOnly('cm_crafting_cancel', function(a) return core:AdminCancel(a[1], 'console') end)
consoleOnly('cm_crafting_reconcile', function(a) return core:AdminReconcile(a[1], 'console') end)
consoleOnly('cm_crafting_status', function() return inventory.ready(), 'live item settlement requires cm-inventory ExecuteCraftTransaction' end)

CreateThread(function()
    local ok, err = pcall(function() Store.EnsureSchema() end)
    if not ok then print(('[cm-crafting] ^1schema error: %s^7'):format(tostring(err))); return end
    ready = true
    -- Recipes/stations live in memory: ask content resources to register again (local server event, not networked).
    TriggerEvent('cm-crafting:server:registryReady')
    local rok, rerr = pcall(function() return core:Recover() end)
    if not rok then print(('[cm-crafting] recovery error: %s'):format(tostring(rerr))) end
    if not inventory.ready() then print('[cm-crafting] live item settlement DISABLED: cm-inventory craft transaction contract is not available (is cm-inventory started?).') end
    while true do
        Wait(Config.SweepSeconds * 1000)
        local sok, serr = pcall(function() return core:Sweep() end)
        if not sok then print(('[cm-crafting] sweep error: %s'):format(tostring(serr))) end
    end
end)
