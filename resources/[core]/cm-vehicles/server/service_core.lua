-- Vehicle service mutation core: patch validation + trusted-caller policy.
-- PURE (no FiveM natives, no SQL) so tests/service_selftest.lua can run it with a plain Lua interpreter.
-- Wiring (database, statebag sync, exports) lives in server/main.lua; contract in docs/API_SERVICE.md.
CMVehicles = CMVehicles or {}
local Core = {}
CMVehicles.ServiceCore = Core

Core.FIELDS = { fuel = true, engineHealth = true, bodyHealth = true, tankHealth = true, dirtLevel = true,
    conditionState = true, clearVisualDamage = true }

local function finiteNumber(v)
    v = tonumber(v)
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

-- -> clean patch | nil, reason. Rejects unknown keys (never silently dropped) and malformed values (never coerced to 0).
-- `allowedFields` nil = internal caller (every serviceable field); otherwise a { field = true } allowlist.
function Core.Sanitize(U, patch, allowedFields)
    if type(patch) ~= 'table' then return nil, 'invalid_patch' end
    local clean, count = {}, 0
    for key, value in pairs(patch) do
        if type(key) ~= 'string' or not Core.FIELDS[key] then return nil, 'unsupported_field' end
        if allowedFields and allowedFields[key] ~= true then return nil, 'field_not_permitted' end
        if key == 'fuel' then
            local n = finiteNumber(value); if not n then return nil, 'invalid_patch' end
            clean.fuel = math.floor(math.max(0, math.min(100, n)))
        elseif key == 'dirtLevel' then
            local n = finiteNumber(value); if not n then return nil, 'invalid_patch' end
            clean.dirtLevel = math.max(0, math.min(15, n))
        elseif key == 'engineHealth' or key == 'bodyHealth' or key == 'tankHealth' then
            local n = finiteNumber(value); if not n then return nil, 'invalid_patch' end
            clean[key] = U.NormalizeHealth(n, 1000.0)
        elseif key == 'conditionState' then
            if type(value) ~= 'table' then return nil, 'invalid_patch' end
            clean.conditionState = U.SanitizeConditionState(value)
        elseif key == 'clearVisualDamage' then
            if type(value) ~= 'boolean' then return nil, 'invalid_patch' end
            clean.clearVisualDamage = value
        end
        count = count + 1
    end
    if count == 0 then return nil, 'invalid_patch' end
    if clean.clearVisualDamage == true and clean.conditionState == nil then clean.conditionState = {} end
    clean.clearVisualDamage = nil
    if next(clean) == nil then return nil, 'invalid_patch' end
    return clean
end

-- -> true, allowedFields|nil (nil = same-resource/internal caller) | false, invoker
function Core.ResolveCaller(invoker, selfResource, trustedCallers)
    if invoker == nil or invoker == selfResource then return true, nil end
    local allowed = type(trustedCallers) == 'table' and trustedCallers[invoker]
    if type(allowed) ~= 'table' then return false, invoker end
    return true, allowed
end
