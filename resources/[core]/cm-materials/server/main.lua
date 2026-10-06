-- cm-materials: READ-ONLY server exports over the code-owned catalog (shared/catalog.lua). No client surface, no database, no mutation API,
-- no items/money. Every export returns deep copies, so a caller cannot alter the catalog. Clients never supply or receive authority from here.
-- Spec: agent-docs/CM_MATERIAL_ECONOMY.md
local M, G = CMMaterials, CMMaterials.Graph
local valid, validated = false, false

local function itemDef(name)
    if GetResourceState('cm-items') ~= 'started' then return nil end
    local ok, def = pcall(function() return exports['cm-items']:GetItem(name) end)
    if ok and type(def) == 'table' then return def end
    return nil
end

local function validate()
    local errs = G.validate(M, { itemDef = itemDef })
    validated = true
    valid = #errs == 0
    if valid then
        local n = 0 for _ in pairs(M.Items) do n = n + 1 end
        print(('[cm-materials] catalog v%d valid: %d materials, %d processing recipes (no live source/sink is active yet)'):format(M.Version, n, #M.Recipes))
    else
        for _, e in ipairs(errs) do print(('^1[cm-materials] catalog error: %s^7'):format(e)) end
        print('^1[cm-materials] catalog INVALID: exports fail closed until fixed.^7')
    end
    return valid
end

CreateThread(function()
    -- cm-items may still be starting; retry briefly, then settle on the result (fail closed).
    for _ = 1, 10 do
        if GetResourceState('cm-items') == 'started' and validate() then return end
        Wait(1000)
    end
    if not validated or not valid then validate() end
end)

local function ready() return valid == true end

exports('IsMaterial', function(id)
    return ready() and type(id) == 'string' and M.Items[id] ~= nil
end)

exports('GetMaterial', function(id)
    if not ready() or type(id) ~= 'string' or not M.Items[id] then return nil end
    local m = G.deepCopy(M.Items[id]); m.id = id
    m.quantityCeilingPerHour = G.quantityCeilingPerHour(M, id)
    return m
end)

exports('GetMaterialReferenceValue', function(id)
    if not ready() or type(id) ~= 'string' or not M.Items[id] then return nil end
    return M.Items[id].refValue   -- balance anchor, NOT a price anyone may be paid
end)

exports('GetMaterialSources', function(id)
    if not ready() or type(id) ~= 'string' or not M.Items[id] then return nil end
    return G.deepCopy(M.Items[id].sources)
end)

exports('GetMaterialSinks', function(id)
    if not ready() or type(id) ~= 'string' or not M.Items[id] then return nil end
    return G.deepCopy(M.Items[id].sinks)
end)

exports('GetMaterialQuantityCeiling', function(id)
    if not ready() then return nil end
    return G.quantityCeilingPerHour(M, id)
end)

exports('GetProductionGraph', function()
    if not ready() then return nil end
    return G.productionGraph(M)
end)

-- Enabled production recipe definitions for one station type, ready for exports['cm-crafting']:RegisterCraftRecipe(def).
-- The resource that OWNS the station registers them under its own trusted name (cm-crafting pins a recipe to its registering resource).
exports('GetProcessingRecipes', function(stationType)
    if not ready() or type(stationType) ~= 'string' or not M.StationTypes[stationType] then return nil end
    local out = {}
    for _, r in ipairs(M.Recipes) do
        if r.enabled == true and r.stations[1] == stationType then
            local def = G.deepCopy(r)
            def.enabled = nil   -- not a cm-crafting field
            out[#out + 1] = def
        end
    end
    return out
end)

RegisterCommand('cm_materials_status', function(src)
    if src ~= 0 then return end
    print(('[cm-materials] valid=%s validated=%s'):format(tostring(valid), tostring(validated)))
end, true)
