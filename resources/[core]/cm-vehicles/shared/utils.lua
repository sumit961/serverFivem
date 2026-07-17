CMVehicles = CMVehicles or {}
CMVehicles.Utils = CMVehicles.Utils or {}
local U = CMVehicles.Utils

function U.Debug(...)
    if CMVehicles.Config and CMVehicles.Config.Debug then print('[CM-VEHICLES]', ...) end
end

function U.NormalizePlate(plate)
    return tostring(plate or ''):upper():gsub('%s+', '')
end

function U.Truthy(value)
    if value == true then return true end
    if value == false or value == nil then return false end
    if tonumber(value) == 1 then return true end
    local s = tostring(value):lower()
    return s == 'true' or s == 'yes' or s == 'on'
end

function U.Encode(v)
    local ok, out = pcall(json.encode, v or {})
    return ok and out or '{}'
end

function U.Decode(v)
    if type(v) == 'table' then return v end
    if not v or v == '' then return {} end
    local ok, out = pcall(json.decode, v)
    return ok and type(out) == 'table' and out or {}
end

function U.ClampHealth(v)
    v = tonumber(v) or 0.0
    if v < 0.0 then return 0.0 end
    if v > 1000.0 then return 1000.0 end
    return v
end

-- Saved condition and bootstrap condition are intentionally different.
--
-- Saved health is gameplay state. A numeric 0.0 is a real destroyed component
-- and MUST survive garage storage, recall, resource restarts and routing-bucket
-- migration. Only missing / non-numeric / NaN data uses the fallback.
--
-- Values strictly between 0 and 1 are treated as legacy 0..1 fractions. Zero is
-- excluded because it is a valid destroyed value.
function U.NormalizeSavedHealth(v, defaultValue)
    local n = tonumber(v)
    if n == nil or n ~= n then n = tonumber(defaultValue) or 1000.0 end
    if n > 0.0 and n <= 1.0 then n = n * 1000.0 end
    return U.ClampHealth(n)
end

-- Backward-compatible name used throughout cm-vehicles. It now preserves a
-- genuine zero rather than silently repairing it.
function U.NormalizeHealth(v, defaultValue)
    return U.NormalizeSavedHealth(v, defaultValue)
end

-- House-garage saved condition uses the same rules as every other saved vehicle.
-- The safe 1000-health bootstrap is carried separately in the spawn payload and
-- is never written back to the database.
function U.NormalizeGarageHealth(v, defaultValue)
    return U.NormalizeSavedHealth(v, defaultValue)
end

-- Temporary condition used only while a brand-new network entity initializes.
-- It must be healthy enough for FiveM's damage skeleton to accept later writes.
function U.NormalizeBootstrapHealth(v, defaultValue)
    local fallback = tonumber(defaultValue) or 1000.0
    local n = tonumber(v)
    if n == nil or n ~= n or n <= 1.0 then n = fallback end
    return U.ClampHealth(n)
end

function U.SanitizeConditionState(value)
    value = type(value) == 'table' and value or {}
    local out = {
        windowSchema = 2,
        brokenWindows = {},
        doors = {},
        tyres = {},
    }

    -- v1.3.2.6: Legacy snapshots stored every IsVehicleWindowIntact result.
    -- GTA returns false for window indexes/bones a model does not actually have,
    -- so those legacy rows could make all glass smash on every garage recall.
    -- Only schema-2 snapshots are trusted for glass damage. Existing legacy
    -- window maps are intentionally ignored once; the next legitimate storage
    -- captures a fresh model-aware schema-2 snapshot.
    local schema = tonumber(value.windowSchema or value.conditionVersion or value.version) or 0
    if schema >= 2 then
        local broken = type(value.brokenWindows) == 'table' and value.brokenWindows or {}
        for i = 0, 7 do
            local key = tostring(i)
            local isBroken = broken[key]
            if isBroken == nil then isBroken = broken[i] end
            if isBroken == true then out.brokenWindows[key] = true end
        end

        -- Backward-compatible schema-2 reader for early test builds that used
        -- windows[index] = false instead of brokenWindows[index] = true.
        if type(value.windows) == 'table' then
            for i = 0, 7 do
                local key = tostring(i)
                local intact = value.windows[key]
                if intact == nil then intact = value.windows[i] end
                if intact == false then out.brokenWindows[key] = true end
            end
        end
    end

    for i = 0, 7 do
        local key = tostring(i)
        local door = value.doors and (value.doors[key] or value.doors[i])
        if type(door) == 'table' then
            out.doors[key] = {
                damaged = door.damaged == true,
                broken = door.broken == true,
                angle = math.max(0.0, math.min(1.0, tonumber(door.angle) or 0.0)),
            }
        end

        local tyre = value.tyres and (value.tyres[key] or value.tyres[i])
        if type(tyre) == 'table' then
            out.tyres[key] = { burst = tyre.burst == true, onRim = tyre.onRim == true }
        end
    end
    out.engineRunning = value.engineRunning == true
    out.undriveable = value.undriveable == true
    return out
end
function U.MergeConditionWear(existing, incoming)
    existing = U.SanitizeConditionState(existing)
    incoming = U.SanitizeConditionState(incoming)
    local out = {
        windowSchema = 2,
        brokenWindows = {},
        doors = {},
        tyres = {},
    }
    for i = 0, 7 do
        local key = tostring(i)
        if existing.brokenWindows[key] == true or incoming.brokenWindows[key] == true then
            out.brokenWindows[key] = true
        end

        local oldDoor, newDoor = existing.doors[key], incoming.doors[key]
        if oldDoor or newDoor then
            oldDoor, newDoor = oldDoor or {}, newDoor or {}
            out.doors[key] = {
                damaged = oldDoor.damaged == true or newDoor.damaged == true,
                broken = oldDoor.broken == true or newDoor.broken == true,
                angle = math.max(0.0, math.min(1.0,
                    tonumber(newDoor.angle) or tonumber(oldDoor.angle) or 0.0)),
            }
        end

        local oldTyre, newTyre = existing.tyres[key], incoming.tyres[key]
        if oldTyre or newTyre then
            oldTyre, newTyre = oldTyre or {}, newTyre or {}
            out.tyres[key] = {
                burst = oldTyre.burst == true or newTyre.burst == true,
                onRim = oldTyre.onRim == true or newTyre.onRim == true,
            }
        end
    end
    out.engineRunning = incoming.engineRunning == true
    out.undriveable = incoming.undriveable == true
    return out
end
function U.Notify(src, msg, typeName)
    TriggerClientEvent('cm-vehicles:client:notify', src, msg or '', typeName or 'info')
end

function U.CallExport(resource, method, ...)
    if GetResourceState(resource) ~= 'started' then return false, nil end
    local args = { ... }
    local ok, result, extra = pcall(function()
        return exports[resource][method](table.unpack(args))
    end)
    if ok then return true, result, extra end
    print(('[CM-VEHICLES] Export failed: %s.%s | %s'):format(resource, method, tostring(result)))
    return false, result
end
