-- cm-materials: pure (no FiveM, no database) validation + analysis of the material catalog. Used by the server at start and by the self-test.
CMMaterials = CMMaterials or {}
local G = {}
CMMaterials.Graph = G

local STAGE_RANK = { raw = 1, processed = 2, component = 3 }

local function isInt(n) return type(n) == 'number' and n == n and n % 1 == 0 end

function G.deepCopy(v)
    if type(v) ~= 'table' then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = G.deepCopy(x) end
    return o
end

local function sortedKeys(t)
    local k = {}
    for key in pairs(t) do k[#k + 1] = key end
    table.sort(k)
    return k
end
G.sortedKeys = sortedKeys

function G.recipeById(catalogRecipes, id)
    for _, r in ipairs(catalogRecipes) do if r.id == id then return r end end
end

function G.recipeValues(M, recipe, itemsCat)
    local inV, outV = 0, 0
    for _, l in ipairs(recipe.inputs) do
        local m = itemsCat[l.item]; inV = inV + (m and m.refValue or 0) * l.amount
    end
    for _, l in ipairs(recipe.outputs) do
        local m = itemsCat[l.item]; outV = outV + (m and m.refValue or 0) * l.amount
    end
    local created = outV - inV
    local E = M.Economy.processing
    local allowance = recipe.durationSeconds * E.timeValuePerSecond + math.floor(inV * E.inputPremium)
    return { inputValue = inV, outputValue = outV, created = created, allowance = allowance,
        createdPerHour = recipe.durationSeconds > 0 and math.floor(created * 3600 / recipe.durationSeconds) or 0 }
end

-- Items a gathering job may award per hour so that MATERIAL reference value stays inside its share of the activity band.
function G.quantityCeilingPerHour(M, id)
    local m = M.Items[id]
    if not m or not m.refValue or m.refValue <= 0 then return nil end
    local budget = M.Economy.gatheringActivityBandPerHour[1] * M.Economy.maxMaterialShareOfActivity
    return math.floor(budget / m.refValue)
end

-- Item graph edges: input item -> output item, one per recipe line pair.
local function edges(M)
    local e = {}
    for _, r in ipairs(M.Recipes) do
        for _, i in ipairs(r.inputs) do for _, o in ipairs(r.outputs) do e[#e + 1] = { from = i.item, to = o.item, recipe = r.id } end end
    end
    return e
end

function G.findCycle(M)
    local adj = {}
    for _, e in ipairs(edges(M)) do adj[e.from] = adj[e.from] or {}; adj[e.from][#adj[e.from] + 1] = e.to end
    local state, stack = {}, {}
    local found
    local function dfs(n)
        state[n] = 1; stack[#stack + 1] = n
        for _, nxt in ipairs(adj[n] or {}) do
            if state[nxt] == 1 then
                found = found or { table.unpack(stack) }; found[#found + 1] = nxt
                return
            elseif not state[nxt] then dfs(nxt); if found then return end end
        end
        stack[#stack] = nil; state[n] = 2
    end
    for _, n in ipairs(sortedKeys(adj)) do if not state[n] then dfs(n); if found then break end end end
    return found
end

-- ctx.itemDef(name) -> the cm-items definition table or nil.   Returns a list of error strings (empty = valid).
function G.validate(M, ctx)
    local errs = {}
    local function err(fmt, ...) errs[#errs + 1] = fmt:format(...) end
    ctx = ctx or {}
    local E = M.Economy

    for _, id in ipairs(sortedKeys(M.Items)) do
        local m = M.Items[id]
        if type(id) ~= 'string' or not id:match('^[a-z0-9_]+$') then err('%s: invalid item id', tostring(id)) end
        if ctx.itemDef then
            local def = ctx.itemDef(id)
            if not def then err('%s: not defined in cm-items', id)
            else
                if def.category ~= 'material' then err('%s: cm-items category must be material (is %s)', id, tostring(def.category)) end
                if def.stack ~= true or def.unique == true then err('%s: must be a stackable non-unique commodity', id) end
                if def.metadataRequired ~= nil or def.metadataSchema ~= nil then err('%s: commodities must not require metadata', id) end
                if def.usable == true then err('%s: commodities must not be usable', id) end
                if type(def.weight) ~= 'number' or def.weight < 1 or def.weight > 2000 then err('%s: weight %s outside 1..2000 g', id, tostring(def.weight)) end
            end
        end
        if not STAGE_RANK[m.stage] then err('%s: invalid stage %s', id, tostring(m.stage)) end
        if not M.Categories[m.category] then err('%s: invalid category %s', id, tostring(m.category)) end
        for _, t in ipairs(m.tags or {}) do if not M.Tags[t] then err('%s: unknown tag %s', id, tostring(t)) end end
        if not isInt(m.refValue) or m.refValue <= 0 then err('%s: refValue must be a positive whole number', id)
        elseif m.refValue % 5 ~= 0 then err('%s: refValue %d is not a round (x5) balance value', id, m.refValue) end
        if not M.Statuses[m.status] then err('%s: invalid status %s', id, tostring(m.status)) end
        if m.directSale ~= false then
            if type(m.directSale) ~= 'table' or not isInt(m.directSale.price) or m.directSale.price <= 0
                or m.directSale.price > math.floor((m.refValue or 0) * E.directSaleMaxShareOfReference) then
                err('%s: directSale must be false or { price <= %d%% of refValue }', id, E.directSaleMaxShareOfReference * 100)
            end
        end
        if m.status ~= 'DEFERRED' and (#(m.sources or {}) == 0 or #(m.sinks or {}) == 0) then err('%s: a non-deferred material needs at least one source and one sink', id) end
        for _, list in ipairs({ m.sources or {}, m.sinks or {} }) do
            for _, link in ipairs(list) do
                if not M.LinkStatuses[link.status] then err('%s: invalid link status %s', id, tostring(link.status)) end
                if link.kind == 'process' then
                    local r = G.recipeById(M.Recipes, link.recipe)
                    if not r then err('%s: link references unknown recipe %s', id, tostring(link.recipe))
                    else
                        if link.station and r.stations[1] ~= link.station then err('%s: link station %s is not the station of %s', id, tostring(link.station), r.id) end
                        local lines = (list == (m.sources or {})) and r.outputs or r.inputs   -- a source recipe must PRODUCE the item, a sink recipe must CONSUME it
                        local touches = false
                        for _, l in ipairs(lines) do if l.item == id then touches = true end end
                        if not touches then err('%s: recipe %s does not %s it', id, r.id, (list == (m.sources or {})) and 'produce' or 'consume') end
                    end
                elseif not link.owner then err('%s: external link without owner', id) end
            end
        end
        if m.status == 'ACTIVE' then
            for _, list in ipairs({ m.sources, m.sinks }) do
                for _, link in ipairs(list) do if link.status ~= 'active' then err('%s: ACTIVE material has a non-active link', id) end end
            end
        end
        if m.status == 'ACTIVE' then   -- raw and processed alike need a live consumer
            local hasSink = false
            for _, link in ipairs(m.sinks or {}) do if link.status == 'active' then hasSink = true end end
            if not hasSink then err('%s: ACTIVE material has no active sink', id) end
        end
    end

    local seen = {}
    for _, r in ipairs(M.Recipes) do
        if seen[r.id] then err('%s: duplicate recipe id', r.id) end
        seen[r.id] = true
        if type(r.id) ~= 'string' or not r.id:match('^materials:[%l%d_]+$') then err('%s: recipe id must be materials:<name>', tostring(r.id)) end
        if not isInt(r.durationSeconds) or r.durationSeconds < 1 or r.durationSeconds > 3600 then err('%s: invalid duration', r.id) end
        if r.handcraft ~= false then err('%s: production recipes need a station (handcraft must be false)', r.id) end
        if type(r.stations) ~= 'table' or #r.stations == 0 then err('%s: no station type', r.id) end
        for _, s in ipairs(r.stations or {}) do if not M.StationTypes[s] then err('%s: impossible station type %s', r.id, tostring(s)) end end
        if type(r.batch) ~= 'table' or not isInt(r.batch.min) or not isInt(r.batch.max) or r.batch.min < 1 or r.batch.max < r.batch.min or r.batch.max > 50 then err('%s: invalid batch', r.id) end
        local inSet, minIn, maxOut = {}, 99, 0
        for _, l in ipairs(r.inputs or {}) do
            local m = M.Items[l.item]
            if not m then err('%s: input %s is not a catalog material', r.id, tostring(l.item)) else
                if m.status == 'DEFERRED' and r.enabled then err('%s: enabled recipe uses DEFERRED material %s', r.id, l.item) end
                minIn = math.min(minIn, STAGE_RANK[m.stage] or 99)
            end
            if not isInt(l.amount) or l.amount < 1 or l.amount > 1000 then err('%s: invalid input amount for %s', r.id, tostring(l.item)) end
            inSet[l.item] = true
        end
        for _, l in ipairs(r.outputs or {}) do
            local m = M.Items[l.item]
            if not m then err('%s: output %s is not a catalog material', r.id, tostring(l.item)) else
                if m.status == 'DEFERRED' and r.enabled then err('%s: enabled recipe uses DEFERRED material %s', r.id, l.item) end
                maxOut = math.max(maxOut, STAGE_RANK[m.stage] or 0)
            end
            if inSet[l.item] then err('%s: output %s is also an input', r.id, l.item) end
            if not isInt(l.amount) or l.amount < 1 or l.amount > 1000 then err('%s: invalid output amount for %s', r.id, tostring(l.item)) end
            if l.metadata ~= nil then err('%s: commodity outputs must not carry metadata', r.id) end
        end
        if #(r.inputs or {}) == 0 or #(r.outputs or {}) == 0 then err('%s: needs inputs and outputs', r.id) end
        if maxOut < minIn then err('%s: output stage is below the input stage', r.id) end
        local v = G.recipeValues(M, r, M.Items)
        if v.inputValue <= 0 or v.outputValue <= 0 then err('%s: zero/negative value anomaly', r.id) end
        if v.created > v.allowance then err('%s: creates %d reference value, allowance is %d (duration %ds)', r.id, v.created, v.allowance, r.durationSeconds) end
        if v.created < -math.floor(v.inputValue * 0.2) then err('%s: destroys more than 20%% of input value (%d)', r.id, v.created) end
        if v.createdPerHour > E.processing.maxValueCreatedPerHour then err('%s: creates %d value/hour back-to-back, cap is %d', r.id, v.createdPerHour, E.processing.maxValueCreatedPerHour) end
    end

    local cycle = G.findCycle(M)
    if cycle then err('production graph contains a cycle: %s', table.concat(cycle, ' -> ')) end
    return errs
end

-- Serializable view used by GetProductionGraph().
function G.productionGraph(M)
    local nodes = {}
    for _, id in ipairs(sortedKeys(M.Items)) do
        local m = M.Items[id]
        nodes[#nodes + 1] = { id = id, stage = m.stage, category = m.category, refValue = m.refValue, status = m.status }
    end
    local recs = {}
    for _, r in ipairs(M.Recipes) do
        local v = G.recipeValues(M, r, M.Items)
        recs[#recs + 1] = { id = r.id, station = r.stations[1], durationSeconds = r.durationSeconds, enabled = r.enabled == true, inputs = G.deepCopy(r.inputs), outputs = G.deepCopy(r.outputs),
            inputValue = v.inputValue, outputValue = v.outputValue }
    end
    return { version = M.Version, nodes = nodes, recipes = recs }
end
